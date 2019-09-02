# Make sure we're failing even though we pipe to xcpretty
SHELL := /bin/bash -o pipefail -o errexit
WORKING_DIR := ./
SCHEME = LibForstaSwift
XCODE_BUILD := xcrun xcodebuild -scheme LibForstaSwift
DEPENDENCIES := .dependencies-built

.PHONY: build test retest clean dependencies ci pristine docs

default: clean $(DEPENDENCIES) build

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
	rm -f $(DEPENDENCIES)

docs: $(DEPENDENCIES)
	@ echo building api docs
	@ jazzy \
                --clean \
                --hide-documentation-coverage \
                --author "Forsta, Inc" \
                --author_url https://forsta.io \
                --github_url https://github.com/ForstaLabs/LibForstaSwift \
                --github-file-prefix https://github.com/ForstaLabs/LibForstaSwift/blob/master \
                --xcodebuild-arguments -scheme,LibForstaSwift \
                --module LibForstaSwift \
                --root-url https://forstalabs.github.io/LibForstaSwift/LATEST/index.html \
                --output docs \
                --theme fullwidth

