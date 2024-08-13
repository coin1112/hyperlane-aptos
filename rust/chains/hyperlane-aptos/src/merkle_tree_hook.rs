use crate::types::*;
use crate::AptosMailbox;
use crate::{utils, AptosMailboxIndexer};
use async_trait::async_trait;
use derive_new::new;
use hyperlane_core::Indexer;
use hyperlane_core::LogMeta;
use hyperlane_core::MerkleTreeInsertion;
use hyperlane_core::SequenceAwareIndexer;
use hyperlane_core::{
    accumulator::incremental::IncrementalMerkle, ChainCommunicationError, ChainResult, Checkpoint,
    MerkleTreeHook, H256,
};
use hyperlane_core::{HyperlaneMessage, Indexed};
use std::num::NonZeroU64;
use std::ops::RangeInclusive;
use std::str::FromStr;
use tracing::{debug, instrument};

#[async_trait]
impl MerkleTreeHook for AptosMailbox {
    #[instrument(err, ret, skip(self))]
    async fn tree(&self, _lag: Option<NonZeroU64>) -> ChainResult<IncrementalMerkle> {
        let view_response = utils::send_view_request(
            &self.aptos_client,
            self.package_address.to_hex_literal(),
            "mailbox".to_string(),
            "outbox_get_tree".to_string(),
            vec![],
            vec![],
        )
        .await?;
        let view_result =
            serde_json::from_str::<MoveMerkleTree>(&view_response[0].to_string()).unwrap();
        Ok(view_result.into())
    }

    #[instrument(err, ret, skip(self))]
    async fn latest_checkpoint(&self, lag: Option<NonZeroU64>) -> ChainResult<Checkpoint> {
        let tree = self.tree(lag).await?;

        let root = tree.root();
        let count: u32 = tree
            .count()
            .try_into()
            .map_err(ChainCommunicationError::from_other)?;
        let index = count.checked_sub(1).ok_or_else(|| {
            ChainCommunicationError::from_contract_error_str(
                "Outbox is empty, cannot compute checkpoint",
            )
        })?;

        let checkpoint = Checkpoint {
            merkle_tree_hook_address: H256::from_str(&self.package_address.to_hex()).unwrap(),
            mailbox_domain: self.domain.id(),
            root,
            index,
        };
        Ok(checkpoint)
    }

    #[instrument(err, ret, skip(self))]
    async fn count(&self, _maybe_lag: Option<NonZeroU64>) -> ChainResult<u32> {
        let tree = self.tree(_maybe_lag).await?;
        tree.count()
            .try_into()
            .map_err(ChainCommunicationError::from_other)
    }
}

/// Struct that retrieves event data for Aptos merkle tree hook contract
#[derive(Debug, new)]
pub struct AptosMerkleTreeHookIndexer(AptosMailboxIndexer);

#[async_trait]
impl Indexer<MerkleTreeInsertion> for AptosMerkleTreeHookIndexer {
    async fn fetch_logs(
        &self,
        range: RangeInclusive<u32>,
    ) -> ChainResult<Vec<(Indexed<MerkleTreeInsertion>, LogMeta)>> {
        debug!(
            ?range,
            "AptosMerkleTreeHookIndexer::Indexer<MerkleTreeInsertion>::fetch_logs"
        );
        let messages = self.0.fetch_logs(range).await?;
        let merkle_tree_insertions = messages
            .into_iter()
            .map(|(m, meta)| (message_to_merkle_tree_insertion(m.inner()).into(), meta))
            .collect();

        Ok(merkle_tree_insertions)
    }

    async fn get_finalized_block_number(&self) -> ChainResult<u32> {
        Indexer::<HyperlaneMessage>::get_finalized_block_number(&self.0).await
    }
}

fn message_to_merkle_tree_insertion(message: &HyperlaneMessage) -> MerkleTreeInsertion {
    let leaf_index = message.nonce;
    let message_id = message.id();
    MerkleTreeInsertion::new(leaf_index, message_id)
}

#[async_trait]
impl SequenceAwareIndexer<MerkleTreeInsertion> for AptosMerkleTreeHookIndexer {
    async fn latest_sequence_count_and_tip(&self) -> ChainResult<(Option<u32>, u32)> {
        SequenceAwareIndexer::<HyperlaneMessage>::latest_sequence_count_and_tip(&self.0).await
    }
}
