module GLOBE_CORE::GlobePayXCore {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use std::type_info;

    /// Maximum u64 value as u128 for overflow checks
    const U64_MAX: u128 = 18446744073709551615;

    #[event]
    struct TransferEvent has store, drop {
        sender: address,
        recipient: address,
        coin_type: vector<u8>,
        amount: u64,
        ts: u64
    }

    #[event]
    struct SwapEvent has store, drop {
        user: address,
        coin_in: vector<u8>,
        coin_out: vector<u8>,
        amount_in: u64,
        amount_out: u64,
        rate_1e18: u128,
        fee: u64,
        ts: u64
    }

    #[event]
    struct AuditEvent has store, drop {
        caller: address,
        action: vector<u8>,
        data: vector<u8>,
        ts: u64
    }

    struct CoreAdmin has key {
        owner: address,
        swap_fee_bps: u64,
        swap_counter: u64
    }

    struct SwapInfo has store, drop {
        id: u64,
        user: address,
        coin_in_name: vector<u8>,
        coin_out_name: vector<u8>,
        amount_in: u64,
        amount_out: u64,
        rate_1e18: u128,
        fee: u64,
        executed: bool,
        ts: u64
    }

    struct SwapRequests has key {
        requests: Table<u64, SwapInfo>
    }

    // --------- Errors ---------
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_NOT_MODULE_ACCOUNT: u64 = 2;
    const E_BPS_TOO_LARGE: u64 = 3;
    const E_INVALID_AMOUNT: u64 = 4;
    const E_OVERFLOW: u64 = 10;
    const E_SLIPPAGE: u64 = 11;
    const E_NOT_OWNER: u64 = 12;
    const E_SWAP_NOT_FOUND: u64 = 13;
    const E_SWAP_ALREADY_EXECUTED: u64 = 14;
    const E_INSUFFICIENT_LIQUIDITY: u64 = 15;
    const E_INVALID_INPUT: u64 = 16;

    // --------- Helper functions ---------
    fun vec_clone(v: &vector<u8>): vector<u8> {
        let result = vector::empty<u8>();
        let len = vector::length(v);
        let i = 0;
        while (i < len) {
            vector::push_back(&mut result, *vector::borrow(v, i));
            i = i + 1;
        };
        result
    }

    fun init_module(account: &signer) {
        let module_addr = signer::address_of(account);
        assert!(module_addr == @GLOBE_CORE, E_NOT_MODULE_ACCOUNT);
        assert!(!exists<CoreAdmin>(module_addr), E_ALREADY_INITIALIZED);

        move_to(account, CoreAdmin { 
            owner: module_addr, 
            swap_fee_bps: 25, 
            swap_counter: 0 
        });
        move_to(account, SwapRequests { 
            requests: table::new<u64, SwapInfo>() 
        });
    }

    public entry fun set_swap_fee_bps(account: &signer, new_bps: u64) acquires CoreAdmin {
        let caller = signer::address_of(account);
        let module_addr = @GLOBE_CORE;
        let admin_ref = borrow_global_mut<CoreAdmin>(module_addr);
        assert!(admin_ref.owner == caller, E_NOT_OWNER);
        assert!(new_bps <= 10000, E_BPS_TOO_LARGE);
        admin_ref.swap_fee_bps = new_bps;
    }

    public entry fun send_stablecoin<CoinType>(
        sender: &signer, 
        recipient: address, 
        amount: u64
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(coin::is_account_registered<CoinType>(recipient), E_INVALID_INPUT);

        let coin_obj = coin::withdraw<CoinType>(sender, amount);
        coin::deposit<CoinType>(recipient, coin_obj);

        // Emit event using new event system
        event::emit(TransferEvent {
            sender: signer::address_of(sender),
            recipient,
            coin_type: *string::bytes(&type_info::type_name<CoinType>()),
            amount,
            ts: timestamp::now_seconds()
        });
    }

