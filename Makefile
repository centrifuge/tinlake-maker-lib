all: build
clean  :; dapp clean
update:
	dapp update
build: update
	dapp --use solc:0.5.12 build
test: update
	dapp --use solc:0.5.12 test --rpc
deploy: build
	dapp create TinlakeMakerLib
