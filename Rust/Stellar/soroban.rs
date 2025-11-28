use soroban_sdk::{contract, contractimpl, Address, Env, Symbol, Vec, Map, map, vec, token};

// Define the contract
#[contract]
pub struct CrossChainYieldGateway;

// Define storage keys and mock data structures
#[contractimpl]
impl CrossChainYieldGateway {
    // Storage for user balances and vault allocations
    const USER_BALANCES: Symbol = Symbol::new(&"USER_BALANCES"); // Map<Address, Map<Symbol, u128>>: user -> (token -> amount)
    const VAULT_ALLOCATIONS: Symbol = Symbol::new(&"VAULT_ALLOCATIONS"); // Map<Address, Map<Symbol, u128>>: user -> (vault -> amount)
    const VAULT_APYS: Symbol = Symbol::new(&"VAULT_APYS"); // Map<Symbol, u64>: vault -> APY (e.g., 500 for 5%)

    // Initialize the contract with mock vault data
    pub fn initialize(env: Env) {
        // Mock vaults: Vault A (USDC Staking, 5%), Vault B (XLM Lending, 7%)
        let vault_apys: Map<Symbol, u64> = map![
            &env,
            (Symbol::new(&env, "VAULT_A"), 500), // 5% APY
            (Symbol::new(&env, "VAULT_B"), 700)  // 7% APY
        ];
        env.storage().persistent().set(&Self::VAULT_APYS, &vault_apys);
    }

    // Simulate cross-chain import (mints mock wrapped tokens)
    pub fn import_token(env: Env, user: Address, chain: Symbol, token: Symbol, amount: u128) {
        user.require_auth(); // Ensure user authorizes the transaction

        // Simulate minting wrapped token (e.g., ETH -> Stellar-wETH)
        let wrapped_token = Symbol::new(&env, &format!("w{}", token.to_string()));
        
        // Update user balance
        let mut balances: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::USER_BALANCES)
            .unwrap_or(map![&env]);
        let mut user_tokens = balances.get(&user).unwrap_or(map![&env]);
        user_tokens.set(wrapped_token.clone(), amount);
        balances.set(user.clone(), user_tokens);
        env.storage().persistent().set(&Self::USER_BALANCES, &balances);

