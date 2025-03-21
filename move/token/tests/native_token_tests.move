#[test_only]
module hp_token::native_tests {

    use aptos_framework::account;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::block;
    use aptos_framework::coin::Self;
    use hp_igps::test_utils::set_igps_for_test;
    use hp_isms::multisig_ism;
    use hp_library::account_utils::derive_address_from_public_key;
    use hp_library::h256::{Self, H256};
    use hp_library::ism_metadata;
    use hp_library::msg_utils;
    use hp_library::test_utils;
    use hp_library::utils;
    use hp_mailbox::mailbox;
    use hp_router::router::{Self, RouterCap};
    use hp_token::native_token::{Self, NativeToken};
    use std::bcs;
    use std::debug;
    use std::features;
    use std::option;
    use std::signer;
    use std::vector;
    use aptos_std::from_bcs::to_bytes;


    const APTOS_TESTNET_DOMAIN: u32 = 14402;
    const DESTINATION_DOMAIN: u32 = 14402; // use destination chain the same as origin

    // Send and receive a native token test
    // A native token is a token like aptos on aptos or eth on ethereum
    // Use the same chain to send and receive
    // 1. tests calls dispatch() to send native coins
    // 2. it acts as a verifier and signs send checkpoint
    // 3. it calls handle() to validate signed transaction
    // 4. it ensures that tokens are transferred
    #[test(
        aptos_framework= @0x1,
        hp_router= @hp_router,
        hp_mailbox= @hp_mailbox,
        hp_igps= @hp_igps,
        hp_isms= @hp_isms,
        hp_token= @hp_token,
        alice= @0xa11ce,
        bob = @0xb0b,
    )]
    fun dispatch_handle_test(aptos_framework: signer, hp_router: signer,
                             hp_mailbox: signer, hp_igps: signer, hp_isms: signer,
                             hp_token: signer, alice: signer, bob: signer) {
        test_utils::setup(
            &aptos_framework,
            &hp_token,
            vector[@hp_mailbox, @hp_token, @hp_igps, @hp_isms, @0xa11ce, @0xb0b]
        );

        // enable auid feature because mailbox needs to call `get_transaction_hash()`
        let feature = features::get_auids();
        features::change_feature_flags_for_next_epoch(&aptos_framework, vector[feature], vector[]);

        // block must be initilized because mailbox access block resource
        account::create_account_for_test(@aptos_framework);
        block::initialize_for_test(&aptos_framework, 1000 /* epoch_interval */);

        // init mailbox
        mailbox::init_for_test(&hp_mailbox);
        mailbox::initialize(&hp_mailbox, APTOS_TESTNET_DOMAIN);

        // init router module
        // this is a global hash map which keeps track of all individual
        // local token routers and domains and their remote counterparts
        router::init_for_test(&hp_router);

        // init native token router module
        // token modules are also called routers in hypelane jargon
        // these are token contracts which are responsible of keeping track of
        // token balances and are inserted into the router roater using
        // enroll_remote_router()
        native_token::init_for_test(&hp_token);

        // enroll a remote token router which handles native token transfer on the other chain
        // since we use the same chain the remote router is the same as the sending one - hp_token
        // in real scenario the receiving router would be a synthetic token router
        let destination_router = bcs::to_bytes(&signer::address_of(&hp_token));
        router::enroll_remote_router<NativeToken>(&hp_token, DESTINATION_DOMAIN, destination_router);

        // check routers and domains
        assert!(router::get_remote_router_for_test<NativeToken>(DESTINATION_DOMAIN) == destination_router, 0);
        assert!(router::get_routers<NativeToken>() == vector[destination_router], 0);
        assert!(router::get_domains<NativeToken>() == vector[DESTINATION_DOMAIN], 0);

        // init gas paymaster for gas transfers first
        // set exchange rate: 1 x 1
        let token_exchange_rate: u128 = 10_000_000_000;
        let gas_price: u128 = 10;

        let required_gas_amount = set_igps_for_test(&hp_igps, DESTINATION_DOMAIN,
            native_token::get_default_gas_amount(),
            gas_price, token_exchange_rate);

        // beneficiary address containing reserved tokens
        let beneficiary_address = native_token::get_beneficiary();

        let alice_address = signer::address_of(&alice);
        let bob_address = signer::address_of(&bob);
        let igps_address = signer::address_of(&hp_igps);

        // check balance pre-transfer
        let alice_balance_pre = coin::balance<AptosCoin>(alice_address);
        let bob_balance_pre = coin::balance<AptosCoin>(bob_address);
        let beneficiary_balance_pre = coin::balance<AptosCoin>(beneficiary_address);
        let igps_balance_pre = coin::balance<AptosCoin>(igps_address);

        // send tokens
        let amount: u64 = 12;
        native_token::transfer_remote(&alice,
            DESTINATION_DOMAIN,
            bcs::to_bytes<address>(&bob_address),
            amount);

        // check balance post-transfer
        let alice_balance_post = coin::balance<AptosCoin>(alice_address);
        let beneficiary_balance_post = coin::balance<AptosCoin>(beneficiary_address);
        let igps_balance_post = coin::balance<AptosCoin>(igps_address);
        let bob_balance_post = coin::balance<AptosCoin>(bob_address);

        // alice balance decreased by amount
        assert!(alice_balance_pre - alice_balance_post == amount + required_gas_amount, 0);

        // gas paymaster balance increased
        assert!(igps_balance_post - igps_balance_pre == required_gas_amount, 0);

        // beneficiary balance increased
        assert!(beneficiary_balance_post - beneficiary_balance_pre == amount, 0);

        // bob balance has not changed
        assert!(bob_balance_post == bob_balance_pre, 0);

        // check message is in mailbox
        assert!(mailbox::outbox_get_count() == 1, 0);

        // retrieve checkpoint just like a validator
        let (root, count) = mailbox::outbox_latest_checkpoint();

        // format message and its digest to sign just like a validator would do
        let token_message_bytes = msg_utils::format_token_message(amount);
        let (message_bytes, digest_bytes_to_sign) = msg_utils::format_message_and_digest(root,
            count - 1,
            APTOS_TESTNET_DOMAIN,
            signer::address_of(&hp_token),
            signer::address_of(&hp_mailbox),
            DESTINATION_DOMAIN,
            bcs::to_bytes<address>(&bob_address),
            token_message_bytes);

        std::debug::print<std::string::String>(&std::string::utf8(b"-----digest_bytes_to_sign------------"));
        std::debug::print(&digest_bytes_to_sign);

        // if this fails you would need to use sign_msg.js to get a new digest_bytes_signature below
        // it is not possible to sign inside move
        assert!(&digest_bytes_to_sign == &x"06398b6c59f3e55bf7362f835acaaa187c3b11f33f05187bbe004a7c879b3ccf", 0);

        // A test signature from this Ethereum address:
        //   Address: 0x050D907812D2D2de09Ba8D6cE414d6fee84C29Cb
        //   Private Key: 0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499
        //   Public Key: 0x6bbae7820a27ff21f28ba5a4b64c8b746cdd95e2b3264a686dd15651ef90a2a1 // LN1_ISMS_ADDRESS
        // The signature was generated using ethers-js:
        //   wallet = new ethers.Wallet('0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499')
        //   await wallet.signMessage(ethers.utils.arrayify('06398b6c59f3e55bf7362f835acaaa187c3b11f33f05187bbe004a7c879b3ccf'))

        // Or use 'node sign_msg.js' to sign a message in message_bytes if digest_bytes_to_sign changes
        // node sign_msg.js 0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499 06398b6c59f3e55bf7362f835acaaa187c3b11f33f05187bbe004a7c879b3ccf
        let digest_bytes_signature = x"909f3b00d43b2ffd24d0a27c37cc35d66b74f1584e6683c660171c1d3711be161654fc1edde422b19584c9f813a328cf76dca69374e7455d871ab26e7430ddad1b";

        // package signature and other attributes into checkpoint metadata just like a validator
        let metadata_bytes = ism_metadata::format_signature_into_bytes(
            signer::address_of(&hp_mailbox),
            root,
            count - 1,
            digest_bytes_signature
        );

        // ensure that correct validator address can be derived from signed message
        // LN1_ISMS_ADDRESS
        let isms1_eth_address = @0x050D907812D2D2de09Ba8D6cE414d6fee84C29Cb;
        ensure_validator_address(isms1_eth_address,
            digest_bytes_to_sign,
            digest_bytes_signature);

        // init ism
        // interchain security module is responsible
        // for verifying signatures and checkin signature threshold
        // it will be used inside handle_message() on the other chain
        // below allowing tokens to be minted or transferred
        multisig_ism::init_for_test(&hp_isms);
        multisig_ism::set_validators_and_threshold(
            &hp_isms,
            vector[isms1_eth_address],
            1, // threshold
            DESTINATION_DOMAIN   // origin_domain
        );

        let bob_balance_pre_1 = coin::balance<AptosCoin>(bob_address);
        let beneficiary_balance_pre_1 = coin::balance<AptosCoin>(beneficiary_address);

        // handle message
        // This method will check signatures, threshold and doesn mint/transfer
        // on the other chain
        native_token::handle_message(message_bytes, metadata_bytes);

        let bob_balance_post_1 = coin::balance<AptosCoin>(bob_address);
        let beneficiary_balance_post_1 = coin::balance<AptosCoin>(beneficiary_address);

        // check balances
        assert!(bob_balance_post_1 - bob_balance_pre_1 == amount, 0);
        assert!(beneficiary_balance_pre_1 - beneficiary_balance_post_1 == amount, 0);
    }

    fun ensure_validator_address(expected_eth_address: address,
                                 digest_bytes_to_sign: vector<u8>,
                                 digest_bytes_signature: vector<u8>) {
        // Derive validator ethereum address
        // This test is to ensure that signing key hasn't changed
        // as native_token::handle_message() below calls veryfy() inside and expects this address
        // If a signer address changes, replace isms1_eth_address with a new value produced by
        // secp256k1_recover_ethereum_address()
        let digest_bytes_hash = utils::eth_signed_message_hash(&digest_bytes_to_sign);
        let eth_address_opt = utils::secp256k1_recover_ethereum_address(&digest_bytes_hash, &digest_bytes_signature);
        assert!(option::is_some(&eth_address_opt), 0);
        let eth_address_bytes = option::borrow(&eth_address_opt);

        std::debug::print<std::string::String>(&std::string::utf8(b"-----eth_address_bytes------------"));
        std::debug::print(eth_address_bytes);

        // make sure it matches expected address
        assert!(utils::compare_bytes_and_address(
            eth_address_bytes,
            &expected_eth_address
        ), 0);
    }
}