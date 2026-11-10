PREFIX ?= $(HOME)/.local

.PHONY: build test install uninstall clean

build:
	swift build -c release

test:
	swift test

install: build
	install -d "$(PREFIX)/bin"
	install -m 755 .build/release/strider "$(PREFIX)/bin/strider"

uninstall:
	-"$(PREFIX)/bin/strider" agent uninstall
	rm -f "$(PREFIX)/bin/strider"

clean:
	swift package clean
