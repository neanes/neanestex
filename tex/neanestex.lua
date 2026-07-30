neanestex = neanestex or {}
local neanestex = neanestex

local err, warn, info, log = luatexbase.provides_module({
    name = "neanestex",
    date = "2025/02/27",
    version = "1.0.0",
    description = "A package for inserting Byzantine Chant scores into LaTeX.",
    author = "danielgarthur",
    license = "GPL-3.0",
})

local schema_version = 2
-- Schema changes
-- 1 to 2: Positive lyricsVerticalOffset now moves lyrics down, making it consistent with other offsets in the schema

local lualibs = require("lualibs")
local json = utilities.json
local glyphNameToCodepointMap = {}
local font_metadata = nil
local neume_font_data_map = {}
local neume_font_family = nil
local neume_font_file_map = {}
local neume_font_metadata_file_map = {}
local neume_font_metadata_file_map_default = {
    ["Neanes"] = "neanes.metadata.json",
    ["NeanesRTL"] = "neanesrtl.metadata.json",
    ["NeanesStathisSeries"] = "neanesstathisseries.metadata.json",
}

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

local function set_neume_font_family(font_family)
    neume_font_family = font_family

    if neume_font_data_map[neume_font_family] == nil then
        neume_font_data_map[neume_font_family] = load_font_data(neume_font_family)
    end
end

local function set_neume_font_file(font_family, filepath)
    neume_font_file_map[font_family] = filepath
end

local function set_neume_font_metadata_file(font_family, filepath)
    neume_font_metadata_file_map[font_family] = filepath
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
    local data = neume_font_data_map[neume_font_family]

    if data == nil then
        err("Font data has not been loaded yet. Did you forget to call \\byzsetneumefont?")
    end

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

