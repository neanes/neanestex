neanestex = neanestex or {}
local neanestex = neanestex

local err, warn, info, log = luatexbase.provides_module({
    name = "neanestex",
    date = "2026/07/30",
    version = "1.1.0",
    description = "A package for inserting Byzantine Chant scores into LaTeX.",
    author = "danielgarthur",
    license = "GPL-3.0",
})

local schema_version = 3
-- Schema changes
-- 1 to 2: Positive lyricsVerticalOffset now moves lyrics down, making it consistent with other offsets in the schema
-- 2 to 3: Text typography moved to an interned table of fully resolved text
-- styles. Elements reference the final style they render with. Exact font face
-- names and structured OpenType feature settings are preserved. Alignment is
-- spelled out everywhere, including on mode keys, which used to abbreviate it
-- to a single letter. Every v3 text style carries the exact postscriptName.
-- Family selection plus recognizable bold/italic axes is only the v1/v2
-- compatibility path. Glyph positioning includes layout-resolved spacing,
-- offsets, transferred measure-bar placement, and leading lyric hyphens.

local lualibs = require("lualibs")
local json = utilities.json
local glyphNameToCodepointMap = {}
local font_metadata = nil
local neume_font_data_map = {}
local neume_font_family = nil
local neume_font_file_map = {}
local neume_font_metadata_file_map = {}
local neume_font_metadata_file_map_default = {
    ["Neanes"] = "neanesengraving.metadata.json",
    ["NeanesRTL"] = "neanesrtlengraving.metadata.json",
    ["NeanesStathisSeries"] = "neanesstathisseriesengraving.metadata.json",
}

local DEFAULT_TEXT_STYLE_ID = "default-text"
local LYRICS_STYLE_ID = "lyrics"
local DROP_CAP_STYLE_ID = "drop-cap"

local text_style_definitions = {}
local text_style_schema_version = schema_version

-- The distinct font selectors one score references, declared up front. A v1/v2
-- family selector uses bold/italic NFSS axes; a v3 selector is one required
-- PostScript face and OpenType feature combination. The serial is never reset so
-- a macro name is unique across every score in the document, whatever grouping
-- the surrounding LaTeX applies.
local font_selector_macros = {}
local font_selector_declarations = {}
local font_selector_serial = 0

local function read_json(filename)
    local file = io.open(filename, "r")
    if not file then
        return err("read_json: file not found " .. filename)
    end
    local content = file:read("*all")
    file:close()
    return content
end

local glyphnames = json.tolua(read_json(kpse.find_file("glyphnames.json", "tex")))

local function load_font_data(font)
    local font_metadata_filename = neume_font_metadata_file_map[font]

    if font_metadata_filename == nil then
        font_metadata_filename = neume_font_metadata_file_map_default[font]
    end

    local font_metadata_path = kpse.find_file(font_metadata_filename, "tex") or font_metadata_filename
    local font_metadata = json.tolua(read_json(font_metadata_path))

    local glyph_name_to_codepoint_map = {}

    for glyph, data in pairs(glyphnames) do
        glyph_name_to_codepoint_map[glyph] = data.codepoint:sub(3)
    end

    for glyph, data in pairs(font_metadata.optionalGlyphs) do
        glyph_name_to_codepoint_map[glyph] = data.codepoint:sub(3)
    end

    return {
        glyph_name_to_codepoint_map = glyph_name_to_codepoint_map,
        font_metadata = font_metadata,
    }
end

local function get_neume_font_data(font_family)
    if neume_font_data_map[font_family] == nil then
        neume_font_data_map[font_family] = load_font_data(font_family)
    end

    return neume_font_data_map[font_family]
end

local function set_neume_font_family(font_family)
    neume_font_family = font_family
    get_neume_font_data(neume_font_family)
end

local function set_neume_font_file(font_family, filepath)
    neume_font_file_map[font_family] = filepath
end

local function set_neume_font_metadata_file(font_family, filepath)
    neume_font_metadata_file_map[font_family] = filepath

    -- Font data is cached by family, so changing its metadata must discard data
    -- loaded from the previous path. Reload it immediately so an unavailable or
    -- invalid override fails at the configuration command rather than at use.
    neume_font_data_map[font_family] = nil
    get_neume_font_data(font_family)
end

local function get_neume_font(font_family)
    local result = neume_font_file_map[font_family]

    if result == nil then
        warn("No neume font filepath was specified for " .. font_family .. ". Attempting to use installed fonts.")
        return font_family
    else
        return result
    end
end

local function codepoint_from_glyph_name(glyph_name)
    if neume_font_family == nil then
        return err("No neume font family was selected. Did you forget to call \\byzsetneumefontfamily?")
    end

    local data = get_neume_font_data(neume_font_family)
    local codepoint = data.glyph_name_to_codepoint_map[glyph_name]

    if codepoint == nil then
        err("Unknown glyph name: " .. glyph_name)
    end

    tex.sprint(data.glyph_name_to_codepoint_map[glyph_name])
end

local function find_mark_anchor_name(base, mark)
    for anchor_name, _ in pairs(font_metadata.glyphsWithAnchors[mark] or {}) do
        if font_metadata.glyphsWithAnchors[base] and font_metadata.glyphsWithAnchors[base][anchor_name] then
            return anchor_name
        end
    end

    return nil
end

local function get_mark_offset(base, mark, extra_offset)
    local mark_anchor_name = find_mark_anchor_name(base, mark)

    if mark_anchor_name == nil then
        warn("Missing anchor for base: " .. base .. "mark: " .. mark)
        return { x = 0, y = 0 }
    end

    local mark_anchor = font_metadata.glyphsWithAnchors[mark][mark_anchor_name]

    local base_anchor = font_metadata.glyphsWithAnchors[base][mark_anchor_name]

    local extra_x = 0
    local extra_y = 0

    if extra_offset then
        extra_x = extra_offset.x
        extra_y = extra_offset.y
    end

    return {
        x = base_anchor[1] - mark_anchor[1] + extra_x,
        y = -(base_anchor[2] - mark_anchor[2]) + extra_y,
    }
end

