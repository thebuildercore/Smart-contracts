address 0xGLOBE_CORE {
module GlobePayXCore {
    use std::signer;
    use std::vector;
    use std::string;
    use std::table::{Table};
    use aptos_framework::coin;
    use aptos_framework::event;

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
        swap_fee_bps: u64 // basis points: 25 = 0.25%
    }

    /// Initialize — call once from module owner address to create events and admin
    public entry fun init_module(account: &signer, owner: address) {
        // only init once
        assert!(!exists<CoreEvents>(signer::address_of(account)), 1);
        let transfer_h = event::new_event_handle<TransferEvent>(account);
        let swap_h = event::new_event_handle<SwapEvent>(account);
        move_to(account, CoreEvents { transfer_handle: transfer_h, swap_handle: swap_h });
        move_to(account, CoreAdmin { owner, swap_fee_bps: 25 });
    }

    /// Admin setter for fee
    public entry fun set_swap_fee_bps(account: &signer, new_bps: u64) {
        let addr = signer::address_of(account);
        let admin_ref = borrow_global_mut<CoreAdmin>(addr);
        // restrict to admin only
        assert!(admin_ref.owner == addr, 2);
        assert!(new_bps <= 10000, 3);
        admin_ref.swap_fee_bps = new_bps;
    }

    /// P2P transfer — withdraw from caller and deposit to recipient
    /// Generic over CoinType (any coin registered on Aptos)
    public entry fun send_stablecoin<CoinType>(sender: &signer, recipient: address, amount: u64) {
        assert!(amount > 0, 4);
        let recipient_addr = recipient;
        // withdraw from sender
        let coin_obj = coin::withdraw<CoinType>(sender, amount);
        // deposit into recipient's account
        coin::deposit<CoinType>(recipient_addr, coin_obj);

        // Emit event
        let module_addr = @0xGLOBE_CORE;
        if (exists<CoreEvents>(module_addr)) {
            let ev = borrow_global_mut<CoreEvents>(module_addr);
            let ev_struct = TransferEvent {
                sender: signer::address_of(sender),
                recipient: recipient_addr,
                coin_type: vector::empty<u8>(), // optional: fill via type info
                amount,
                ts: aptos_framework::timestamp::now_seconds()
            };
            event::emit_event(&mut ev.transfer_handle, ev_struct);
        }
    }

    /// Swap coin A -> coin B using a given rate parameter.
    /// rate_1e18: amount_out_before_fee = amount_in * rate_1e18 / 1e18
    /// Caller must approve / have amount in their account; function withdraws from caller
    public entry fun swap<CoinIn, CoinOut>(user: &signer, amount_in: u64, min_out: u64, rate_1e18: u128) {
        assert!(amount_in > 0, 10);
        // withdraw coin in from user
        let taken = coin::withdraw<CoinIn>(user, amount_in);

        // compute raw out as u128 to avoid overflow
        let raw_out_128 = (u128::from(amount_in) * rate_1e18) / 1000000000000000000u128;
        // fee from admin state (module owner)
        let module_addr = @0xGLOBE_CORE;
        let admin_ref = borrow_global<CoreAdmin>(module_addr);
        let fee_bps = admin_ref.swap_fee_bps;
        let fee_amount_128 = (raw_out_128 * u128::from(fee_bps)) / 10000u128;
        let amount_out_128 = raw_out_128 - fee_amount_128;
        let amount_out = u64::try_from(amount_out_128).expect("overflow amount_out");

        assert!(amount_out >= min_out, 11);

        // For demonstration: deposit CoinOut into user
        // IMPORTANT: this assumes module (or some liquidity holder) owns sufficient CoinOut balance.
        // For a simple path we deposit from module account to user.
        // So module should hold liquidity for CoinOut.
        // First, module withdraws coinOut from its own holdings:
        let module_signer = &signer::borrow_address(&module_addr); // pseudocode: you will call this transaction from module account or use resource account pattern
        // In practice you would transfer the module-owned CoinOut to user; here we use coin::deposit
        // NOTE: aptos requires the module to call deposit with an actual coin value. For clarity, we'll assume the module had previously deposited "liquidity" in a resource we can withdraw; here we omit low-level liquidity management.
        // For now: deposit raw_out (minus fee) into user using a placeholder:
        coin::deposit<CoinOut>(signer::address_of(user), coin::zero<CoinOut>());

        // record fee: store fee under module for later withdrawal (omitted depositing actual fee coins in this simplified flow)

        // emit swap event
        if (exists<CoreEvents>(module_addr)) {
            let ev = borrow_global_mut<CoreEvents>(module_addr);
            let ev_struct = SwapEvent {
                user: signer::address_of(user),
                coin_in: vector::empty<u8>(),
                coin_out: vector::empty<u8>(),
                amount_in,
                amount_out,
                rate_1e18,
                fee: u64::try_from(fee_amount_128).unwrap_or(0),
                ts: aptos_framework::timestamp::now_seconds()
            };
            event::emit_event(&mut ev.swap_handle, ev_struct);
        }
    }

    /// Generic audit helper (emit an arbitrary module-level event)
    public entry fun emit_generic_audit(account: &signer, action: vector<u8>, data: vector<u8>) {
        // For small utilities; see docs for how to implement module-level generic events
        // left as a placeholder: Aptos supports many ways to log; prefer structured events above
        let _ = action;
        let _ = data;
    }
}
}
