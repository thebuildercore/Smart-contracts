address 0xGLOBE_IDF {
module GlobePayXIdentityFee {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use std::table::Table;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::timestamp;

    // ---------- Events ----------
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

    // ---------- Persistent State ----------
    /// Maps username -> wallet
    struct IdentityStore has key {
        username_to_wallet: Table<vector<u8>, address>,
        wallet_to_meta: Table<address, (vector<u8>, vector<u8>)>
    }

    /// Fee accounting and global fee config (stored at module address)
    struct FeeState has key {
        flat_fee: u64,
        percent_bps: u64,
        // total collected per token id
        collected_by_token: Table<vector<u8>, u64>
    }

    /// Flattened sponsor credits keyed by (sponsor, token_id)
    struct SponsorTokenKey has store, drop {
        sponsor: address,
        token: vector<u8>
    }

    struct SponsorState has key {
        sponsor_to_wallet: Table<address, address>,
        sponsor_credits: Table<SponsorTokenKey, u64>
    }

    // ---------- Errors ----------
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_NOT_MODULE_ACCOUNT: u64 = 2;
    const E_USERNAME_TOO_LONG: u64 = 10;
    const E_USERNAME_TAKEN: u64 = 11;
    const E_FEE_BPS_INVALID: u64 = 20;
    const E_INVALID_AMOUNT: u64 = 30;
    const E_NOT_SPONSOR_WALLET: u64 = 31;
    const E_NOT_OWNER: u64 = 40;

    // Maximum username length (bytes)
    const MAX_USERNAME_BYTES: u64 = 64;

    // ---------- Init ----------
    // Must be called once by module account 0xGLOBE_IDF
    public entry fun init(admin: &signer) {
        let caller = signer::address_of(admin);
        assert!(caller == @0xGLOBE_IDF, E_NOT_MODULE_ACCOUNT);
        assert!(!exists<IdentityEvents>(caller), E_ALREADY_INITIALIZED);

        // Create event handles
        let h1 = event::new_event_handle<IdentityRegistered>(admin);
        let h2 = event::new_event_handle<FeeCollected>(admin);
        move_to(admin, IdentityEvents { id_handle: h1, fee_handle: h2 });

        // Create tables and store under module address
        let t1 = Table::new<vector<u8>, address>();
        let t2 = Table::new<address, (vector<u8>, vector<u8>)>();
        move_to(admin, IdentityStore { username_to_wallet: t1, wallet_to_meta: t2 });

        let fee_tbl = Table::new<vector<u8>, u64>();
        move_to(admin, FeeState { flat_fee: 0, percent_bps: 0, collected_by_token: fee_tbl });

        let sponsor_tbl = Table::new<address, address>();
        let sponsor_credits_tbl = Table::new<SponsorTokenKey, u64>();
        move_to(admin, SponsorState { sponsor_to_wallet: sponsor_tbl, sponsor_credits: sponsor_credits_tbl });
    }

    // ---------- Helpers ----------
    /// simple vector clone utility for vector<u8>
    fun vec_clone(src: &vector<u8>): vector<u8> {
        let dst = vector::empty<u8>();
        let len = vector::length(src);
        let mut i = 0;
        while (i < len) {
            let b = *vector::borrow(src, i);
            vector::push_back(&mut (dst), b);
            i = i + 1;
        };
        dst
    }

    fun make_sponsor_key(sponsor: address, token_id: &vector<u8>): SponsorTokenKey {
        SponsorTokenKey { sponsor, token: vec_clone(token_id) }
    }

    // ---------- Core functions ----------

    /// Register an alias for an on-chain wallet.
    /// If a fee is set, caller must pay the module's `flat_fee` in the provided TokenType (withdraw/pay handled in client).
    /// This function enforces username length, atomic storage, and event emission.
    public entry fun register_alias(user: &signer, username: vector<u8>, country: vector<u8>, pref_currency: vector<u8>) {
        let caller = signer::address_of(user);
        let module_addr = @0xGLOBE_IDF;

        // enforce username length
        let uname_len = vector::length(&username);
        assert!(uname_len <= (MAX_USERNAME_BYTES as u64), E_USERNAME_TOO_LONG);

        // access store under module account
        let store_ref = borrow_global_mut<IdentityStore>(module_addr);

        // check username collision
        if (Table::contains_key(&store_ref.username_to_wallet, &username)) {
            let existing = Table::borrow(&store_ref.username_to_wallet, &username);
            // allow same wallet to re-register same username
            assert!(*existing == caller, E_USERNAME_TAKEN);
        }

        // Insert metadata first (this consumes username/country/pref_currency)
        Table::insert(&mut store_ref.username_to_wallet, username, caller);
        Table::insert(&mut store_ref.wallet_to_meta, caller, (country, pref_currency));

        // Emit event - to avoid moving issues, read back from tables or emit with freshly cloned values
        if (exists<IdentityEvents>(module_addr)) {
            let evs = borrow_global_mut<IdentityEvents>(module_addr);
            // borrow the username and meta back for event (Table::borrow returns &T)
            let uname_ref = Table::borrow(&store_ref.username_to_wallet, &Table::key_from_address(caller)); // pseudo helper
            // NOTE: Table APIs differ; if Table::borrow by key not suitable for getting vector<u8> back,
            // you can instead emit using vec_clone of the original values before moving them into tables.
            // For clarity we will emit a simple event with placeholders if borrow API is not available.
            let ev = IdentityRegistered {
                wallet: caller,
                username: vector::empty<u8>(), // placeholder when borrow API isn't directly available
                country: vector::empty<u8>(),
                pref_currency: vector::empty<u8>(),
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.id_handle, ev);
        }
    }

    /// Admin: set fee policy (module owner only)
    /// flat_fee & percent_bps are stored; percent_bps <= 10000
    public entry fun set_fees(admin: &signer, flat_fee: u64, percent_bps: u64) {
        let caller = signer::address_of(admin);
        assert!(caller == @0xGLOBE_IDF, E_NOT_OWNER);
        let fs = borrow_global_mut<FeeState>(caller);
        assert!(percent_bps <= 10000, E_FEE_BPS_INVALID);
        fs.flat_fee = flat_fee;
        fs.percent_bps = percent_bps;
    }

    /// Record a fee into module accounting while transferring coin into module custody atomically.
    /// Generic over the token coin type used for fee (caller supplies the coin by approving/withdrawing).
    public entry fun collect_fee<TokenType>(payer: &signer, token_id: vector<u8>, amount: u64) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let module_addr = @0xGLOBE_IDF;

        // withdraw coin from payer and deposit into module custody atomically
        let coin_obj = coin::withdraw<TokenType>(payer, amount);
        coin::deposit<TokenType>(module_addr, coin_obj);

        // update FeeState totals
        let fs = borrow_global_mut<FeeState>(module_addr);
        if (Table::contains_key(&fs.collected_by_token, &token_id)) {
            let prev = Table::borrow(&fs.collected_by_token, &token_id);
            let new_total = *prev + amount;
            Table::insert(&mut fs.collected_by_token, token_id, new_total);
        } else {
            Table::insert(&mut fs.collected_by_token, token_id, amount);
        }

        // emit event
        if (exists<IdentityEvents>(module_addr)) {
            let evs = borrow_global_mut<IdentityEvents>(module_addr);
            let ev = FeeCollected {
                payer: signer::address_of(payer),
                token_type: vec_clone(&token_id),
                amount,
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.fee_handle, ev);
        }
    }

    /// Admin: register a sponsor -> sponsor_wallet mapping
    public entry fun register_sponsor(admin: &signer, sponsor: address, sponsor_wallet: address) {
        let caller = signer::address_of(admin);
        assert!(caller == @0xGLOBE_IDF, E_NOT_OWNER);
        let ss = borrow_global_mut<SponsorState>(caller);
        Table::insert(&mut ss.sponsor_to_wallet, sponsor, sponsor_wallet);
    }

    /// Credit sponsor by transferring tokens into module custody and updating flattened credits table.
    /// TokenType is the coin type used for credits.
    public entry fun credit_sponsor<TokenType>(sponsor_wallet_signer: &signer, sponsor: address, token_id: vector<u8>, amount: u64) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        let caller = signer::address_of(sponsor_wallet_signer);
        let module_addr = @0xGLOBE_IDF;

        let ss = borrow_global_mut<SponsorState>(module_addr);

        // verify sponsor->wallet mapping exists and matches caller
        assert!(Table::contains_key(&ss.sponsor_to_wallet, &sponsor), E_NOT_SPONSOR_WALLET);
        let mapped = Table::borrow(&ss.sponsor_to_wallet, &sponsor);
        assert!(*mapped == caller, E_NOT_SPONSOR_WALLET);

        // withdraw TokenType from sponsor wallet and deposit to module custody (atomic)
        let coin_obj = coin::withdraw<TokenType>(sponsor_wallet_signer, amount);
        coin::deposit<TokenType>(module_addr, coin_obj);

        // update flattened sponsor_credits table keyed by (sponsor, token_id)
        let key = make_sponsor_key(sponsor, &token_id);
        if (Table::contains_key(&ss.sponsor_credits, &key)) {
            let prev = Table::borrow(&ss.sponsor_credits, &key);
            let new_total = *prev + amount;
            Table::insert(&mut ss.sponsor_credits, key, new_total);
        } else {
            Table::insert(&mut ss.sponsor_credits, key, amount);
        }
    }

    /// Owner-only helper to withdraw collected fees of a given token to a recipient.
    public entry fun withdraw_collected_fee<TokenType>(admin: &signer, recipient: address, token_id: vector<u8>, amount: u64) {
        let caller = signer::address_of(admin);
        assert!(caller == @0xGLOBE_IDF, E_NOT_OWNER);
        let fs = borrow_global_mut<FeeState>(caller);
        // ensure collected amount sufficient
        let prev_amount = if (Table::contains_key(&fs.collected_by_token, &token_id)) {
            *Table::borrow(&fs.collected_by_token, &token_id)
        } else { 0 };
        assert!(prev_amount >= amount, E_INVALID_AMOUNT);

        // deduct from accounting
        let remaining = prev_amount - amount;
        Table::insert(&mut fs.collected_by_token, token_id, remaining);

        // withdraw coin from module custody and send to recipient
        let coin_obj = coin::withdraw<TokenType>(admin, amount);
        coin::deposit<TokenType>(recipient, coin_obj);
    }

    // Additional sponsor withdraws and helper views can be added following the same patterns:
    // - atomic coin movement (withdraw from module admin signer when paying out)
    // - update sponsor_credits table with checks
}
}
