address 0xGLOBE_BUSINESS {
module GlobePayXBusiness {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_framework::coin;
    use aptos_framework::event;
    use std::table::Table;

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

    /// Simple Org resource: admin address and existence flag
    struct Org has key {
        admin: address
    }

    /// Treasury storage for an org and a coin type: tag -> balance
    struct OrgTreasury<CoinType> has key {
        org: address,
        balances: Table<vector<u8>, u64> // tag -> balance in CoinType smallest units
    }

    public entry fun init(account: &signer) {
        assert!(!exists<BusinessEvents>(signer::address_of(account)), 1);
        let ph = event::new_event_handle<PayrollEvent>(account);
        let th = event::new_event_handle<TreasuryEvent>(account);
        move_to(account, BusinessEvents { payroll_handle: ph, treasury_handle: th });
    }

    public entry fun create_org(account: &signer, org_addr: address, admin: address) {
        // only contract deployer can call this in this simplified model
        // store org resource under org_addr
        assert!(!exists<Org>(org_addr), 2);
        move_to(&signer::borrow_address(&org_addr), Org { admin });
    }

    /// Batch payroll: employer withdraws total and contract distributes to recipients
    public entry fun batch_pay<CoinType>(
        employer: &signer,
        recipients: vector<address>,
        amounts: vector<u64>,
        memo: vector<u8>
    ) {
        let len_r = vector::length(&recipients);
        let len_a = vector::length(&amounts);
        assert!(len_r == len_a, 10);
        assert!(len_r > 0, 11);

        // Calculate total
        let mut i = 0;
        let mut total: u128 = 0;
        while (i < len_r) {
            let amt = *vector::borrow(&amounts, i);
            assert!(amt > 0, 12);
            total = total + u128::from(amt);
            i = i + 1;
        }
        assert!(total <= u128::from(u64::MAX), 13);
        let total_u64 = u64::try_from(total).unwrap();

        // withdraw total from employer
        let coins = coin::withdraw<CoinType>(employer, total_u64);

        // Now split and deposit to recipients
        // Splitting coins object into pieces is usually supported via coin::split/merge; simplified here
        // For brevity: we assume coin::split exists; otherwise do repeated withdraws as separate txs.
        // This pseudo-code shows concept:
        // let mut rem_coins = coins;
        i = 0;
        while (i < len_r) {
            let recipient = *vector::borrow(&recipients, i);
            let amt = *vector::borrow(&amounts, i);
            // create a coin piece and deposit (actual impl needs coin::split; left as conceptual)
            coin::deposit<CoinType>(recipient, coin::zero<CoinType>());
            // emit event per payment
            let events_addr = @0xGLOBE_BUSINESS;
            if (exists<BusinessEvents>(events_addr)) {
                let evs = borrow_global_mut<BusinessEvents>(events_addr);
                let ev = PayrollEvent {
                    employer: signer::address_of(employer),
                    employee: recipient,
                    coin_type: vector::empty<u8>(),
                    amount: amt,
                    memo: memo,
                    ts: aptos_framework::timestamp::now_seconds()
                };
                event::emit_event(&mut evs.payroll_handle, ev);
            }
            i = i + 1;
        }
    }

    /// Finance treasury: fund an org's tagged balance
    public entry fun fund_treasury<CoinType>(funder: &signer, org_addr: address, tag: vector<u8>, amount: u64) {
        assert!(amount > 0, 20);
        // withdraw from funder into contract's custody
        let coinobj = coin::withdraw<CoinType>(funder, amount);
        // credit numeric balance in OrgTreasury<CoinType> under org_addr
        if (!exists<OrgTreasury<CoinType>>(org_addr)) {
            let table = Table::new<vector<u8>, u64>();
            move_to(&signer::borrow_address(&org_addr), OrgTreasury::<CoinType> { org: org_addr, balances: table });
        }
        let mut treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        let opt = Table::get_mut(&mut treasury.balances, tag);
        if (option::is_some(&opt)) {
            let prev = *option::borrow(&opt);
            *option::borrow_mut(&opt) = prev + amount;
        } else {
            Table::insert(&mut treasury.balances, tag, amount);
        }
        // emit event
        let events_addr = @0xGLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent { org: org_addr, from_tag: vector::empty<u8>(), to_tag: tag, coin_type: vector::empty<u8>(), amount, ts: aptos_framework::timestamp::now_seconds() };
            event::emit_event(&mut evs.treasury_handle, ev);
        }
    }

    /// Internal transfer between tags (org admin only)
    public entry fun internal_transfer<CoinType>(caller: &signer, org_addr: address, from_tag: vector<u8>, to_tag: vector<u8>, amount: u64) {
        assert!(amount > 0, 30);
        assert!(exists<Org>(org_addr), 31);
        let org = borrow_global<Org>(org_addr);
        assert!(org.admin == signer::address_of(caller), 32);
        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        let from_bal = Table::remove(&mut treasury.balances, from_tag);
        assert!(from_bal >= amount, 33);
        let new_from = from_bal - amount;
        Table::insert(&mut treasury.balances, from_tag, new_from);
        // add to to_tag
        let to_prev_opt = Table::get_mut(&mut treasury.balances, to_tag);
        if (option::is_some(&to_prev_opt)) {
            let prev = *option::borrow(&to_prev_opt);
            *option::borrow_mut(&to_prev_opt) = prev + amount;
        } else {
            Table::insert(&mut treasury.balances, to_tag, amount);
        }

        let events_addr = @0xGLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent { org: org_addr, from_tag, to_tag, coin_type: vector::empty<u8>(), amount, ts: aptos_framework::timestamp::now_seconds() };
            event::emit_event(&mut evs.treasury_handle, ev);
        }
    }

    /// Withdraw from tag to an external wallet (org admin)
    public entry fun withdraw_from_tag<CoinType>(caller: &signer, org_addr: address, tag: vector<u8>, to: address, amount: u64) {
        assert!(exists<Org>(org_addr), 40);
        let org = borrow_global<Org>(org_addr);
        assert!(org.admin == signer::address_of(caller), 41);
        let treasury = borrow_global_mut<OrgTreasury<CoinType>>(org_addr);
        let bal = Table::remove(&mut treasury.balances, tag);
        assert!(bal >= amount, 42);
        Table::insert(&mut treasury.balances, tag, bal - amount);
        // deposit coin to 'to'; but we need actual coin object in module custody - simplified
        coin::deposit<CoinType>(to, coin::zero<CoinType>());
        // emit
        let events_addr = @0xGLOBE_BUSINESS;
        if (exists<BusinessEvents>(events_addr)) {
            let evs = borrow_global_mut<BusinessEvents>(events_addr);
            let ev = TreasuryEvent { org: org_addr, from_tag: tag, to_tag: vector::empty<u8>(), coin_type: vector::empty<u8>(), amount, ts: aptos_framework::timestamp::now_seconds() };
            event::emit_event(&mut evs.treasury_handle, ev);
        }
    }

    // Additional helpers (get balances) would be read-only functions via chain API
}
}
