module hp_token::events {
    struct SentTransferRemote has store, drop {
        destination: u32,
        recipient: vector<u8>,
        amount: u64
    }

    public fun new_sent_transfer_remote_event(
        destination: u32,
        recipient: vector<u8>,
        amount: u64
    ): SentTransferRemote {
        SentTransferRemote { destination, recipient, amount }
    }
}