local function escape_latex(str)
    local replacements = {
        ["\\"] = "\\textbackslash{}",
        ["{"] = "\\{",
        ["}"] = "\\}",
        ["$"] = "\\$",
        ["&"] = "\\&",
        ["%"] = "\\%",
        ["#"] = "\\#",
        ["_"] = "\\_",
        ["^"] = "\\textasciicircum{}",
        ["~"] = "\\textasciitilde{}",
        ["\n"] = "\\\\",
        ["\u{E280}"] = "{\\byzneumefont\u{E280}}",
        ["\u{E281}"] = "{\\byzneumefont\u{E281}}",
        ["\u{1D0B4}"] = "{\\byzneumefont\u{1D0B4}}",
        ["\u{1D0B5}"] = "{\\byzneumefont\u{1D0B5}}",
    }
    return str:gsub("[\\%$%&%#_%^{}~\n]", replacements):gsub("\u{E280}", replacements["\u{E280}"]):gsub("\u{E281}", replacements["\u{E281}"]):gsub("\u{1D0B4}", replacements["\u{1D0B4}"]):gsub("\u{1D0B5}", replacements["\u{1D0B5}"])
end

-- Whitespace-tokenized so "Semibold" is not read as "Bold".
local function font_style_has_token(font_style, expected)
    for token in string.gmatch(font_style or "", "%S+") do
        if string.lower(token) == expected then
            return true
        end
    end

    return false
end

-- The NFSS axes a style label names.
local function font_style_axes(font_style)
    return font_style_has_token(font_style, "bold"), font_style_has_token(font_style, "italic") or font_style_has_token(font_style, "oblique")
end

local function legacy_font_style(weight, style)
    local bold = weight == "700" or weight == 700 or weight == "bold"
    local italic = style == "italic" or (style and string.match(style, "^oblique"))

    if bold and italic then
        return "Bold Italic"
    elseif bold then
        return "Bold"
    elseif italic then
        return "Italic"
    else
        return "Regular"
    end
end

-- Schema v3 spells alignment out; v1 and v2 abbreviated it to one letter. Fold
-- the old spelling into the new one so everything downstream sees just the one
-- vocabulary.
local function normalize_alignment(alignment)
    if alignment == "c" then
        return "center"
    elseif alignment == "r" then
        return "right"
    elseif alignment == "l" then
        return "left"
    end

    return alignment
end

-- The one-letter position \makebox wants. Justified text has no \makebox
-- equivalent, so it sets flush left like unaligned text.
local function alignment_position(alignment)
    if alignment == "center" then
        return "c"
    elseif alignment == "right" then
        return "r"
    else
        return "l"
    end
end

-- v1 and v2 keyed the three built-in styles off a per-element-kind name in
-- page setup. The style id is ours; the key is theirs.
local LEGACY_STYLE_SPECS = {
    { id = DEFAULT_TEXT_STYLE_ID, key = "textBox" },
    { id = LYRICS_STYLE_ID, key = "lyrics" },
    { id = DROP_CAP_STYLE_ID, key = "dropCap" },
}

local function create_legacy_text_styles(page_setup)
    local styles = {}

    for _, spec in ipairs(LEGACY_STYLE_SPECS) do
        styles[#styles + 1] = {
            id = spec.id,
            alignment = "left",
            fontFamily = page_setup.fontFamilies[spec.key],
            fontSize = page_setup.fontSizes[spec.key],
            fontStyle = legacy_font_style(page_setup[spec.key .. "DefaultFontWeight"], page_setup[spec.key .. "DefaultFontStyle"]),
            color = page_setup.colors[spec.key],
            -- Drop caps had no text decoration before v3, so this is nil there.
            textDecoration = page_setup[spec.key .. "DefaultTextDecoration"] or "none",
        }
    end

    return styles
end

local function load_text_styles(data)
    text_style_definitions = {}
    text_style_schema_version = data.schemaVersion

    local styles = data.textStyles
    if not styles or data.schemaVersion < 3 then
        styles = create_legacy_text_styles(data.pageSetup)
    end

    for _, style in ipairs(styles) do
        text_style_definitions[style.id] = style
    end
end

local function get_legacy_text_style(style_id)
    return text_style_definitions[style_id] or text_style_definitions[DEFAULT_TEXT_STYLE_ID] or {}
end

local function legacy_element_style(element, prefix, paragraph_style_id)
    local function value(name)
        if prefix == "" then
            return element[name]
        end

        return element[prefix .. name:sub(1, 1):upper() .. name:sub(2)]
    end

    local base = get_legacy_text_style(paragraph_style_id)
    local font_style = base.fontStyle
    local weight = value("fontWeight")
    local style = value("fontStyle")

    if weight or style then
        local bold, italic = font_style_axes(base.fontStyle)
        font_style = legacy_font_style(weight or (bold and "700" or "400"), style or (italic and "italic" or "normal"))
    end

    -- None of these fields can hold false, so `or` is the whole merge.
    return {
        alignment = normalize_alignment(value("alignment")) or base.alignment,
        fontFamily = value("fontFamily") or base.fontFamily,
        fontSize = value("fontSize") or base.fontSize,
        fontStyle = font_style,
        color = value("color") or base.color,
        textDecoration = value("textDecoration") or base.textDecoration,
    }
end

local function raw_font_feature(tag, value)
    if type(tag) ~= "string" or not string.match(tag, "^[%a%d][%a%d][%a%d][%a%d]$") then
        warn("Ignoring a font feature with an invalid OpenType tag")
        return nil
    end

    if type(value) ~= "number" or value % 1 ~= 0 or value < 0 or value > 65535 then
        warn("Ignoring font feature " .. tag .. " with an invalid value")
        return nil
    end

    if value == 0 then
        return "-" .. tag
    elseif value == 1 then
        return "+" .. tag
    else
        -- No "+" prefix: luaotfload reads "+tag=N" as XeTeX syntax, whose
        -- alternate indices are zero-based, and increments N. Our values are
        -- already one-based, so the bare "tag=N" form is the one that means
        -- what we intend.
        return string.format("%s=%d", tag, value)
    end
end

