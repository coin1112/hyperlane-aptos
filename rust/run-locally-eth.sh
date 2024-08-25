# run e2e tests for eth
export E2E_CI_MODE='true'
export E2E_CI_TIMEOUT_SEC='600'
export E2E_KATHY_MESSAGES='20'
export RUST_BACKTRACE='full'
export SEALEVEL_ENABLED=false # disable solana tests
cargo run --release --bin run-locally --features test-utils
