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

    struct ReceivedTransferRemote has store, drop {
        origin: u32,
        recipient: address,
        amount: u64
    }

    public fun new_received_transfer_remote_event(
        origin: u32,
        recipient: address,
        amount: u64
    ): ReceivedTransferRemote {
        ReceivedTransferRemote { origin, recipient, amount }
    }
}