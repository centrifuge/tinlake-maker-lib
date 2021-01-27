all: build
clean  :; dapp clean
update:
	dapp update
build: update
	dapp --use solc:0.5.15 build
test: update
	dapp --use solc:0.5.15 test
deploy: build
	dapp create TinlakeMakerLib
