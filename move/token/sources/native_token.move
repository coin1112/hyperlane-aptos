/// Native hyperlane token

module hp_token::native_token {
    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::Self;
    use aptos_framework::event::{Self, EventHandle};
    use hp_library::msg_utils;
    use hp_mailbox::mailbox;
    use hp_router::router;
    use hp_token::events::{Self, SentTransferRemote, ReceivedTransferRemote};
    use std::signer;

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
        beneficiary: address,
        signer_cap: account::SignerCapability,
        sent_transfer_remote_events: EventHandle<SentTransferRemote>,
        received_transfer_remote_events: EventHandle<ReceivedTransferRemote>,
    }

    /// Initialize Module
    fun init_module(account: &signer) {
        // todo: coin1 get a random seed
        let seed: vector<u8> = x"123456";
        // obtain router capability which allows to exchange
        // native tokens on aptos with synthetic equvalent on the other blockchain
        let (resource_account, signer_cap) = account::create_resource_account(account, seed);

        // register resource_account so that it can accept AptosCoins
        coin::register<AptosCoin>(&resource_account);

        let cap = router::init<NativeToken>(account);
        move_to<State>(account, State {
            cap,
            beneficiary: signer::address_of(&resource_account),
            signer_cap,
            sent_transfer_remote_events: account::new_event_handle<SentTransferRemote>(account),
            received_transfer_remote_events: account::new_event_handle<ReceivedTransferRemote>(account),
        });
    }

    // Send aptos native token to a synthetic equvalent on the other chain
    // TODO: coin add support for custom gas_amount
    public entry fun transfer_remote(
        account: &signer,
        dest_domain: u32,
        recipient: vector<u8>,
        amount: u64,
    ) acquires State {
        let state = borrow_global_mut<State>(@hp_token);

        let account_address = signer::address_of(account);

        // Check if the account has enough balance
        let balance = coin::balance<AptosCoin>(account_address);
        assert!(balance >= amount, E_INSUFFICIENT_BALANCE);
        let message_body = msg_utils::format_token_message(amount);

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

        // emit SentTransferRemote event
        event::emit_event<SentTransferRemote>(
            &mut state.sent_transfer_remote_events,
            events::new_sent_transfer_remote_event(
                dest_domain,
                recipient,
                amount
            )
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

        // transfer coins
        // get token message
        let token_message = msg_utils::body(&message);
        // extract amount to transfer
        let amount = msg_utils::amount_from_token_message(&token_message);
        let recipient = msg_utils::recipient(&message);

        // Check if the beneficiary has enough balance
        let balance = coin::balance<AptosCoin>(state.beneficiary);
        assert!(balance >= amount, E_INSUFFICIENT_BALANCE);

        // transfer to recipient
        let resource_signer = account::create_signer_with_capability(&state.signer_cap);
        let coin = coin::withdraw<AptosCoin>(&resource_signer, amount);
        coin::deposit<AptosCoin>(recipient, coin);

        // emit SentTransferRemote event;
        let origin_domain = msg_utils::origin_domain(&message);
        event::emit_event<ReceivedTransferRemote>(
            &mut state.received_transfer_remote_events,
            events::new_received_transfer_remote_event(
                origin_domain,
                recipient,
                amount
            )
        );
    }

    #[view]
    /// Get beneficiary, e.g. address containing reserve of transferred coins
    public fun get_beneficiary(): address acquires State {
        let state = borrow_global<State>(@hp_token);
        state.beneficiary
    }

    #[test_only]
    public fun init_for_test(account: &signer) {
        init_module(account);
    }

    #[test_only]
    public fun get_default_gas_amount(): u256 {
        DEFAULT_GAS_AMOUNT
    }
}
