--------------------------------------------------------------------------------
-- neanestest.lua
-- Assertion engine for the NeanesTeX test suite.  Loaded by neanestest.sty and
-- driven from *.lvt documents compiled with lualatex.
--
-- Two families of assertions:
--
--   * Immediate assertions: numeric checks operate directly on their arguments;
--     box checks inspect \neanestestbox for vertical-list structure, glyph
--     properties, and content. Structural positions are located with
--     \neanesanchor specials.
--
--   * Deferred page assertions: \neanesmark places a \latelua whatsit whose
--     callback records, at shipout, the page number and vertical page position
--     of the mark.  expect_* assertions are evaluated at end of document,
--     after all pages have shipped.
--
-- Every assertion appends a PASS/FAIL line to the record. finish() emits the
-- record between l3build's log markers; assertion failures make l3build's
-- normalized output differ from the saved .tlg reference.
--------------------------------------------------------------------------------

local M = {}

M.results = {}
M.failures = 0
M.marks = {}
M.deferred = {}
M.box = nil

--------------------------------------------------------------------------------
-- Node-type constants resolved by name, so subtype renumbering in a future
-- LuaTeX shows up as a loud failure rather than silently wrong assertions.
--------------------------------------------------------------------------------

local GLUE_ID = node.id("glue")
local KERN_ID = node.id("kern")
local PENALTY_ID = node.id("penalty")
local HLIST_ID = node.id("hlist")
local VLIST_ID = node.id("vlist")
local RULE_ID = node.id("rule")
local GLYPH_ID = node.id("glyph")
local DISC_ID = node.id("disc")
local WHATSIT_ID = node.id("whatsit")

local SPECIAL_SUB, COLORSTACK_SUB, PDF_LITERAL_SUB
for id, name in pairs(node.whatsits()) do
    if name == "special" then
        SPECIAL_SUB = id
    elseif name == "pdf_colorstack" then
        COLORSTACK_SUB = id
    elseif name == "pdf_literal" then
        PDF_LITERAL_SUB = id
    end
end
assert(SPECIAL_SUB and COLORSTACK_SUB and PDF_LITERAL_SUB, "neanestest: whatsit subtypes not found")

-- A private key in a box node's properties table points at the snapshot taken
-- from that exact box. Refilling the register creates a new box node without
-- this stamp, which is what makes a stale snapshot detectable.
local BOX_SNAPSHOT_PROPERTY = {}

--------------------------------------------------------------------------------
-- Result recording
--------------------------------------------------------------------------------

-- Tabs do not survive l3build log normalization unchanged.
local SEP = " | "

-- `quiet` suppresses the running diagnostic lines, which is only right once
-- \START has opened the normalized region.
local function record(ok, name, detail, quiet)
    local status = ok and "PASS" or "FAIL"
    if not ok then
        M.failures = M.failures + 1
    end
    local line = status .. SEP .. name .. SEP .. (detail or "")
    table.insert(M.results, line)
    if quiet then
        return
    end
    texio.write_nl("log", "neanestest: " .. line)
    if not ok then
        texio.write_nl("term", "neanestest: " .. line)
    end
end

local function sp2pt(sp)
    return string.format("%.3fpt", sp / 65536)
end

--------------------------------------------------------------------------------
-- Immediate numeric assertions
--------------------------------------------------------------------------------

function M.check_num(name, got, expected)
    record(got == expected, name, string.format("got %d, expected %d", got, expected))
end

function M.check_dim(name, got, expected, tol)
    local ok = math.abs(got - expected) <= tol
    record(ok, name, string.format("got %s, expected %s +/- %s", sp2pt(got), sp2pt(expected), sp2pt(tol)))
end

function M.check_dim_range(name, got, min, max)
    local ok = got >= min and got <= max
    record(ok, name, string.format("got %s, expected [%s, %s]", sp2pt(got), sp2pt(min), sp2pt(max)))
end

