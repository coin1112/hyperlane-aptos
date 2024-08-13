//! Run this from the hyperlane-monorepo/rust directory using `cargo run -r -p
//! run-locally`.
//!
//! Environment arguments:
//! - `E2E_CI_MODE`: true/false, enables CI mode which will automatically wait
//!   for kathy to finish
//! running and for the queues to empty. Defaults to false.
//! - `E2E_CI_TIMEOUT_SEC`: How long (in seconds) to allow the main loop to run
//!   the test for. This
//! does not include the initial setup time. If this timeout is reached before
//! the end conditions are met, the test is a failure. Defaults to 10 min.
//! - `E2E_KATHY_MESSAGES`: Number of kathy messages to dispatch. Defaults to 16 if CI mode is enabled.
//! else false.

use std::{
    fs,
    path::Path,
    process::{Child, ExitCode},
    sync::atomic::{AtomicBool, Ordering},
    thread::sleep,
    time::{Duration, Instant},
};

use ethers_contract::MULTICALL_ADDRESS;
use logging::log;
pub use metrics::fetch_metric;
use program::Program;
use tempfile::tempdir;

use crate::{
    aptos::*,
    aptos::*,
    config::Config,
    ethereum::start_anvil,
    invariants::{termination_invariants_met, APTOS_MESSAGES_EXPECTED},
    metrics::agent_balance_sum,
    solana::*,
    utils::{concat_path, make_static, stop_child, AgentHandles, ArbitraryData, TaskHandle},
};
use std::env;

mod aptos;
mod config;
mod cosmos;
mod ethereum;
mod invariants;
mod logging;
mod metrics;
mod program;
mod solana;
mod utils;

/// These private keys are from hardhat/anvil's testing accounts.
const RELAYER_KEYS: &[&str] = &[
    // test1
    "0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6",
    // test2
    "0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97",
    // test3
    "0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356",
    // sealeveltest1
    "0x892bf6949af4233e62f854cb3618bc1a3ee3341dc71ada08c4d5deca239acf4f",
    // sealeveltest2
    "0x892bf6949af4233e62f854cb3618bc1a3ee3341dc71ada08c4d5deca239acf4f",
    // aptoslocalnet1
    "0x8cb68128b8749613f8df7612e4efd281f8d70f6d195c53a14c27fc75980446c1", // 0x8b43
    // aptoslocalnet2
    "0xf984db645790f569c23821273a95ee3878949e1098c29bcb0ba14101309adeae", //cc78
];
/// These private keys are from hardhat/anvil's testing accounts.
/// These must be consistent with the ISM config for the test.
const VALIDATOR_KEYS: &[&str] = &[
    // eth
    // "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a",
    // "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba",
    // "0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e",
    // sealevel
    // "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
    // aptoslocalnet1,
    "0xb25d6937002ecd4d79c7bdfddc0053febc8896f2109e96c45bf69efd84544cd5", // 0x21779477..
    // aptoslocalnet2,
    "0xe299c1e6e1f89b4ed2992782137e24d5edbfc51bb702635a85ed6b687c2b5988", // 0xef7a..
];

// const VALIDATOR_ORIGIN_CHAINS: &[&str] = &["test1", "test2", "test3", "sealeveltest1"];
const VALIDATOR_ORIGIN_CHAINS: &[&str] = &["aptoslocalnet1", "aptoslocalnet2"];

const AGENT_BIN_PATH: &str = "target/debug";
const INFRA_PATH: &str = "../typescript/infra";
const MONOREPO_ROOT_PATH: &str = "../";

const ZERO_MERKLE_INSERTION_KATHY_MESSAGES: u32 = 10;

type DynPath = Box<dyn AsRef<Path>>;

static RUN_LOG_WATCHERS: AtomicBool = AtomicBool::new(true);
static SHUTDOWN: AtomicBool = AtomicBool::new(false);

/// Struct to hold stuff we want to cleanup whenever we exit. Just using for
/// cleanup purposes at this time.
#[derive(Default)]
struct State {
    agents: Vec<(String, Child)>,
    watchers: Vec<Box<dyn TaskHandle<Output = ()>>>,
    data: Vec<Box<dyn ArbitraryData>>,
}

impl State {
    fn push_agent(&mut self, handles: AgentHandles) {
        self.agents.push((handles.0, handles.1));
        self.watchers.push(handles.2);
        self.watchers.push(handles.3);
        self.data.push(handles.4);
    }
}

