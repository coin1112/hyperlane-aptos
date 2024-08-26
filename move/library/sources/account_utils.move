module hp_library::account_utils {
    use std::vector;
    use aptos_std::from_bcs;
    use hp_library::utils::{ extract_from_bytes };

    public fun derive_address_from_public_key(public_key: vector<u8>): address {
        // Compute the authentication key by hashing the public key with the scheme identifier
        vector::push_back(&mut public_key, 0x00);

        let auth_key = std::hash::sha3_256(public_key);

        // The account address is the first 32 bytes of the authentication key
        from_bcs::to_address(extract_from_bytes(&auth_key, 0, 32))
    }


    #[test]
    fun print_account_address() {
        let address = derive_address_from_public_key(x"A7ED51291E0D1DE0C20D40D3D8BC3E479BA611E6E52B89C4844A249055F73FC1");
        std::debug::print<std::string::String>(&std::string::utf8(b"-----print_account_address------------"));
        std::debug::print(&address);
    }
}