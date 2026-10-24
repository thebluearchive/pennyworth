# The native build system is used because SwiftPM's default (swift-build) fails
# on machines with a malformed SDK under CommandLineTools/SDKs. Override with
#   make SWIFT_FLAGS= ...
# once that is fixed or when building with full Xcode.
SWIFT_FLAGS ?= --disable-sandbox --build-system native
CONFIG ?= release

# Command Line Tools ship swift-testing but don't put it on the search path.
TESTING_FW ?= $(shell xcode-select -p)/Library/Developer/Frameworks
TEST_FLAGS ?= -Xswiftc -F$(TESTING_FW) -Xlinker -rpath -Xlinker $(TESTING_FW)

APP := dist/Pennyworth.app

.PHONY: build test app run install clean

build:
	swift build $(SWIFT_FLAGS) -c $(CONFIG)

test:
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS)

app:
	SWIFT_FLAGS="$(SWIFT_FLAGS)" CONFIG=$(CONFIG) scripts/bundle.sh

run: app
	-pkill -x Pennyworth
	open $(APP)

install: app
	-pkill -x Pennyworth
	rm -rf ~/Applications/Pennyworth.app
	mkdir -p ~/Applications
	cp -R $(APP) ~/Applications/
	open ~/Applications/Pennyworth.app

clean:
	rm -rf .build dist
