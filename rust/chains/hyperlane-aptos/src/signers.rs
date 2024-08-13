use aptos_sdk::crypto::ed25519::{Ed25519PrivateKey, Ed25519PublicKey};
use aptos_sdk::crypto::{PrivateKey, ValidCryptoMaterialStringExt};
use aptos_sdk::types::account_address::AccountAddress;
use aptos_sdk::types::transaction::authenticator::AuthenticationKey;
use ed25519_dalek::SecretKey;
use hyperlane_core::ChainCommunicationError;
use hyperlane_core::ChainResult;
use solana_sdk::msg;
use solana_sdk::signer::keypair::Keypair;

#[derive(Debug)]
/// Signer for aptos chain
pub struct AptosSigner {
    /// Key pair
    pub keypair: Keypair,
    /// precomputed address, use aptos_cli code to derive address from keypair
    pub address: String,
}

impl AptosSigner {
    /// create new signer
    ///
    /// # Arguments
    /// * `private_key` - private key for signer
    /// * `prefix` - prefix for signer address
    pub fn new(secret: SecretKey) -> ChainResult<Self> {
        // TODO: how to simplify this?
        // secret -> ed25519_dalek::Keypair -> solana_sdk::signer::keypair::Keypair
        let keypair = Keypair::from_bytes(&ed25519_dalek::Keypair::from(secret).to_bytes())
            .map_err(|err| {
                msg!("{}", err);
                ChainCommunicationError::from_other_str("Cannot create keypair")
            })?;

        let binding = hex::encode(keypair.secret().to_bytes());
        let private_key_hex = binding.as_str();
        let private_key = match Ed25519PrivateKey::from_encoded_string(private_key_hex) {
            Ok(private_key) => private_key,
            Err(_) => {
                return Err(ChainCommunicationError::from_other_str(
                    "Cannot create private key",
                ));
            }
        };

        let public_key = private_key.public_key();
        let account_address = account_address_from_public_key(&public_key);
        Ok(Self {
            keypair,
            address: account_address.to_string(),
        })
    }
}

/// aptos uses a special way to generate account address from public key
/// the code is borrowed from aptos_cli code
pub fn account_address_from_public_key(public_key: &Ed25519PublicKey) -> AccountAddress {
    let auth_key = AuthenticationKey::ed25519(public_key);
    AccountAddress::new(*auth_key.account_address())
}

#[cfg(test)]
mod tests {
    use ed25519_dalek::SecretKey;
    use hyperlane_core::utils::hex_or_base58_to_h256;
    use hyperlane_core::Encode;

    #[test]
    fn test_private_key_to_public_key() {
        // Replace with your actual private key in hex format
        let private_key_str = "0x8cb68128b8749613f8df7612e4efd281f8d70f6d195c53a14c27fc75980446c1";
        let private_key_bytes = hex_or_base58_to_h256(private_key_str).unwrap();

        let secret = SecretKey::from_bytes(&private_key_bytes.to_vec())
            .expect("Invalid aptos ed25519 secret key");

        let aptos_signer = match super::AptosSigner::new(secret) {
            Ok(signer) => signer,
            Err(err) => panic!("Cannot create aptos signer, err: {:?}", err),
        };

        let expected_account_address =
            "0x8b4376073a408ece791f4adc34a8afdde405bae071711dcbb95ca4e5d4f26c93";
        assert_eq!(aptos_signer.address, expected_account_address);
    }
}
