module parkinglot::parkinglot {
    use sui::coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};
    use sui::coin::Coin;
    use sui::tx_context::sender;

    // Define error codes
    const EParkingSlotNotAvailable: u64 = 2;
    const EParkingSlotNotOccupied: u64 = 3;
    const ENotAdmin: u64 = 101;
    const ENotMony: u64 = 888;

    // Define the Slot structure
    public struct Slot has key, store {
        id: UID,
        status: bool,
        start_time: u64,
        end_time: u64,
        current_user: address,
        ownerAddress: address,
        slot_profits: u64,
    }

    // Define the ParkingLot structure
    public struct ParkingLot has key, store {
        id: UID,
        admin: address,
        slots: vector<Slot>,
        balance: Balance<SUI>,
        total_profits: u64,
    }

    // Define the PaymentRecord structure
    public struct PaymentRecord has key, store {
        id: UID,
        amount: u64,
        payment_time: u64,
        user: address,
    }

    // Define the AdminCap structure
    public struct AdminCap has key, store {
        id: UID,
        admin: address,
    }

    // Initialize the parking lot and the admin
    fun init(ctx: &mut tx_context::TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
            admin: ctx.sender(),
        };
        transfer::public_transfer(admin_cap, ctx.sender());

        let parking_lot = ParkingLot {
            id: object::new(ctx),
            admin: ctx.sender(),
            slots: vector::empty(),
            balance: balance::zero(),
            total_profits: 0,
        };
        transfer::share_object(parking_lot);
    }

    // Create a new parking slot
    public fun create_slot(_: &AdminCap, ctx: &mut TxContext, parking_lot: &mut ParkingLot, owner: address) {

        let new_slot = Slot {
            id: object::new(ctx),
            status: false,
            start_time: 0,
            end_time: 0,
            current_user: @0x0,
            ownerAddress: owner,
            slot_profits: 0,
        };
        vector::push_back(&mut parking_lot.slots, new_slot);
    }

    // Reserve a parking slot
    public fun reserve_slot(slot: &mut Slot, clock: &Clock, user: address) {
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
        slot.start_time = timestamp_ms(clock) + 4 * 3600000; // Reserve the slot for 4 hours later
        slot.current_user = user;
    }

    // Enter a parking slot
    public fun enter_slot(slot: &mut Slot, clock: &Clock, user: address) {
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
        slot.start_time = timestamp_ms(clock);
        slot.current_user = user;
    }

    // Exit a parking slot
    public entry fun exit_slot(slot: &mut Slot, clock: &Clock, parking_lot: &mut ParkingLot, coin: &mut Coin<SUI>, ctx: &mut tx_context::TxContext) {
        assert!(slot.status, EParkingSlotNotOccupied);
        let current_user = slot.current_user;
        assert!(current_user == sender(ctx), EParkingSlotNotOccupied);

        slot.end_time = timestamp_ms(clock);

        let parking_fee = calculate_parking_fee(slot.start_time, slot.end_time);

        let current_user_balance = coin::balance_mut(coin);
        let payment_coin = coin::take(current_user_balance, parking_fee, ctx);

        coin::put(&mut parking_lot.balance, payment_coin); // Put into the parking lot balance

        slot.slot_profits = slot.slot_profits + parking_fee; // Save the slot's profits

        let payment_record = create_payment_record(
            parking_fee,
            timestamp_ms(clock),
            slot.current_user,
            ctx
        );
        transfer::public_transfer(payment_record, parking_lot.admin);

        slot.status = false;
        slot.current_user = @0x0; // Clear the current user address

        parking_lot.total_profits = parking_lot.total_profits + parking_fee;
    }

    // Create a payment record
    public fun create_payment_record(
        amount: u64,
        payment_time: u64,
        user: address,
        ctx: &mut tx_context::TxContext
    ): PaymentRecord {
        let id_ = object::new(ctx);
        PaymentRecord {
            id: id_,
            amount,
            payment_time,
            user,
        }
    }

    // Calculate the parking fee
    public fun calculate_parking_fee(start_time: u64, end_time: u64): u64 {
        let duration = (end_time - start_time) / 3600000; // Convert to hours
        let base_rate: u64;

        if (duration >= 0 && duration < 10) {
            base_rate = 3;
        } else if (duration >= 10 && duration < 100) {
            base_rate = 2;
        } else {
            base_rate = 1;
        };

        duration * base_rate
    }

    // Withdraw profits, all profits are transferred to the admin address, can be modified as needed
    public fun withdraw_profits(
        admin: &AdminCap,
        self: &mut ParkingLot,
        amount: u64,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(sender(ctx) == admin.admin, ENotAdmin);
        assert!(amount < self.total_profits / 10, ENotMony);
        let question = coin::take(&mut self.balance, amount, ctx); // In case of emergency, the admin can withdraw up to 10% of the total funds
        transfer::public_transfer(question, admin.admin);

        self.total_profits = self.total_profits - amount; // Only update the total balance, individual slot balances remain unchanged
    }

    // Distribute profits, the distribution plan can be modified as needed
    public fun distribute_profits(adminpull: &mut ParkingLot, slotowner: &mut Slot, ctx: &mut tx_context::TxContext) {
        assert!(sender(ctx) == slotowner.ownerAddress, ENotAdmin);
        let total_balance = balance::value(&adminpull.balance);
        let admin_amount = total_balance / 10;
        let owner_amount = total_balance * 8 / 10;

        let admin_coin = coin::take(&mut adminpull.balance, admin_amount, ctx); // Admin takes 10% of the profits
        transfer::public_transfer(admin_coin, adminpull.admin);

        let owner_coin = coin::take(&mut adminpull.balance, owner_amount, ctx); // Slot owner takes 80% of the profits
        transfer::public_transfer(owner_coin, slotowner.ownerAddress);

        adminpull.total_profits = adminpull.total_profits - slotowner.slot_profits * 9 / 10;
        slotowner.slot_profits = slotowner.slot_profits / 10; // Calculate the remaining profits
    }

    // Test function to generate parking slots (for testing purposes only)
    #[test_only]
    public fun test_generate_slots(ctx: &mut tx_context::TxContext) {
        init(ctx);
    }
}