local function font_raw_features(style)
    local settings = style.fontFeatures or {}
    local features = {}

    if type(settings) ~= "table" then
        warn("Ignoring fontFeatures because it is not an object")
        return ""
    end

    for tag, value in pairs(settings) do
        local feature = raw_font_feature(tag, value)
        if feature then
            features[#features + 1] = { tag = tag, raw = feature }
        end
    end

    -- JSON object order is not significant. Sort by tag so equivalent feature
    -- maps always produce the same RawFeature string and font-selector key.
    table.sort(features, function(a, b)
        return a.tag < b.tag
    end)

    local raw_features = {}
    for _, feature in ipairs(features) do
        raw_features[#raw_features + 1] = feature.raw
    end

    return table.concat(raw_features, ",")
end

-- Control sequence names are letters only, so the serial is spelled in letters
-- and the reference is terminated with {} rather than a space, which would eat
-- a leading space in the content that follows.
local function font_macro_name(serial)
    local letters = ""

    repeat
        letters = string.char(97 + serial % 26) .. letters
        serial = math.floor(serial / 26)
    until serial == 0

    return "\\byzfont" .. letters
end

local function font_style_commands(style)
    local bold, italic = font_style_axes(style.fontStyle)

    if bold and italic then
        return "\\bfseries\\itshape"
    elseif bold then
        return "\\bfseries"
    elseif italic then
        return "\\itshape"
    end

    return ""
end

-- fontspec rebuilds a selector and re-parses its options on every \fontspec, at
-- a cost of roughly a millisecond, and a score references only a handful of
-- distinct family/face/feature combinations. Declare each one once per score
-- and let the elements reference it by name. The reference is cached on the
-- style, which is freshly parsed per score, so it cannot outlive the
-- declarations it names.
local function register_font_selector(style)
    if style.font_selector then
        return style.font_selector
    end

    local is_v3 = text_style_schema_version >= 3
    local declaration_command = is_v3 and "\\newfontface" or "\\newfontfamily"
    local font_name = is_v3 and style.postscriptName or style.fontFamily

    local raw_features = font_raw_features(style)
    local font_options = raw_features ~= "" and string.format("[RawFeature={%s}]", raw_features) or ""
    -- declaration_command distinguishes an exact face from a family, so it also
    -- keeps the two kinds of selector apart in the cache.
    local key = declaration_command .. "\0" .. font_options .. "\0" .. font_name
    local macro = font_selector_macros[key]

    if not macro then
        font_selector_serial = font_selector_serial + 1
        macro = font_macro_name(font_selector_serial)
        font_selector_macros[key] = macro
        font_selector_declarations[#font_selector_declarations + 1] = string.format("%s%s%s{%s}", declaration_command, macro, font_options, font_name)
    end

    style.font_selector = macro .. "{}" .. (not is_v3 and font_style_commands(style) or "")

    return style.font_selector
end

-- Print time. Every selector was registered by prepare_element_styles, before
-- include_score flushed the declarations, so a miss here means an element is
-- being printed that the pre-pass did not resolve. Say so, rather than emitting
-- a reference to a control sequence that was never declared.
local function font_selection(style)
    return assert(style.font_selector, "No font selector was registered for this text style")
end

local function decorate_content(result, style)
    if style.textDecoration == "underline" then
        result = string.format("\\underLine{%s}", result)
    end

    if style.strokeWidth and style.strokeWidth > 0 then
        local stroke_color = style.strokeColor
        if not stroke_color or stroke_color == "currentcolor" then
            stroke_color = style.color or "000000"
        end

        local stroke_color_option
        if string.match(stroke_color, "^%x%x%x%x%x%x$") then
            stroke_color_option = string.format("[HTML]{%s}", stroke_color)
        else
            stroke_color_option = stroke_color
        end

        result = string.format("\\textpdfrender{TextRenderingMode=FillStroke,LineWidth=%fbp,StrokeColor={%s}}{%s}", style.strokeWidth, stroke_color_option, result)
    end

    return result
end

local function styled_content(content, style)
    local result = decorate_content(escape_latex(content), style)

    return string.format("{%s%s}", font_selection(style), result)
end

local function style_color_command(style, command)
    return style.color and string.format("%s[HTML]{%s}", command, style.color) or command .. "{black}"
end

-- The size and leading always travel together, so every element emits them as
-- one fragment.
-- TODO: Implement paragraph-style lineHeight faithfully in NeanesTeX. Until
-- then, ignore it and use conventional text leading rather than the score-wide
-- \baselineskip, which represents the distance between staves.
local function style_font_setup(style)
    local size = style.fontSize
    assert(type(size) == "number", "Text style fontSize must be a number")

    return string.format("\\fontsize{%fbp}{%fbp}", size, size * 1.2)
end

-- The style an element renders in, or nil for one that prints no text. Classify
-- the element once, then adapt once: schema v3 looks up the complete style
-- Neanes selected for it, while v1 and v2 need the field prefix and built-in
-- style their sparse typography was spread across. Keeping this separate from
-- the traversal below means a new element type is one branch here rather than
-- another level of nesting.
local function resolve_element_style(element)
    local style_id, prefix, legacy_style_id

    if element.type == "note" and (element.lyrics or element.isFullMelisma) then
        style_id, prefix, legacy_style_id = element.lyricsStyleId, "lyrics", LYRICS_STYLE_ID
    elseif element.type == "dropcap" then
        style_id, prefix, legacy_style_id = element.styleId, "", DROP_CAP_STYLE_ID
    elseif element.type == "textbox" and element.inline then
        style_id, prefix, legacy_style_id = element.styleId, "", LYRICS_STYLE_ID
    elseif element.type == "textbox" and (element.content ~= "" or element.multipanel) then
        style_id, prefix, legacy_style_id = element.styleId, "", DEFAULT_TEXT_STYLE_ID
    else
        return nil
    end

    if text_style_schema_version < 3 then
        return legacy_element_style(element, prefix, legacy_style_id)
    end

    return assert(text_style_definitions[style_id], "Unknown schema v3 text style id: " .. tostring(style_id))
end

-- Resolve every styled element once, before anything is printed, and cache the
-- result on the element. This is what lets the score declare its font families
-- up front, and it keeps the schema-version adaptation in one pass instead of
-- one branch per element type at print time. Elements that print nothing are
-- skipped so a score never declares a font it does not use.
local function prepare_element_styles(sections)
    font_selector_macros = {}
    font_selector_declarations = {}

    for _, section in ipairs(sections) do
        for _, line in ipairs(section.lines) do
            for _, element in ipairs(line.elements) do
                local style = resolve_element_style(element)

                if style then
                    element.resolved_style = style
                    -- The declaration itself is emitted by include_score.
                    register_font_selector(style)
                end
            end
        end
    end
end

local function measure_bar_text(glyph_name, manual_offset)
    local result = string.format('\\textcolor{byzcolormeasurebar}{\\char"%s}', glyphNameToCodepointMap[glyph_name])

    if manual_offset and manual_offset.y ~= 0 then
        return string.format("\\raisebox{-%fem}{%s}", manual_offset.y, result)
    end

    return result
end

local function print_measure_bar(glyph_name, offset, spacing_before, spacing_after, manual_offset)
    offset = offset or 0
    spacing_before = spacing_before or 0
    spacing_after = spacing_after or 0
    local manual_x = manual_offset and manual_offset.x or 0

    if spacing_before ~= 0 then
        tex.sprint(string.format("\\hspace{%fbp}", spacing_before))
    end

    if offset ~= 0 then
        tex.sprint(string.format("\\hspace{%fbp}", offset))
    end

    if manual_x ~= 0 then
        tex.sprint(string.format("\\hspace{%fem}", manual_x))
    end

    tex.sprint(measure_bar_text(glyph_name, manual_offset))

    if manual_x ~= 0 then
        tex.sprint(string.format("\\hspace{-%fem}", manual_x))
    end

    if offset ~= 0 then
        tex.sprint(string.format("\\hspace{%fbp}", -offset))
    end

    if spacing_after ~= 0 then
        tex.sprint(string.format("\\hspace{%fbp}", spacing_after))
    end
end

local function print_transferred_measure_bar(glyph_name, offset, spacing_before, manual_offset)
    local position = (offset or 0) + (spacing_before or 0)
    local manual_x = manual_offset and manual_offset.x or 0

    tex.sprint(string.format("\\rlap{\\hspace{%fbp}{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont\\hspace{%fem}%s}}", position, manual_x, measure_bar_text(glyph_name, manual_offset)))
end

local function print_leading_lyric_hyphen(note, pageSetup)
    if note.leadingLyricHyphenOffset == nil then
        return
    end

    local style = note.resolved_style
    local color = style_color_command(style, "\\textcolor")
    local hyphen = styled_content("-", style)
    local offset_from_cursor = note.leadingLyricHyphenOffset - note.width

    tex.sprint(string.format("\\rlap{\\hspace{%fbp}\\raisebox{-%fbp}{%s{%s%s}}}", offset_from_cursor, pageSetup.lyricsVerticalOffset, color, style_font_setup(style), hyphen))
end

local function print_note(note, pageSetup)
    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", note.x))
    tex.sprint(string.format("\\makebox[%fbp]{\\textcolor{byzcolorneume}{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont", note.width))

    if note.measureBarLeft and not string.match(note.measureBarLeft, "Above$") then
        print_measure_bar(note.measureBarLeft, note.computedMeasureBarLeftOffsetX, 0, note.computedMeasureBarLeftLeadingSpacing, note.measureBarLeftOffset)
    end

    if note.vareia then
        local offset_x = note.vareiaOffset and note.vareiaOffset.x or 0
        local offset_y = note.vareiaOffset and note.vareiaOffset.y or 0

        if offset_x ~= 0 then
            tex.sprint(string.format("\\hspace{%fem}", offset_x))
        end

        if offset_y ~= 0 then
            tex.sprint(string.format('\\raisebox{-%fem}{\\char"%s}', offset_y, glyphNameToCodepointMap["vareia"]))
        else
            tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap["vareia"]))
        end

        if offset_x ~= 0 then
            tex.sprint(string.format("\\hspace{-%fem}", offset_x))
        end

        if note.vareiaInternalSpacing then
            tex.sprint(string.format("\\hspace{%fbp}", note.vareiaInternalSpacing))
        end
    end

    -- If the user specified an additional offset, we must manually position the marks
    if note.timeOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.time, note.timeOffset)
        tex.sprint(string.format('\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.time], offset.x))
    end

    if note.gorgonOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.gorgon, note.gorgonOffset)
        tex.sprint(string.format('\\textcolor{byzcolorgorgon}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.gorgon], offset.x))
    end

    if note.gorgonSecondaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.gorgonSecondary, note.gorgonSecondaryOffset)
        tex.sprint(string.format('\\textcolor{byzcolorgorgon}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.gorgonSecondary], offset.x))
    end

    if note.fthoraOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.fthora, note.fthoraOffset)
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.fthora], offset.x))
    end

    if note.fthoraSecondaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.fthoraSecondary, note.fthoraSecondaryOffset)
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.fthoraSecondary], offset.x))
    end

    if note.fthoraTertiaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.fthoraTertiary, note.fthoraTertiaryOffset)
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.fthoraTertiary], offset.x))
    end

    if note.accidentalOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.accidental, note.accidentalOffset)
        tex.sprint(string.format('\\textcolor{byzcoloraccidental}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.accidental], offset.x))
    end

    if note.accidentalSecondaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.accidentalSecondary, note.accidentalSecondaryOffset)
        tex.sprint(string.format('\\textcolor{byzcoloraccidental}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.accidentalSecondary], offset.x))
    end

    if note.accidentalTertiaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.accidentalTertiary, note.accidentalTertiaryOffset)
        tex.sprint(string.format('\\textcolor{byzcoloraccidental}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.accidentalTertiary], offset.x))
    end

    local manually_position_indicators = note.noteIndicatorOffset or note.isonOffset

    if manually_position_indicators and note.noteIndicator then
        local offset = get_mark_offset(note.quantitativeNeume, note.noteIndicator, note.noteIndicatorOffset)
        tex.sprint(string.format('\\textcolor{byzcolornoteindicator}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.noteIndicator], offset.x))
    end

    if manually_position_indicators and note.ison then
        local offset = get_mark_offset(note.quantitativeNeume, note.ison, note.isonOffset)
        tex.sprint(string.format('\\textcolor{byzcolorison}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.ison], offset.x))
    end

    if note.koronisOffset then
        local offset = get_mark_offset(note.quantitativeNeume, "koronis", note.koronisOffset)
        tex.sprint(string.format('\\textcolor{byzcolorkoronis}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap["koronis"], offset.x))
    end

    if note.measureNumberOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.measureNumber, note.measureNumberOffset)
        tex.sprint(string.format('\\textcolor{byzcolormeasurenumber}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.measureNumber], offset.x))
    end

    if note.tieOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.tie, note.tieOffset)
        tex.sprint(string.format('\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.tie], offset.x))
    end

    if note.stavrosOffset then
        local offset = get_mark_offset(note.quantitativeNeume, "stavrosAbove", note.stavrosOffset)
        tex.sprint(string.format('\\textcolor{byzcolorcross}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap["stavrosAbove"], offset.x))
    end

    if note.measureBarLeft and string.match(note.measureBarLeft, "Above$") and note.measureBarLeftOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.measureBarLeft, note.measureBarLeftOffset)
        tex.sprint(string.format('\\textcolor{byzcolormeasurebar}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.measureBarLeft], offset.x))
    end

    -- Print the main neume
    if note.quantitativeNeume == "breath" then
        tex.sprint(string.format('\\textcolor{byzcolorbreath}{\\char"%s}', glyphNameToCodepointMap[note.quantitativeNeume]))
    elseif note.quantitativeNeume == "stavros" then
        tex.sprint(string.format('\\textcolor{byzcolorcross}{\\char"%s}', glyphNameToCodepointMap[note.quantitativeNeume]))
    else
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.quantitativeNeume]))
    end

    if note.stavros and not note.stavrosOffset then
        tex.sprint(string.format('\\textcolor{byzcolorcross}{\\char"%s}', glyphNameToCodepointMap["stavrosAbove"]))
    end

    if note.vocalExpression then
        local vocal_expression_base = string.match(note.vocalExpression, "^[^.]+")
        if vocal_expression_base == "heteron" or vocal_expression_base == "heteronConnecting" or vocal_expression_base == "endofonon" then
            tex.sprint(string.format('\\textcolor{byzcolorheteron}{\\char"%s}', glyphNameToCodepointMap[note.vocalExpression]))
        else
            tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.vocalExpression]))
        end
    end

    -- If the user did not specify an additional offset, latex+luacolor will position the marks correctly
    if note.time and not note.timeOffset then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.time]))
    end

    if note.gorgon and not note.gorgonOffset then
        tex.sprint(string.format('\\textcolor{byzcolorgorgon}{\\char"%s}', glyphNameToCodepointMap[note.gorgon]))
    end

    if note.gorgonSecondary and not note.gorgonSecondaryOffset then
        tex.sprint(string.format('\\textcolor{byzcolorgorgon}{\\char"%s}', glyphNameToCodepointMap[note.gorgonSecondary]))
    end

    if note.fthora and not note.fthoraOffset then
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\char"%s}', glyphNameToCodepointMap[note.fthora]))
    end

    if note.fthoraSecondary and not note.fthoraSecondaryOffset then
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\char"%s}', glyphNameToCodepointMap[note.fthoraSecondary]))
    end

    if note.fthoraTertiary and not note.fthoraTertiaryOffset then
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\char"%s}', glyphNameToCodepointMap[note.fthoraTertiary]))
    end

    if note.accidental and not note.accidentalOffset then
        tex.sprint(string.format('\\textcolor{byzcoloraccidental}{\\char"%s}', glyphNameToCodepointMap[note.accidental]))
    end

    if note.accidentalSecondary and not note.accidentalSecondaryOffset then
        tex.sprint(string.format('\\textcolor{byzcoloraccidental}{\\char"%s}', glyphNameToCodepointMap[note.accidentalSecondary]))
    end

    if note.accidentalTertiary and not note.accidentalTertiaryOffset then
        tex.sprint(string.format('\\textcolor{byzcoloraccidental}{\\char"%s}', glyphNameToCodepointMap[note.accidentalTertiary]))
    end

    if note.noteIndicator and not manually_position_indicators then
        tex.sprint(string.format('\\textcolor{byzcolornoteindicator}{\\char"%s}', glyphNameToCodepointMap[note.noteIndicator]))
    end

    if note.ison and not manually_position_indicators then
        tex.sprint(string.format('\\textcolor{byzcolorison}{\\char"%s}', glyphNameToCodepointMap[note.ison]))
    end

    if note.koronis and not note.koronisOffset then
        tex.sprint(string.format('\\textcolor{byzcolorkoronis}{\\char"%s}', glyphNameToCodepointMap["koronis"]))
    end

    if note.measureNumber and not note.measureNumberOffset then
        tex.sprint(string.format('\\textcolor{byzcolormeasurenumber}{\\char"%s}', glyphNameToCodepointMap[note.measureNumber]))
    end

    if note.measureBarLeft and string.match(note.measureBarLeft, "Above$") and not note.measureBarLeftOffset then
        tex.sprint(measure_bar_text(note.measureBarLeft))
    end

    if note.tie and not note.tieOffset then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.tie]))
    end

    -- Right measure bar is last
    if note.measureBarRight and not note.measureBarRightIsTransferred then
        print_measure_bar(note.measureBarRight, note.computedMeasureBarRightOffsetX, note.computedMeasureBarRightTrailingSpacing, 0, note.measureBarRightOffset)
    end

    -- close \textcolor{} and \makebox{}
    tex.sprint("}}")

    -- Neanes positions a transferred right measure bar absolutely at the end
    -- of the note box, so it must not affect the box width or lyric centering.
    if note.measureBarRight and note.measureBarRightIsTransferred then
        print_transferred_measure_bar(note.measureBarRight, note.computedMeasureBarRightOffsetX, note.computedMeasureBarRightTrailingSpacing, note.measureBarRightOffset)
    end

    print_leading_lyric_hyphen(note, pageSetup)

    if note.lyrics then
        local lyricPos = note.lyricsLeftAlign and "l" or "c"
        local style = note.resolved_style
        local color = style_color_command(style, "\\textcolor")
        local lyrics = decorate_content(escape_latex(note.lyrics), style)

        local offset = 0

        if note.lyricsHorizontalOffset then
            offset = note.lyricsHorizontalOffset
        end

        tex.sprint(string.format("\\hspace{-%fbp}", note.width - offset))
        tex.sprint(string.format("\\raisebox{-%fbp}{%s{\\makebox[%fbp][%s]{%s%s%s", pageSetup.lyricsVerticalOffset, color, note.width - offset, lyricPos, style_font_setup(style), font_selection(style), lyrics))

        -- Melismas
        if note.melismaWidth and note.melismaWidth > 0 then
            if note.isHyphen then
                for _, hyphenOffset in ipairs(note.hyphenOffsets) do
                    tex.sprint(string.format("\\hspace{%fbp}\\rlap{-}\\hspace{-%fbp}", hyphenOffset, hyphenOffset))
                end
            else
                tex.sprint(string.format("\\hspace{%fbp}\\rule{%fbp}{%fbp}\\hspace{-%fbp}", pageSetup.lyricsMelismaSpacing, note.melismaWidth - pageSetup.lyricsMelismaSpacing, pageSetup.lyricsMelismaThickness, note.melismaWidth))
            end
        end

        -- close \raisebox{\makebox{\textcolor{}}}
        tex.sprint("}}}")
    elseif note.isFullMelisma then
        local style = note.resolved_style
        tex.sprint(string.format("\\hspace{-%fbp}", note.width))
        tex.sprint(string.format("\\raisebox{-%fbp}{%s{\\makebox[%fbp][l]{%s%s", pageSetup.lyricsVerticalOffset, style_color_command(style, "\\textcolor"), note.width, style_font_setup(style), font_selection(style)))

        if note.isHyphen then
            for _, hyphenOffset in ipairs(note.hyphenOffsets) do
                tex.sprint(string.format("\\hspace{%fbp}\\rlap{-}\\hspace{-%fbp}", hyphenOffset, hyphenOffset))
            end
        else
            tex.sprint(string.format("\\rule{%fbp}{%fbp}\\hspace{-%fbp}", note.melismaWidth, pageSetup.lyricsMelismaThickness, note.melismaWidth))
        end

        -- close \raisebox{\textcolor{\makebox{}}}
        tex.sprint("}}}")
    end

    tex.sprint(string.format("\\hspace{-%fbp}", note.width))
    tex.sprint(string.format("\\hspace{%fbp}", -note.x))

    -- close \mbox{}
    tex.sprint("}")
end

local function print_martyria(martyria, pageSetup)
    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", martyria.x))

    local verticalOffset = (pageSetup.martyriaVerticalOffset or 0) + (martyria.verticalOffset or 0)

    if verticalOffset ~= 0 then
        tex.sprint(string.format("\\raisebox{-%fbp}{", verticalOffset))
    end

    tex.sprint(string.format("\\textcolor{byzcolormartyria}{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont"))

    if martyria.measureBarLeft and not string.match(martyria.measureBarLeft, "Above$") then
        print_measure_bar(martyria.measureBarLeft, martyria.computedMeasureBarLeftOffsetX, 0, martyria.computedMeasureBarLeftLeadingSpacing)
    end

    if martyria.tempoLeft then
        local offset = martyria.tempoLeftOffsetX or 0

        if offset ~= 0 then
            tex.sprint(string.format("\\hspace{%fbp}", offset))
        end

        tex.sprint(string.format('\\textcolor{byzcolortempo}{\\char"%s}', glyphNameToCodepointMap[martyria.tempoLeft]))

        if offset ~= 0 then
            tex.sprint(string.format("\\hspace{-%fbp}", offset))
        end

        if martyria.tempoLeftSpacing then
            tex.sprint(string.format("\\hspace{%fbp}", martyria.tempoLeftSpacing))
        end
    end

    tex.sprint(string.format('\\char"%s\\char"%s', glyphNameToCodepointMap[martyria.note], glyphNameToCodepointMap[martyria.rootSign]))

    if martyria.fthora then
        tex.sprint(string.format('\\textcolor{byzcolorfthora}{\\char"%s}', glyphNameToCodepointMap[martyria.fthora]))
    end

    if martyria.tempo then
        tex.sprint(string.format('\\textcolor{byzcolortempo}{\\char"%s}', glyphNameToCodepointMap[martyria.tempo]))
    end

    if martyria.measureBarLeft and string.match(martyria.measureBarLeft, "Above$") then
        print_measure_bar(martyria.measureBarLeft, martyria.computedMeasureBarLeftOffsetX, 0, martyria.computedMeasureBarLeftLeadingSpacing)
    end

    if martyria.quantitativeNeume then
        if martyria.quantitativeNeumeSpacing then
            tex.sprint(string.format("\\hspace{%fbp}", martyria.quantitativeNeumeSpacing))
        end

        tex.sprint(string.format('\\textcolor{byzcolorneume}{\\char"%s}', glyphNameToCodepointMap[martyria.quantitativeNeume]))
    end

    if martyria.tempoRight then
        if martyria.tempoRightSpacing then
            tex.sprint(string.format("\\hspace{%fbp}", martyria.tempoRightSpacing))
        end

        tex.sprint(string.format('\\textcolor{byzcolortempo}{\\char"%s}', glyphNameToCodepointMap[martyria.tempoRight]))
    end

    if martyria.measureBarRight then
        print_measure_bar(martyria.measureBarRight, martyria.computedMeasureBarRightOffsetX, martyria.computedMeasureBarRightTrailingSpacing, 0)
    end

    tex.sprint("}")

    if verticalOffset ~= 0 then
        -- Close \raisebox
        tex.sprint("}")
    end

    tex.sprint(string.format("\\hspace{-%fbp}", martyria.width))
    tex.sprint(string.format("\\hspace{%fbp}", -martyria.x))
    tex.sprint("}")
end

local function print_tempo(tempo, pageSetup)
    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", tempo.x))
    tex.sprint(string.format("\\textcolor{byzcolortempo}{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont"))

    tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[tempo.neume]))

    -- end \textcolor
    tex.sprint("}")
    tex.sprint(string.format("\\hspace{-%fbp}", tempo.width))
    tex.sprint(string.format("\\hspace{%fbp}", -tempo.x))
    -- end \mbox
    tex.sprint("}")
end

local function print_drop_cap(dropCap, pageSetup)
    local style = dropCap.resolved_style
    local color = style_color_command(style, "\\textcolor")
    local content = styled_content(dropCap.content, style)

    local verticalAdjustment = dropCap.verticalAdjustment and dropCap.verticalAdjustment or 0

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", dropCap.x))
    tex.sprint(string.format("\\raisebox{-%fbp}{{%s{%s%s}}}", pageSetup.lyricsVerticalOffset + verticalAdjustment, color, style_font_setup(style), content))
    tex.sprint(string.format("\\hspace{-%fbp}", dropCap.width))
    tex.sprint(string.format("\\hspace{%fbp}", -dropCap.x))
    tex.sprint("}")
end

local function print_mode_key(modeKey, pageSetup)
    local font_size = modeKey.fontSize and string.format("%fbp", modeKey.fontSize) or "\\byzmodekeysize"
    local color = modeKey.color and string.format("\\textcolor[HTML]{%s}", modeKey.color) or "\\textcolor{byzcolormodekey}"

    if modeKey.marginTop then
        tex.sprint(string.format("\\vspace{-\\baselineskip}", modeKey.marginTop))
        tex.sprint(string.format("\\vspace{%fbp}", modeKey.marginTop))
        tex.sprint("\\newline")
    end

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\makebox[%fbp][%s]{", modeKey.width, alignment_position(normalize_alignment(modeKey.alignment))))
    tex.sprint(string.format("%s{\\fontsize{%s}{\\baselineskip}\\byzneumefont", color, font_size))

    tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap["modeWordEchos"]))
    if modeKey.isPlagal then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap["modePlagal"]))
    end
    if modeKey.isVarys then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap["modeWordVarys"]))
    end
    tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.martyria]))
    if modeKey.note then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.note]))
    end
    if modeKey.fthoraAboveNote then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.fthoraAboveNote]))
    end
    if modeKey.quantitativeNeumeAboveNote then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.quantitativeNeumeAboveNote]))
    end
    if modeKey.note2 then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.note2]))
    end
    if modeKey.fthoraAboveNote2 then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.fthoraAboveNote2]))
    end
    if modeKey.quantitativeNeumeAboveNote2 then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.quantitativeNeumeAboveNote2]))
    end
    if modeKey.quantitativeNeumeRight then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.quantitativeNeumeRight]))
    end
    if modeKey.fthoraAboveQuantitativeNeumeRight then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[modeKey.fthoraAboveQuantitativeNeumeRight]))
    end
    if modeKey.tempo and not modeKey.tempoAlignRight then
        tex.sprint(string.format('\\hspace{6bp}\\raisebox{0.45em}{\\textcolor{byzcolortempo}{\\char"%s}}', glyphNameToCodepointMap[modeKey.tempo]))
    end

    -- end \textcolor and \makebox
    tex.sprint("}}")
    tex.sprint(string.format("\\hspace{-%fbp}", modeKey.width))

    if (modeKey.tempo and modeKey.tempoAlignRight) or modeKey.showAmbitus then
        tex.sprint(string.format("\\makebox[%fbp][r]{", modeKey.width))
        tex.sprint(string.format("%s{\\fontsize{%s}{\\baselineskip}\\byzneumefont", color, font_size))

        if modeKey.showAmbitus then
            tex.sprint(
                string.format(
                    '\\raisebox{3bp}{{\\sffamily{}(}\\raisebox{0.45em}{\\textcolor{byzcolormartyria}{\\char"%s\\char"%s}}\\hspace{7.5bp}{\\sffamily{}-}\\hspace{1.5bp}\\raisebox{0.45em}{\\textcolor{byzcolormartyria}{\\char"%s\\char"%s}}\\hspace{3bp}{\\sffamily{})}}',
                    glyphNameToCodepointMap[modeKey.ambitusLowNote],
                    glyphNameToCodepointMap[modeKey.ambitusLowRootSign],
                    glyphNameToCodepointMap[modeKey.ambitusHighNote],
                    glyphNameToCodepointMap[modeKey.ambitusHighRootSign]
                )
            )

            if modeKey.tempo and modeKey.tempoAlignRight then
                tex.sprint("\\hspace{6bp}")
            end
        end

        if modeKey.tempo and modeKey.tempoAlignRight then
            tex.sprint(string.format('\\raisebox{0.45em}{\\textcolor{byzcolortempo}{\\char"%s}}', glyphNameToCodepointMap[modeKey.tempo]))
        end

        -- end \textcolor and \makebox
        tex.sprint("}}")

        tex.sprint(string.format("\\hspace{-%fbp}", modeKey.width))
    end

    -- end \mbox
    tex.sprint("}")

    local height = modeKey.height

    if modeKey.marginBottom then
        height = height + modeKey.marginBottom
    end

    tex.sprint(string.format("\\vspace{-\\baselineskip}\\vspace{%fbp}", height))
