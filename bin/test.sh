#!/usr/bin/env bash
set -e

dapp build --extract
hevm dapp-test --rpc="$ETH_RPC_URL" --json-file=out/dapp.sol.json