        // Emit event for UI
        env.events().publish(("import_token", user, chain, token), amount);
    }

    // Deposit funds into a vault (manual or auto-optimization)
    pub fn deposit(env: Env, user: Address, token: Symbol, amount: u128, auto_optimize: bool) {
        user.require_auth();

        // Verify user has enough tokens
        let balances: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::USER_BALANCES)
            .unwrap_or(map![&env]);
        let user_tokens = balances.get(&user).unwrap_or(map![&env]);
        let current_balance = user_tokens.get(&token).unwrap_or(0);
        assert!(current_balance >= amount, "Insufficient balance");

        // Select vault (auto or manual)
        let vault = if auto_optimize {
            Self::get_best_vault(&env)
        } else {
            // For manual, assume token maps to a vault (e.g., USDC -> VAULT_A)
            if token == Symbol::new(&env, "wUSDC") {
                Symbol::new(&env, "VAULT_A")
            } else {
                Symbol::new(&env, "VAULT_B")
            }
        };

        // Update balances
        let mut user_tokens = user_tokens.clone();
        user_tokens.set(token.clone(), current_balance - amount);
        let mut balances = balances.clone();
        balances.set(user.clone(), user_tokens);
        env.storage().persistent().set(&Self::USER_BALANCES, &balances);

        // Update vault allocations
        let mut allocations: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::VAULT_ALLOCATIONS)
            .unwrap_or(map![&env]);
        let mut user_vaults = allocations.get(&user).unwrap_or(map![&env]);
        let current_vault_amount = user_vaults.get(&vault).unwrap_or(0);
        user_vaults.set(vault.clone(), current_vault_amount + amount);
        allocations.set(user.clone(), user_vaults);
        env.storage().persistent().set(&Self::VAULT_ALLOCATIONS, &allocations);

        // Emit event
        env.events().publish(("deposit", user, vault, token), amount);
    }

    // Optimize funds to the highest APY vault
    pub fn optimize(env: Env, user: Address) {
        user.require_auth();

        // Get current allocations
        let allocations: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::VAULT_ALLOCATIONS)
            .unwrap_or(map![&env]);
        let user_vaults = allocations.get(&user).unwrap_or(map![&env]);

        // Find best vault
        let best_vault = Self::get_best_vault(&env);

        // Reallocate all funds to best vault (mock swap logic)
        let mut total_amount = 0;
        let mut new_user_vaults = map![&env];
        for (vault, amount) in user_vaults.iter() {
            if vault != best_vault {
                total_amount += amount;
            } else {
                new_user_vaults.set(vault, amount);
            }
        }
        let current_best_amount = new_user_vaults.get(&best_vault).unwrap_or(0);
        new_user_vaults.set(best_vault.clone(), current_best_amount + total_amount);

        // Update allocations
        let mut allocations = allocations.clone();
        allocations.set(user.clone(), new_user_vaults);
        env.storage().persistent().set(&Self::VAULT_ALLOCATIONS, &allocations);

        // Emit event (mock Soroswap swap)
        env.events().publish(("optimize", user, best_vault), total_amount);
    }

    // Withdraw funds from a vault
    pub fn withdraw(env: Env, user: Address, vault: Symbol, amount: u128) {
        user.require_auth();

        // Verify allocation
        let allocations: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::VAULT_ALLOCATIONS)
            .unwrap_or(map![&env]);
        let user_vaults = allocations.get(&user).unwrap_or(map![&env]);
        let current_amount = user_vaults.get(&vault).unwrap_or(0);
        assert!(current_amount >= amount, "Insufficient vault balance");

        // Update vault allocations
        let mut user_vaults = user_vaults.clone();
        user_vaults.set(vault.clone(), current_amount - amount);
        let mut allocations = allocations.clone();
        allocations.set(user.clone(), user_vaults);
        env.storage().persistent().set(&Self::VAULT_ALLOCATIONS, &allocations);

        // Update user balance (mock return to XLM)
        let token = Symbol::new(&env, "XLM");
        let mut balances: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::USER_BALANCES)
            .unwrap_or(map![&env]);
        let mut user_tokens = balances.get(&user).unwrap_or(map![&env]);
        let current_balance = user_tokens.get(&token).unwrap_or(0);
        user_tokens.set(token, current_balance + amount);
        balances.set(user.clone(), user_tokens);
        env.storage().persistent().set(&Self::USER_BALANCES, &balances);

        // Emit event
        env.events().publish(("withdraw", user, vault), amount);
    }

    // Swap tokens via Soroswap (mock)
    pub fn swap(env: Env, user: Address, from_token: Symbol, to_token: Symbol, amount: u128) {
        user.require_auth();

        // Verify balance
        let balances: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::USER_BALANCES)
            .unwrap_or(map![&env]);
        let user_tokens = balances.get(&user).unwrap_or(map![&env]);
        let current_balance = user_tokens.get(&from_token).unwrap_or(0);
        assert!(current_balance >= amount, "Insufficient balance");

        // Mock Soroswap swap (assume 1:1 for simplicity)
        let mut user_tokens = user_tokens.clone();
        user_tokens.set(from_token.clone(), current_balance - amount);
        user_tokens.set(to_token.clone(), user_tokens.get(&to_token).unwrap_or(0) + amount);
        let mut balances = balances.clone();
        balances.set(user.clone(), user_tokens);
        env.storage().persistent().set(&Self::USER_BALANCES, &balances);

        // Emit event
        env.events().publish(("swap", user, from_token, to_token), amount);
    }

    // Get portfolio data for UI
    pub fn get_portfolio(env: Env, user: Address) -> Map<Symbol, u128> {
        let allocations: Map<Address, Map<Symbol, u128>> = env.storage().persistent()
            .get(&Self::VAULT_ALLOCATIONS)
            .unwrap_or(map![&env]);
        allocations.get(&user).unwrap_or(map![&env])
    }

    // Helper: Get the vault with the highest APY
    fn get_best_vault(env: &Env) -> Symbol {
        let vault_apys: Map<Symbol, u64> = env.storage().persistent()
            .get(&Self::VAULT_APYS)
            .unwrap_or(map![env]);
        let mut best_vault = Symbol::new(env, "VAULT_A");
        let mut max_apy = 0;
        for (vault, apy) in vault_apys.iter() {
            if apy > max_apy {
                max_apy = apy;
                best_vault = vault;
            }
        }
        best_vault
    }
}
