
#[test_only]
module hp_token::native_token_tests {
    use std::debug;


    #[test(aptos_framework=@0x1, hp_router=@hp_router)]
    fun dummy_test(aptos_framework: signer, hp_router: signer) {
        debug::print<std::string::String>(&std::string::utf8(b"dummy_test"));
    }
}