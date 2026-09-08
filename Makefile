# Development shortcuts — the real logic lives in SwiftPM and scripts/.

.PHONY: help build bundle install run demo clean

help: ## List the available targets
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

build: ## Compile (debug)
	swift build

bundle: ## Release build → dist/Majordomo.app
	./scripts/bundle.sh

install: ## Build and install to /Applications
	./scripts/install.sh

run: bundle ## Run the bundled app
	./dist/Majordomo.app/Contents/MacOS/Majordomo

demo: bundle ## Run on fixture data (no accounts, network, or Keychain)
	MAJORDOMO_DEMO=1 MAJORDOMO_OPEN_MAIN=1 ./dist/Majordomo.app/Contents/MacOS/Majordomo

clean: ## Drop build products
	rm -rf .build dist
