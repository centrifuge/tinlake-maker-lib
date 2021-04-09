all: build
clean  :; dapp clean
update:
	dapp update
build: update
	dapp --use solc:0.5.12 build
test: update
	dapp --use solc:0.5.12 test --match TinlakeManagerUnitTest
	dapp --use solc:0.5.12 test --match KovanRPC --rpc-url "https://kovan.$RPC_ENDPOINT"
  # todo: dapp --use solc:0.5.12 test --match DssSpellTest
deploy: build
	dapp create TinlakeMakerLib
