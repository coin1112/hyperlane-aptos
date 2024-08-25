#common
set -e
export HYP_RUST_BACKTRACE=full
export HYP_LOG_FORMAT=compact
export HYP_LOG_LEVEL=debug
export HYP_CHAINS_TEST1_INDEX_CHUNK=1
export HYP_CHAINS_TEST2_INDEX_CHUNK=1
export HYP_CHAINS_TEST3_INDEX_CHUNK=1
export HYP_CHAINS_TEST1_CUSTOMRPCURLS="http://127.0.0.1:8545,http://127.0.0.1:8545,http://127.0.0.1:8545"
#base validator
export HYP_CHAINS_TEST1_RPCCONSENSUSTYPE=quorum
export HYP_CHAINS_TEST2_CUSTOMRPCURLS="http://127.0.0.1:8545,http://127.0.0.1:8545,http://127.0.0.1:8545"
export HYP_CHAINS_TEST2_RPCCONSENSUSTYPE=fallback
export HYP_CHAINS_TEST3_CUSTOMRPCURLS="http://127.0.0.1:8545"
export HYP_CHAINS_APTISLOCALNET1_RPCCONSENSUSTYPE=httpFallback
export HYP_CHAINS_APTOSLOCALNET2_RPCCONSENSUSTYPE=httpFallback
export HYP_CHAINS_APTOSLOCALNET1_SIGNER_KEY="0xb25d6937002ecd4d79c7bdfddc0053febc8896f2109e96c45bf69efd84544cd5"
export HYP_CHAINS_APTOSLOCALNET2_SIGNER_KEY="0xe299c1e6e1f89b4ed2992782137e24d5edbfc51bb702635a85ed6b687c2b5988"
export HYP_CHAINS_TEST1_BLOCKS_REORGPERIOD=0
export HYP_CHAINS_TEST2_BLOCKS_REORGPERIOD=0
export HYP_CHAINS_TEST3_BLOCKS_REORGPERIOD=0
export HYP_REORGPERIOD=0
export HYP_INTERVAL=5
export HYP_CHAINS_APTOSLOCALNET1_MERKLETREEHOOK="0x476307c25c54b76b331a4e3422ae293ada422f5455efed1553cf4de1222a108f" # invalid
export HYP_CHAINS_APTOSLOCALNET2_MERKLETREEHOOK="0xd338e68ca12527e77cab474ee8ec91ffa4e6512ced9ae8f47e28c5c7c4804b78" # invalid
export HYP_CHECKPOINTSYNCER_TYPE=localStorage
export HYP_LOG_LEVEL=0
export HYP_CHAINS_APTOSLOCALNET1_CONNECTION_URL="http://127.0.0.1:8080/v1"
export HYP_CHAINS_APTOSLOCALNET2_CONNECTION_URL="http://127.0.0.1:8080/v1"


if [ $# -eq 0 ]; then
  echo "Error: No arguments were passed. allowed 0 or 1"
  exit 1
fi


#validator
if [[ $1 -eq 0 ]]; then
  echo "Setting up validator 0"
  export HYP_METRICSPORT=9094
  export HYP_DB="/tmp/hp/validator0"
  export HYP_ORIGINCHAINNAME=aptoslocalnet1
  export HYP_VALIDATOR_KEY="0xb25d6937002ecd4d79c7bdfddc0053febc8896f2109e96c45bf69efd84544cd5"
  export HYP_CHECKPOINTSYNCER_PATH="/tmp/hp/checkpoints0"
elif [[ $1 -eq 1 ]]; then
  echo "Setting up validator 1"
  export HYP_METRICSPORT=9095
  export HYP_DB="/tmp/hp/validator1"
  export HYP_ORIGINCHAINNAME=aptoslocalnet2
  export HYP_VALIDATOR_KEY="0xe299c1e6e1f89b4ed2992782137e24d5edbfc51bb702635a85ed6b687c2b5988"
  export HYP_CHECKPOINTSYNCER_PATH="/tmp/hp/checkpoints1"
else
  echo "Error: Argument must be 0 or 1."
  exit 1
fi

rm -rf "HYP_DB" || true
rm -rf "$HYP_CHECKPOINTSYNCER_PATH" || true
mkdir -p "HYP_DB"
mkdir -p "$HYP_CHECKPOINTSYNCER_PATH"

target/debug/validator


