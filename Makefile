SHELL := /bin/bash -x
BUILDDIR := build
TEXMFCACHE := $(CURDIR)/$(BUILDDIR)/texmf-cache

EXAMPLES := $(basename $(notdir $(wildcard examples/*.tex)))
BYZX_SOURCES := $(wildcard examples/*.byzx tests/latex/unit/fixtures/*.byzx tests/latex/integration/fixtures/*.byzx)
BYZX_RICH_SOURCES := \
	tests/latex/unit/fixtures/colors.byzx \
	tests/latex/unit/fixtures/mode-key-layout-branches.byzx \
	tests/latex/unit/fixtures/opentype-matrix.byzx \
	tests/latex/unit/fixtures/positioning-matrix.byzx \
	tests/latex/unit/fixtures/text-box-layout-branches.byzx \
	tests/latex/unit/fixtures/text-styles.byzx
BYZX_STANDARD_SOURCES := $(filter-out $(BYZX_RICH_SOURCES),$(BYZX_SOURCES))

# Shared package tree, font directory, and writable luaotfload font cache.
TEXMF_ENV := OSFONTDIR=$(CURDIR)/examples TEXMFHOME=$(CURDIR)/texmf TEXMFVAR=$(TEXMFCACHE)
LATEXMK := $(TEXMF_ENV) TEXINPUTS=$(CURDIR)/tex//: latexmk -cd
L3BUILD := $(TEXMF_ENV) l3build
L3BUILD_OPTIONS ?=
LUA_SOURCES := build.lua $(wildcard config-*.lua tex/*.lua tests/latex/harness/*.lua)
TEX_SOURCES := $(sort $(shell find examples tests/latex tex -type f \( -name '*.tex' -o -name '*.lvt' -o -name '*.sty' -o -name '*.cls' \)))

.PHONY: all examples test test-latex clean check fmt lint export

all: examples

examples: $(addprefix example-,$(EXAMPLES))

test: test-latex

test-latex: | $(TEXMFCACHE)
	$(L3BUILD) check $(L3BUILD_OPTIONS)

# One test or reference. The configuration is part of the target name so that
# test names duplicated across configurations stay addressable.
test-latex-unit-%: | $(TEXMFCACHE)
	$(L3BUILD) check $(L3BUILD_OPTIONS) -c config-unit $*

test-latex-integration-%: | $(TEXMFCACHE)
	$(L3BUILD) check $(L3BUILD_OPTIONS) -c config-integration $*

save-latex-unit-%: | $(TEXMFCACHE)
	$(L3BUILD) save $(L3BUILD_OPTIONS) -c config-unit $*

save-latex-integration-%: | $(TEXMFCACHE)
	$(L3BUILD) save $(L3BUILD_OPTIONS) -c config-integration $*

export:
	@if [[ -z "$${NEANES_EXECUTABLE:-}" ]]; then \
		echo "NEANES_EXECUTABLE must point to a Neanes executable" >&2; \
		exit 1; \
	fi
	"$$NEANES_EXECUTABLE" --silent-latex $(BYZX_STANDARD_SOURCES)
	"$$NEANES_EXECUTABLE" --silent-latex --latex-include-mode-keys --latex-include-text-boxes $(BYZX_RICH_SOURCES)

example-%: | $(TEXMFCACHE)
	$(LATEXMK) -outdir=$(abspath $(BUILDDIR)/examples) -jobname=$* examples/$*.tex

example-%-pv: | $(TEXMFCACHE)
	$(LATEXMK) -pv -outdir=$(abspath $(BUILDDIR)/examples) -jobname=$* examples/$*.tex

example-%-pvc: | $(TEXMFCACHE)
	$(LATEXMK) -pvc -outdir=$(abspath $(BUILDDIR)/examples) -jobname=$* examples/$*.tex

$(TEXMFCACHE):
	mkdir -p $@
	OSFONTDIR=$(CURDIR)/examples TEXMFVAR=$(TEXMFCACHE) luaotfload-tool --update

clean:
	rm -rf $(BUILDDIR)

check: lint test all

lint:
	mbake validate Makefile
	mbake format --check Makefile
	tex-fmt --check $(TEX_SOURCES)
	stylua --check $(LUA_SOURCES)

fmt:
	mbake format Makefile
	tex-fmt $(TEX_SOURCES)
	stylua $(LUA_SOURCES)