end

local function print_text_box_inline(textBox)
    local style = textBox.resolved_style
    local color = style_color_command(style, "\\textcolor")
    local position = alignment_position(style.alignment)
    local content = styled_content(textBox.content, style)
    if textBox.contentBottom and textBox.contentBottom ~= "" then
        content = string.format("\\shortstack[%s]{%s\\\\%s}", position, content, styled_content(textBox.contentBottom, style))
    end

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", textBox.x))
    tex.sprint(string.format("\\makebox[%fbp][%s]{", textBox.width, position))
    tex.sprint(string.format("%s{%s%s", color, style_font_setup(style), content))

    -- end \textcolor and \makebox
    tex.sprint("}}")
    tex.sprint(string.format("\\hspace{-%fbp}", textBox.width))
    tex.sprint(string.format("\\hspace{%fbp}", -textBox.x))

    -- end \mbox
    tex.sprint("}")
end

local function print_text_box(textBox)
    if textBox.inline then
        print_text_box_inline(textBox)
        return
    end

    -- An empty, non-multipanel text box prints nothing, which is exactly the
    -- case resolve_element_style leaves unstyled. Ask it rather than restating
    -- the condition, so the two cannot drift apart.
    local style = textBox.resolved_style

    if not style then
        tex.sprint("\\vspace{-\\baselineskip}")
        tex.sprint(string.format("\\vspace{%fbp}", textBox.height))
        return
    end

    local color = style_color_command(style, "\\color")
    local content

    if textBox.multipanel then
        content = string.format(
            "\\makebox[\\linewidth][l]{%s}\\hspace{-\\linewidth}\\makebox[\\linewidth][c]{%s}\\hspace{-\\linewidth}\\makebox[\\linewidth][r]{%s}",
            styled_content(textBox.contentLeft or "", style),
            styled_content(textBox.contentCenter or "", style),
            styled_content(textBox.contentRight or "", style)
        )
    else
        content = styled_content(textBox.content, style)
    end

    if textBox.marginTop then
        tex.sprint("\\vspace{-\\baselineskip}")
        tex.sprint(string.format("\\vspace{%fbp}", textBox.marginTop))
        tex.sprint("\\newline")
    end

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", textBox.x))
    tex.sprint(string.format("\\parbox[b][%fbp][c]{%fbp}{", textBox.height, textBox.width))

    if style.alignment == "center" then
        tex.sprint("\\centering")
    elseif style.alignment == "right" then
        tex.sprint("\\raggedleft")
    elseif style.alignment == "left" then
        tex.sprint("\\raggedright")
    end

    tex.sprint(string.format("%s{%s%s", color, style_font_setup(style), content))

    -- end \textcolor and \parbox
    tex.sprint("}}")
    tex.sprint(string.format("\\hspace{-%fbp}", textBox.width))

    -- end \mbox
    tex.sprint("}")

    local height = textBox.height

    if textBox.marginBottom then
        height = height + textBox.marginBottom
    end

    tex.sprint(string.format("\\vspace{-\\baselineskip}\\vspace{%fbp}", height))
