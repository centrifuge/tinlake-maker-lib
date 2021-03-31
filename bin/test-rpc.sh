#!/usr/bin/env bash
set -e

dapp --use solc:0.5.12 build --extract
hevm dapp-test --rpc="$ETH_RPC_URL" --json-file=out/dapp.sol.json --verbose=1