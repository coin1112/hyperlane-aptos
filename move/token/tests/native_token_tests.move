#[test_only]
module hp_token::native_tests {
    use std::vector;
    use std::signer;
    use std::features;
    use std::debug;
    use std::option;
    use std::bcs;
    use aptos_framework::block;
    use aptos_framework::account;
    use hp_library::account_utils::derive_address_from_public_key;

    use hp_mailbox::mailbox;
    use hp_igps::igp_tests;
    use hp_library::test_utils;
    use hp_router::router::{Self, RouterCap};
    use hp_token::native_token::{Self, NativeToken};
    use hp_library::utils;
    use hp_library::msg_utils;
    use hp_library::ism_metadata;
    use hp_library::h256::{Self, H256};
    use hp_isms::multisig_ism;

    const APTOS_TESTNET_DOMAIN: u32 = 14402;
    const BSC_TESTNET_DOMAIN: u32 = 14402; // use destination chain the same as origin

    #[test(aptos_framework=@0x1, hp_router=@hp_router, hp_mailbox=@hp_mailbox, hp_igps=@hp_igps, hp_isms=@hp_isms, hp_token=@hp_token, alice=@0xa11ce)]
    fun dispatch_test(aptos_framework: signer, hp_router: signer,
                      hp_mailbox: signer, hp_igps: signer, hp_isms: signer,
                      hp_token: signer, alice: signer)  {
        test_utils::setup(&aptos_framework, &hp_token, vector[@hp_mailbox, @hp_token, @hp_igps, @hp_isms, @0xa11ce]);

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
        router::init_for_test(&hp_router);

        // init native token module
        native_token::init_for_test(&hp_token);

        // enroll fake remote router which handles native token transfer on the other chain
        let bsc_testnet_router = bcs::to_bytes(&signer::address_of(&hp_token));
        debug::print<std::string::String>(&std::string::utf8(b"-----bsc_testnet_router------------"));
        debug::print(&bsc_testnet_router);
        router::enroll_remote_router<NativeToken>(&hp_token, BSC_TESTNET_DOMAIN, bsc_testnet_router);

        // check routers and domains
        assert!(router::get_remote_router_for_test<NativeToken>(BSC_TESTNET_DOMAIN) == bsc_testnet_router, 0);
        assert!(router::get_routers<NativeToken>() == vector[bsc_testnet_router], 0);
        assert!(router::get_domains<NativeToken>() == vector[BSC_TESTNET_DOMAIN], 0);

        // init gas paypaster for gas transfers first
        igp_tests::init_igps_for_test(&hp_igps);

        // send tokens
        let message_body = vector[0, 0, 0, 0];
        native_token::remote_transfer(&hp_token, BSC_TESTNET_DOMAIN, message_body);

        // check message is in mailbox
        assert!(mailbox::outbox_get_count() == 1, 0);

        // retrieve checkpoint
        let (root, count) = mailbox::outbox_latest_checkpoint();
        debug::print<std::string::String>(&std::string::utf8(b"-----merle tree root------------"));
        debug::print(&root);
        debug::print<std::string::String>(&std::string::utf8(b"-----merle tree count------------"));
        debug::print(&count);

        // get message id
        let message_bytes = msg_utils::format_message_into_bytes(
            utils::get_version(), // version
            count-1,   // nonce
            APTOS_TESTNET_DOMAIN,   // domain
            signer::address_of(&hp_token),          // sender address
            BSC_TESTNET_DOMAIN,   // destination domain
            bsc_testnet_router,            // recipient
            message_body
        );
        let message_id = msg_utils::id(&message_bytes);

        debug::print<std::string::String>(&std::string::utf8(b"-----message_bytes------------"));
        debug::print(&message_bytes);

        // use 'node sign_msg.js' to sign a message in message_bytes
        let message_signature = x"7b7e6675f0aeae7732e03cb19a675454b2a195f071df8327408c80a87ae2b8c23c23ad8e88207e053d54e55dc2d56d7ed72f93a8cf72b271788b7ab1c29e803a1b";

        debug::print<std::string::String>(&std::string::utf8(b"-----message_signature------------"));
        debug::print(&message_signature);

        // let signer_address = utils::secp256k1_recover_ethereum_address(
        //     &signed_digest_bytes,
        //     &validator_signature
        // );
        //
        // debug::print<std::string::String>(&std::string::utf8(b"-----signer_address_test------------"));
        // debug::print(&signer_address);

        // let address = derive_address_from_public_key(option::borrow(&signer_address));
        // std::debug::print<std::string::String>(&std::string::utf8(b"-----print_account_address_test------------"));
        // std::debug::print(&address);


        let metadata_bytes = ism_metadata::format_signature_into_bytes(
            signer::address_of(&hp_mailbox),
            root,
            count-1,
            message_signature
        );

        // generate digest
        let signed_digest_bytes = utils::eth_signed_message_hash(&utils::ism_checkpoint_hash(
            signer::address_of(&hp_mailbox),
            APTOS_TESTNET_DOMAIN,
            root,
            count-1,
            message_id
        ));

        debug::print<std::string::String>(&std::string::utf8(b"-----signed_digest_bytes_test------------"));
        debug::print(&signed_digest_bytes);

        debug::print<std::string::String>(&std::string::utf8(b"-----mailbox_addr_test------------"));
        debug::print(&signer::address_of(&hp_mailbox));

        debug::print<std::string::String>(&std::string::utf8(b"-----domain_test------------"));
        debug::print(&APTOS_TESTNET_DOMAIN);

        debug::print<std::string::String>(&std::string::utf8(b"-----root_test------------"));
        debug::print(&root);


        // init ism
        multisig_ism::init_for_test(&hp_isms);
        multisig_ism::set_validators_and_threshold(
            &hp_isms,
            vector[signer::address_of(&hp_isms)],
            1,   // threshold
            BSC_TESTNET_DOMAIN   // origin_domain
        );

        // handle message
        native_token::handle_message(message_bytes, metadata_bytes);
    }
}