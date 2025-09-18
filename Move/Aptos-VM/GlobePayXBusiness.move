module GLOBE_BUSINESS::GlobePayXBusiness {
    use std::signer;
    use std::vector;
    use std::string;
    use std::option;
    use std::u64;
    use aptos_std::table::{Self, Table};
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_std::type_info;

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
    struct Org has key {
        admin: address
    }

    struct OrgTreasury<CoinType> has key {
        org: address,
        balances: Table<vector<u8>, u64>
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
    public entry fun init(account: &signer) {
        let addr = signer::address_of(account);
        assert!(!exists<BusinessEvents>(addr), E_ALREADY_INITIALIZED);
        let ph = event::new_event_handle<PayrollEvent>(account);
        let th = event::new_event_handle<TreasuryEvent>(account);
        move_to(account, BusinessEvents { payroll_handle: ph, treasury_handle: th });
    }

    // ---------- Org lifecycle ----------
    public entry fun create_org(caller: &signer) {
        let addr = signer::address_of(caller);
        assert!(!exists<Org>(addr), E_INVALID_INPUT);
        move_to(caller, Org { admin: addr });
    }

    // ---------- Payroll ----------
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

        let i: u64 = 0;
        let total: u128 = 0u128;
        while (i < len_r) {
            let amt = *vector::borrow(&amounts, i);
            assert!(amt > 0, E_ZERO_AMOUNT);
            total = total + (amt as u128);
            i = i + 1;
        };
        assert!(total <= (u64::MAX as u128), E_OVERFLOW);

        let j: u64 = 0;
        while (j < len_r) {
            let recipient = *vector::borrow(&recipients, j);
            let amt = *vector::borrow(&amounts, j);
            assert!(coin::is_account_registered<CoinType>(recipient), E_INVALID_INPUT);

            let piece = coin::withdraw<CoinType>(employer, amt);
            coin::deposit<CoinType>(recipient, piece);

            let events_addr = @GLOBE_BUSINESS;
            if (exists<BusinessEvents>(events_addr)) {
                let evs = borrow_global_mut<BusinessEvents>(events_addr);
                let ev = PayrollEvent {
                    employer: signer::address_of(employer),
                    employee: recipient,
                    coin_type: string::bytes(type_info::type_name<CoinType>()),
                    amount: amt,
                    memo: vec_clone(&memo),
                    ts: timestamp::now_seconds()
                };
                event::emit_event(&mut evs.payroll_handle, ev);
            };
            j = j + 1;
        };
    }

    // ---------- Treasury (backed by real coins held in org account) ----------
    public entry fun fund_treasury<CoinType>(funder: &signer, org_addr: address, tag: vector<u8>, amount: u64) {
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(coin::is_account_registered<CoinType>(org_addr), E_INVALID_INPUT);

        let coin_obj = coin::withdraw<CoinType>(funder, amount);
        coin::deposit<CoinType>(org_addr, coin_obj);

        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        assert!(exists<OrgTreasury<CoinType>>(org_addr), E_INVALID_INPUT);

        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        if (table::contains(&treasury.balances, &tag)) {
            let prev_ref = table::borrow(&treasury.balances, &tag);
            let new_balance = *prev_ref + amount;
            table::upsert(&mut treasury.balances, tag, new_balance);
        } else {
            table::upsert(&mut treasury.balances, tag, amount);
        };

        let events_addr = @GLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent {
                org: org_addr,
                from_tag: vector::empty<u8>(),
                to_tag: vec_clone(&tag),
                coin_type: string::bytes(type_info::type_name<CoinType>()),
                amount,
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.treasury_handle, ev);
        };
    }

    public entry fun init_treasury<CoinType>(org_signer: &signer) {
        let org_addr = signer::address_of(org_signer);
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        assert!(!exists<OrgTreasury<CoinType>>(org_addr), E_INVALID_INPUT);

        let tbl = table::new<vector<u8>, u64>();
        move_to(org_signer, OrgTreasury { org: org_addr, balances: tbl });
    }

    public entry fun internal_transfer<CoinType>(caller: &signer, org_addr: address, from_tag: vector<u8>, to_tag: vector<u8>, amount: u64) {
        assert!(amount > 0, E_ZERO_AMOUNT);
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        let org = borrow_global<Org>(org_addr);
        assert!(org.admin == signer::address_of(caller), E_NOT_ADMIN);

        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        assert!(table::contains(&treasury.balances, &from_tag), E_INSUFFICIENT_BALANCE);
        let from_prev = *table::borrow(&treasury.balances, &from_tag);
        assert!(from_prev >= amount, E_INSUFFICIENT_BALANCE);
        let new_from = from_prev - amount;
        table::upsert(&mut treasury.balances, from_tag, new_from);

        if (table::contains(&treasury.balances, &to_tag)) {
            let to_prev = *table::borrow(&treasury.balances, &to_tag);
            table::upsert(&mut treasury.balances, to_tag, to_prev + amount);
        } else {
            table::upsert(&mut treasury.balances, to_tag, amount);
        };

        let events_addr = @GLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent {
                org: org_addr,
                from_tag: vec_clone(&from_tag),
                to_tag: vec_clone(&to_tag),
                coin_type: string::bytes(type_info::type_name<CoinType>()),
                amount,
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.treasury_handle, ev);
        };
    }

    public entry fun withdraw_from_tag<CoinType>(org_signer: &signer, tag: vector<u8>, to: address, amount: u64) {
        let org_addr = signer::address_of(org_signer);
        assert!(exists<Org>(org_addr), E_ORG_NOT_FOUND);
        let org = borrow_global<Org>(org_addr);
        assert!(org.admin == signer::address_of(org_signer), E_NOT_ADMIN);
        assert!(coin::is_account_registered<CoinType>(to), E_INVALID_INPUT);

        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        assert!(table::contains(&treasury.balances, &tag), E_INSUFFICIENT_BALANCE);
        let bal = *table::borrow(&treasury.balances, &tag);
        assert!(bal >= amount, E_INSUFFICIENT_BALANCE);
        table::upsert(&mut treasury.balances, tag, bal - amount);

        let coin_obj = coin::withdraw<CoinType>(org_signer, amount);
        coin::deposit<CoinType>(to, coin_obj);

        let events_addr = @GLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent {
                org: org_addr,
                from_tag: vec_clone(&tag),
                to_tag: vector::empty<u8>(),
                coin_type: string::bytes(type_info::type_name<CoinType>()),
                amount,
                ts: timestamp::now_seconds()
            };
            event::emit_event(&mut evs.treasury_handle, ev);
        };
    }

    // ---------- Small helpers ----------
    fun vec_clone(src: &vector<u8>): vector<u8> {
        let dst: vector<u8> = vector::empty<u8>();
        let len = vector::length(src);
        let i: u64 = 0;
        while (i < len) {
            let b = *vector::borrow(src, i);
            vector::push_back(&mut dst, b);
            i = i + 1;
        };
        dst
    }
}
