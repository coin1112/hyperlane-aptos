# run e2e tests for cosmos 
cargo test --release --package run-locally --bin run-locally --features cosmos test-utils -- cosmos::test --nocapture
