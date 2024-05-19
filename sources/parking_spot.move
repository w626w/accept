module parkinglot::parkinglot {

    //==============================================================================================
    // Dependencies
    //==============================================================================================

    use sui::coin;
    use sui::balance;
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};
    use sui::errors::{assert, abort};
    use sui::object::{UID, ID, self};
    use sui::transfer;
    use sui::tx_context::{self, TxContext};
    use sui::vector;
    use sui::types::address::address;
    use sui::event::emit;

    //==============================================================================================
    // Error codes
    //==============================================================================================

    const EParkingSlotNotAvailable: u64 = 2;
    const EUnauthorized: u64 = 5;
    const EPaymentRequired: u64 = 6;
    const EExceedsMaxDuration: u64 = 7;

    //==============================================================================================
    // Structs
    //==============================================================================================

    // Define the structure of a parking slot
    public struct Slot has key, store {
        id: UID,             // Unique identifier for the slot
        status: bool,        // Status of the slot (true: occupied, false: vacant)
        start_time: u64,     // Timestamp indicating when the slot was first used
        end_time: u64,       // Timestamp indicating when the slot was last vacated
        fee_paid: bool,      // Flag to indicate if the parking fee has been paid
        user: option::Option<address>, // Address of the user occupying the slot
    }

    // Define the structure of a parking lot
    public struct ParkingLot has key, store {
        id: UID,             // Unique identifier for the parking lot
        admin: address,      // Address of the administrator
        slots: vector<Slot>, // Vector to store parking slots
        balance: balance::Balance<SUI>, // Balance of the parking lot in SUI tokens
        max_duration: u64,   // Maximum parking duration in milliseconds
    }

    // Define the structure of a payment record
    public struct PaymentRecord has key, store {
        id: UID,             // Unique identifier for the payment record
        amount: u64,         // Amount paid for parking
        payment_time: u64,   // Timestamp indicating when the payment was made
    }

    // Define the structure of administrator capabilities
    public struct AdminCap has key, store {
        id: UID,             // Unique identifier for the admin capabilities
        admin: address,      // Address of the admin
    }

    // Define the structure of events
    public struct Event has key, store {
        id: UID,             // Unique identifier for the event
        description: string::String,  // Description of the event
        timestamp: u64,      // Timestamp of the event
    }

    //==============================================================================================
    // Module Initialization
    //==============================================================================================

    // Initialize the module, creating a new parking lot and admin capability
    public fun init(ctx: &mut TxContext) {
        let admin_address = tx_context::sender(ctx);
        // Create AdminCap object
        let admin_cap = AdminCap {
            id: object::new(ctx),
            admin: admin_address,
        };
        // Safely transfer AdminCap object
        transfer::public_transfer(admin_cap, admin_address);

        // Create ParkingLot object
        let parking_lot = ParkingLot {
            id: object::new(ctx),
            admin: admin_address,
            slots: vector::empty(),
            balance: balance::zero(),
            max_duration: 86400000, // Default maximum duration set to 24 hours in milliseconds
        };
        // Safely transfer ParkingLot object
        transfer::public_transfer(parking_lot, admin_address);
    }

    //==============================================================================================
    // Slot Management
    //==============================================================================================

    // Only administrators can create parking slots
    public fun create_slot(admin_cap: &AdminCap, parking_lot: &mut ParkingLot, ctx: &mut TxContext) {
        assert!(admin_cap.admin == parking_lot.admin, EUnauthorized); // Ensure caller is an administrator
        let new_slot = Slot {
            id: object::new(ctx),
            status: false,
            start_time: 0,
            end_time: 0,
            fee_paid: false,
            user: option::none(),
        };
        vector::push_back(&mut parking_lot.slots, new_slot);
    }

    // Reserve a parking slot
    public fun reserve_slot(slot: &mut Slot, user: address) {
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
        slot.user = option::some(user);
    }

    // Occupy a parking slot
    public fun enter_slot(slot: &mut Slot, user: address, clock: &Clock, parking_lot: &ParkingLot) {
        assert!(slot.user == option::some(user), EUnauthorized); // Ensure the caller is the reserved user
        assert!(timestamp_ms(clock) - slot.start_time <= parking_lot.max_duration, EExceedsMaxDuration); // Ensure max duration is not exceeded
        slot.status = true;
        slot.start_time = timestamp_ms(clock); // Record start time
        emit_event("enter_slot", user, slot.id, slot.start_time);
    }

    // Pay for parking
    public fun pay_for_parking(slot: &mut Slot, amount: u64, parking_lot: &mut ParkingLot, ctx: &mut TxContext, clock: &Clock): PaymentRecord {
        assert!(slot.user == option::some(tx_context::sender(ctx)), EUnauthorized); // Ensure the caller is the reserved user
        slot.fee_paid = true;
        let payment_time = timestamp_ms(clock);
        let payment_record = PaymentRecord {
            id: object::new(ctx),
            amount: amount,
            payment_time: payment_time,
        };
        balance::add(&mut parking_lot.balance, amount);
        emit_event("pay_for_parking", tx_context::sender(ctx), slot.id, payment_time);
        payment_record
    }

    // Vacate a parking slot
    public fun exit_slot(slot: &mut Slot, clock: &Clock) {
        assert!(slot.status, EParkingSlotNotAvailable); // Ensure slot is occupied
        assert!(slot.fee_paid, EPaymentRequired); // Ensure fee is paid before exiting
        slot.status = false;
        slot.end_time = timestamp_ms(clock); // Record end time
        slot.fee_paid = false; // Reset fee paid status
        emit_event("exit_slot", option::extract(slot.user), slot.id, slot.end_time);
        slot.user = option::none(); // Clear user reservation
    }

    //==============================================================================================
    // Payment Management
    //==============================================================================================

    // Calculate parking fee
    public fun calculate_parking_fee(start_time: u64, end_time: u64, base_rate: u64, is_peak: bool): u64 {
        let duration = end_time - start_time;
        if is_peak {
            duration * base_rate * 2
        } else {
            duration * base_rate
        }
    }

    // Withdraw profits from the parking lot (ensure caller is administrator)
    public fun withdraw_profits(
        admin_cap: &AdminCap,
        parking_lot: &mut ParkingLot,
        amount: u64,
        ctx: &mut TxContext
    ): coin::Coin<SUI> {
        assert!(tx_context::sender(ctx) == admin_cap.admin, EUnauthorized);
        coin::take(&mut parking_lot.balance, amount, ctx)
    }

    // Distribute profits of the parking lot
    public fun distribute_profits(parking_lot: &mut ParkingLot, ctx: &mut TxContext) {
        let total_balance = balance::value(&parking_lot.balance);
        let admin_amount = total_balance;
        let admin_coin = coin::take(&mut parking_lot.balance, admin_amount, ctx);
        transfer::public_transfer(admin_coin, parking_lot.admin);
    }

    //==============================================================================================
    // Utility Functions
    //==============================================================================================

    // Verify ownership of the admin cap
    fun verify_admin_ownership(admin_cap: &AdminCap, parking_lot: &ParkingLot) -> bool {
        admin_cap.admin == parking_lot.admin
    }

    // Optional: Implement timeout management for parking slots (placeholder)
    public fun set_slot_timeout(slot: &mut Slot, timeout_duration: u64, clock: &Clock) {
        // Implement timeout logic based on your requirements
        let current_time = timestamp_ms(clock);
        if (slot.status && current_time - slot.start_time >= timeout_duration) {
            slot.status = false;
            slot.end_time = current_time;
        }
    }

    // Optional: Review Transfer Policies to ensure security (placeholder)
    public fun review_transfer_policy<T: store>(policy: &TransferPolicy<T>) -> bool {
        // Implement logic to check policy's constraints
        // Ensure it prevents unauthorized access or manipulation
        true // Placeholder logic; replace with actual checks
    }

    // Emit event
    fun emit_event(event_type: &str, user: address, slot_id: UID, timestamp: u64) {
        let event = Event {
            id: object::new(&mut tx_context::current_context()),
            description: format!("{} by {} on slot {} at {}", event_type, user, slot_id, timestamp),
            timestamp: timestamp,
        };
        emit(event);
    }

    //==============================================================================================
    // Testing Functions
    //==============================================================================================

    // Test function for generating slots (only for testing purposes)
    #[test_only]
    public fun test_init_parking_lot(ctx: &mut TxContext) {
        // Initialize test environment
        init(ctx);
    }
}