local function print_note(note, pageSetup)
    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", note.x))
    tex.sprint(string.format("\\makebox[%fbp]{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont", note.width))

    if note.measureBarLeft then
        tex.sprint(string.format('\\textcolor{byzcolormeasurebar}{\\char"%s}', glyphNameToCodepointMap[note.measureBarLeft]))
    end

    if note.vareia then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap["vareia"]))
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

    if note.isonOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.ison, note.isonOffset)
        tex.sprint(string.format('\\textcolor{byzcolorison}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.ison], offset.x))
    end

    if note.noteIndicatorOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.noteIndicator, note.noteIndicatorOffset)
        tex.sprint(string.format('\\textcolor{byzcolornoteindicator}{\\hspace{%fem}\\raisebox{-%fem}{\\char"%s}}\\hspace{-%fem}', offset.x, offset.y, glyphNameToCodepointMap[note.noteIndicator], offset.x))
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

    -- Print the main neume
    tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.quantitativeNeume]))

    if note.vocalExpression then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.vocalExpression]))
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

    if note.ison and not note.isonOffset then
        tex.sprint(string.format('\\textcolor{byzcolorison}{\\char"%s}', glyphNameToCodepointMap[note.ison]))
    end

    if note.noteIndicator and not note.noteIndicatorOffset then
        tex.sprint(string.format('\\textcolor{byzcolornoteindicator}{\\char"%s}', glyphNameToCodepointMap[note.noteIndicator]))
    end

    if note.koronis and not note.koronisOffset then
        tex.sprint(string.format('\\textcolor{byzcolorkoronis}{\\char"%s}', glyphNameToCodepointMap["koronis"]))
    end

    if note.measureNumber and not note.measureNumberOffset then
        tex.sprint(string.format('\\textcolor{byzcolormeasurenumber}{\\char"%s}', glyphNameToCodepointMap[note.measureNumber]))
    end

    if note.tie and not note.tieOffset then
        tex.sprint(string.format('\\char"%s', glyphNameToCodepointMap[note.tie]))
    end

    -- Right measure bar is last
    if note.measureBarRight then
        tex.sprint(string.format('\\textcolor{byzcolormeasurebar}{\\char"%s}', glyphNameToCodepointMap[note.measureBarRight]))
    end

    -- close \makebox{}
    tex.sprint("}")

    if note.lyrics then
        local lyricPos = note.lyricsLeftAlign and "l" or "c"
        local fontSize = note.lyricsFontSize and string.format("%fbp", note.lyricsFontSize) or "\\byzlyricsize"
        local color = note.lyricsColor and string.format("\\textcolor[HTML]{%s}", note.lyricsColor) or "\\textcolor{byzcolorlyrics}"
        local is_bold = note.lyricsFontWeight == "700" or pageSetup.lyricsDefaultFontWeight == "700"
        local is_italic = note.lyricsFontStyle == "italic" or pageSetup.lyricsDefaultFontStyle == "italic"
        local lyrics = escape_latex(note.lyrics)
        lyrics = is_italic and string.format("\\textit{%s}", lyrics) or lyrics
        lyrics = is_bold and string.format("\\textbf{%s}", lyrics) or lyrics
        lyrics = note.lyricsFontFamily and string.format("{\\fontspec{%s}%s}", note.lyricsFontFamily, lyrics) or string.format("\\byzlyricfont{}{%s}", lyrics)

        local offset = 0

        if note.lyricsHorizontalOffset then
            offset = note.lyricsHorizontalOffset
        end

        tex.sprint(string.format("\\hspace{-%fbp}", note.width - offset))
        tex.sprint(string.format("\\raisebox{-%fbp}{%s{\\makebox[%fbp][%s]{\\fontsize{%s}{\\baselineskip}%s", pageSetup.lyricsVerticalOffset, color, note.width - offset, lyricPos, fontSize, lyrics))

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
        tex.sprint(string.format("\\hspace{-%fbp}", note.width))
        tex.sprint(string.format("\\raisebox{-%fbp}{\\makebox[%fbp][l]{", pageSetup.lyricsVerticalOffset, note.width))

        if note.isHyphen then
            for _, hyphenOffset in ipairs(note.hyphenOffsets) do
                tex.sprint(string.format("\\hspace{%fbp}\\rlap{-}\\hspace{-%fbp}", hyphenOffset, hyphenOffset))
            end
        else
            tex.sprint(string.format("\\rule{%fbp}{%fbp}\\hspace{-%fbp}", note.melismaWidth, pageSetup.lyricsMelismaThickness, note.melismaWidth))
        end

        -- close \raisebox{\makebox{}}
        tex.sprint("}}")
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
        tex.sprint(string.format('\\textcolor{byzcolormeasurebar}{\\char"%s}', glyphNameToCodepointMap[martyria.measureBarLeft]))
    end

    if martyria.tempoLeft then
        tex.sprint(string.format('\\textcolor{byzcolortempo}{\\char"%s}', glyphNameToCodepointMap[martyria.tempoLeft]))
    end

    tex.sprint(string.format('\\char"%s\\char"%s', glyphNameToCodepointMap[martyria.note], glyphNameToCodepointMap[martyria.rootSign]))

    if martyria.fthora then
        tex.sprint(string.format('\\textcolor{byzcolormartyria}{\\char"%s}', glyphNameToCodepointMap[martyria.fthora]))
    end

    if martyria.tempo then
        tex.sprint(string.format('\\textcolor{byzcolortempo}{\\char"%s}', glyphNameToCodepointMap[martyria.tempo]))
    end

    if martyria.measureBarLeft and string.match(martyria.measureBarLeft, "Above$") then
        tex.sprint(string.format('\\textcolor{byzcolormeasurebar}{\\char"%s}', glyphNameToCodepointMap[martyria.measureBarLeft]))
    end

    if martyria.tempoRight then
        tex.sprint(string.format('\\textcolor{byzcolortempo}{\\char"%s}', glyphNameToCodepointMap[martyria.tempoRight]))
    end

    if martyria.measureBarRight then
        tex.sprint(string.format('\\textcolor{byzcolormeasurebar}{\\char"%s}', glyphNameToCodepointMap[martyria.measureBarRight]))
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
    local font_size = dropCap.fontSize and string.format("%fbp", dropCap.fontSize) or "\\byzdropcapsize"
    local color = dropCap.color and string.format("\\textcolor[HTML]{%s}", dropCap.color) or "\\textcolor{byzcolordropcap}"
    local is_bold = dropCap.fontWeight == "700" or pageSetup.dropCapDefaultFontWeight == "700"
    local is_italic = dropCap.fontStyle == "italic" or pageSetup.dropCapDefaultFontStyle == "italic"
    local content = escape_latex(dropCap.content)
    content = is_italic and string.format("\\textit{%s}", content) or content
    content = is_bold and string.format("\\textbf{%s}", content) or content
    content = dropCap.fontFamily and string.format("{\\fontspec{%s}%s}", dropCap.fontFamily, content) or string.format("\\byzdropcapfont{}{%s}", content)

    local verticalAdjustment = dropCap.verticalAdjustment and dropCap.verticalAdjustment or 0

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", dropCap.x))
    tex.sprint(string.format("\\raisebox{-%fbp}{{%s{\\fontsize{%s}{\\baselineskip}%s}}}", pageSetup.lyricsVerticalOffset + verticalAdjustment, color, font_size, content))
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
    tex.sprint(string.format("\\makebox[%fbp][%s]{", modeKey.width, modeKey.alignment))
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
        tex.sprint(string.format('\\hspace{6bp}\\raisebox{0.45em}{\\char"%s}', glyphNameToCodepointMap[modeKey.tempo]))
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
                    '\\raisebox{3bp}{{\\sffamily{}(}\\raisebox{0.45em}{\\char"%s\\char"%s}\\hspace{7.5bp}{\\sffamily{}-}\\hspace{1.5bp}\\raisebox{0.45em}{\\char"%s\\char"%s}\\hspace{3bp}{\\sffamily{})}}',
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
            tex.sprint(string.format('\\raisebox{0.45em}{\\char"%s}', glyphNameToCodepointMap[modeKey.tempo]))
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

