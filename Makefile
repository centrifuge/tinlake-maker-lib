all: build
clean  :; dapp clean
update:
	dapp update
build: update
	dapp --use solc:0.5.12 build
test: update
	dapp --use solc:0.5.12 test --rpc https://kovan.infura.io/v3/f9ba987e8cb34418bb53cdbd4d8321b5
deploy: build
	dapp create TinlakeMakerLib
