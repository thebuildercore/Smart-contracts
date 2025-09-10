address 0xGLOBE_BUSINESS {
module GlobePayXBusiness {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use std::table::Table;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::timestamp;

    // ---------- Events ----------
    struct PayrollEvent has store, drop {
        employer: address,
        employee: address,
        coin_type: vector<u8>,
        amount: u64,
        memo: vector<u8>,
        ts: u64
    }

    struct TreasuryEvent has store, drop {
        org: address,
        from_tag: vector<u8>,
        to_tag: vector<u8>,
        coin_type: vector<u8>,
        amount: u64,
        ts: u64
    }

    struct BusinessEvents has key {
        payroll_handle: event::EventHandle<PayrollEvent>,
        treasury_handle: event::EventHandle<TreasuryEvent>
    }

    // ---------- Org & Treasury state ----------
    /// Simple Org resource: admin address and existence flag
    struct Org has key {
        admin: address
    }

    /// Treasury storage for an org per coin type: tag -> numeric balance
    /// NOTE: numeric balances are backed by real coins held in the org account's coin store.
    struct OrgTreasury<CoinType> has key {
        org: address,
        balances: Table<vector<u8>, u64> // tag -> balance in CoinType smallest units
    }

    // ---------- Errors ----------
    const E_ALREADY_INITIALIZED: u64 = 1;
    const E_NOT_ORG_SIGNER: u64 = 2;
    const E_INVALID_INPUT: u64 = 10;
    const E_MISMATCH_LENGTH: u64 = 11;
    const E_ZERO_AMOUNT: u64 = 12;
    const E_OVERFLOW: u64 = 13;
    const E_ORG_NOT_FOUND: u64 = 20;
    const E_NOT_ADMIN: u64 = 21;
    const E_INSUFFICIENT_BALANCE: u64 = 22;

    // ---------- Init ----------
    // Create module-level event handles (call from module account)
    public entry fun init(account: &signer) {
        let addr = signer::address_of(account);
        assert!(!exists<BusinessEvents>(addr), E_ALREADY_INITIALIZED);
        let ph = event::new_event_handle<PayrollEvent>(account);
        let th = event::new_event_handle<TreasuryEvent>(account);
        move_to(account, BusinessEvents { payroll_handle: ph, treasury_handle: th });
    }

    // ---------- Org lifecycle ----------
    /// Create an Org resource at the caller's address. The caller becomes the org admin.
    /// This ensures treasury coins are held in the same account that controls withdrawals.
    public entry fun create_org(caller: &signer) {
        let addr = signer::address_of(caller);
        assert!(!exists<Org>(addr), E_INVALID_INPUT);
        move_to(caller, Org { admin: addr });
    }

    // ---------- Payroll ----------
    /// Batch payroll: employer (caller) pays multiple recipients in a single transaction.
    /// We perform per-recipient withdraws from the employer and deposits to employees to avoid relying on coin::split API.
    public entry fun batch_pay<CoinType>(
        employer: &signer,
        recipients: vector<address>,
        amounts: vector<u64>,
        memo: vector<u8>
    ) {
        let len_r = vector::length(&recipients);
        let len_a = vector::length(&amounts);
        assert!(len_r == len_a, E_MISMATCH_LENGTH);
        assert!(len_r > 0, E_INVALID_INPUT);

        // compute total and validate amounts to prevent overflow
        let mut i = 0;
        let mut total: u128 = 0;
        while (i < len_r) {
            let amt = *vector::borrow(&amounts, i);
            assert!(amt > 0, E_ZERO_AMOUNT);
            total = total + u128::from(amt);
            i = i + 1;
        }
        assert!(total <= u128::from(u64::MAX), E_OVERFLOW);

        // Instead of a single large withdraw + split (which depends on coin::split availability),
n        // we withdraw per-recipient. This keeps semantics simple and atomic within the transaction.
        i = 0;
        while (i < len_r) {
            let recipient = *vector::borrow(&recipients, i);
            let amt = *vector::borrow(&amounts, i);
            // withdraw amt from employer and deposit to recipient
            let piece = coin::withdraw<CoinType>(employer, amt);
            coin::deposit<CoinType>(recipient, piece);

            // emit payroll event
            let events_addr = @0xGLOBE_BUSINESS;
            if (exists<BusinessEvents>(events_addr)) {
                let evs = borrow_global_mut<BusinessEvents>(events_addr);
                let ev = PayrollEvent {
                    employer: signer::address_of(employer),
                    employee: recipient,
                    coin_type: vector::empty<u8>(), // consider using TypeInfo if available
                    amount: amt,
                    memo: vec_clone(&memo),
                    ts: timestamp::now_seconds()
                };
                event::emit_event(&mut evs.payroll_handle, ev);
            }
            i = i + 1;
        }
    }

    // ---------- Treasury (backed by real coins held in org account) ----------
    /// Fund an org's tagged balance. The coin is moved from funder -> org account custody and the tag balance updated.
    public entry fun fund_treasury<CoinType>(funder: &signer, org_addr: address, tag: vector<u8>, amount: u64) {
        assert!(amount > 0, E_ZERO_AMOUNT);

        // transfer coin from funder to org account custody
        let coin_obj = coin::withdraw<CoinType>(funder, amount);
        coin::deposit<CoinType>(org_addr, coin_obj);

        // ensure Org exists
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);

        // ensure OrgTreasury<CoinType> exists under org_addr; if not create it (module stores under org account)
        if (!exists<OrgTreasury<CoinType>>(org_addr)) {
            let tbl = Table::new<vector<u8>, u64>();
            // move the treasury resource to the org account so balances mirror custody
            // NOTE: to move into org account we need a signer for org_addr — but move_to requires signer reference.
            // Instead we create the OrgTreasury under the org account by relying on the org to call an init function.
            // For simplicity here, we assert the OrgTreasury already exists or require org to call init_treasury.
            // To keep this function safe, we'll assert the treasury exists; org should create it via init_treasury.
            assert!(false, E_INVALID_INPUT);
        }

        // update numeric balance (backed by coins in org account coin store)
        let mut treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        if (Table::contains_key(&treasury.balances, &tag)) {
            let prev = Table::borrow(&treasury.balances, &tag);
            let new_balance = *prev + amount;
            Table::insert(&mut treasury.balances, tag, new_balance);
        } else {
            Table::insert(&mut treasury.balances, tag, amount);
        }

        // emit event
        let events_addr = @0xGLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent { org: org_addr, from_tag: vector::empty<u8>(), to_tag: vec_clone(&tag), coin_type: vector::empty<u8>(), amount, ts: timestamp::now_seconds() };
            event::emit_event(&mut evs.treasury_handle, ev);
        }
    }

    /// Org must call this once to initialize its treasury for a specific CoinType
    public entry fun init_treasury<CoinType>(org_signer: &signer) {
        let org_addr = signer::address_of(org_signer);
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        assert!(!exists<OrgTreasury<CoinType>>(org_addr), E_INVALID_INPUT);
        let tbl = Table::new<vector<u8>, u64>();
        move_to(org_signer, OrgTreasury::<CoinType> { org: org_addr, balances: tbl });
    }

    /// Internal transfer between tags (org admin only). Numeric ledger update only — coins remain in org account custody.
    public entry fun internal_transfer<CoinType>(caller: &signer, org_addr: address, from_tag: vector<u8>, to_tag: vector<u8>, amount: u64) {
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        let org = borrow_global<Org>(org_addr);
        assert!(org.admin == signer::address_of(caller), E_NOT_ADMIN);

        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        // check from_tag balance
        assert!(Table::contains_key(&treasury.balances, &from_tag), E_INSUFFICIENT_BALANCE);
        let from_prev = *Table::borrow(&treasury.balances, &from_tag);
        assert!(from_prev >= amount, E_INSUFFICIENT_BALANCE);
        let new_from = from_prev - amount;
        Table::insert(&mut treasury.balances, from_tag, new_from);

        // add to to_tag
        if (Table::contains_key(&treasury.balances, &to_tag)) {
            let to_prev = *Table::borrow(&treasury.balances, &to_tag);
            Table::insert(&mut treasury.balances, to_tag, to_prev + amount);
        } else {
            Table::insert(&mut treasury.balances, to_tag, amount);
        }

        // emit event
        let events_addr = @0xGLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent { org: org_addr, from_tag: vec_clone(&from_tag), to_tag: vec_clone(&to_tag), coin_type: vector::empty<u8>(), amount, ts: timestamp::now_seconds() };
            event::emit_event(&mut evs.treasury_handle, ev);
        }
    }

    /// Withdraw from tag to an external wallet (org admin must be the org account signer)
    /// This performs a coin::withdraw from the org account (caller) and sends to `to`.
    public entry fun withdraw_from_tag<CoinType>(org_signer: &signer, tag: vector<u8>, to: address, amount: u64) {
        let org_addr = signer::address_of(org_signer);
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        let org = borrow_global<Org>(org_addr);
        assert!(org.admin == org_addr, E_NOT_ADMIN); // admin must be the org account itself in this simplified model

        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        assert!(Table::contains_key(&treasury.balances, &tag), E_INSUFFICIENT_BALANCE);
        let bal = *Table::borrow(&treasury.balances, &tag);
        assert!(bal >= amount, E_INSUFFICIENT_BALANCE);
        Table::insert(&mut treasury.balances, tag, bal - amount);

        // withdraw coin from org account (org_signer) and deposit to recipient
        let coin_obj = coin::withdraw<CoinType>(org_signer, amount);
        coin::deposit<CoinType>(to, coin_obj);

        // emit event
        let events_addr = @0xGLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent { org: org_addr, from_tag: vec_clone(&tag), to_tag: vector::empty<u8>(), coin_type: vector::empty<u8>(), amount, ts: timestamp::now_seconds() };
            event::emit_event(&mut evs.treasury_handle, ev);
        }
    }

    // ---------- Small helpers ----------
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
}
}
