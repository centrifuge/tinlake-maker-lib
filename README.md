# Tinlake Manager

Implements https://github.com/makerdao/mips/pull/115.

The `TinlakeManager` contract acts as a `GemJoin` for the DROP token and
manages a single vault.

It manages only one urn, which can be liquidated in two stages:
## Soft liquidation
Tries to recover as much dai as possible without liquidating the cdp by calling
pool.disburse().

## Hard liquidation
This is essentially a write off of the debt of the vault


# Spell

A mainnet targeted spell, integrating the manager and the drop token into maker
as a collateral type.

# Testing

RPC testing with `dapp test --rpc <ETH_RPC_URL>`.
Use `--cache` for rapid testing.