    public entry fun swap_request<CoinIn, CoinOut>(
        user: &signer, 
        amount_in: u64, 
        min_out: u64, 
        rate_1e18: u128
    ) acquires CoreAdmin, SwapRequests {
        assert!(amount_in > 0, E_INVALID_AMOUNT);
        let module_addr = @GLOBE_CORE;
        assert!(coin::is_account_registered<CoinIn>(module_addr), E_INVALID_INPUT);

        let taken = coin::withdraw<CoinIn>(user, amount_in);
        coin::deposit<CoinIn>(module_addr, taken);

        let raw_out_128 = ((amount_in as u128) * rate_1e18) / 1000000000000000000u128;

        let admin_ref = borrow_global<CoreAdmin>(module_addr);
        let fee_bps = admin_ref.swap_fee_bps;
        let fee_amount_128 = (raw_out_128 * (fee_bps as u128)) / 10000u128;
        let amount_out_128 = raw_out_128 - fee_amount_128;

        assert!(amount_out_128 <= U64_MAX, E_OVERFLOW);
        assert!(fee_amount_128 <= U64_MAX, E_OVERFLOW);

        let amount_out = amount_out_128 as u64;
        let fee = fee_amount_128 as u64;

        assert!(amount_out >= min_out, E_SLIPPAGE);

        let admin_ref_mut = borrow_global_mut<CoreAdmin>(module_addr);
        let swap_id = admin_ref_mut.swap_counter + 1;
        admin_ref_mut.swap_counter = swap_id;

        let info = SwapInfo {
            id: swap_id,
            user: signer::address_of(user),
            coin_in_name: *string::bytes(&type_info::type_name<CoinIn>()),
            coin_out_name: *string::bytes(&type_info::type_name<CoinOut>()),
            amount_in,
            amount_out,
            rate_1e18,
            fee,
            executed: false,
            ts: timestamp::now_seconds()
        };

        let swaps_ref = borrow_global_mut<SwapRequests>(module_addr);
        table::add(&mut swaps_ref.requests, swap_id, info);
    }

    public entry fun execute_swap<CoinIn, CoinOut>(
        admin: &signer, 
        swap_id: u64
    ) acquires CoreAdmin, SwapRequests {
        let caller = signer::address_of(admin);
        let module_addr = @GLOBE_CORE;
        let admin_ref = borrow_global<CoreAdmin>(module_addr);
        assert!(admin_ref.owner == caller, E_NOT_OWNER);

        let swaps_ref = borrow_global_mut<SwapRequests>(module_addr);
        assert!(table::contains(&swaps_ref.requests, swap_id), E_SWAP_NOT_FOUND);
        let info = table::remove(&mut swaps_ref.requests, swap_id);
        assert!(!info.executed, E_SWAP_ALREADY_EXECUTED);

        let total_needed = info.amount_out + info.fee;
        assert!(coin::balance<CoinOut>(caller) >= total_needed, E_INSUFFICIENT_LIQUIDITY);
        assert!(coin::is_account_registered<CoinOut>(info.user), E_INVALID_INPUT);

        // Withdraw the total amount needed
        let coin_out_total = coin::withdraw<CoinOut>(admin, total_needed);
        
        // Extract the user's portion
        let coin_for_user = coin::extract(&mut coin_out_total, info.amount_out);
        coin::deposit<CoinOut>(info.user, coin_for_user);
        
        // Deposit the fee to module account
        coin::deposit<CoinOut>(module_addr, coin_out_total);

        // Emit event
        event::emit(SwapEvent {
            user: info.user,
            coin_in: vec_clone(&info.coin_in_name),
            coin_out: vec_clone(&info.coin_out_name),
            amount_in: info.amount_in,
            amount_out: info.amount_out,
            rate_1e18: info.rate_1e18,
            fee: info.fee,
            ts: timestamp::now_seconds()
        });
    }

    public entry fun emit_generic_audit(
        account: &signer, 
        action: vector<u8>, 
        data: vector<u8>
    ) {
        event::emit(AuditEvent {
            caller: signer::address_of(account),
            action: vec_clone(&action),
            data: vec_clone(&data),
            ts: timestamp::now_seconds()
        });
    }

    // --------- View functions ---------
    #[view]
    public fun get_swap_fee_bps(): u64 acquires CoreAdmin {
        let admin = borrow_global<CoreAdmin>(@GLOBE_CORE);
        admin.swap_fee_bps
    }

    #[view]
    public fun get_swap_counter(): u64 acquires CoreAdmin {
        let admin = borrow_global<CoreAdmin>(@GLOBE_CORE);
        admin.swap_counter
    }

    #[view]
    public fun get_swap_info(swap_id: u64): (address, u64, u64, u128, u64, bool) acquires SwapRequests {
        let swaps = borrow_global<SwapRequests>(@GLOBE_CORE);
        if (table::contains(&swaps.requests, swap_id)) {
            let info = table::borrow(&swaps.requests, swap_id);
            (info.user, info.amount_in, info.amount_out, info.rate_1e18, info.fee, info.executed)
        } else {
            (@0x0, 0, 0, 0, 0, false)
        }
    }

    #[view]
    public fun is_owner(addr: address): bool acquires CoreAdmin {
        let admin = borrow_global<CoreAdmin>(@GLOBE_CORE);
        admin.owner == addr
    }
}
