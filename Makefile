# Make sure we're failing even though we pipe to xcpretty
SHELL := /bin/bash -o pipefail -o errexit
WORKING_DIR := ./
SCHEME = LibForstaSwift
XCODE_BUILD := xcrun xcodebuild -scheme LibForstaSwift
DEPENDENCIES := .dependencies-built

.PHONY: build test retest clean dependencies ci pristine docs

default: clean $(DEPENDENCIES)

ci: $(DEPENDENCIES) test
	$(XCODE_BUILD) build

dependencies $(DEPENDENCIES):
	carthage update --platform iOS
	@ touch $(DEPENDENCIES)

build: $(DEPENDENCIES)
	$(XCODE_BUILD) build | xcpretty

test: build
	$(XCODE_BUILD) test | xcpretty

clean:
	$(XCODE_BUILD) clean | xcpretty

pristine: clean
	rm -rf Carthage
	rm -f $(DEPENDENCIES)

docs:
	@ echo building api docs
	@ jazzy 

