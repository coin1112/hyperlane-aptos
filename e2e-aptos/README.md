# e2e tests for aptos

## Run e2e tests manually

```
# in rust directory
./run-local-aptos.sh
./init-local-aptos.sh
./run-validator.sh 0 # run validator for aptoslocal1
cd ../move/e2e
./init_states.sh send_hello_ln1_to_ln2 # send hello from aptos1 to aptos2
./init_states.sh send_hello_ln2_to_ln1
```

## Cleanup

```angular2html
# stop aptos
./stop-local-aptos.sh

# stop hyperlane agents
./stop-local-hyperlane.sh
```

# Run e2e test suite

```
# this runs aptos local client, 2 validators, relayer and test message scraper
# run-locally binary will send test messages between 2 set of aptos smart contracts,
# validators will sign them, relayer will deliver signatures and test scraper counts them
# in rust directory
../rust/target/debug/run-locally-aptos
...
<E2E> E2E tests passed
...

```

run tests in infinite mode

```angular2html
HYB_BASE_LOOP=1  ../rust/target/debug/run-locally-aptos

```
