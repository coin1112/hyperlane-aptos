// Import the ethers library
const { ethers } = require('ethers');

async function main() {
  // Retrieve the private key and message from the command line arguments
  const [privateKey, message] = process.argv.slice(2);

  // Check if the required arguments are provided
  if (!privateKey || !message) {
    console.error('Usage: node sign_msg.js <privateKey> <message>. E.g.');
    console.error(
      'node sign_msg.js 0xe1434ec74549ce4c3d6eded91a0656f864b0982fdb196ef511921efc25dfc499 0x367c815be770c0b6de0249ce32c68512365ffcda8f586726527df3e7169e406d',
    );
    process.exit(1);
  }

  // Initialize a wallet instance with the provided private key
  const wallet = new ethers.Wallet(privateKey);

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