local function print_text_box_inline(textBox, pageSetup)
    local font_size = textBox.fontSize and string.format("%fbp", textBox.fontSize) or "\\byzlyricsize"
    local color = textBox.color and string.format("\\textcolor[HTML]{%s}", textBox.color) or "\\textcolor{byzcolorlyrics}"
    local is_bold = textBox.fontWeight == "700" or pageSetup.lyricsDefaultFontWeight == "700"
    local is_italic = textBox.fontStyle == "italic" or pageSetup.lyricsDefaultFontStyle == "italic"
    local content = escape_latex(textBox.content)
    content = is_italic and string.format("\\textit{%s}", content) or content
    content = is_bold and string.format("\\textbf{%s}", content) or content
    content = textBox.fontFamily and string.format("{\\fontspec{%s}%s}", textBox.fontFamily, content) or string.format("\\byzlyricfont{}{%s}", content)

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", textBox.x))
    tex.sprint(string.format("\\makebox[%fbp][%s]{", textBox.width, textBox.alignment))
    tex.sprint(string.format("%s{\\fontsize{%s}{\\baselineskip}%s", color, font_size, content))

    -- end \textcolor and \makebox
    tex.sprint("}}")
    tex.sprint(string.format("\\hspace{-%fbp}", textBox.width))
    tex.sprint(string.format("\\hspace{%fbp}", -textBox.x))

    -- end \mbox
    tex.sprint("}")
end

