# LaTeX test suite

Every test in `unit/` and `integration/` is a complete document compiled with
LuaLaTeX by l3build. The `neanestest` harness emits an assertion record; l3build
normalizes it and compares it with the `.tlg` reference. Assertion failures are
reported by that standard comparison, while genuine TeX errors are recorded as
exit-status changes.

```sh
make test
make test-latex
make test-latex-unit-score-text-leading
```

Products land beneath `build/l3build/test-<config>/`. On failure, start with
the test's `.diff`; re-run that test with its log displayed for more context.

```sh
make test-latex-unit-score-text-leading \
  L3BUILD_OPTIONS="--halt-on-error --show-log-on-error"
```

Always select a configuration with `-c` when naming a test; the default
configuration runs no tests here. `build.lua` supplies the bundled font
directory and the writable luaotfload cache the tests need, so a bare `l3build`
invocation works as documented upstream and never writes to the real font
cache. The Make targets are shorthand for the same thing.

After inspecting a test's diff and confirming the new output, refresh its `.tlg`
reference through the corresponding save target:

```sh
make save-latex-unit-score-text-leading
```

For a broad intentional output change across both configurations,
`make test-latex L3BUILD_OPTIONS=--show-saves` makes l3build print the save
command for each failing test. (`--show-saves` has no effect when only one
configuration runs.) Those printed commands can be run as-is. Review every diff
first.

## Test layout

- The repository-root `build.lua`, `config-unit.lua`, and
  `config-integration.lua` configure l3build, with one test directory owned by
  each explicit configuration.
- Every `.lvt` starts with l3build's `regression-test.tex` driver. The custom
  harness uses its standard start marker and lets the driver close the record
  when the document ends.
- `tests/latex/harness/neanestest.sty` and
  `tests/latex/harness/neanestest.lua` provide the assertion layer and are
  copied into the isolated l3build test run as support files; `neanestest.sty`
  loads its Lua neighbor through kpathsea, as `neanestex.sty` does.
- `tests/latex/unit/` contains harness contracts and package box-level tests.
  Package tests typeset material into `\neanestestbox`, walk the node list, and
  assert dimensions, glue, penalties, baseline distances, text,
  glyph fonts, sizes, colors, positions, and OpenType feature selection.
- `tests/latex/integration/` exercises public package workflows in complete
  documents. It checks real exported scores, default/named/wildcard section
  selection, supported element kinds, rich text, and page layout. The unit-level
  package API test checks standalone glyph commands.
- `tests/latex/unit/fixtures/` and `tests/latex/integration/fixtures/` contain
  the score inputs owned by each suite. l3build copies the active suite's
  fixtures beside its build products because this version of `neanestex` opens
  score files relative to the current working directory.

The build copies the package files, test harness, fixtures, and required example
font assets into l3build's isolated test directory. Test and example builds
share the writable `build/texmf-cache`.

## Fixture setup

The harness also owns the setup every score test repeats:

- `\NeanesUseBundledNeumeFont` selects the bundled engraving font, its
  metadata, and the family the package's own glyph lookup resolves against.
- `\NeanesGlyph{name}` expands to the character the package maps `name` to,
  so assertions address a neume by name rather than by its private-use
  codepoint and `tex/glyphnames.json` stays the sole owner of that map. A
  moved glyph then fails as an unknown name instead of as a hex literal that
  matches nothing. `package-api.lvt` keeps literal codepoints deliberately:
  its assertions pin the mapping itself.
- `\NeanesScoreParagraphs{file}{section}` renders a score and leaves the number
  of paragraphs it emitted in `\NeanesScoreParagraphCount`.
- `\NeanesInstrumentScore{assertions}` patches `\neanesscore` so that every
  score in an unmodified example document is counted, has its first two
  paragraphs marked, records its leading in `\NeanesScoreBaseline`, and is
  followed by `assertions`.

## Immediate assertions

The numeric and dimension assertions operate directly on their arguments:

- `\NeanesCheckNum`
- `\NeanesCheckDim` and `\NeanesCheckDimRange`
- `\NeanesPackageLoaded`

Box assertions operate on `\neanestestbox`. After filling the box, call
`\NeanesUseBox` before making any of them. It walks the box once and snapshots
everything the assertions read: the top-level vertical list, and every glyph
with its font, size, effective color, and position. A test with fifty assertions
therefore inspects the box once rather than fifty times. Refill the box and
`\NeanesUseBox` must be called again; the harness rejects a stale snapshot.

```tex
\setbox\neanestestbox=\vbox{
  \noindent\neanesanchor{first}First line.\par
  \noindent\neanesanchor{second}Second line.\par
}
\NeanesUseBox
\NeanesBaselineGap{ordinary leading}{first}{second}
{\baselineskip-0.02pt}{\baselineskip+0.02pt}
```

Available structural assertions include:

