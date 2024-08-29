module hp_library::msg_utils {
    use std::string::{Self, String};
    use std::bcs;
    use std::vector;

    use aptos_std::from_bcs;
    use aptos_std::aptos_hash;

    use hp_library::utils::{ extract_from_bytes, extract_from_bytes_reversed,
        ism_checkpoint_hash, get_version};

    /// Convert message ata into bytes
    public fun format_message_into_bytes(
        version: u8,
        nonce: u32,
        origin: u32,
        sender: address,
        destination: u32,
        recipient: vector<u8>,
        body: vector<u8>,
    ): vector<u8> {
        let result = vector::empty<u8>();
        // convert into big-endian
        let nonce_bytes = bcs::to_bytes<u32>(&nonce);
        vector::reverse(&mut nonce_bytes);
        let origin_domain_bytes = bcs::to_bytes<u32>(&origin);
        vector::reverse(&mut origin_domain_bytes);
        let dest_domain_bytes = bcs::to_bytes<u32>(&destination);
        vector::reverse(&mut dest_domain_bytes);

        vector::append(&mut result, bcs::to_bytes<u8>(&version));
        vector::append(&mut result, nonce_bytes);
        vector::append(&mut result, origin_domain_bytes);
        vector::append(&mut result, bcs::to_bytes<address>(&sender));
        vector::append(&mut result, dest_domain_bytes);
        vector::append(&mut result, recipient);
        vector::append(&mut result, body);
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

    public fun recipient(bytes: &vector<u8>): address {
        from_bcs::to_address(extract_from_bytes(bytes, 45, 77))
    }

    public fun body(bytes: &vector<u8>): vector<u8> {
        extract_from_bytes(bytes, 77, 0)
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

    // Serialize transfer_remote() data into byte arry to send to the other chain
    public fun format_token_message(
        amount: u64,
    ): vector<u8> {
        let result = vector::empty<u8>();
        // use little endian format since EVM uses it
        let amount_bytes = bcs::to_bytes<u64>(&amount);
        vector::append(&mut result, amount_bytes);
        result
    }

    public fun amount_from_token_message(bytes: &vector<u8>): u64 {
        from_bcs::to_u64(extract_from_bytes(bytes, 0, 8))
    }

    #[test_only]
    public fun format_message_and_digest(
        root: vector<u8>,
        nonce: u32,
        domain_origin: u32,
        sender_address: address,
        mailbox_address: address,
        domain_target: u32,
        recipient: vector<u8>,
        message_body: vector<u8>,
    ): (vector<u8>, vector<u8>) {
        // get message id
        let message_bytes = format_message_into_bytes(
            get_version(), // version
            nonce,
            domain_origin, // domain
            sender_address, // sender address
            domain_target, // destination domain
            recipient, // recipient
            message_body
        );
        let message_id = id(&message_bytes);

        // generate digest to sign
        // note that message_id is derived as a hash of the full message
        // which gurantees message integrity
        let digest_bytes_to_sign = ism_checkpoint_hash(
            mailbox_address,
            domain_origin,
            root,
            nonce,
            message_id
        );
        (message_bytes, digest_bytes_to_sign)
    }
}