end

local function include_score(filename, sectionName)
    local data = json.tolua(read_json(filename))

    if data == nil then
        error("Score file could not be parsed because the JSON is invalid. Is there a typo? Filename: " .. filename)
    end

    if schema_version < data.schemaVersion then
        warn(string.format("The score %s uses schema version %d. This version of neanestex only supports schema versions <= %d", filename, data.schemaVersion, schema_version))
    end

    load_text_styles(data)

    -- Find the section(s)
    local sections = {}

    if sectionName == "*" then
        sections = data.sections
    else
        local section = nil

        for _, s in ipairs(data.sections) do
            if (sectionName == "" and s.default) or s.name == sectionName then
                section = s
                break
            end
        end

        if section == nil and sectionName == nil then
            err("Could not find default section")
        end

        if section == nil then
            err("Could not find section " .. sectionName)
        end

        sections[1] = section
    end

    prepare_element_styles(sections)

    -- Load the font metadata
    local neume_font_data = get_neume_font_data(data.pageSetup.fontFamilies.neume)
    glyphNameToCodepointMap = neume_font_data.glyph_name_to_codepoint_map
    font_metadata = neume_font_data.font_metadata

    -- Check that the metadata version matches the score's font version
    local metadata_font_version = font_metadata.fontVersion
    local score_font_version = data.fontVersions[data.pageSetup.fontFamilies.neume]

    if metadata_font_version and score_font_version and metadata_font_version ~= score_font_version then
        warn(string.format("The font version in the metadata (%s) does not match the font version in the score (%s)", metadata_font_version, score_font_version))
    end

    -- Check that the OTF file version matches the score's font version
    local otf_font_file = neume_font_file_map[data.pageSetup.fontFamilies.neume]

    if otf_font_file then
        local otf_font_data = fontloader.open(neume_font_file_map[data.pageSetup.fontFamilies.neume])

        if otf_font_data and score_font_version then
            if otf_font_data.version and otf_font_data.version ~= score_font_version then
                warn(string.format("The font version (%s) does not match the font version in the score (%s)", otf_font_data.version, score_font_version))
            end
            fontloader.close(otf_font_data)
        end
    end

    -- open a new section so that our variables do not persist forever
    tex.sprint("{")

    for _, declaration in ipairs(font_selector_declarations) do
        tex.sprint(declaration)
    end

    tex.sprint(string.format("\\setlength{\\byzneumesize}{%fbp}", data.pageSetup.fontSizes.neume))
    tex.sprint(string.format("\\setlength{\\byzmodekeysize}{%fbp}", data.pageSetup.fontSizes.modeKey))

    tex.sprint(string.format("\\renewfontfamily{\\byzneumefont}{%s}", get_neume_font(data.pageSetup.fontFamilies.neume)))

    tex.sprint(string.format("\\setlength{\\baselineskip}{%fbp}", data.pageSetup.lineHeight))

    tex.sprint(string.format("\\definecolor{byzcoloraccidental}{HTML}{%s}", data.pageSetup.colors.accidental))
    tex.sprint(string.format("\\definecolor{byzcolorbreath}{HTML}{%s}", data.pageSetup.colors.breath or data.pageSetup.colors.neume))
    tex.sprint(string.format("\\definecolor{byzcolorcross}{HTML}{%s}", data.pageSetup.colors.cross or data.pageSetup.colors.neume))
    tex.sprint(string.format("\\definecolor{byzcolorfthora}{HTML}{%s}", data.pageSetup.colors.fthora))
    tex.sprint(string.format("\\definecolor{byzcolorgorgon}{HTML}{%s}", data.pageSetup.colors.gorgon))
    tex.sprint(string.format("\\definecolor{byzcolorheteron}{HTML}{%s}", data.pageSetup.colors.heteron))
    tex.sprint(string.format("\\definecolor{byzcolorison}{HTML}{%s}", data.pageSetup.colors.ison))
    tex.sprint(string.format("\\definecolor{byzcolorkoronis}{HTML}{%s}", data.pageSetup.colors.koronis))
    tex.sprint(string.format("\\definecolor{byzcolormartyria}{HTML}{%s}", data.pageSetup.colors.martyria))
    tex.sprint(string.format("\\definecolor{byzcolormeasurebar}{HTML}{%s}", data.pageSetup.colors.measureBar))
    tex.sprint(string.format("\\definecolor{byzcolormeasurenumber}{HTML}{%s}", data.pageSetup.colors.measureNumber))
    tex.sprint(string.format("\\definecolor{byzcolormodekey}{HTML}{%s}", data.pageSetup.colors.modeKey))
    tex.sprint(string.format("\\definecolor{byzcolorneume}{HTML}{%s}", data.pageSetup.colors.neume))
    tex.sprint(string.format("\\definecolor{byzcolornoteindicator}{HTML}{%s}", data.pageSetup.colors.noteIndicator))
    tex.sprint(string.format("\\definecolor{byzcolortempo}{HTML}{%s}", data.pageSetup.colors.tempo))

    first_line = true

    for section_index, section in ipairs(sections) do
        for line_index, line in ipairs(section.lines) do
            if #line.elements > 0 and not first_line then
                tex.sprint("\\newline")
            else
                first_line = false
            end

            if #line.elements > 0 then
                tex.sprint("\\noindent")
            end
            for _, element in ipairs(line.elements) do
                if element.type == "note" then
                    print_note(element, data.pageSetup)
                end
                if element.type == "martyria" then
                    print_martyria(element, data.pageSetup)
                end
                if element.type == "tempo" then
                    print_tempo(element, data.pageSetup)
                end
                if element.type == "dropcap" then
                    print_drop_cap(element, data.pageSetup)
                end
                if element.type == "modekey" then
                    print_mode_key(element, data.pageSetup)
                end
                if element.type == "textbox" then
                    print_text_box(element)
                end
            end
        end
    end

    tex.sprint("\\par")
    -- close the section
    tex.sprint("}")
end

neanestex.include_score = include_score
neanestex.codepoint_from_glyph_name = codepoint_from_glyph_name
neanestex.set_neume_font_family = set_neume_font_family
neanestex.set_neume_font_file = set_neume_font_file
neanestex.set_neume_font_metadata_file = set_neume_font_metadata_file