impl Drop for State {
    fn drop(&mut self) {
        SHUTDOWN.store(true, Ordering::Relaxed);
        log!("Signaling children to stop...");
        // stop children in reverse order
        self.agents.reverse();
        for (name, mut agent) in self.agents.drain(..) {
            log!("Stopping child {}", name);
            stop_child(&mut agent);
        }
        log!("Joining watchers...");
        RUN_LOG_WATCHERS.store(false, Ordering::Relaxed);
        for w in self.watchers.drain(..) {
            w.join_box();
        }
        // drop any held data
        self.data.reverse();
        for data in self.data.drain(..) {
            drop(data)
        }
        fs::remove_dir_all(SOLANA_CHECKPOINT_LOCATION).unwrap_or_default();
    }
}

fn main() -> ExitCode {
    // on sigint we want to trigger things to stop running
    ctrlc::set_handler(|| {
        log!("Terminating...");
        SHUTDOWN.store(true, Ordering::Relaxed);
    })
    .unwrap();

    assert_eq!(VALIDATOR_ORIGIN_CHAINS.len(), VALIDATOR_KEYS.len());
    const VALIDATOR_COUNT: usize = VALIDATOR_KEYS.len();
    let is_loop = env::var("HYP_LOOP").map_or_else(|_| false, |v| v != "0" && v != "false");
    log!("Will run in loop mode. Press CTRL-C to stop: {}", is_loop);

    let config = Config::load();

    let checkpoints_dirs: Vec<DynPath> = (0..VALIDATOR_COUNT)
        .map(|_| Box::new(tempdir().unwrap()) as DynPath)
        .collect();

    let rocks_db_dir = tempdir().unwrap();
    let relayer_db = concat_path(&rocks_db_dir, "relayer");
    let validator_dbs = (0..VALIDATOR_COUNT)
        .map(|i| concat_path(&rocks_db_dir, format!("validator{i}")))
        .collect::<Vec<_>>();

    let common_agent_env = Program::default()
        .env("RUST_BACKTRACE", "full")
        .hyp_env("LOG_FORMAT", "compact")
        .hyp_env("LOG_LEVEL", "debug")
        .hyp_env("CHAINS_TEST1_INDEX_CHUNK", "1")
        .hyp_env("CHAINS_TEST2_INDEX_CHUNK", "1")
        .hyp_env("CHAINS_TEST3_INDEX_CHUNK", "1");

    let multicall_address_string: String = format!("0x{}", hex::encode(MULTICALL_ADDRESS));

    let relayer_env = common_agent_env
        .clone()
        .bin(concat_path(AGENT_BIN_PATH, "relayer"))
        .hyp_env("CHAINS_TEST1_RPCCONSENSUSTYPE", "fallback")
        .hyp_env(
            "CHAINS_TEST2_CONNECTION_URLS",
            "http://127.0.0.1:8545,http://127.0.0.1:8545,http://127.0.0.1:8545",
        )
        .hyp_env(
            "CHAINS_TEST1_BATCHCONTRACTADDRESS",
            multicall_address_string.clone(),
        )
        .hyp_env("CHAINS_TEST1_MAXBATCHSIZE", "5")
        // by setting this as a quorum provider we will cause nonce errors when delivering to test2
        // because the message will be sent to the node 3 times.
        .hyp_env("CHAINS_TEST2_RPCCONSENSUSTYPE", "quorum")
        .hyp_env(
            "CHAINS_TEST2_BATCHCONTRACTADDRESS",
            multicall_address_string.clone(),
        )
        .hyp_env("CHAINS_TEST2_MAXBATCHSIZE", "5")
        .hyp_env("CHAINS_TEST3_CONNECTION_URL", "http://127.0.0.1:8545")
        .hyp_env(
            "CHAINS_TEST3_BATCHCONTRACTADDRESS",
            multicall_address_string,
        )
        .hyp_env("CHAINS_TEST3_MAXBATCHSIZE", "5")
        .hyp_env("METRICSPORT", "9092")
        .hyp_env("DB", relayer_db.to_str().unwrap())
        .hyp_env("CHAINS_TEST1_SIGNER_KEY", RELAYER_KEYS[0])
        .hyp_env("CHAINS_TEST2_SIGNER_KEY", RELAYER_KEYS[1])
        // .hyp_env("CHAINS_SEALEVELTEST1_SIGNER_KEY", RELAYER_KEYS[3])
        // .hyp_env("CHAINS_SEALEVELTEST2_SIGNER_KEY", RELAYER_KEYS[4])
        .hyp_env("CHAINS_APTOSLOCALNET1_SIGNER_KEY", RELAYER_KEYS[5])
        .hyp_env("CHAINS_APTOSLOCALNET2_SIGNER_KEY", RELAYER_KEYS[6])
        .hyp_env("CHAINS_APTOSLOCALNET1_RPCCONSENSUSTYPE", "httpFallback")
        .hyp_env("CHAINS_APTOSLOCALNET2_RPCCONSENSUSTYPE", "httpFallback")
        .hyp_env(
            "CHAINS_APTOSLOCALNET1_CONNECTION_URLS",
            "http://127.0.0.1:8080/v1",
        )
        .hyp_env(
            "CHAINS_APTOSLOCALNET2_CONNECTION_URLS",
            "http://127.0.0.1:8080/v1",
        )
        .hyp_env("RELAYCHAINS", "invalidchain,otherinvalid")
        .hyp_env("ALLOWLOCALCHECKPOINTSYNCERS", "true")
        .hyp_env(
            "GASPAYMENTENFORCEMENT",
            r#"[{
                "type": "minimum",
                "payment": "1",
                "matchingList": [
                    {
                        "originDomain": ["13375","13376"],
                        "destinationDomain": ["13375","13376"]
                    }
                ]
            },
            {
                "type": "none"
            }]"#,
        )
        .hyp_env(
            "CHAINS_APTOSLOCALNET1_MERKLETREEHOOK",
            "0x476307c25c54b76b331a4e3422ae293ada422f5455efed1553cf4de1222a108f",
        )
        .hyp_env(
            "CHAINS_APTOSLOCALNET2_MERKLETREEHOOK",
            "0xd338e68ca12527e77cab474ee8ec91ffa4e6512ced9ae8f47e28c5c7c4804b78",
        )
        .arg(
            "chains.test1.customRpcUrls",
            "http://127.0.0.1:8545,http://127.0.0.1:8545,http://127.0.0.1:8545",
        )
        // default is used for TEST3
        .arg("defaultSigner.key", RELAYER_KEYS[2])
        .arg("relayChains", "aptoslocalnet1,aptoslocalnet2");

    let base_validator_env = common_agent_env
        .clone()
        .bin(concat_path(AGENT_BIN_PATH, "validator"))
        .hyp_env(
            "CHAINS_TEST1_CUSTOMRPCURLS",
            "http://127.0.0.1:8545,http://127.0.0.1:8545,http://127.0.0.1:8545",
        )
        .hyp_env("CHAINS_TEST1_RPCCONSENSUSTYPE", "quorum")
        .hyp_env(
            "CHAINS_TEST2_CUSTOMRPCURLS",
            "http://127.0.0.1:8545,http://127.0.0.1:8545,http://127.0.0.1:8545",
        )
        .hyp_env("CHAINS_TEST2_RPCCONSENSUSTYPE", "fallback")
        .hyp_env("CHAINS_TEST3_CUSTOMRPCURLS", "http://127.0.0.1:8545")
        .hyp_env("CHAINS_APTOSLOCALNET1_RPCCONSENSUSTYPE", "httpFallback")
        .hyp_env("CHAINS_APTOSLOCALNET2_RPCCONSENSUSTYPE", "httpFallback")
        .hyp_env("CHAINS_APTOSLOCALNET1_SIGNER_KEY", VALIDATOR_KEYS[0])
        .hyp_env("CHAINS_APTOSLOCALNET2_SIGNER_KEY", VALIDATOR_KEYS[1])
        .hyp_env("CHAINS_TEST1_BLOCKS_REORGPERIOD", "0")
        .hyp_env("CHAINS_TEST2_BLOCKS_REORGPERIOD", "0")
        .hyp_env("CHAINS_TEST3_BLOCKS_REORGPERIOD", "0")
        .hyp_env(
            "CHAINS_APTOSLOCALNET1_MERKLETREEHOOK",
            "0x476307c25c54b76b331a4e3422ae293ada422f5455efed1553cf4de1222a108f",
        )
        .hyp_env(
            "CHAINS_APTOSLOCALNET2_MERKLETREEHOOK",
            "0xd338e68ca12527e77cab474ee8ec91ffa4e6512ced9ae8f47e28c5c7c4804b78",
        )
        .hyp_env("INTERVAL", "5")
        .hyp_env("CHECKPOINTSYNCER_TYPE", "localStorage");

    let validator_envs = (0..VALIDATOR_COUNT)
        .map(|i| {
            base_validator_env
                .clone()
                .hyp_env("METRICSPORT", (9094 + i).to_string())
                .hyp_env("DB", validator_dbs[i].to_str().unwrap())
                .hyp_env("ORIGINCHAINNAME", VALIDATOR_ORIGIN_CHAINS[i])
                .hyp_env("VALIDATOR_KEY", VALIDATOR_KEYS[i])
                .hyp_env(
                    "CHECKPOINTSYNCER_PATH",
                    (*checkpoints_dirs[i]).as_ref().to_str().unwrap(),
                )
        })
        .collect::<Vec<_>>();

    let mut state = State::default();

    log!(
        "Signed checkpoints in {}",
        checkpoints_dirs
            .iter()
            .map(|d| (**d).as_ref().display().to_string())
            .collect::<Vec<_>>()
            .join(", ")
    );
    log!("Relayer DB in {}", relayer_db.display());
    (0..VALIDATOR_COUNT).for_each(|i| {
        log!("Validator {} DB in {}", i + 1, validator_dbs[i].display());
    });

    //
    // Ready to run...
    //

    install_aptos_cli().join();
    let aptos_local_net_runner = start_aptos_local_testnet().join();
    state.push_agent(aptos_local_net_runner);
    start_aptos_deploying().join();
    init_aptos_modules_state().join();

    // this task takes a long time in the CI so run it in parallel
    log!("Building rust...");
    let build_rust = Program::new("cargo")
        .cmd("build")
        .arg("features", "test-utils")
        .arg("bin", "relayer")
        .arg("bin", "validator")
        .filter_logs(|l| !l.contains("workspace-inheritance"))
        .run();

    //let start_anvil = start_anvil(config.clone());

    build_rust.join();

    // spawn 1st validator before any messages have been sent to test empty mailbox
    state.push_agent(validator_envs.first().unwrap().clone().spawn("VL1"));

    sleep(Duration::from_secs(5));

    // spawn the rest of the validators
    for (i, validator_env) in validator_envs.into_iter().enumerate().skip(1) {
        let validator = validator_env.spawn(make_static(format!("VL{}", 1 + i)));
        state.push_agent(validator);
    }

    for _i in 0..(APTOS_MESSAGES_EXPECTED / 4) {
        aptos_send_messages().join();
    }

    state.push_agent(relayer_env.spawn("RLY"));

    for _i in 0..(APTOS_MESSAGES_EXPECTED / 4) {
        aptos_send_messages().join();
    }

    log!("Setup complete! Agents running in background...");
    log!("Ctrl+C to end execution...");

    // Send half the kathy messages after the relayer comes up
    // kathy_env_double_insertion.clone().run().join();
    // kathy_env_zero_insertion.clone().run().join();
    // state.push_agent(kathy_env_single_insertion.flag("mineforever").spawn("KTY"));

    let loop_start = Instant::now();
    // give things a chance to fully start.
    sleep(Duration::from_secs(10));
    let mut failure_occurred = false;
    let starting_relayer_balance: f64 = agent_balance_sum(9092).unwrap();
    while !SHUTDOWN.load(Ordering::Relaxed) {
        if !is_loop {
            if termination_invariants_met(&config, starting_relayer_balance).unwrap_or(false) {
                // end condition reached successfully
                break;
            } else if (Instant::now() - loop_start).as_secs() > config.ci_mode_timeout {
                // we ran out of time
                log!("CI timeout reached before queues emptied");
                failure_occurred = true;
                break;
            }
        }

        // verify long-running tasks are still running
        for (name, child) in state.agents.iter_mut() {
            if let Some(status) = child.try_wait().unwrap() {
                if !status.success() {
                    log!(
                        "Child process {} exited unexpectedly, with code {}. Shutting down",
                        name,
                        status.code().unwrap()
                    );
                    failure_occurred = true;
                    SHUTDOWN.store(true, Ordering::Relaxed);
                    break;
                }
            }
        }

        sleep(Duration::from_secs(5));
    }

    if failure_occurred {
        log!("E2E tests failed");
        ExitCode::FAILURE
    } else {
        log!("E2E tests passed");
        ExitCode::SUCCESS
    }
}
