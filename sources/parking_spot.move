module parking_spot::parking_spot {
    use sui::coin;
    use sui::balance;
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};

    // Error codes
    const EParkingSlotNotAvailable: u64 = 2;
    const EUnauthorizedAccess: u64 = 3;
    const ESlotNotFound: u64 = 4;
    const EInsufficientFunds: u64 = 5;

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
    public fun init(ctx: &mut tx_context::TxContext) {
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
        assert!(admin_cap.admin == parking_lot.admin, EUnauthorizedAccess); // Ensure caller is an administrator
        let new_slot = Slot {
            id: object::new(ctx),
            status: false,
            start_time: 0,
            end_time: 0,
        };
        vector::push_back(&mut parking_lot.slots, new_slot);
    }

    // Reserve a parking slot
    public fun reserve_slot(parking_lot: &mut ParkingLot, slot_id: UID) {
        let index = find_slot_index(&parking_lot.slots, slot_id);
        let slot = &mut vector::borrow_mut(&mut parking_lot.slots, index);
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
    }

    // Occupy a parking slot
    public fun enter_slot(slot: &mut Slot, clock: &Clock) {
        assert!(!slot.status, EParkingSlotNotAvailable); // Ensure slot is not occupied
        slot.status = true;
        slot.start_time = timestamp_ms(clock); // Record start time
    }

    // Vacate a parking slot
    public fun exit_slot(slot: &mut Slot, clock: &Clock, parking_lot: &mut ParkingLot, rate: u64, ctx: &mut tx_context::TxContext) {
        assert!(slot.status, EParkingSlotNotAvailable); // Ensure slot is occupied
        slot.status = false;
        slot.end_time = timestamp_ms(clock); // Record end time

        // Calculate and collect parking fee
        let fee = calculate_parking_fee(slot.start_time, slot.end_time, rate, false);
        let payment_record = create_payment_record(fee, ctx, clock);
        balance::add(&mut parking_lot.balance, fee);
        transfer::public_transfer(payment_record, tx_context::sender(ctx));
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
        assert!(tx_context::sender(ctx) == admin.admin, EUnauthorizedAccess);
        assert!(balance::value(&self.balance) >= amount, EInsufficientFunds);
        let coin = coin::take(&mut self.balance, amount, ctx);
        transfer::public_transfer(coin, admin.admin);
        coin
    }

    // Distribute profits of the parking lot
    public fun distribute_profits(self: &mut ParkingLot, ctx: &mut tx_context::TxContext) {
        let total_balance = balance::value(&self.balance);
        let admin_amount = total_balance;

        let admin_coin = coin::take(&mut self.balance, admin_amount, ctx);

        transfer::public_transfer(admin_coin, self.admin);
    }

    // Find a slot index by its UID
    public fun find_slot_index(slots: &vector<Slot>, slot_id: UID): u64 {
        let len = vector::length(slots);
        let mut i = 0;
        while (i < len) {
            let slot = &vector::borrow(slots, i);
            if (slot.id == slot_id) {
                return i;
            }
            i = i + 1;
        }
        assert!(false, ESlotNotFound);
        0
    }

    // Get parking lot information
    public fun get_parking_lot_info(parking_lot: &ParkingLot): (UID, address, u64) {
        (parking_lot.id, parking_lot.admin, balance::value(&parking_lot.balance))
    }

    // Get slot information
    public fun get_slot_info(slot: &Slot): (UID, bool, u64, u64) {
        (slot.id, slot.status, slot.start_time, slot.end_time)
    }

    // Test function for generating slots (only for testing purposes)
    #[test_only]
    public fun test_generate_slots(ctx: &mut tx_context::TxContext) {
        // Initialize test environment
        init(ctx);
    }
}