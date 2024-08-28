// Import the ethers library
const { ethers } = require('ethers');

async function main() {
  // Initialize a wallet instance with a private key
  const wallet = new ethers.Wallet(
    '0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499',
  );

  // Define the message to be signed
  const message =
    '0x000000000000003842f5ee93f71eac3125478f7877dcc3172bef0daa4669001a3b9a05d530ac74a4af00003842f5ee93f71eac3125478f7877dcc3172bef0daa4669001a3b9a05d530ac74a4af00000000';

  // Convert the message to a byte array
  const messageBytes = ethers.utils.arrayify(message);

  // Sign the message
  const signature = await wallet.signMessage(messageBytes);

  // Output the signature
  console.log('Signature:', signature);
}

// Execute the main function
main().catch((error) => {
  console.error('Error:', error);
});
