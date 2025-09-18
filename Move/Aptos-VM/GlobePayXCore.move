module GLOBE_CORE::GlobePayXCore {
    use std::signer;
    use std::vector;
    use std::string;
    use std::u64;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::type_info;

    /// Events
    struct TransferEvent has store, drop {
        sender: address,
        recipient: address,
        coin_type: vector<u8>, // friendly type id
        amount: u64,
        ts: u64
    }

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

    /// A resource kept under the module's account to hold EventHandles
    struct CoreEvents has key {
        transfer_handle: event::EventHandle<TransferEvent>,
        swap_handle: event::EventHandle<SwapEvent>
    }

    /// Admin state (owner)
    struct CoreAdmin has key {
        owner: address,
        swap_fee_bps: u64, // basis points: 25 = 0.25%
        swap_counter: u64
    }

    /// A pending swap request (two-step swap to avoid requiring module signer during user tx)
    struct SwapInfo has store {
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

    /// Table of swap requests keyed by swap id (stored under module account)
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
    const E_INVALID_INPUT: u64 = 16; // Added for registration checks

    /// Initialize — must be called from the module account (0xGLOBE_CORE)
    public entry fun init_module(account: &signer) {
        let module_addr = signer::address_of(account);
        // enforce that init is run by module account
        assert!(module_addr == @GLOBE_CORE, E_NOT_MODULE_ACCOUNT);
        // only init once
        assert!(!exists<CoreEvents>(module_addr), E_ALREADY_INITIALIZED);

        let transfer_h = event::new_event_handle<TransferEvent>(account);
        let swap_h = event::new_event_handle<SwapEvent>(account);
        move_to(account, CoreEvents { transfer_handle: transfer_h, swap_handle: swap_h });
        move_to(account, CoreAdmin { owner: module_addr, swap_fee_bps: 25, swap_counter: 0 });
        move_to(account, SwapRequests { requests: table::new<u64, SwapInfo>() });
    }

    /// Admin setter for fee (only module owner can call)
    public entry fun set_swap_fee_bps(account: &signer, new_bps: u64) {
        let caller = signer::address_of(account);
        let module_addr = @GLOBE_CORE;
        let admin_ref = borrow_global_mut<CoreAdmin>(module_addr);
        // restrict to admin only (owner stored in admin_ref)
        assert!(admin_ref.owner == caller, E_NOT_OWNER);
        assert!(new_bps <= 10000, E_BPS_TOO_LARGE);
        admin_ref.swap_fee_bps = new_bps;
    }

    /// P2P transfer — withdraw from caller and deposit to recipient
    /// Generic over CoinType (any coin registered on Aptos)
    public entry fun send_stablecoin<CoinType>(sender: &signer, recipient: address, amount: u64) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(coin::is_account_registered<CoinType>(recipient), E_INVALID_INPUT);

        // withdraw from sender
        let coin_obj = coin::withdraw<CoinType>(sender, amount);
        // deposit into recipient's account (module emits event from module account)
        coin::deposit<CoinType>(recipient, coin_obj);

        // Emit event
        let module_addr = @GLOBE_CORE;
        if (exists<CoreEvents>(module_addr)) {
            let evs = borrow_global_mut<CoreEvents>(module_addr);
            let ev_struct = TransferEvent {
                sender: signer::address_of(sender),
                recipient,
                coin_type: string::bytes(type_info::type_name<CoinType>()),
                amount,
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.transfer_handle, ev_struct);
        }
    }

    /*
      Swap design: two-step to avoid requiring module signer inside user's transaction.
      - User calls `swap_request` which withdraws CoinIn from user and deposits it into module account.
         It stores a SwapInfo (with computed amount_out and fee) in the module's SwapRequests table.
      - Module owner calls `execute_swap` with the swap id to perform the CoinOut payout from module account
         to the user (module owner must have or hold CoinOut liquidity at module account). This allows proper
         liquidity checks and atomic movement of CoinOut to user by an authorized signer.
    */

    /// User side: create a swap request. Withdraw CoinIn and deposit it to module address.
    public entry fun swap_request<CoinIn, CoinOut>(user: &signer, amount_in: u64, min_out: u64, rate_1e18: u128) {
        assert!(amount_in > 0, E_INVALID_AMOUNT);
        let module_addr = @GLOBE_CORE;
        assert!(coin::is_account_registered<CoinIn>(module_addr), E_INVALID_INPUT);

        // withdraw coin in from user
        let taken = coin::withdraw<CoinIn>(user, amount_in);
        // transfer coin_in into module account as liquidity (module account must hold coins for swaps)
        coin::deposit<CoinIn>(module_addr, taken);

        // compute raw out as u128 to avoid overflow
        let raw_out_128 = ((amount_in as u128) * rate_1e18) / 1000000000000000000u128;

        // fee from admin state (module owner)
        let admin_ref = borrow_global<CoreAdmin>(module_addr);
        let fee_bps = admin_ref.swap_fee_bps;
        let fee_amount_128 = (raw_out_128 * (fee_bps as u128)) / 10000u128;
        let amount_out_128 = raw_out_128 - fee_amount_128;

        // overflow safety
        assert!(amount_out_128 <= (u64::MAX as u128), E_OVERFLOW);
        assert!(fee_amount_128 <= (u64::MAX as u128), E_OVERFLOW);

        // safe conversion after check
        let amount_out = (amount_out_128 as u64);
        let fee = (fee_amount_128 as u64);

        // slippage check
        assert!(amount_out >= min_out, E_SLIPPAGE);

        // increment swap counter and record request
        let admin_ref_mut = borrow_global_mut<CoreAdmin>(module_addr);
        let swap_id = admin_ref_mut.swap_counter + 1;
        admin_ref_mut.swap_counter = swap_id;

        // prepare SwapInfo
        let info = SwapInfo {
            id: swap_id,
            user: signer::address_of(user),
            coin_in_name: string::bytes(type_info::type_name<CoinIn>()),
            coin_out_name: string::bytes(type_info::type_name<CoinOut>()),
            amount_in,
            amount_out,
            rate_1e18,
            fee,
            executed: false,
            ts: timestamp::now_seconds()
        };

        // insert into SwapRequests table
        let swaps_ref = borrow_global_mut<SwapRequests>(module_addr);
        table::add(&mut swaps_ref.requests, swap_id, info);
    }

    /// Owner side: execute a pending swap. Must be called by module owner (module account signer).
    /// This withdraws CoinOut (amount_out + fee) from the module signer and deposits amount_out to user
    /// and the fee to module treasury (module account in this design keeps the fees).
    public entry fun execute_swap<CoinIn, CoinOut>(admin: &signer, swap_id: u64) {
        let caller = signer::address_of(admin);
        let module_addr = @GLOBE_CORE;
        // require owner
        let admin_ref = borrow_global<CoreAdmin>(module_addr);
        assert!(admin_ref.owner == caller, E_NOT_OWNER);

        // fetch swap info
        let swaps_ref = borrow_global_mut<SwapRequests>(module_addr);
        assert!(table::contains(&swaps_ref.requests, swap_id), E_SWAP_NOT_FOUND);
        let info = table::remove(&mut swaps_ref.requests, swap_id);
        assert!(!info.executed, E_SWAP_ALREADY_EXECUTED);

        // ensure module (caller) has sufficient CoinOut liquidity
        let total_needed = info.amount_out + info.fee; // both u64
        assert!(coin::balance<CoinOut>(caller) >= total_needed, E_INSUFFICIENT_LIQUIDITY);
        assert!(coin::is_account_registered<CoinOut>(info.user), E_INVALID_INPUT);

        // withdraw CoinOut from the admin signer (module account) to transfer to user + fee
        let coin_out_total = coin::withdraw<CoinOut>(admin, total_needed);

        // split coin: deposit amount_out to user
        let coin_for_user = coin::split(coin_out_total, info.amount_out, @GLOBE_CORE);
        coin::deposit<CoinOut>(info.user, coin_for_user);
        // remaining in coin_out_total is fee (we'll deposit it back to module account as fee treasury)
        coin::deposit<CoinOut>(module_addr, coin_out_total);

        // emit event (using original info; executed flag not needed for event)
        if (exists<CoreEvents>(module_addr)) {
            let evs = borrow_global_mut<CoreEvents>(module_addr);
            let ev_struct = SwapEvent {
                user: info.user,
                coin_in: info.coin_in_name,
                coin_out: info.coin_out_name,
                amount_in: info.amount_in,
                amount_out: info.amount_out,
                rate_1e18: info.rate_1e18,
                fee: info.fee,
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.swap_handle, ev_struct);
        }

        // Optionally keep a record of executed swap (omitted to avoid unbounded storage). Off-chain indexers can read events.
    }

    /// Generic audit helper (emit an arbitrary module-level event)
    public entry fun emit_generic_audit(account: &signer, action: vector<u8>, data: vector<u8>) {
        // Placeholder: Expand to emit a custom event if needed
        let _ = account;
        let _ = action;
        let _ = data;
    }
}
