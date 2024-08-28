// Import the ethers library
const { ethers } = require('ethers');

async function main() {
  // Initialize a wallet instance with a private key
  const wallet = new ethers.Wallet(
    '0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499',
  );

  // Define the message to be signed
  const message =
    '0x9c56d415bcd9cb091a96b577667a8b15292f80561584a5af9d63f033593bcd63';
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
