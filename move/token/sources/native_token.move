/// Native hyperlane token

module hp_token::native_token {
    use std::vector;
    use hp_router::router;
    use hp_library::token_msg_utils;
    use hp_mailbox::mailbox;

    const DEFAULT_GAS_AMOUNT: u256 = 1_000_000_000;

    struct NativeToken {}

    struct State has key {
        cap: router::RouterCap<NativeToken>,
        received_messages: vector<vector<u8>>
    }

    /// Initialize Module
    fun init_module(account: &signer) {
        // obtain router capability which allows to exchange
        // native tokens on aptos with synthetic equvalent on the other blockchain
        let cap = router::init<NativeToken>(account);
        move_to<State>(account, State {
            cap,
            received_messages: vector::empty()
        });
    }

    // Send aptos native token to a synthetic equvalent on the other chain
    public entry fun remote_transfer(
        account: &signer,
        dest_domain: u32,
        message: vector<u8>
    ) acquires State {
        let state = borrow_global<State>(@hp_token);

        mailbox::dispatch_with_gas<NativeToken>(
            account,
            dest_domain,
            message,
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
}
