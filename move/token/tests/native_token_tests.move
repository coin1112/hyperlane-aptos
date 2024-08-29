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
        alice= @0xa11ce
    )]
    fun dispatch_handle_test(aptos_framework: signer, hp_router: signer,
                      hp_mailbox: signer, hp_igps: signer, hp_isms: signer,
                      hp_token: signer, alice: signer) {
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
        let bsc_testnet_router = bcs::to_bytes(&signer::address_of(&hp_token));
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

        // retrieve checkpoint just like a validator
        let (root, count) = mailbox::outbox_latest_checkpoint();

        // format message and its digest to sign just like a validator would do
        let (message_bytes, digest_bytes_to_sign) = msg_utils::format_message_and_digest(root,
            count - 1,
            APTOS_TESTNET_DOMAIN,
            signer::address_of(&hp_token),
            signer::address_of(&hp_mailbox),
            BSC_TESTNET_DOMAIN,
            bsc_testnet_router,
            message_body);

        // if this fails you would need to use sign_msg.js to get a new digest_bytes_signature below
        // it is not possible to sign inside move
        assert(&digest_bytes_to_sign == &x"9c56d415bcd9cb091a96b577667a8b15292f80561584a5af9d63f033593bcd63", 0);

        // A test signature from this Ethereum address:
        //   Address: 0xae58d95bfd2ea752280279f73a1ba40de7336349
        //   Private Key: 0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499
        //   Public Key: 0x6bbae7820a27ff21f28ba5a4b64c8b746cdd95e2b3264a686dd15651ef90a2a1
        // The signature was generated using ethers-js:
        //   wallet = new ethers.Wallet('0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499')
        //   await wallet.signMessage(ethers.utils.arrayify('0x9c56d415bcd9cb091a96b577667a8b15292f80561584a5af9d63f033593bcd63'))

        // use 'node sign_msg.js' to sign a message in message_bytes if digest_bytes_to_sign changes
        let digest_bytes_signature = x"085386535540a4356437672fda5e5260f7d85ae1aa80b08a5e4d315738317e5669d9b94379dcf9e2766bbc1aba4ee5f59a90b300fb59971f4d8b0739bbfa0c371c";

        // package signature and othjer attributes into checkpoint metadata just like a validator
        let metadata_bytes = ism_metadata::format_signature_into_bytes(
            signer::address_of(&hp_mailbox),
            root,
            count - 1,
            digest_bytes_signature
        );

        // Derive validator ethereum address
        // This test is to ensure that signing key hasn't changed
        // as native_token::handle_message() below calls veryfy() inside and expects this address
        // If a signer address changes, replace isms1_eth_address with a new value produced by
        // secp256k1_recover_ethereum_address()
        let eth_address_opt = utils::secp256k1_recover_ethereum_address(&digest_bytes_to_sign, &digest_bytes_signature);
        assert(option::is_some(&eth_address_opt), 0);
        let eth_address_bytes = option::borrow(&eth_address_opt);
        let isms1_eth_address = @0xae58d95bfd2ea752280279f73a1ba40de7336349;

        // make sure it matches expected address for LN1_ISMS_ADDRESS
        assert(utils::compare_bytes_and_address(
            eth_address_bytes,
            &isms1_eth_address
        ), 0);

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
            BSC_TESTNET_DOMAIN   // origin_domain
        );

        // handle message
        // This method will check signatures, threshold and doesn mint/transfer
        // on the other chain
        native_token::handle_message(message_bytes, metadata_bytes);
    }
}