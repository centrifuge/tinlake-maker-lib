all: build
clean  :; dapp clean
update:
	dapp update
build: update
	dapp --use $$(which solc) build
test: update
	# dapp --use $$(which solc) test --rpc
	dapp --use $$(which solc) test
deploy :; dapp create TinlakeMakerLib
