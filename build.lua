module = "neanestex"

-- The text fonts the tests select by family, and a writable luaotfload cache.
-- Setting these here rather than only in the Makefile means a bare l3build
-- invocation works -- including the `l3build save -c <config> <name>` command
-- l3build itself prints when a test fails -- and that no test run writes into
-- the user's real font cache. An exported value wins, so the Makefile stays in
-- charge whenever it is the caller.
if not os.getenv("OSFONTDIR") then
    os.setenv("OSFONTDIR", abspath("examples"))
end

if not os.getenv("TEXMFVAR") then
    local cache = abspath("build/texmf-cache")
    mkdir(cache)
    os.setenv("TEXMFVAR", cache)
end

sourcefiledir = "tex"
sourcefiles = { "*.json", "*.lua", "*.sty" }
installfiles = sourcefiles
unpackfiles = {}

checkconfigs = { "config-unit", "config-integration" }
checkengines = { "luatex" }
checkopts = "-interaction=nonstopmode -halt-on-error -file-line-error"

-- Use l3build's standard log normalization and comparison. PDF test types are
-- intentionally off.
test_order = { "log" }

-- Make compile-status changes part of the reference diff.
recordstatus = true

builddir = "build/l3build"

-- Copy the test harness through l3build's standard support-file mechanism.
supportdir = "tests/latex/harness"
checksuppfiles = { "*.lua", "*.sty" }

-- Example assets a test opens by name from its working directory, because this
-- version of neanestex resolves the neume font, its metadata, and score files
-- relative to the current directory. l3build's own support-file mechanisms each
-- take a single directory and both are already spoken for, so copy this third
-- set beside each test here; they are test support, not package installation
-- files. Text fonts are resolved by family through OSFONTDIR and need no copy.
--
-- These two are the pair named by \NeanesUseBundledNeumeFont in
-- tests/latex/harness/neanestest.sty. A configuration appends whatever else its
-- own fixtures input, so a suite pays only for the scores it uses.
checkexamplefiles = { "NeanesEngraving.otf", "neanesengraving.metadata.json" }

function checkinit_hook()
    local errorlevel = 0

    for _, file in ipairs(checkexamplefiles) do
        errorlevel = errorlevel + cp(file, "examples", testdir)
    end

    return errorlevel
end
