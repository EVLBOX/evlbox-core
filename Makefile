.PHONY: test lint install

test:
	bats test/

lint:
	shellcheck install.sh cli/evlbox

install:
	@echo "Installing evlbox CLI to /usr/local/bin/evlbox..."
	cp cli/evlbox /usr/local/bin/evlbox
	chmod +x /usr/local/bin/evlbox
	@echo "Done."
