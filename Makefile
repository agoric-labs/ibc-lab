IMAGE_AGORIC=agoric/agoric-sdk:agoricdev-11
IMAGE_HERMES=informalsystems/hermes:0.14.1
NETWORK_CONFIG=https://devnet.agoric.net/network-config
#######

CHAIN_COSMOS=cosmoshub-testnet
HERMES=IMAGE_HERMES=$(IMAGE_HERMES) ./hermes.sh

# ISSUE: use matching key names in hermes.config for consistency
ADDR_AG_KEY=keys/agdevkey
ADDR_COSMOS_KEY=keys/hubkey
CHAIN_AG=$(shell curl -Ss "$(NETWORK_CONFIG)" | jq -r .chainName)
RPC_ADDR=$(shell curl -Ss "$(NETWORK_CONFIG)" | jq -r .rpcAddrs[0])

start: hermes.config tasks
	$(HERMES) start

tasks: task/restore-keys task/tap-cosmos-faucet task/tap-agoric-faucet

hermes.config: hermes.config.template
	cp hermes.config.template hermes.config
	case "$(RPC_ADDR)" in \
	https://*.rpc.agoric.net*) \
	  rpc="$(RPC_ADDR)"; \
		grpc=$$(echo "$(RPC_ADDR)" | sed -e 's/\.rpc\./.grpc./'); \
		ws=$$(echo "$(RPC_ADDR)" | sed -e 's/^http/ws/') ;; \
	http://*:26657) \
		rpc="$(RPC_ADDR)"; \
		grpc=$$(echo "$(RPC_ADDR)" | sed -e 's/:26657$$/:9090/'); \
		ws='ws://$(RPC_ADDR)' ;; \
	*:26657) \
	  rpc="http://$(RPC_ADDR)"; \
	  grpc=$$(echo "$$rpc" | sed -e 's/:26657$$/:9090/'); \
		ws='ws://$(RPC_ADDR)' ;; \
	*) echo "Don't know how to form gRPC address from $(RPC_ADDR)"; exit 1 ;; \
	esac; \
	sed -i.bak -e 's/@AG_CHAIN_NAME@/$(CHAIN_AG)/g' \
		-e 's!@AG_RPC@!$(RPC_ADDR)!g' \
		-e "s!@AG_GRPC@!$$grpc!g" \
		-e "s!@AG_WS@!$$ws!g" \
		hermes.config

KEYFILE=ibc-relay-mnemonic
task/restore-keys: $(KEYFILE) hermes.config
	mkdir -p keys hermes-home
	sudo chown 1000 hermes-home
	set -ue; \
		MNEMONIC="$$(cat $(KEYFILE))"; \
		echo $$MNEMONIC | sha1sum ; \
		$(HERMES) --json keys restore $(CHAIN_AG) -p "m/44'/564'/0'/0/0" -m "$$MNEMONIC" | jq -r --exit-status '.result | capture("\\((?<addr>.*)\\)") | .addr' > keys/agdevaddr.tmp; \
		$(HERMES) --json keys restore $(CHAIN_COSMOS) -m "$$MNEMONIC" | jq -r --exit-status '.result | capture("\\((?<addr>.*)\\)") | .addr' > keys/cosmosaddr.tmp
	mv keys/agdevaddr.tmp keys/agdevaddr
	mv keys/cosmosaddr.tmp keys/cosmosaddr
	mkdir -p task && touch $@

task/create-connection: hermes.config tasks
	$(HERMES) -j create connection $(CHAIN_COSMOS) $(CHAIN_AG) \
		| tee /dev/stderr | tail -1 > task/create-connection

task/create-channel: hermes.config tasks
	$(HERMES) -j create channel $(CHAIN_COSMOS) $$(jq -r .result.a_side.connection_id < task/create-connection) \
		--port-a transfer --port-b transfer -o unordered \
		| tee /dev/stderr | tail -1 >> task/create-channel
	mkdir -p task && touch $@

$(KEYFILE):
	docker run --rm $(IMAGE_AGORIC) keys mnemonic >$@
	chmod -w $@

task/tap-cosmos-faucet: keys/cosmosaddr
	@echo tapping faucet
	@echo per https://tutorials.cosmos.network/connecting-to-testnet/using-cli.html#requesting-tokens-from-the-faucet
	curl -X POST -d '{"address": "$(shell cat keys/cosmosaddr)"}' https://faucet.testnet.cosmos.network | tee /dev/stderr | jq --exit-status '.transfers[0].status == "ok"'
	mkdir -p task && touch $@

task/tap-agoric-faucet: keys/agdevaddr
	case "$(RPC_ADDR)" in \
	http://* | https://*) node="$(RPC_ADDR)" ;; \
	*) node="tcp://$(RPC_ADDR)" ;; \
	esac; \
	if ! docker run --rm $(IMAGE_AGORIC) --node $$node query bank balances $(shell cat keys/agdevaddr) -o json | tee /dev/stderr | jq --exit-status '.balances[0]' || exit 1; then \
		echo if the balance below is empty,; \
		echo visit https://agoric.com/discord; \
		echo go to the "#faucet" channel; \
		echo enter: !faucet client $(shell cat keys/agdevaddr); \
		echo press enter after this has been done; \
		read dummy; \
	fi
	mkdir -p task && touch $@

clean:
	rm -f $(KEYFILE)
	rm -rf keys
	rm -rf task
	rm -rf hermes-home
	rm -f hermes.config
