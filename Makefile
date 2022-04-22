IMAGE_AGORIC=agoric/agoric-sdk:17
IMAGE_HERMES=informalsystems/hermes:0.13.0
NETWORK_CONFIG=https://stage.agoric.net/network-config
#######

CHAIN_COSMOS=cosmoshub-testnet
HERMES=docker run -it -v$$PWD/hermes-home:/home/hermes:z -v$$PWD:/config $(IMAGE_HERMES) -c /config/hermes.config

# ISSUE: use matching key names in hermes.config for consistency
ADDR_AG_KEY=keys/agdevkey
ADDR_COSMOS_KEY=keys/hubkey
CHAIN_AG=$(shell curl -Ss "$(NETWORK_CONFIG)" | jq -r .chainName)
RPC_IP=$(shell curl -Ss "$(NETWORK_CONFIG)" | jq -r .rpcAddrs[0] | cut -d":" -f1)

start: 
	$(HERMES) start

hermes.config: 
	cp hermes.config.template hermes.config
	sed -e "s/AG_CHAIN_NAME/$(CHAIN_AG)/g" -e "s/AG_RPC_IP/$(RPC_IP)/g" hermes.config.template > hermes.config

KEYFILE=ibc-relay-mnemonic
task/restore-keys: $(KEYFILE) hermes.config
	mkdir -p keys ; \
	MNEMONIC="$$(cat $(KEYFILE))"; \
	echo $$MNEMONIC | sha1sum ; \
	$(HERMES) keys restore $(CHAIN_AG) -p "m/44'/564'/0'/0/0" -m "$$MNEMONIC" | awk '{print $$5}' | tr -d '()' > $(ADDR_AG_KEY); \
	$(HERMES) keys restore $(CHAIN_COSMOS) -m "$$MNEMONIC" | awk '{print $$5}' | tr -d '()' > $(ADDR_COSMOS_KEY); \
	mkdir -p task && touch $@

task/create-channel: hermes.config task/restore-keys task/tap-cosmos-faucet task/tap-agoric-faucet
	$(HERMES) create channel $(CHAIN_COSMOS) $(CHAIN_AG) --port-a transfer --port-b transfer -o unordered
	mkdir -p task && touch $@

$(KEYFILE): 
	docker run --rm $(IMAGE_AGORIC) keys mnemonic >$@
	chmod -w $@

task/tap-cosmos-faucet: hermes.config
	@echo tapping faucet
	@echo per https://tutorials.cosmos.network/connecting-to-testnet/using-cli.html#requesting-tokens-from-the-faucet
	curl -X POST -d '{"address": "$(shell cat ${ADDR_COSMOS_KEY})"}' https://faucet.testnet.cosmos.network
	mkdir -p task && touch $@

task/tap-agoric-faucet: hermes.config
	@echo if the balance below is empty,
	@echo visit https://agoric.com/discord
	@echo go to the "#faucet" channel
	@echo enter: !faucet client $(shell cat $(ADDR_AG_KEY))
	@echo press enter after this has been done
	read
	docker run --rm $(IMAGE_AGORIC) --node http://$(RPC_IP):26657 query bank balances $(shell cat $(ADDR_AG_KEY)) -o json  | jq --exit-status '.balances[0]' || exit 1
	mkdir -p task && touch $@

clean:
	rm -f $(KEYFILE)
	rm -rf keys
	rm -rf task
	rm -rf hermes-home
	rm -f hermes.config