-- Verdict shared by the "every occurrence of this character must ..."
-- assertions: at least one occurrence, and none of them bad.
local function record_every_occurrence(name, count, bad, detail)
    record(count > 0 and #bad == 0, name, detail .. (#bad == 0 and "" or "; saw " .. table.concat(bad, ", ")))
end

--------------------------------------------------------------------------------
-- Box scanning
--
-- use_box() walks \neanestestbox once and snapshots everything the assertions
-- need into plain Lua data: the top-level vertical list, and every glyph with
-- its font, size, effective color and position.  Assertions read that snapshot
-- rather than the node list, so they stay valid after the box register is
-- reused and a test with fifty assertions still walks the box once.
--------------------------------------------------------------------------------

-- Name and size are constant per font id, and a score box holds thousands of
-- glyphs drawn from a handful of fonts, so resolve each id once.
local font_info = {}

local function glyph_font(n)
    local info = font_info[n.font]
    if not info then
        local f = font.getfont(n.font) or font.fonts[n.font]
        info = { name = (f and (f.fullname or f.name)) or "?", size = (f and f.size) or 0 }
        font_info[n.font] = info
    end
    return info.name, info.size
end

-- The name carried by an \neanesanchor special, or nil for any other whatsit.
local function anchor_name(n)
    return (n.data or ""):match("^neanes:(.*)$")
end

-- The luacolor attribute, when that package is managing color. Glyph color is
-- then carried per node rather than by the color stack.
local function luacolor_attribute()
    local package = oberdiek and oberdiek.luacolor
    return package and package.getattribute and package.getattribute()
end

-- Fold one node into the snapshot.  `place` carries the glyph's position within
-- its top-level line, and is nil wherever coordinates are not defined.
local function collect(n, out, state, place)
    if n.id == GLYPH_ID then
        local fname, fsize = glyph_font(n)
        local glyph = {
            char = n.char,
            font = fname,
            font_id = n.font,
            size = fsize,
            color = state.color,
            color_attribute = state.attribute and node.has_attribute(n, state.attribute) or nil,
        }
        if place then
            glyph.line = place.line
            glyph.outer_box_width = place.outer
            -- Coordinates are defined only for a glyph sitting directly in a
            -- horizontal list; one dropped straight into a vertical list still
            -- belongs to the line and its enclosing box.
            if place.x then
                glyph.x = place.x + (n.xoffset or 0)
                glyph.y = place.y + (n.yoffset or 0)
            end
        end
        table.insert(out.glyphs, glyph)
        if n.char and n.char < 0x110000 then
            table.insert(out.text, utf8.char(n.char))
        end
    elseif n.id == GLUE_ID then
        if n.width > 0 then
            table.insert(out.text, " ")
        end
    elseif n.id == RULE_ID then
        table.insert(out.rules, { width = n.width, height = n.height, depth = n.depth })
    elseif n.id == DISC_ID and n.replace then
        for replacement in node.traverse(n.replace) do
            collect(replacement, out, state, place)
        end
    elseif n.id == WHATSIT_ID then
        if n.subtype == SPECIAL_SUB then
            local data = n.data or ""
            table.insert(out.literals, data)
            local anchor = anchor_name(n)
            if anchor then
                table.insert(out.specials, anchor)
            end
        elseif n.subtype == PDF_LITERAL_SUB then
            table.insert(out.literals, n.data or "")
        elseif n.subtype == COLORSTACK_SUB then
            local data = n.data or ""
            table.insert(out.colors, data)
            if n.command == 0 then
                state.color = data
            elseif n.command == 1 then
                table.insert(state.stack, state.color)
                state.color = data
            elseif n.command == 2 then
                state.color = table.remove(state.stack) or ""
            end
        end
    end
end

local scan_hlist, scan_vlist, scan_unplaced

-- A list whose glyphs have no defined position: outside any top-level
-- horizontal list, or directly inside a vertical one.
scan_unplaced = function(head, out, state)
    for n in node.traverse(head) do
        collect(n, out, state, nil)
        if n.id == HLIST_ID or n.id == VLIST_ID then
            scan_unplaced(n.list, out, state)
        end
    end
end

-- Nested boxes retain their own shifts, and effective glue accounts for
-- centered or fill material in an already packed parent.  Keeping the top-level
-- line number explicit prevents an offset assertion from comparing unrelated
-- score lines.  `outer` is the width of the direct child box of the line that
-- encloses these glyphs, which is what pins an overlay's horizontal advance.
scan_hlist = function(parent, out, state, origin_x, origin_y, line, outer)
    local place = { line = line, x = origin_x, y = origin_y, outer = outer }

    for n in node.traverse(parent.list) do
        collect(n, out, state, place)

        if n.id == HLIST_ID then
            scan_hlist(n, out, state, place.x, origin_y + (n.shift or 0), line, outer or n.width)
        elseif n.id == VLIST_ID then
            scan_vlist(n, out, state, place.x, origin_y + (n.shift or 0), line, outer or n.width)
        end

        if n.id == GLUE_ID then
            place.x = place.x + node.effective_glue(n, parent, true)
        elseif n.id == KERN_ID then
            place.x = place.x + n.kern
        elseif n.id == DISC_ID and n.replace then
            place.x = place.x + node.dimensions(n.replace)
        elseif n.width then
            place.x = place.x + n.width
        end
    end
end

scan_vlist = function(parent, out, state, origin_x, origin_y, line, outer)
    local place = { line = line, outer = outer }
    local y = origin_y - parent.height

    for n in node.traverse(parent.list) do
        if n.id == HLIST_ID then
            y = y + n.height
            scan_hlist(n, out, state, origin_x + (n.shift or 0), y, line, outer)
            y = y + n.depth
        elseif n.id == VLIST_ID then
            y = y + n.height
            scan_vlist(n, out, state, origin_x + (n.shift or 0), y, line, outer)
            y = y + n.depth
        else
            collect(n, out, state, place)
            if n.id == GLUE_ID then
                y = y + node.effective_glue(n, parent, true)
            elseif n.id == KERN_ID then
                y = y + n.kern
            elseif n.id == RULE_ID then
                y = y + n.height + n.depth
            end
        end
    end
end

function M.use_box(boxnum)
    local b = tex.box[boxnum]
    assert(b, "neanestest: box " .. boxnum .. " is void")

    local out = { glyphs = {}, text = {}, specials = {}, colors = {}, literals = {}, rules = {} }
    local state = { color = "", stack = {}, attribute = luacolor_attribute() }
    local trace = {}
    local line = 0

    for n in node.traverse(b.list) do
        local e = { id = n.id, subtype = n.subtype }
        if n.id == GLUE_ID then
            e.width = n.width
        elseif n.id == KERN_ID then
            e.width = n.kern
        elseif n.id == PENALTY_ID then
            e.penalty = n.penalty
        elseif n.id == HLIST_ID or n.id == VLIST_ID or n.id == RULE_ID then
            e.height = n.height
            e.depth = n.depth
        elseif n.id == WHATSIT_ID and n.subtype == SPECIAL_SUB then
            e.anchor = anchor_name(n)
        end

        local text_from = #out.text + 1
        local specials_from = #out.specials + 1

        collect(n, out, state, nil)

        if n.id == HLIST_ID then
            line = line + 1
            scan_hlist(n, out, state, 0, 0, line, nil)
        elseif n.id == VLIST_ID then
            scan_unplaced(n.list, out, state)
        end

        if n.id == HLIST_ID or n.id == VLIST_ID then
            e.text = table.concat(out.text, "", text_from, #out.text)
            e.specials = table.move(out.specials, specials_from, #out.specials, 1, {})
        end

        table.insert(trace, e)
    end

    out.text = table.concat(out.text)
    out.trace = trace
    out.boxnum = boxnum

    local properties = node.getproperty(b)
    if not properties then
        properties = {}
        node.setproperty(b, properties)
    end
    properties[BOX_SNAPSHOT_PROPERTY] = out

    M.box = out
end

-- The snapshot taken by the most recent \NeanesUseBox.  Only use_box() ever
-- stamps a box with its snapshot, so a register that still points back at this
-- one cannot have been refilled since.
local function snapshot()
    local captured = assert(M.box, "neanestest: use_box() not called")
    local current = tex.box[captured.boxnum]
    local properties = current and node.getproperty(current)
    assert(properties and properties[BOX_SNAPSHOT_PROPERTY] == captured, "neanestest: box changed since use_box() was called")
    return captured
end

-- Debug aid: dump the current trace to the log.  Deliberately not asserted by
-- any test; it exists to make a failing one legible.
function M.dump_trace()
    if not M.box then
        texio.write_nl("log", "neanestest: no trace")
        return
    end
    for i, e in ipairs(snapshot().trace) do
        local desc = node.type(e.id)
        if e.id == GLUE_ID or e.id == KERN_ID then
            desc = string.format("%s subtype=%s width=%s", desc, tostring(e.subtype), sp2pt(e.width))
        elseif e.id == PENALTY_ID then
            desc = string.format("penalty %d", e.penalty)
        elseif e.height then
            desc = string.format("%s h=%s d=%s text=[%s] anchors=[%s]", desc, sp2pt(e.height), sp2pt(e.depth), e.text or "", e.specials and table.concat(e.specials, ",") or "")
        elseif e.anchor then
            desc = "anchor " .. e.anchor
        end
        texio.write_nl("log", string.format("neanestest trace %3d %s", i, desc))
    end
end

-- Top-level index of an anchor: either a vertical-mode \neanesanchor whatsit or
-- a box whose interior contains the anchor.
local function anchor_index(name)
    for i, e in ipairs(snapshot().trace) do
        if e.anchor == name then
            return i, false
        end
        if e.specials then
            for _, s in ipairs(e.specials) do
                if s == name then
                    return i, true
                end
            end
        end
    end
    return nil
end

-- The line a gap measurement should attach to: the box containing the
-- anchor, or the first box after a vertical-mode anchor.
local function line_index(name)
    local i, inside = anchor_index(name)
    if not i then
        return nil
    end
    if inside then
        return i
    end
    local trace = snapshot().trace
    for j = i + 1, #trace do
        local e = trace[j]
        if e.id == HLIST_ID or e.id == VLIST_ID then
            return j
        end
    end
    return nil
end

-- The span of trace entries between the lines owning two anchors, or nil
-- (with the failure already recorded) when the anchors are missing or
-- inverted.
local function region(name, a, b)
    local ia, ib = line_index(a), line_index(b)
    if not ia or not ib then
        record(false, name, string.format("anchor not found: %s=%s %s=%s", a, tostring(ia), b, tostring(ib)))
        return nil
    end
    if ia >= ib then
        record(false, name, string.format("anchors out of order: %s@%d %s@%d", a, ia, b, ib))
        return nil
    end
    return ia, ib
end

-- The trace entries lying strictly between the lines owning two anchors, or nil
-- (with the failure already recorded) when the anchors cannot be resolved.
local function entries_between(name, a, b)
    local ia, ib = region(name, a, b)
    if not ia then
        return nil
    end
    return table.move(snapshot().trace, ia + 1, ib - 1, 1, {}), ia + 1
end

-- Baseline-to-baseline distance between the line owning anchor a and the
-- line owning anchor b: depth of the first, everything between, height of
-- the second.
function M.check_baseline_gap(name, a, b, min, max)
    local ia, ib = region(name, a, b)
    if not ia then
        return
    end
    local trace = snapshot().trace
    local gap = trace[ia].depth
    for i = ia + 1, ib - 1 do
        local e = trace[i]
        if e.id == GLUE_ID or e.id == KERN_ID then
            gap = gap + e.width
        elseif e.height then
            gap = gap + e.height + e.depth
        end
    end
    gap = gap + trace[ib].height
    local ok = gap >= min and gap <= max
    record(ok, name, string.format("baseline gap %s, expected [%s, %s]", sp2pt(gap), sp2pt(min), sp2pt(max)))
end

-- A penalty node of exactly this value exists strictly between the anchors.
function M.check_penalty_between(name, a, b, value)
    local entries = entries_between(name, a, b)
    if not entries then
        return
    end
    local seen = {}
    for _, e in ipairs(entries) do
        if e.id == PENALTY_ID then
            if e.penalty == value then
                record(true, name, string.format("penalty %d present", value))
                return
            end
            table.insert(seen, tostring(e.penalty))
        end
    end
    record(false, name, string.format("penalty %d absent; saw [%s]", value, table.concat(seen, ",")))
end

-- A glue node of this width (within tol) exists strictly between the anchors.
function M.check_glue_width_between(name, a, b, width, tol)
    local entries = entries_between(name, a, b)
    if not entries then
        return
    end
    local seen = {}
    for _, e in ipairs(entries) do
        if e.id == GLUE_ID then
            if math.abs(e.width - width) <= tol then
                record(true, name, string.format("glue %s present", sp2pt(e.width)))
                return
            end
            table.insert(seen, sp2pt(e.width))
        end
    end
    record(false, name, string.format("no glue near %s; saw [%s]", sp2pt(width), table.concat(seen, ",")))
end

-- No glue within tol of this width exists strictly between the anchors.
function M.check_no_glue_width_between(name, a, b, width, tol)
    local entries, first_index = entries_between(name, a, b)
    if not entries then
        return
    end
    for i, e in ipairs(entries) do
        if e.id == GLUE_ID and math.abs(e.width - width) <= tol then
            record(false, name, string.format("found forbidden glue %s at %d", sp2pt(e.width), first_index + i - 1))
            return
        end
    end
    record(true, name, string.format("no glue within %s of %s", sp2pt(tol), sp2pt(width)))
end

--------------------------------------------------------------------------------
-- Glyph-level assertions, all reading the snapshot taken by \NeanesUseBox
--------------------------------------------------------------------------------

-- Every snapshot glyph for `char`, in document order.  All the per-character
-- assertions address occurrences the same way, so the walk is written once.
local function occurrences(char)
    local codepoint = utf8.codepoint(char)
    local found = {}

    for _, glyph in ipairs(snapshot().glyphs) do
        if glyph.char == codepoint then
            table.insert(found, glyph)
        end
    end

    return found
end

-- The nth occurrence of `char`, and how many occurrences were seen. `required`
-- names a field the selected glyph must carry, which is how positioned and
-- boxed glyphs are validated without changing the occurrence numbering.
local function find_occurrence(char, occurrence, required)
    local found = occurrences(char)
    local glyph = found[occurrence]

    if not glyph then
        return nil, #found, nil
    end
    if required and glyph[required] == nil then
        return nil, #found, required
    end
    return glyph, #found, nil
end

local function occurrence_failure(char, occurrence, count, missing_field)
    if missing_field then
        return string.format("glyph %q #%d lacks required field %s", char, occurrence, missing_field)
    end
    return string.format("glyph occurrence missing: %q #%d (saw %d)", char, occurrence, count)
end

-- The horizontal origin of one glyph within its top-level line.  A range is
-- more useful than an exact coordinate for alignment contracts because it
-- remains stable when a bundled font's advance width changes slightly.
function M.check_glyph_x_range(name, char, occurrence, min, max)
    local glyph, count, missing_field = find_occurrence(char, occurrence, "x")
    if not glyph then
        record(false, name, occurrence_failure(char, occurrence, count, missing_field))
        return
    end

    record(glyph.x >= min and glyph.x <= max, name, string.format("x origin %s, expected %s .. %s", sp2pt(glyph.x), sp2pt(min), sp2pt(max)))
end

function M.check_glyph_count(name, char, expected)
    local count = #occurrences(char)
    record(count == expected, name, string.format("%d occurrence(s) of %q, expected %d", count, char, expected))
end

-- Every occurrence of `char` uses a font with exactly the requested synthetic
-- weight and slant. fontspec records FakeBold and FakeSlant as the luaotfload
-- `embolden` and `slant` features; testing both their presence and absence
-- keeps the two independent flags from being conflated.
function M.check_glyph_synthesis(name, char, expected_bold, expected_italic)
    local found = occurrences(char)
    local bad = {}

    for _, glyph in ipairs(found) do
        local f = font.getfont(glyph.font_id)
        local raw = f and f.specification and f.specification.features and f.specification.features.raw
        assert(raw, "neanestest: no specification.features.raw for font " .. glyph.font_id)

        local bold = tonumber(raw.embolden or 0) ~= 0
        local italic = tonumber(raw.slant or 0) ~= 0

        if bold ~= expected_bold or italic ~= expected_italic then
            table.insert(bad, string.format("font %d has bold=%s italic=%s", glyph.font_id, tostring(bold), tostring(italic)))
        end
    end

    record_every_occurrence(name, #found, bad, string.format("%d occurrence(s) of %q use synthetic bold=%s italic=%s", #found, char, tostring(expected_bold), tostring(expected_italic)))
end

-- Keys fontspec puts in a raw feature table that select the face rather than
-- request an OpenType feature.  Everything else in that table is a tag the
-- score asked for.
local SELECTOR_KEYS = { mode = true, script = true, language = true }

-- Each distinct font in the snapshot whose full name is exactly `fontname`, as
-- its id and its raw fontspec feature table.  The name is compared whole
-- because faces nest by prefix -- "Source Serif 4" is a prefix of "Source Serif
-- 4 Display Semibold" -- and a substring match would let the wrong face answer
-- for the one under test.  `specification.features.raw` is a luaotfload
-- internal and the most fragile path in this file, so both font assertions
-- reach it through here rather than spelling it out twice.
local function each_named_font(fontname)
    local glyphs = snapshot().glyphs
    local seen_ids = {}
    local i = 0

    return function()
        while true do
            i = i + 1
            local glyph = glyphs[i]
            if not glyph then
                return nil
            end
            if not seen_ids[glyph.font_id] and glyph.font == fontname then
                seen_ids[glyph.font_id] = true
                local f = font.getfont(glyph.font_id)
                local raw = f and f.specification and f.specification.features and f.specification.features.raw
                assert(raw, "neanestest: no specification.features.raw for font " .. glyph.font_id)
                return glyph.font_id, raw
            end
        end
    end
end

-- The OpenType tags one face requests, with the selector keys dropped.
local function requested_features(raw)
    local tags = {}

    for key, value in pairs(raw) do
        if not SELECTOR_KEYS[key] then
            tags[key] = value
        end
    end

    return tags
end

-- fontspec's +tag/-tag spelling, sorted, so a failure detail is stable.
local function format_features(tags)
    local parts = {}

    for tag, value in pairs(tags) do
        if value == true then
            table.insert(parts, "+" .. tag)
        elseif value == false then
            table.insert(parts, "-" .. tag)
        else
            table.insert(parts, "+" .. tag .. "=" .. tostring(value))
        end
    end

    table.sort(parts)
    return #parts > 0 and table.concat(parts, ",") or "(none)"
end

local function same_features(tags, expected)
    for tag, value in pairs(expected) do
        if tags[tag] ~= value then
            return false
        end
    end

    for tag in pairs(tags) do
        if expected[tag] == nil then
            return false
        end
    end

    return true
end

-- One used face of `fontname` requests exactly the OpenType tags in `csv`, and
-- no others.  Feature tokens use fontspec's +tag/-tag spelling.
--
-- luaotfload builds a separate face for every distinct feature set, so the
-- whole set identifies the selector a text style was supposed to produce.
-- Asking only that the listed tags be present would let a neighbouring style's
-- face -- one carrying those tags among others -- answer in its place, which
-- is the same hole an inexact font name opens.  This is an assertion about the
-- selector NeanesTeX hands to luaotfload, not about the shaped glyphs.
function M.check_font_features(name, fontname, csv)
    local expected = {}
    for token in csv:gmatch("[^,%s]+") do
        local sign, tag = token:match("^([+-])([%a%d][%a%d][%a%d][%a%d])$")
        assert(sign and tag, "neanestest: invalid feature token " .. token)
        expected[tag] = sign == "+"
    end

    local seen = {}

    for _, raw in each_named_font(fontname) do
        local tags = requested_features(raw)
        if same_features(tags, expected) then
            record(true, name, string.format("font %q requests exactly %s", fontname, csv))
            return
        end
        table.insert(seen, format_features(tags))
    end

    local detail = #seen > 0 and string.format("saw %s", table.concat(seen, " ")) or string.format("no used face named %q", fontname)
    record(false, name, string.format("no face of %q requests exactly %s: %s", fontname, csv, detail))
end

-- Every used face of `fontname` was declared with `script`, and at least one
-- such face exists. fontspec stamps a document-level Script default onto every
-- face it creates, so a score's own \newfontface declarations inherit the
-- surrounding document's script. One face keeping the script proves nothing
-- about the rest, so the assertion covers them all: a style whose face silently
-- dropped it is exactly the regression worth catching.
function M.check_font_script(name, fontname, script)
    local bad = {}
    local count = 0

    for _, raw in each_named_font(fontname) do
        count = count + 1
        if raw.script ~= script then
            table.insert(bad, string.format("%q", tostring(raw.script)))
        end
    end

    record_every_occurrence(name, count, bad, string.format("%d face(s) of %q request script %q", count, fontname, script))
end

-- Substring search over one of the snapshot's recorded string lists.
local function check_contains(name, list, needle, noun)
    local found = false
    for _, data in ipairs(list) do
        if data:find(needle, 1, true) then
            found = true
            break
        end
    end
    record(found, name, string.format("%s %q %s", noun, needle, found and "present" or "absent"))
end

function M.check_pdf_literal(name, needle)
    check_contains(name, snapshot().literals, needle, "PDF literal")
end

function M.check_pdf_colorstack(name, needle)
    check_contains(name, snapshot().colors, needle, "PDF color-stack operation")
end

-- At least one rule in the box has the requested dimensions.  Rules are
-- searched recursively because score melismas sit inside several nested
-- element and color boxes.
function M.check_rule_size(name, expected_width, expected_height, expected_depth, tol)
    local rules = snapshot().rules
    local closest

    for _, r in ipairs(rules) do
        if math.abs(r.width - expected_width) <= tol and math.abs(r.height - expected_height) <= tol and math.abs(r.depth - expected_depth) <= tol then
            record(true, name, string.format("rule %s x %s + %s present", sp2pt(r.width), sp2pt(r.height), sp2pt(r.depth)))
            return
        end

        local distance = math.abs(r.width - expected_width) + math.abs(r.height - expected_height) + math.abs(r.depth - expected_depth)
        if not closest or distance < closest.distance then
            closest = { distance = distance, width = r.width, height = r.height, depth = r.depth }
        end
    end

    local detail = string.format("no rule matched %s x %s + %s +/- %s; saw %d rule(s)", sp2pt(expected_width), sp2pt(expected_height), sp2pt(expected_depth), sp2pt(tol), #rules)
    if closest then
        detail = detail .. string.format("; closest was %s x %s + %s", sp2pt(closest.width), sp2pt(closest.height), sp2pt(closest.depth))
    end
    record(false, name, detail)
end

-- The width of the direct child box containing an addressed glyph occurrence.
-- Score elements are emitted as direct child mboxes of their paragraph line,
-- so this pins whether an overlay changes the element's horizontal advance.
function M.check_glyph_outer_box_width(name, char, occurrence, expected, tol)
    local glyph, count, missing_field = find_occurrence(char, occurrence, "outer_box_width")
    if not glyph then
        record(false, name, occurrence_failure(char, occurrence, count, missing_field))
        return
    end

    local width = glyph.outer_box_width
    record(math.abs(width - expected) <= tol, name, string.format("outer box width %s, expected %s +/- %s", sp2pt(width), sp2pt(expected), sp2pt(tol)))
end

-- Compare the origins of two addressed glyph occurrences on the same line.
-- Occurrence indices make repeated quantitative neumes usable as width oracles.
function M.check_glyph_offset(name, from_char, from_occurrence, to_char, to_occurrence, expected_x, expected_y, tol)
    local from, from_count, from_missing_field = find_occurrence(from_char, from_occurrence, "x")
    local to, to_count, to_missing_field = find_occurrence(to_char, to_occurrence, "x")

    if not from or not to then
        local problems = {}
        if not from then
            table.insert(problems, occurrence_failure(from_char, from_occurrence, from_count, from_missing_field))
        end
        if not to then
            table.insert(problems, occurrence_failure(to_char, to_occurrence, to_count, to_missing_field))
        end
        record(false, name, table.concat(problems, "; "))
        return
    end

    if from.line ~= to.line then
        record(false, name, string.format("glyphs lie on different lines: %d and %d", from.line, to.line))
        return
    end

    local dx = to.x - from.x
    local dy = to.y - from.y
    local ok = math.abs(dx - expected_x) <= tol and math.abs(dy - expected_y) <= tol
    record(ok, name, string.format("offset (%s, %s), expected (%s, %s) +/- %s", sp2pt(dx), sp2pt(dy), sp2pt(expected_x), sp2pt(expected_y), sp2pt(tol)))
end

-- Every occurrence of `char` uses a font whose name contains `pattern`
-- (want) or contains it nowhere (not want), and at least one occurrence
-- exists.
function M.check_glyph_font(name, char, pattern, want)
    local found = occurrences(char)
    local bad = {}
    for _, g in ipairs(found) do
        if (g.font:find(pattern, 1, true) ~= nil) ~= want then
            table.insert(bad, string.format("%q", g.font))
        end
    end
    local how = want and "in fonts matching" or "in no font matching"
    record_every_occurrence(name, #found, bad, string.format("%d occurrence(s) of %q %s %q", #found, char, how, pattern))
end

-- Every occurrence of `char` is set at `expected` sp within `tol`, and at
-- least one occurrence exists.  Addressing a character rather than merely a
-- font makes mixed-size score boxes testable without depending on node order.
function M.check_glyph_size(name, char, expected, tol)
    local found = occurrences(char)
    local bad = {}
    for _, g in ipairs(found) do
        if math.abs(g.size - expected) > tol then
            table.insert(bad, sp2pt(g.size))
        end
    end
    record_every_occurrence(name, #found, bad, string.format("%d occurrence(s) of %q at %s +/- %s", #found, char, sp2pt(expected), sp2pt(tol)))
end

-- Some glyph in the box uses a font whose name contains `pattern` at a size
-- of at least `minsize` sp.  Zero `minsize` checks presence only.
function M.check_any_glyph(name, pattern, minsize)
    local best
    for _, g in ipairs(snapshot().glyphs) do
        if g.font:find(pattern, 1, true) then
            if not best or g.size > best then
                best = g.size
            end
        end
    end
    if not best then
        record(false, name, string.format("no glyph in font matching %q", pattern))
    else
        record(best >= minsize, name, string.format("font %q at %s, wanted >= %s", pattern, sp2pt(best), sp2pt(minsize)))
    end
end

-- No glyph in the box is set at a size below `minsize` sp.  Catches
-- superscript or script-size intrusions in material meant to be uniform.
function M.check_no_glyph_smaller(name, minsize)
    local smallest
    for _, g in ipairs(snapshot().glyphs) do
        if not smallest or g.size < smallest then
            smallest = g.size
        end
    end
    if not smallest then
        record(false, name, "box has no glyphs")
    else
        record(smallest >= minsize, name, string.format("smallest glyph %s, wanted >= %s", sp2pt(smallest), sp2pt(minsize)))
    end
end

-- A color-stack push in the box begins with `prefix` (e.g. the rg values of
-- a named red).
function M.check_color(name, prefix)
    for _, c in ipairs(snapshot().colors) do
        if c:sub(1, #prefix) == prefix then
            record(true, name, "color " .. prefix .. " present")
            return
        end
    end
    record(false, name, "no color starting " .. prefix)
end

-- Every occurrence of `char` in the box uses the color represented by
-- `prefix`. A unique glyph can address one piece of otherwise mixed-color
-- material.
function M.check_glyph_color(name, char, prefix)
    local found = occurrences(char)
    local bad = {}
    local package = oberdiek and oberdiek.luacolor
    local expected_attribute = package and package.getvalue and package.getvalue(prefix)
    for _, glyph in ipairs(found) do
        if expected_attribute then
            if glyph.color_attribute ~= expected_attribute then
                table.insert(bad, glyph.color_attribute and "<attribute " .. glyph.color_attribute .. ">" or "<default>")
            end
        elseif glyph.color:sub(1, #prefix) ~= prefix then
            table.insert(bad, glyph.color == "" and "<default>" or glyph.color)
        end
    end
    record_every_occurrence(name, #found, bad, string.format("%d occurrence(s) of %q; wanted color %q", #found, char, prefix))
end

-- The concatenated glyph text of the box contains `needle`.  Reliable only
-- for plain upright/italic text: font features (small caps, ligatures) remap
-- chars to private glyph slots.
function M.check_box_text(name, needle)
    local text = snapshot().text
    record(text:find(needle, 1, true) ~= nil, name, string.format("needle %q, haystack %q", needle, text))
end

function M.check_box_text_absent(name, needle)
    local text = snapshot().text
    local ok = text:find(needle, 1, true) == nil
    record(ok, name, string.format("needle %q %s in haystack %q", needle, ok and "absent" or "present", text))
end

function M.check_box_text_order(name, csv)
    local text = snapshot().text
    local cursor = 1
    local positions = {}
    for needle in csv:gmatch("[^,]+") do
        local position = text:find(needle, cursor, true)
        if not position then
            record(false, name, string.format("ordered needle %q absent after byte %d in haystack %q", needle, cursor, text))
            return
        end
        positions[#positions + 1] = string.format("%s@%d", needle, position)
        cursor = position + #needle
    end
    record(true, name, "ordered " .. table.concat(positions, ", "))
end

--------------------------------------------------------------------------------
-- Shipout marks and deferred page assertions
--------------------------------------------------------------------------------

-- Called from the \latelua whatsit during shipout. A repeated name keeps
-- the first sighting's position.
function M.mark(name)
    if not M.marks[name] then
        local _, y = pdf.getpos()
        M.marks[name] = { page = status.total_pages + 1, y = y }
    end
end

local function defer(name, fn)
    table.insert(M.deferred, { name = name, fn = fn })
end

function M.expect_same_page(name, csv)
    defer(name, function()
        local missing, described = {}, {}
        local first, same = nil, true

        for token in csv:gmatch("[^,%s]+") do
            local m = M.marks[token]
            table.insert(described, string.format("%s=p%s", token, m and tostring(m.page) or "?"))
            if not m then
                table.insert(missing, token)
            elseif first == nil then
                first = m.page
            elseif m.page ~= first then
                same = false
            end
        end

        if #missing > 0 then
            record(false, name, "missing marks: " .. table.concat(missing, ","))
        else
            record(same, name, table.concat(described, " "))
        end
    end)
end

-- Marks on the same page, with vertical distance in the inclusive range (sp).
function M.expect_vdist_range(name, a, b, min, max)
    defer(name, function()
        local ma, mb = M.marks[a], M.marks[b]
        if not ma or not mb then
            record(false, name, "missing mark")
            return
        end
        if ma.page ~= mb.page then
            record(false, name, string.format("%s=p%d %s=p%d", a, ma.page, b, mb.page))
            return
        end
        local d = ma.y - mb.y
        local ok = d >= min and d <= max
        record(ok, name, string.format("vdist %s, expected %s .. %s", sp2pt(d), sp2pt(min), sp2pt(max)))
    end)
end

--------------------------------------------------------------------------------
-- Finish: run deferred assertions and write the normalized result record.
--------------------------------------------------------------------------------

function M.run_deferred()
    for _, d in ipairs(M.deferred) do
        local ok, err = pcall(d.fn)
        if not ok then
            record(false, d.name, "assertion error: " .. tostring(err))
        end
    end
end

function M.finish()
    -- A test with no assertions must differ from every valid passing reference.
    if #M.results == 0 then
        record(false, "harness", "no assertions ran", true)
    end
    for _, line in ipairs(M.results) do
        texio.write_nl("log", line)
    end
    texio.write_nl("log", "TOTAL" .. SEP .. #M.results .. SEP .. M.failures)
    texio.write_nl("term", string.format("neanestest: %d assertion(s), %d failure(s)", #M.results, M.failures))
    if M.failures > 0 then
        tex.error("neanestest: assertion failure", {
            string.format("The test recorded %d failed assertion(s).", M.failures),
        })
    end
end

return M
