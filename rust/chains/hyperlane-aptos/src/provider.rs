use aptos_sdk::crypto::HashValue;
use aptos_sdk::rest_client::aptos_api_types::Transaction;

use async_trait::async_trait;
use tracing::warn;

use hyperlane_core::{
    BlockInfo, ChainCommunicationError, ChainInfo, ChainResult, HyperlaneChain, HyperlaneDomain,
    HyperlaneProvider, TxnInfo, TxnReceiptInfo, H256, U256,
};

use crate::{convert_hex_string_to_h256, AptosClient};

/// A wrapper around a Aptos provider to get generic blockchain information.
#[derive(Debug)]
pub struct AptosHpProvider {
    domain: HyperlaneDomain,
    aptos_client: AptosClient,
}

impl AptosHpProvider {
    /// Create a new Aptos provider.
    pub fn new(domain: HyperlaneDomain, rest_url: String) -> Self {
        let aptos_client = AptosClient::new(rest_url);
        AptosHpProvider {
            domain,
            aptos_client,
        }
    }
}

impl HyperlaneChain for AptosHpProvider {
    fn domain(&self) -> &HyperlaneDomain {
        &self.domain
    }

    fn provider(&self) -> Box<dyn HyperlaneProvider> {
        Box::new(AptosHpProvider::new(
            self.domain.clone(),
            self.aptos_client.path_prefix_string(),
        ))
    }
}

#[async_trait]
impl HyperlaneProvider for AptosHpProvider {
    async fn get_block_by_hash(&self, _hash: &H256) -> ChainResult<BlockInfo> {
        // getting block by hash is not supported in Aptos
        todo!() // FIXME
    }

    async fn get_txn_by_hash(&self, hash: &H256) -> ChainResult<TxnInfo> {
        let transaction: Transaction = self
            .aptos_client
            .get_transaction_by_hash(HashValue::from_slice(hash.as_bytes()).unwrap())
            .await
            .unwrap()
            .into_inner();

        let mut gas_price = None;
        let mut gas_limit = U256::zero();
        let mut sender = H256::zero();

        let tx_info = transaction.transaction_info().unwrap().clone();

        if let Transaction::UserTransaction(tx) = transaction {
            gas_price = Some(U256::from(tx.request.gas_unit_price.0));
            gas_limit = U256::from(tx.request.max_gas_amount.0);
            sender = convert_hex_string_to_h256(&tx.request.sender.to_string()).unwrap();
        }

        Ok(TxnInfo {
            hash: *hash,
            max_fee_per_gas: None,
            max_priority_fee_per_gas: None,
            gas_price,
            gas_limit,
            nonce: tx_info.version.0,
            sender,
            recipient: None,
            receipt: Some(TxnReceiptInfo {
                gas_used: U256::from(tx_info.gas_used.0),
                cumulative_gas_used: U256::zero(),
                effective_gas_price: None,
            }),
        })
    }

    async fn is_contract(&self, _address: &H256) -> ChainResult<bool> {
        // Aptos account can be both normal account & contract account
        Ok(true)
    }

    async fn get_balance(&self, address: String) -> ChainResult<U256> {
        let balance = self
            .aptos_client
            .get_account_balance(
                address
                    .parse()
                    .map_err(ChainCommunicationError::from_other)?,
            )
            .await
            .map_err(ChainCommunicationError::from_other)?
            .into_inner();
        Ok(U256::from(balance.get()))
    }

    async fn get_chain_metrics(&self) -> ChainResult<Option<ChainInfo>> {
        let state = self
            .aptos_client
            .get_ledger_information()
            .await
            .map_err(ChainCommunicationError::from_other)?;
        let mut version = state.state().version;
        let mut block_depth = 0;
        while version > 0 && block_depth > 1000 {
            let block = self
                .aptos_client
                .get_block_by_version(version, false)
                .await
                .unwrap()
                .into_inner();
            if block.block_height.0 != state.state().block_height {
                version -= 1;
                block_depth += 1;
                continue;
            }
            let timestamp = block.block_timestamp.0;
            return Ok(Some(ChainInfo {
                latest_block: BlockInfo {
                    hash: convert_hex_string_to_h256(&block.block_hash.to_string()).unwrap(),
                    timestamp, // microseconds
                    number: state.state().block_height,
                },
                min_gas_price: None,
            }));
        }
        warn!(
            "No block found for the current ledger version {} and block_height {}",
            state.state().version,
            state.state().block_height
        );
        Ok(None)
    }
}