local function print_text_box(textBox, pageSetup)
    if textBox.inline then
        print_text_box_inline(textBox, pageSetup)
        return
    end

    if textBox.content == "" then
        tex.sprint("\\vspace{-\\baselineskip}")
        tex.sprint(string.format("\\vspace{%fbp}", textBox.height))
        return
    end

    local font_size = textBox.fontSize and string.format("%fbp", textBox.fontSize) or "\\byztextboxsize"
    local color = textBox.color and string.format("\\color[HTML]{%s}", textBox.color) or "\\color{byzcolorlyrics}"
    local is_bold = textBox.fontWeight == "700" or pageSetup.textBoxDefaultFontWeight == "700"
    local is_italic = textBox.fontStyle == "italic" or pageSetup.textBoxDefaultFontStyle == "italic"
    local content = escape_latex(textBox.content)
    content = is_italic and string.format("\\textit{%s}", content) or content
    content = is_bold and string.format("\\textbf{%s}", content) or content
    content = textBox.fontFamily and string.format("{\\fontspec{%s}%s}", textBox.fontFamily, content) or string.format("\\byztextboxfont{}{%s}", content)

    if textBox.marginTop then
        tex.sprint("\\vspace{-\\baselineskip}")
        tex.sprint(string.format("\\vspace{%fbp}", textBox.marginTop))
        tex.sprint("\\newline")
    end

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", textBox.x))
    tex.sprint(string.format("\\parbox[b][%fbp][c]{%fbp}{", textBox.height, textBox.width))

    if textBox.alignment == "c" then
        tex.sprint("\\centering")
    end
    if textBox.alignment == "r" then
        tex.sprint("\\hfill")
    end

    tex.sprint(string.format("%s{\\fontsize{%s}{\\baselineskip}%s", color, font_size, content))

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

    -- Load the font metadata
    if neume_font_data_map[data.pageSetup.fontFamilies.neume] == nil then
        neume_font_data_map[data.pageSetup.fontFamilies.neume] = load_font_data(data.pageSetup.fontFamilies.neume)
    end

    glyphNameToCodepointMap = neume_font_data_map[data.pageSetup.fontFamilies.neume].glyph_name_to_codepoint_map
    font_metadata = neume_font_data_map[data.pageSetup.fontFamilies.neume].font_metadata

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

    tex.sprint(string.format("\\setlength{\\byzneumesize}{%fbp}", data.pageSetup.fontSizes.neume))
    tex.sprint(string.format("\\setlength{\\byzmodekeysize}{%fbp}", data.pageSetup.fontSizes.modeKey))
    tex.sprint(string.format("\\setlength{\\byzlyricsize}{%fbp}", data.pageSetup.fontSizes.lyrics))
    tex.sprint(string.format("\\setlength{\\byzdropcapsize}{%fbp}", data.pageSetup.fontSizes.dropCap))
    tex.sprint(string.format("\\setlength{\\byztextboxsize}{%fbp}", data.pageSetup.fontSizes.textBox))

    tex.sprint(string.format("\\renewfontfamily{\\byzneumefont}{%s}", get_neume_font(data.pageSetup.fontFamilies.neume)))
    tex.sprint(string.format("\\renewfontfamily{\\byzlyricfont}{%s}", data.pageSetup.fontFamilies.lyrics))
    tex.sprint(string.format("\\renewfontfamily{\\byzdropcapfont}{%s}", data.pageSetup.fontFamilies.dropCap))
    tex.sprint(string.format("\\renewfontfamily{\\byztextboxfont}{%s}", data.pageSetup.fontFamilies.textBox))

    tex.sprint(string.format("\\setlength{\\baselineskip}{%fbp}", data.pageSetup.lineHeight))

    tex.sprint(string.format("\\definecolor{byzcoloraccidental}{HTML}{%s}", data.pageSetup.colors.accidental))
    tex.sprint(string.format("\\definecolor{byzcolordropcap}{HTML}{%s}", data.pageSetup.colors.dropCap))
    tex.sprint(string.format("\\definecolor{byzcolorfthora}{HTML}{%s}", data.pageSetup.colors.fthora))
    tex.sprint(string.format("\\definecolor{byzcolorgorgon}{HTML}{%s}", data.pageSetup.colors.gorgon))
    tex.sprint(string.format("\\definecolor{byzcolorheteron}{HTML}{%s}", data.pageSetup.colors.heteron))
    tex.sprint(string.format("\\definecolor{byzcolorison}{HTML}{%s}", data.pageSetup.colors.ison))
    tex.sprint(string.format("\\definecolor{byzcolorkoronis}{HTML}{%s}", data.pageSetup.colors.koronis))
    tex.sprint(string.format("\\definecolor{byzcolorlyrics}{HTML}{%s}", data.pageSetup.colors.lyrics))
    tex.sprint(string.format("\\definecolor{byzcolormartyria}{HTML}{%s}", data.pageSetup.colors.martyria))
    tex.sprint(string.format("\\definecolor{byzcolormeasurebar}{HTML}{%s}", data.pageSetup.colors.measureBar))
    tex.sprint(string.format("\\definecolor{byzcolormeasurenumber}{HTML}{%s}", data.pageSetup.colors.measureNumber))
    tex.sprint(string.format("\\definecolor{byzcolormodekey}{HTML}{%s}", data.pageSetup.colors.modeKey))
    tex.sprint(string.format("\\definecolor{byzcolorneume}{HTML}{%s}", data.pageSetup.colors.neume))
    tex.sprint(string.format("\\definecolor{byzcolornoteindicator}{HTML}{%s}", data.pageSetup.colors.noteIndicator))
    tex.sprint(string.format("\\definecolor{byzcolortempo}{HTML}{%s}", data.pageSetup.colors.tempo))
    tex.sprint(string.format("\\definecolor{byzcolortextbox}{HTML}{%s}", data.pageSetup.colors.textBox))

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
                    print_text_box(element, data.pageSetup)
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
