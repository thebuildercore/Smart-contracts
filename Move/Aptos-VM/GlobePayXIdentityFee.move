address 0xGLOBE_IDF {
module GlobePayXIdentityFee {
    use std::signer;
    use std::vector;
    use std::string;
    use std::table::Table;
    use aptos_framework::coin;
    use aptos_framework::event;

    struct IdentityRegistered has store, drop {
        wallet: address,
        username: vector<u8>,
        country: vector<u8>,
        pref_currency: vector<u8>,
        ts: u64
    }

    struct FeeCollected has store, drop {
        payer: address,
        token_type: vector<u8>,
        amount: u64,
        ts: u64
    }

    struct IdentityEvents has key {
        id_handle: event::EventHandle<IdentityRegistered>,
        fee_handle: event::EventHandle<FeeCollected>
    }

    struct IdentityStore has key {
        username_to_wallet: Table<vector<u8>, address>,
        wallet_to_meta: Table<address, (vector<u8>, vector<u8>)>
    }

    struct FeeState has key {
        flat_fee: u64,
        percent_bps: u64,
        collected_by_token: Table<vector<u8>, u64>
    }

    struct SponsorState has key {
        sponsor_to_wallet: Table<address, address>,
        sponsor_credits: Table<address, Table<vector<u8>, u64>> // sponsor -> (token -> credit)
    }

    public entry fun init(account: &signer) {
        assert!(!exists<IdentityEvents>(signer::address_of(account)), 1);
        let h1 = event::new_event_handle<IdentityRegistered>(account);
        let h2 = event::new_event_handle<FeeCollected>(account);
        move_to(account, IdentityEvents { id_handle: h1, fee_handle: h2 });

        let tbl1 = Table::new<vector<u8>, address>();
        let tbl2 = Table::new<address, (vector<u8>, vector<u8>)>();
        move_to(account, IdentityStore { username_to_wallet: tbl1, wallet_to_meta: tbl2 });

        let fee_tbl = Table::new<vector<u8>, u64>();
        move_to(account, FeeState { flat_fee: 0, percent_bps: 0, collected_by_token: fee_tbl });

        let sponsor_tbl = Table::new<address, address>();
        let sponsor_credit_tbl = Table::new<address, Table<vector<u8>, u64>>();
        move_to(account, SponsorState { sponsor_to_wallet: sponsor_tbl, sponsor_credits: sponsor_credit_tbl });
    }

    /// Register an alias for an on-chain wallet
    public entry fun register_alias(user: &signer, username: vector<u8>, country: vector<u8>, pref_currency: vector<u8>) {
        let caller = signer::address_of(user);
        let idx_addr = signer::address_of(user); // identity store is under owner for simplicity
        let store_ref = borrow_global_mut<IdentityStore>(idx_addr);
        let existing = Table::get(&store_ref.username_to_wallet, username);
        assert!(option::is_none(&existing) || option::is_some(&existing) && option::borrow(&existing) == &caller, 10);
        Table::insert(&mut store_ref.username_to_wallet, username, caller);
        Table::insert(&mut store_ref.wallet_to_meta, caller, (country, pref_currency));

        // emit event
        let evs_addr = @0xGLOBE_IDF;
        if (exists<IdentityEvents>(evs_addr)) {
            let evs = borrow_global_mut<IdentityEvents>(evs_addr);
            let ev = IdentityRegistered { wallet: caller, username, country, pref_currency, ts: aptos_framework::timestamp::now_seconds() };
            event::emit_event(&mut evs.id_handle, ev);
        }
    }

    /// Admin: set fee policy
    public entry fun set_fees(admin: &signer, flat_fee: u64, percent_bps: u64) {
        let addr = signer::address_of(admin);
        // only admin (account that holds FeeState) can call — simplified: require same address
        let fs = borrow_global_mut<FeeState>(addr);
        assert!(percent_bps <= 10000, 20);
        fs.flat_fee = flat_fee;
        fs.percent_bps = percent_bps;
    }

    /// Called by other modules to record a fee (the tokens should already be transferred to this module's custody)
    public entry fun record_fee(admin: &signer, token_id: vector<u8>, amount: u64) {
        let addr = signer::address_of(admin);
        let mut fs = borrow_global_mut<FeeState>(addr);
        let prev = Table::get(&fs.collected_by_token, token_id);
        if (option::is_some(&prev)) {
            let current = *option::borrow(&prev);
            Table::insert(&mut fs.collected_by_token, token_id, current + amount);
        } else {
            Table::insert(&mut fs.collected_by_token, token_id, amount);
        }

        // emit event
        let evs_addr = @0xGLOBE_IDF;
        if (exists<IdentityEvents>(evs_addr)) {
            let evs = borrow_global_mut<IdentityEvents>(evs_addr);
            let ev = FeeCollected { payer: signer::address_of(admin), token_type: token_id, amount, ts: aptos_framework::timestamp::now_seconds() };
            event::emit_event(&mut evs.fee_handle, ev);
        }
    }

    /// Sponsor management: register sponsor -> wallet mapping (admin only)
    public entry fun register_sponsor(admin: &signer, sponsor: address, sponsor_wallet: address) {
        let addr = signer::address_of(admin);
        let ss = borrow_global_mut<SponsorState>(addr);
        Table::insert(&mut ss.sponsor_to_wallet, sponsor, sponsor_wallet);
    }

    /// Credit sponsor: sponsor_wallet calls to credit sponsor account by providing coin tokens (coins must be transferred to module)
    public entry fun credit_sponsor(sponsor_wallet_signer: &signer, sponsor: address, token_id: vector<u8>, amount: u64) {
        let caller = signer::address_of(sponsor_wallet_signer);
        let ss_addr = signer::address_of(sponsor_wallet_signer); // simplified ownership model
        let ss = borrow_global_mut<SponsorState>(ss_addr);
        let mapped = Table::get(&ss.sponsor_to_wallet, sponsor);
        assert!(option::is_some(&mapped) && *option::borrow(&mapped) == caller, 30);

        let inner = Table::get(&ss.sponsor_credits, sponsor);
        if (option::is_some(&inner)) {
            let credits_table = option::borrow_mut(&inner);
            let prev = Table::get(credits_table, token_id);
            if (option::is_some(&prev)) {
                let p = *option::borrow(&prev);
                Table::insert(credits_table, token_id, p + amount);
            } else {
                Table::insert(credits_table, token_id, amount);
            }
        } else {
            let new_table = Table::new<vector<u8>, u64>();
            Table::insert(&mut new_table, token_id, amount);
            Table::insert(&mut ss.sponsor_credits, sponsor, new_table);
        }
    }

    // Sponsor withdraw etc. omitted for brevity; same pattern as credit

}
}