- `\NeanesBaselineGap`
- `\NeanesPenaltyBetween`
- `\NeanesGlueWidthBetween` and `\NeanesNoGlueWidthBetween`
- `\NeanesDumpTrace` for diagnostics

Glyph and content assertions read the same snapshot, which covers
`\neanestestbox` recursively:

- `\NeanesGlyphFont`, `\NeanesGlyphFontNot`, and `\NeanesGlyphSize`
- `\NeanesGlyphCount`, `\NeanesGlyphOuterBoxWidth`, and `\NeanesGlyphOffset`
- `\NeanesRuleSize` and `\NeanesGlyphXRange`
- `\NeanesGlyphColor`
- `\NeanesAnyGlyph` and `\NeanesNoGlyphSmaller`
- `\NeanesFontFeatures`, `\NeanesFontScript`, `\NeanesPdfLiteral`, and
  `\NeanesPdfColorstack`
- `\NeanesBoxColor`
- `\NeanesBoxText`, `\NeanesBoxTextAbsent`, and `\NeanesBoxTextOrder`

These assertions cover NeanesTeX's primary output contracts: neume and text
font selection, glyph sizing, score colors, lyric and text-box content, line
height, paragraph spacing, offsets, and transitions back to surrounding text.

`\NeanesFontFeatures` and `\NeanesFontScript` name a face by its exact full
name. Faces nest by prefix, so `Source Serif 4` is also a prefix of `Source
Serif 4 Display Semibold`, and a substring match would let a neighbouring face
answer for the one under test. luaotfload builds one face per distinct feature
set, so `\NeanesFontFeatures` asks for the face requesting exactly the listed
tags and no others, which pins the assertion to the selector a single text style
should have produced. `\NeanesFontScript` holds for every face of that name in
the box, not merely the first. Both read the selector NeanesTeX hands to
luaotfload rather than the shaped glyphs.

`\NeanesGlyphOffset{name}{from}{from occurrence}{to}{to occurrence}{x}{y}{tol}`
compares final glyph origins within one top-level line. Occurrence numbers make
repeated neumes addressable, so a test can prove that an overlay leaves the
following element at its exported position. Positive `y` is downward, matching
LuaTeX's box-shift convention. `\NeanesGlyphCount` is the corresponding presence
and multiplicity assertion. `\NeanesGlyphOuterBoxWidth` addresses the direct child
box containing a glyph, making zero-width overlays testable across score lines.

## Deferred page assertions

`\neanesmark{name}` inserts a `\latelua` whatsit. When its page ships, the harness
records the mark's page number and vertical PDF position. Deferred assertions
run at the end of the document, after pending material has been shipped:

- `\NeanesSamePage` for one or more marks; one mark asserts that it shipped
- `\NeanesVDistRange`

Use these for behavior that the page builder can change, including score
transitions near a page bottom, `\flushbottom` stretching, page breaks within
scores, and final rendered vertical distances. These assertions are reserved
for integration tests; unit tests and section-selection checks should use
immediate or box-level assertions.

The paragraph integration tests input the flush-bottom and ragged-bottom
example documents verbatim. `\NeanesInstrumentScore` adds assertions without
changing the examples: both must emit all seven musical paragraphs,
ragged-bottom must retain their natural spacing, and flush-bottom must stretch
their paragraph gaps. The OLHC and blameless examples make default, named, and
wildcard section selection observable in the structural assertion records.
Focused unit fixtures cover
font and content properties, OpenType feature selection, optional mark offsets,
transferred measure bars, martyria tempi, extended mode-key fields, and final
glyph positions. The Greek and Cyrillic sections of the OpenType fixture are
rendered under a document-level `\defaultfontfeatures{Script=...}` so that a
score's own face declarations are shown to inherit it.

## Writing reliable tests

- In shipped documents, place `\neanesmark` inline in paragraph text, never
  between paragraphs. A vertical-mode whatsit is non-discardable and can
  manufacture a page breakpoint at following glue that production markup
  would not contain.
- `\neanesanchor` uses a `\special` and is intended for boxed material. Shipping
  one produces a harmless but noisy `Non-PDF special` message; use `\neanesmark`
  for integration tests.
- Box-text scanning is unreliable under font features. Ligatures, small
  capitals, old-style figures, and specialized neume fonts may map glyphs to
  private codepoints. Prefer structural, font, size, and color assertions when
  testing such content.
- `\NeanesGlyphFont` and `\NeanesGlyphColor` require the addressed character to occur
  at least once. This prevents an assertion from passing vacuously.
- `\NeanesBoxColor` proves that a `pdf_colorstack` operation already occurs in
  the unshipped box. It is not useful when `luacolor` is loaded (including with
  `neanestex`), because `luacolor` emits those operations only at shipout. Use
  `\NeanesGlyphColor` for `neanestex` output or whenever the color must belong to
  a particular glyph.
