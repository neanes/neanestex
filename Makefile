SHELL := /bin/bash -x
BUILDDIR := build
TEXMFCACHE := $(CURDIR)/$(BUILDDIR)/texmf-cache

EXAMPLES := $(basename $(notdir $(wildcard examples/*.tex)))
BYZX_SOURCES := $(wildcard examples/*.byzx)
BYZX_RICH_SOURCES := examples/opentype-matrix.byzx
BYZX_STANDARD_SOURCES := $(filter-out $(BYZX_RICH_SOURCES),$(BYZX_SOURCES))

# luaotfload derives its writable TEXMFCACHE from TEXMFVAR on TeX Live.
LATEXMK := OSFONTDIR=$(CURDIR)/examples TEXMFHOME=$(CURDIR)/texmf TEXMFVAR=$(TEXMFCACHE) TEXINPUTS=$(CURDIR)/tex//: latexmk -cd
LUA_SOURCES := $(wildcard tex/*.lua)
TEX_SOURCES := $(sort $(shell find examples tex -type f \( -name '*.tex' -o -name '*.sty' -o -name '*.cls' \)))

.PHONY: all examples clean check fmt lint export

all: examples

examples: $(addprefix example-,$(EXAMPLES))

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

check: lint all

lint:
	mbake validate Makefile
	mbake format --check Makefile
	tex-fmt --check $(TEX_SOURCES)
	stylua --check $(LUA_SOURCES)

fmt:
	mbake format Makefile
	tex-fmt $(TEX_SOURCES)
	stylua $(LUA_SOURCES)