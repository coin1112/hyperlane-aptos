/// Native hyperlane token

module hp_token::native_token {
    use std::vector;
    use std::signer;
    use hp_router::router;
    use hp_library::token_msg_utils;
    use hp_mailbox::mailbox;
    use hp_library::msg_utils;

    use aptos_framework::coin::Self;
    use aptos_framework::aptos_coin::AptosCoin;

    const DEFAULT_GAS_AMOUNT: u256 = 1_000_000_000;

    // Errors
    const E_AMOUNT_EXCEEDS_BALANCE: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;

    // Native token router
    // Used to send native tokens to another network
    // A native token is the one used to pay for gas on network such as APT or ETH
    // On the other chain it is represented by a synthetic token suth as ETH on Optimism
    // which is a still "native" token on that chain, but has a collateral on the main (ETH) chain
    struct NativeToken {}

    struct State has key {
        cap: router::RouterCap<NativeToken>,
        received_messages: vector<vector<u8>>,
        // holds funds
        beneficiary: address,
    }

    /// Initialize Module
    fun init_module(account: &signer) {
        // obtain router capability which allows to exchange
        // native tokens on aptos with synthetic equvalent on the other blockchain
        let account_address = signer::address_of(account);
        let cap = router::init<NativeToken>(account);
        move_to<State>(account, State {
            cap,
            received_messages: vector::empty(),
            beneficiary: account_address,
        });
    }

    // Send aptos native token to a synthetic equvalent on the other chain
    // TODO: coin add support for custom gas_amount
    public entry fun transfer_remote(
        account: &signer,
        dest_domain: u32,
        amount: u64,
    ) acquires State {
        let state = borrow_global<State>(@hp_token);

        let account_address  = signer::address_of(account);

        // Check if the account has enough balance
        let balance = coin::balance<AptosCoin>(account_address);
        assert!(balance >= amount, E_INSUFFICIENT_BALANCE);
        let message_body = msg_utils::format_transfer_remote_msg_to_bytes(amount);

        // send amount to beneficiary
        let coin = coin::withdraw<AptosCoin>(account, amount);
        coin::deposit<AptosCoin>(state.beneficiary, coin);

        mailbox::dispatch_with_gas<NativeToken>(
            account,
            dest_domain,
            message_body,
            DEFAULT_GAS_AMOUNT,
            &state.cap
        );
    }


    /// Process synthetic tokens transferred from other chains to aptos
    public entry fun handle_message(
        message: vector<u8>,
        metadata: vector<u8>
    ) acquires State {
        let state = borrow_global_mut<State>(@hp_token);

        mailbox::handle_message<NativeToken>(
            message,
            metadata,
            &state.cap
        );

        // TODO: coin1: add logic to mint native token on aptos
        vector::push_back(&mut state.received_messages, token_msg_utils::metadata(&message));
    }

    #[test_only]
    public fun init_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    public fun get_default_gas_amount() : u256 {
        DEFAULT_GAS_AMOUNT
    }
}
