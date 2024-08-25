module hp_library::token_msg_utils {
    // use std::vector;
    use std::string::{Self, String};
    use std::bcs;
    use std::vector;

    use aptos_std::from_bcs;
    use aptos_std::aptos_hash;
    use std::debug;

    use hp_library::utils::{ extract_from_bytes, extract_from_bytes_reversed };

    const E_INVALID_RECIPIENT_LENGTH: u64 = 1;

    /// Convert message data into bytes
    public fun format_message_into_bytes(
        version: u8,
        nonce: u32,
        origin: u32,
        sender: address,
        destination: u32,
        recipient: vector<u8>,
        amount: u128,
        metadata: vector<u8>,
    ): vector<u8> {
        // check input parameters
        // recipient address is 32 bytes
        assert!(vector::length(&recipient) == 32, E_INVALID_RECIPIENT_LENGTH);

        let result = vector::empty<u8>();
        // convert into big-endian
        let nonce_bytes = bcs::to_bytes<u32>(&nonce);
        vector::reverse(&mut nonce_bytes);
        let origin_domain_bytes = bcs::to_bytes<u32>(&origin);
        vector::reverse(&mut origin_domain_bytes);
        let dest_domain_bytes = bcs::to_bytes<u32>(&destination);
        vector::reverse(&mut dest_domain_bytes);
        let amount_bytes = bcs::to_bytes<u128>(&amount);
        vector::reverse(&mut amount_bytes);

        vector::append(&mut result, bcs::to_bytes<u8>(&version));
        vector::append(&mut result, nonce_bytes);
        vector::append(&mut result, origin_domain_bytes);
        vector::append(&mut result, bcs::to_bytes<address>(&sender));
        vector::append(&mut result, dest_domain_bytes);
        vector::append(&mut result, recipient);
        vector::append(&mut result, amount_bytes);
        vector::append(&mut result, metadata);
        result
    }

    public fun id(msg: &vector<u8>): vector<u8> {
        aptos_hash::keccak256(*msg)
    }

    public fun version(bytes: &vector<u8>): u8 {
        from_bcs::to_u8(extract_from_bytes(bytes, 0, 1))
    }

    public fun nonce(bytes: &vector<u8>): u32 {
        from_bcs::to_u32(extract_from_bytes_reversed(bytes, 1, 5))
    }

    public fun origin_domain(bytes: &vector<u8>): u32 {
        from_bcs::to_u32(extract_from_bytes_reversed(bytes, 5, 9))
    }

    public fun sender(bytes: &vector<u8>): vector<u8> {
        extract_from_bytes(bytes, 9, 41)
    }

    public fun dest_domain(bytes: &vector<u8>): u32 {
        from_bcs::to_u32(extract_from_bytes_reversed(bytes, 41, 45))
    }

    public fun recipient(bytes: &vector<u8>): vector<u8> {
        extract_from_bytes(bytes, 45, 77)
    }

    public fun amount(bytes: &vector<u8>): u128 {
        from_bcs::to_u128(extract_from_bytes_reversed(bytes, 77, 93))
    }

    public fun metadata(bytes: &vector<u8>): vector<u8> {
        extract_from_bytes(bytes, 93, 0)
    }

    // This is specific for Aptos cuz the target should have
    // address and module name
    //
    /*struct HpAptosMsgBody has store {
      // 4 module name Length
      length: u32,
      // 0+[Length] Target Module Name
      target_module: String
      // 0+ Body contents
      content: vector<u8>,
    }*/
    // get module name from the message bytes
    public fun extract_module_name_from_body(body_bytes: &vector<u8>): String {
        let module_name_length = from_bcs::to_u32(extract_from_bytes_reversed(body_bytes, 0, 4));
        let module_name_bytes = extract_from_bytes(body_bytes, 4, ((4 + module_name_length) as u64));
        string::utf8(module_name_bytes)
    }


    #[test]
    fun token_msg_roundtrip_test() {
        // encode message
        let recipient_vec: vector<u8> = x"d1eaef049ac77e63f2ffefae43e14c1a73700f25cde849b6614dc3f358012335";
        let metadata_vec: vector<u8> = x"d1eaef049ac77e63f2ffefae43e14c1a73700f25cde849b6614dc3f358";
        let token_msg = format_message_into_bytes(25, 1111, 1234,
            @0xd1eaef049ac77e63f2ffefae43e14c1a73700f25cde849b6614dc3f358012335,
            5678, recipient_vec, 1000, metadata_vec);
        let message = string::utf8(b"token_msg_roundtrip_test: token_msg:");
        debug::print(&message);
        debug::print(&token_msg);

        // decode message
        assert!(version(&token_msg) == 25, 0);
        assert!(nonce(&token_msg) == 1111, 1);
        assert!(origin_domain(&token_msg) == 1234, 2);
        assert!(sender(&token_msg) == x"d1eaef049ac77e63f2ffefae43e14c1a73700f25cde849b6614dc3f358012335", 3);
        assert!(dest_domain(&token_msg) == 5678, 4);
        assert!(recipient(&token_msg) == x"d1eaef049ac77e63f2ffefae43e14c1a73700f25cde849b6614dc3f358012335", 5);
        assert!(amount(&token_msg) == 1000, 6);
        assert!(metadata(&token_msg) == metadata_vec, 7);
    }
}