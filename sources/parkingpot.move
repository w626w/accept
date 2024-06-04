module parkinglot::parkinglot {
    use sui::coin;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::clock::{Clock, timestamp_ms};
    use sui::coin::Coin;
    use sui::tx_context::sender;


    const EParkingSlotNotAvailable: u64 = 2;
    const EParkingSlotNotOccupied: u64 = 3;
    const ENotAdmin: u64 = 101;

    public struct Slot has key, store {
        id: UID,
        status: bool,
        start_time: u64,
        end_time: u64,
        current_user: address,
    }

    public struct ParkingLot has key, store {
        id: UID,
        admin: address,
        slots: vector<Slot>,
        balance: Balance<SUI>,
        total_profits: u64,
    }

    public struct PaymentRecord has key, store {
        id: UID,
        amount: u64,
        payment_time: u64,
        user: address,
    }

    public struct AdminCap has key, store {
        id: UID,
        admin: address,
    }

    // Initialize the parking lot and the admin
    fun init(ctx: &mut tx_context::TxContext) {
        let admin_address = tx_context::sender(ctx);
        let admin_cap = AdminCap {
            id: object::new(ctx),
            admin: admin_address,
        };
        transfer::public_transfer(admin_cap, admin_address);

        let parking_lot = ParkingLot {
            id: object::new(ctx),
            admin: admin_address,
            slots: vector::empty(),
            balance: balance::zero(),
            total_profits: 0,
        };
        transfer::public_transfer(parking_lot, admin_address);
    }

    // Create a new parking slot
    public fun create_slot(admin_cap: &AdminCap, ctx: &mut tx_context::TxContext, parking_lot: &mut ParkingLot) {
        assert!(admin_cap.admin == tx_context::sender(ctx), ENotAdmin);
        let new_slot = Slot {
            id: object::new(ctx),
            status: false,
            start_time: 0,
            end_time: 0,
            current_user:@0x0,
        };
        vector::push_back(&mut parking_lot.slots, new_slot);
    }

    // Reserve a parking slot
    public fun reserve_slot(slot: &mut Slot) {
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
    }

    // Enter a parking slot
    public fun enter_slot(slot: &mut Slot, clock: &Clock, user:address){
        assert!(!slot.status, EParkingSlotNotAvailable);
        slot.status = true;
        slot.start_time = timestamp_ms(clock);
        slot.current_user= user;
    }

    // Exit a parking slot
    public entry fun exit_slot(slot: &mut Slot, clock: &Clock, base_rate: u64, parking_lot: &mut ParkingLot,coin:&mut Coin<SUI>,ctx: &mut TxContext) {
        assert!(slot.status, EParkingSlotNotOccupied);
        let current_user = slot.current_user;
        assert!(current_user == sender(ctx) , EParkingSlotNotOccupied);

        slot.end_time = timestamp_ms(clock);

        let parking_fee = calculate_parking_fee(slot.start_time, slot.end_time, base_rate);

        let current_userBalance=coin::balance_mut(coin);
        let payment_coin = coin::take( current_userBalance, parking_fee, ctx);
        coin::put(&mut parking_lot.balance, payment_coin);

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
    public fun calculate_parking_fee(start_time: u64, end_time: u64, base_rate: u64): u64 {
        let duration = (end_time - start_time) / 3600000; // Convert to hours
        duration * base_rate
    }

    // Withdraw profits, all profits are transferred to the admin address, can be modified as needed
    public fun withdraw_profits(
        admin: &AdminCap,
        self: &mut ParkingLot,
        amount: u64,
        ctx: &mut tx_context::TxContext
    ): coin::Coin<SUI> {
        assert!(sender(ctx) == admin.admin, ENotAdmin);
        coin::take(&mut self.balance, amount, ctx)
    }

    // Distribute profits, the distribution plan can be modified as needed
    public fun distribute_profits(self: &mut ParkingLot, ctx: &mut tx_context::TxContext) {
        assert!(sender(ctx) == self.admin, ENotAdmin);
        let total_balance = balance::value(&self.balance);
        let admin_amount = total_balance;

        let admin_coin = coin::take(&mut self.balance, admin_amount, ctx);

        transfer::public_transfer(admin_coin, self.admin);
    }

    // Test function to generate parking slots (for testing purposes only)
    #[test_only]
    public fun test_generate_slots(ctx: &mut tx_context::TxContext) {
        init(ctx);
    }
}
