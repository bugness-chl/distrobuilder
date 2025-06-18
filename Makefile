VERSION=$(shell grep "var Version" shared/version/version.go | cut -d'"' -f2)
ARCHIVE=distrobuilder-$(VERSION).tar
GO111MODULE=on
SPHINXENV=.sphinx/venv/bin/activate
GOPATH=$(shell go env GOPATH)

.PHONY: default
default:
	gofmt -s -w .
	go install -v ./...
	@echo "distrobuilder built successfully"

.PHONY: update-gomod
update-gomod:
	go get -t -v -u ./...
	go get github.com/go-jose/go-jose/v4@v4.0.5
	go mod tidy -go=1.23.7
	go get toolchain@none
	@echo "Dependencies updated"

.PHONY: check
check: default
	sudo GOENV=$(shell go env GOENV) go test -v ./...

.PHONY: dist
dist:
	# Cleanup
	rm -Rf $(ARCHIVE).gz

	# Create build dir
	$(eval TMP := $(shell mktemp -d))
	git archive --prefix=distrobuilder-$(VERSION)/ HEAD | tar -x -C $(TMP)
	mkdir -p $(TMP)/_dist/src/github.com/lxc
	ln -s ../../../../distrobuilder-$(VERSION) $(TMP)/_dist/src/github.com/lxc/distrobuilder

	# Download dependencies
	cd $(TMP)/distrobuilder-$(VERSION) && go mod vendor

	# Assemble tarball
	tar --exclude-vcs -C $(TMP) -zcf $(ARCHIVE).gz distrobuilder-$(VERSION)/

	# Cleanup
	rm -Rf $(TMP)

.PHONY: doc-setup
doc-setup:
	@echo "Setting up documentation build environment"
	python3 -m venv .sphinx/venv
	. $(SPHINXENV) ; pip install --upgrade -r .sphinx/requirements.txt
	mkdir -p .sphinx/deps/ .sphinx/themes/
	wget -N -P .sphinx/_static/download https://linuxcontainers.org/static/img/favicon.ico https://linuxcontainers.org/static/img/containers.png https://linuxcontainers.org/static/img/containers.small.png
	rm -Rf doc/html

.PHONY: doc
doc: doc-setup doc-incremental

.PHONY: doc-incremental
doc-incremental:
	@echo "Build the documentation"
	. $(SPHINXENV) ; sphinx-build -c .sphinx/ -b dirhtml doc/ doc/html/ -w .sphinx/warnings.txt

.PHONY: doc-serve
doc-serve:
	cd doc/html; python3 -m http.server 8001

.PHONY: doc-spellcheck
doc-spellcheck: doc
	. $(SPHINXENV) ; python3 -m pyspelling -c .sphinx/.spellcheck.yaml

.PHONY: doc-linkcheck
doc-linkcheck: doc-setup
	. $(SPHINXENV) ; sphinx-build -c .sphinx/ -b linkcheck doc/ doc/html/

.PHONY: doc-lint
doc-lint:
	.sphinx/.markdownlint/doc-lint.sh

.PHONY: static-analysis
static-analysis:
ifeq ($(shell command -v golangci-lint),)
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin
endif
ifeq ($(shell command -v codespell),)
	echo "Please install codespell"
	exit 1
endif
	$(GOPATH)/bin/golangci-lint run --timeout 5m
	run-parts $(shell run-parts -V 2> /dev/null 1> /dev/null && echo -n "--exit-on-error --regex '.sh'") test/lint
