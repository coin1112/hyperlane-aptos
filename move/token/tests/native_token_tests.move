#[test_only]
module hp_token::native_tests {
    use std::vector;
    use std::signer;
    use std::features;
    use aptos_framework::block;
    use aptos_framework::account;

    use hp_mailbox::mailbox;
    use hp_igps::igp_tests;
    use hp_library::test_utils;
    use hp_router::router::{Self, RouterCap};
    use hp_token::native_token::{Self, NativeToken};

    const BSC_TESTNET_DOMAIN: u32 = 97;
    const APTOS_TESTNET_DOMAIN: u32 = 14402;

    struct RouterCapWrapper<phantom T> has key {
        router_cap: RouterCap<T>
    }

    #[test(aptos_framework=@0x1, hp_router=@hp_router, hp_mailbox=@hp_mailbox, hp_igps=@hp_igps, hp_token=@hp_token, alice=@0xa11ce)]
    fun dispatch_test(aptos_framework: signer, hp_router: signer, hp_mailbox: signer, hp_igps: signer, hp_token: signer, alice: signer)
    /*acquires RouterCapWrapper*/ {
        test_utils::setup(&aptos_framework, &hp_token, vector[@hp_mailbox, @hp_token, @hp_igps, @0xa11ce]);

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
        let bsc_testnet_router = x"57BBb149A040C04344d80FD788FF84f98DDFd391";
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
    }
}