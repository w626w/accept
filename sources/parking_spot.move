// This module defines a smart contract for managing a parking lot, including parking slots, payments, and administration.

module parkinglot::parkinglot {
    use sui::coin;
    use sui::balance;
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};

    // Error code for when a parking slot is not available
    const EParkingSlotNotAvailable: u64 = 2;

    // Define the structure of a parking slot
    public struct Slot has key, store {
        id: UID,             // Unique identifier for the slot
        status: bool,        // Status of the slot (true: occupied, false: vacant)
        start_time: u64,     // Timestamp indicating when the slot was first used
        end_time: u64,       // Timestamp indicating when the slot was last vacated
    }

    // Define the structure of a parking lot
    public struct ParkingLot has key, store {
        id: UID,             // Unique identifier for the parking lot
        admin: address,      // Address of the administrator
        slots: vector<Slot>, // Vector to store parking slots
        balance: balance::Balance<SUI>, // Balance of the parking lot in SUI tokens
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

    // Define the module initialization function
    fun init(ctx: &mut tx_context::TxContext) {
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
        };
        // Safely transfer ParkingLot object
        transfer::public_transfer(parking_lot, admin_address);
    }

    // Only administrators can create parking slots
    public fun create_slot(admin_cap: &AdminCap, ctx: &mut tx_context::TxContext, parking_lot: &mut ParkingLot) {
        assert!(admin_cap.admin == parking_lot.admin, EParkingSlotNotAvailable); // Ensure caller is an administrator
        let new_slot = Slot {
            id: object::new(ctx),
            status: false,
            start_time: 0,
            end_time: 0,
        };
        vector::push_back(&mut parking_lot.slots, new_slot);
    }

    // Reserve a parking slot
    public fun reserve_slot(slot: &mut Slot) {
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
    }

    // Occupy a parking slot
    public fun enter_slot(slot: &mut Slot, clock: &Clock) {
        assert!(!slot.status, EParkingSlotNotAvailable); // Modify: Ensure slot is not occupied
        slot.status = true;
        slot.start_time = timestamp_ms(clock); // Record start time
    }

    // Vacate a parking slot
    public fun exit_slot(slot: &mut Slot, clock: &Clock) {
        assert!(slot.status, EParkingSlotNotAvailable); // Ensure slot is occupied
        slot.status = false;
        slot.end_time = timestamp_ms(clock); // Record end time
    }

    // Adjust payment record creation
    public fun create_payment_record(amount: u64, ctx: &mut tx_context::TxContext, clock: &Clock): PaymentRecord {
        let payment_time = timestamp_ms(clock); // Ensure Clock object is available and correctly invoked
        let id_ = object::new(ctx);
        PaymentRecord {
            id: id_,
            amount: amount,
            payment_time: payment_time,
        }
    }

    // Calculate parking fee
    public fun calculate_parking_fee(start_time: u64, end_time: u64, base_rate: u64, _is_peak: bool): u64 {
        let duration = end_time - start_time;
        duration * base_rate
    }

    // Withdraw profits from the parking lot (ensure caller is administrator)
    public fun withdraw_profits(
        admin: &AdminCap,
        self: &mut ParkingLot,
        amount: u64,
        ctx: &mut tx_context::TxContext
    ): coin::Coin<SUI> {
        assert!(tx_context::sender(ctx) == admin.admin, 101);
        coin::take(&mut self.balance, amount, ctx)
    }

    // Distribute profits of the parking lot
    public fun distribute_profits(self: &mut ParkingLot, ctx: &mut tx_context::TxContext) {
        let total_balance = balance::value(&self.balance);
        let admin_amount = total_balance;

        let admin_coin = coin::take(&mut self.balance, admin_amount, ctx);

        transfer::public_transfer(admin_coin, self.admin);
    }

    // Test function for generating slots (only for testing purposes)
    #[test_only]
    public fun test_generate_slots(ctx: &mut tx_context::TxContext) {
        // Initialize test environment
        init(ctx);
    }
}
