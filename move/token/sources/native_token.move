/// Native hyperlane token

module hp_token::native_token {
use std::vector;
use hp_router::router;
//use hp_library::msg_utils;//
use hp_mailbox::mailbox;

struct NativeToken {}

struct State has key {
    cap: router::RouterCap<NativeToken>,
    received_messages: vector<vector<u8>>
}

/// Initialize Module
fun init_module(account: &signer) {
    let cap = router::init<NativeToken>(account);
    move_to<State>(account, State {
        cap,
        received_messages: vector::empty()
    });
    }
}
