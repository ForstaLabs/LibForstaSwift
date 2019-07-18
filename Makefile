# Make sure we're failing even though we pipe to xcpretty
SHELL := /bin/bash -o pipefail -o errexit
WORKING_DIR := ./
SCHEME = LibRelaySwift
XCODE_BUILD := xcrun xcodebuild -scheme LibRelaySwift
DEPENDENCIES := .dependencies-built

.PHONY: build test retest clean dependencies ci pristine

default: clean $(DEPENDENCIES) build

ci: $(DEPENDENCIES) test
	$(XCODE_BUILD) build

dependencies $(DEPENDENCIES):
	carthage update --platform iOS
	touch $(DEPENDENCIES)

build: $(DEPENDENCIES)
	$(XCODE_BUILD) build # | xcpretty

test: build
	$(XCODE_BUILD) test # | xcpretty

clean:
	$(XCODE_BUILD) clean # | xcpretty

pristine: clean
	rm -f $(DEPENDENCIES)
