# Set up hyperlane v2 for aptos

## Preqrequisites

- Ubuntu 24.04
- rust 1.76.0
- yarn 3.2.0
- node v20.14.0

### Install Node

This repository targets v20 of node. We recommend using [nvm](https://github.com/nvm-sh/nvm) to manage your node version.

To install nvm

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

To install version 20

```bash
nvm install 20
nvm use 20
```

# install yarn

```bash
sudo apt install yarn
```

## Set up yarn

```
yarn install
yarn build
```

## Build binaries

```
cd rust
cargo build
```

## Run local e2e tests

See [README.md](./e2e-aptos/README.md) for instructions on running e2e tests.
