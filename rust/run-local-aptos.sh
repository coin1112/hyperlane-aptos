set -e
set -x

if [ -z "${HYP_LOCAL_BIN}" ]; then
  export LOCAL_BIN="$HOME/.local/bin"
else
  export LOCAL_BIN="${HYP_LOCAL_BIN}"
fi

# To make use of aptos cli
export PATH="${LOCAL_BIN}:$PATH"

#
# run local aptos node
aptos node run-local-testnet --with-faucet --faucet-port 8081 --force-restart --assume-yes > /tmp/aptos-local-node.log 2>&1&

sleep 20
pushd ../move/e2e/
./compile-and-deploy.sh




