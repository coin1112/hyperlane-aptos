#[test_only]
module hp_igps::test_utils {
    use std::vector;
    use std::signer;

    use aptos_framework::coin::{Self, MintCapability, BurnCapability};
    use aptos_framework::aptos_account;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use hp_igps::igps;
    use hp_igps::gas_oracle;

    public fun init_igps_for_test(hp_igps: &signer) {
        // init `gas_oracle` module with contract account
        gas_oracle::init_for_test(hp_igps);
        // init `igps` module with contract account
        igps::init_for_test(hp_igps);
    }

    public fun set_igps_for_test(account: &signer, destination_domain: u32, default_gas_amount: u256,
                                 gas_price: u128, token_exchange_rate: u128): u64 {
        // init gas paymaster for gas transfers first
        init_igps_for_test(account);

        // set gas data
        hp_igps::gas_oracle::set_remote_gas_data(
            account,
            destination_domain,
            token_exchange_rate,
            gas_price
        );

        // required gas
        let required_gas_amount = (hp_igps::igps::quote_gas_payment(destination_domain,
            default_gas_amount) as u64);
        required_gas_amount
    }
}