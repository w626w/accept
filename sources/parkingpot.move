module parkinglot::parkinglot {
    use sui::coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};
    use sui::coin::Coin;
    use sui::tx_context::sender;
    use sui::table::{Self, Table};

    // Define error codes
    const EParkingSlotNotAvailable: u64 = 2;

    // Define the Slot structure
    public struct Slot has key, store {
        id: UID,
        status: bool,
        seed_num: u8,
        start_time: u64,
        end_time: u64,
        current_user: address,
    }

    // Define the ParkingLot structure
    public struct ParkingLot has key, store {
        id: UID,
        admin: address,
        slots: Table<u8, address>,
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
            slots: table::new(ctx),
            balance: balance::zero(),
            total_profits: 0,
        };
        transfer::share_object(parking_lot);
    }

    // Reserve a parking slot
    public fun reserve_slot(self: &mut ParkingLot, seed_num_: u8, c: &Clock, ctx: &mut TxContext) : Slot {
        assert!(seed_num_ > 0, EParkingSlotNotAvailable);
        // reserve the slot from table 
        table::add(&mut self.slots, seed_num_, ctx.sender());

        let slot = Slot {
            id: object::new(ctx),
            status: true,
            seed_num: seed_num_,
            start_time: timestamp_ms(c) + 4 * 3600000,
            end_time:0,
            current_user: ctx.sender()
        };
        slot
    }

    // Exit a parking slot
    public entry fun exit_slot(slot: Slot, c: &Clock, self: &mut ParkingLot, coin: &mut Coin<SUI>, ctx: &mut TxContext) {

        let parking_fee = calculate_parking_fee(slot.start_time, timestamp_ms(c));
        let current_user_balance = coin::balance_mut(coin);
        let payment_coin = coin::take(current_user_balance, parking_fee, ctx);

        coin::put(&mut self.balance, payment_coin); // Put into the parking lot balance

        let payment_record = create_payment_record(
            parking_fee,
            timestamp_ms(c),
            slot.current_user,
            ctx
        );
        transfer::public_transfer(payment_record, self.admin);
        self.total_profits = self.total_profits + parking_fee;

        table::remove(&mut self.slots, slot.seed_num);
        destroye_slot(slot);
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
        _: &AdminCap,
        self: &mut ParkingLot,
        amount: u64,
        ctx: &mut TxContext
    ) : Coin<SUI> {
        let coin_ = coin::take(&mut self.balance, amount, ctx); // In case of emergency, the admin can withdraw up to 10% of the total funds
        self.total_profits = self.total_profits - amount; // Only update the total balance, individual slot balances remain unchanged
        coin_
    }

    // Test function to generate parking slots (for testing purposes only)
    #[test_only]
    public fun test_generate_slots(ctx: &mut tx_context::TxContext) {
        init(ctx);
    }

    fun destroye_slot(self: Slot) {
        let Slot {
            id,
            status: _,
            seed_num: _,
            start_time: _,
            end_time: _,
            current_user: _
        } = self;
        object::delete(id);
    }
}
