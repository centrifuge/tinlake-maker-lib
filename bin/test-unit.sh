#!/usr/bin/env bash
set -e

dapp --use solc:0.5.15 test --fuzz-runs 500
