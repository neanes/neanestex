neanestex = neanestex or {}
local neanestex = neanestex

local json = require "json"
local font_metadata = nil
local glyphNameToCodepointMap = {}

local function read_json(filename)
    local file = io.open(filename, "r")
    if not file then return "{}" end
    local content = file:read("*all")
    file:close()
    return content
end

local glyphnames = json.decode(read_json("glyphnames.json"))

local function get_mark_offset(base, mark, extra_offset)
    local mark_anchor_name = find_mark_anchor_name(base, mark)

    if mark_anchor_name == nil then
      texio.write_nl("warning", "Missing anchor for base: " .. base ..  "mark: " .. mark)
      return { x = 0, y = 0 }
    end

    local mark_anchor = font_metadata.glyphsWithAnchors[mark][
      mark_anchor_name
    ]

    local base_anchor = font_metadata.glyphsWithAnchors[base][
      mark_anchor_name
    ]

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

local function find_mark_anchor_name(base, mark)
    for anchor_name, _ in pairs(font_metadata.glyphsWithAnchors[mark] or {}) do
        if font_metadata.glyphsWithAnchors[base] and font_metadata.glyphsWithAnchors[base][anchor_name] then
            return anchor_name
        end
    end

    return nil 
end

local function escape_latex(str)
    local replacements = {
        ["\\"] = "\\textbackslash{}", 
        ["{"]  = "\\{",  
        ["}"]  = "\\}",
        ["$"]  = "\\$",  
        ["&"]  = "\\&",    
        ["%"]  = "\\%",
        ["#"]  = "\\#",  
        ["_"]  = "\\_",    
        ["^"]  = "\\textasciicircum{}",
        ["~"]  = "\\textasciitilde{}", 
        ["\n"] = "\\\\",
        ["\u{E280}"] = "{\\byzneumefont\u{E280}}",
        ["\u{E281}"] = "{\\byzneumefont\u{E281}}",
        ["\u{1D0B4}"] = "{\\byzneumefont\u{1D0B4}}",
        ["\u{1D0B5}"] = "{\\byzneumefont\u{1D0B5}}",
    }
    return str:gsub("[\\%$%&%#_%^{}~\n]", replacements)
              :gsub("\u{E280}", replacements["\u{E280}"])
              :gsub("\u{E281}", replacements["\u{E281}"])
              :gsub("\u{1D0B4}", replacements["\u{1D0B4}"])
              :gsub("\u{1D0B5}", replacements["\u{1D0B5}"])
    
end

local function print_note(note, pageSetup)
    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", note.x)) 
    tex.sprint(string.format("\\makebox[%fbp]{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont", note.width))

    if note.measureBarLeft then
        tex.sprint(string.format("\\textcolor{byzcolormeasurebar}{\\char\"%s}", glyphNameToCodepointMap[note.measureBarLeft]))
    end

    if note.vareia then
        tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap["vareia"]))
    end

    -- If the user specified an additional offset, we must manually position the marks
    if note.timeOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.time, note.timeOffset)
        tex.sprint(string.format("\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.time], offset.x))
    end

    if note.gorgonOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.gorgon, note.gorgonOffset)
        tex.sprint(string.format("\\textcolor{byzcolorgorgon}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.gorgon], offset.x))
    end

    if note.gorgonSecondaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.gorgonSecondary, note.gorgonSecondaryOffset)
        tex.sprint(string.format("\\textcolor{byzcolorgorgon}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.gorgonSecondary], offset.x))
    end

    if note.fthoraOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.fthora, note.fthoraOffset)
        tex.sprint(string.format("\\textcolor{byzcolorfthora}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.fthora], offset.x))
    end

    if note.fthoraSecondaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.fthoraSecondary, note.fthoraSecondaryOffset)
        tex.sprint(string.format("\\textcolor{byzcolorfthora}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.fthoraSecondary], offset.x))
    end

    if note.fthoraTertiaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.fthoraTertiary, note.fthoraTertiaryOffset)
        tex.sprint(string.format("\\textcolor{byzcolorfthora}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.fthoraTertiary], offset.x))
    end

    if note.accidentalOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.accidental, note.accidentalOffset)
        tex.sprint(string.format("\\textcolor{byzcoloraccidental}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.accidental], offset.x))
    end

    if note.accidentalSecondaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.accidentalSecondary, note.accidentalSecondaryOffset)
        tex.sprint(string.format("\\textcolor{byzcoloraccidental}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.accidentalSecondary], offset.x))
    end

    if note.accidentalTertiaryOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.accidentalTertiary, note.accidentalTertiaryOffset)
        tex.sprint(string.format("\\textcolor{byzcoloraccidental}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.accidentalTertiary], offset.x))
    end

    if note.isonOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.ison, note.isonOffset)
        tex.sprint(string.format("\\textcolor{byzcolorison}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.ison], offset.x))
    end

    if note.noteIndicatorOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.noteIndicator, note.noteIndicatorOffset)
        tex.sprint(string.format("\\textcolor{byzcolornoteindicator}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.noteIndicator], offset.x))
    end

    if note.koronisOffset then
        local offset = get_mark_offset(note.quantitativeNeume, 'koronis', note.koronisOffset)
        tex.sprint(string.format("\\textcolor{byzcolorkoronis}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap['koronis'], offset.x))
    end

    if note.measureNumberOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.measureNumber, note.measureNumberOffset)
        tex.sprint(string.format("\\textcolor{byzcolormeasurenumber}{\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.measureNumber], offset.x))
    end

    if note.tieOffset then
        local offset = get_mark_offset(note.quantitativeNeume, note.tie, note.tieOffset)
        tex.sprint(string.format("\\hspace{%fem}\\raisebox{-%fem}{\\char\"%s}\\hspace{-%fem}", offset.x, offset.y, glyphNameToCodepointMap[note.tie], offset.x))
    end

    -- Print the main neume
    tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[note.quantitativeNeume]))

    if note.vocalExpression then
        tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[note.vocalExpression]))
    end

    -- If the user did not specify an additional offset, latex+luacolor will position the marks correctly
    if note.time and not note.timeOffset then
            tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[note.time]))
    end

    if note.gorgon and not note.gorgonOffset then
        tex.sprint(string.format("\\textcolor{byzcolorgorgon}{\\char\"%s}", glyphNameToCodepointMap[note.gorgon]))
    end

    if note.gorgonSecondary and not note.gorgonSecondaryOffset then
        tex.sprint(string.format("\\textcolor{byzcolorgorgon}{\\char\"%s}", glyphNameToCodepointMap[note.gorgonSecondary]))
    end

    if note.fthora and not note.fthoraOffset then
        tex.sprint(string.format("\\textcolor{byzcolorfthora}{\\char\"%s}", glyphNameToCodepointMap[note.fthora]))
    end

    if note.fthoraSecondary and not note.fthoraSecondaryOffset then
        tex.sprint(string.format("\\textcolor{byzcolorfthora}{\\char\"%s}", glyphNameToCodepointMap[note.fthoraSecondary]))
    end

    if note.fthoraTertiary and not note.fthoraTertiaryOffset then
        tex.sprint(string.format("\\textcolor{byzcolorfthora}{\\char\"%s}", glyphNameToCodepointMap[note.fthoraTertiary]))
    end

    if note.accidental and not note.accidentalOffset then
        tex.sprint(string.format("\\textcolor{byzcoloraccidental}{\\char\"%s}", glyphNameToCodepointMap[note.accidental]))
    end

    if note.accidentalSecondary and not note.accidentalSecondaryOffset then
        tex.sprint(string.format("\\textcolor{byzcoloraccidental}{\\char\"%s}", glyphNameToCodepointMap[note.accidentalSecondary]))
    end

    if note.accidentalTertiary and not note.accidentalTertiaryOffset then
        tex.sprint(string.format("\\textcolor{byzcoloraccidental}{\\char\"%s}", glyphNameToCodepointMap[note.accidentalTertiary]))
    end

    if note.ison and not note.isonOffset then
        tex.sprint(string.format("\\textcolor{byzcolorison}{\\char\"%s}",glyphNameToCodepointMap[note.ison]))
    end

    if note.noteIndicator and not note.noteIndicatorOffset then
        tex.sprint(string.format("\\textcolor{byzcolornoteindicator}{\\char\"%s}",glyphNameToCodepointMap[note.noteIndicator]))
    end

    if note.koronis and not note.koronisOffset then
        tex.sprint(string.format("\\textcolor{byzcolorkoronis}{\\char\"%s}",glyphNameToCodepointMap['koronis']))
    end

    if note.measureNumber and not note.measureNumberOffset then
        tex.sprint(string.format("\\textcolor{byzcolormeasurenumber}{\\char\"%s}", glyphNameToCodepointMap[note.measureNumber]))
    end

    if note.tie and not note.tieOffset then
        tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[note.tie]))
    end

    -- Right measure bar is last
    if note.measureBarRight then
        tex.sprint(string.format("\\textcolor{byzcolormeasurebar}{\\char\"%s}", glyphNameToCodepointMap[note.measureBarRight]))
    end

    -- close \makebox{}
    tex.sprint("}")

    if note.lyrics then
        local lyricPos = note.lyricsLeftAlign and "l" or "c"
        local fontSize = note.lyricsFontSize and string.format('%fbp', note.lyricsFontSize) or '\\byzlyricsize'
        local color = note.lyricsColor and string.format('\\textcolor[HTML]{%s}', note.lyricsColor) or '\\textcolor{byzcolorlyrics}' 
        local default_weight = pageSetup.lyricsDefaultFontWeight and string.format('\\addfontfeatures{Weight=%s}', pageSetup.lyricsDefaultFontWeight) or ''
        local weight = note.lyricsFontWeight and string.format('\\addfontfeatures{Weight=%s}', note.lyricsFontWeight) or default_weight
        local style = note.lyricsFontStyle and note.lyricsFontStyle or pageSetup.lyricsDefaultFontStyle
        local lyrics = style == 'italic' and string.format('\\textit{%s}', escape_latex(note.lyrics)) or escape_latex(note.lyrics)
        lyrics = note.lyricsFontFamily and string.format("{\\fontspec{%s}%s%s}", note.lyricsFontFamily, weight, lyrics) or string.format('\\byzlyricfont{}{%s%s}', weight, lyrics)

        local offset = 0

        if note.lyricsHorizontalOffset then offset = note.lyricsHorizontalOffset end

        tex.sprint(string.format("\\hspace{-%fbp}", note.width - offset))    
        tex.sprint(string.format("\\raisebox{%fbp}{\\makebox[%fbp][%s]{\\fontsize{%s}{\\baselineskip}%s", pageSetup.lyricsVerticalOffset, note.width - offset, lyricPos, fontSize, lyrics))

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

        -- close \raisebox{\makebox{}}
        tex.sprint("}}")
    elseif note.isFullMelisma then
        tex.sprint(string.format("\\hspace{-%fbp}", note.width))    
        tex.sprint(string.format("\\raisebox{%fbp}{\\makebox[%fbp][l]{", pageSetup.lyricsVerticalOffset, note.width))

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
    tex.sprint(string.format("\\textcolor{byzcolormartyria}{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont"))
    
    if martyria.measureBarLeft and not string.match(martyria.measureBarLeft, 'Above$') then
        tex.sprint(string.format("\\textcolor{byzcolormeasurebar}{\\char\"%s}", glyphNameToCodepointMap[martyria.measureBarLeft]))
    end

    if martyria.tempoLeft then
        tex.sprint(string.format("\\textcolor{byzcolortempo}{\\char\"%s}", glyphNameToCodepointMap[martyria.tempoLeft]))
    end
    
    tex.sprint(string.format("\\char\"%s\\char\"%s", glyphNameToCodepointMap[martyria.note], glyphNameToCodepointMap[martyria.rootSign]))
    
    if martyria.fthora then
        tex.sprint(string.format("\\textcolor{byzcolormartyria}{\\char\"%s}", glyphNameToCodepointMap[martyria.fthora]))
    end

    if martyria.tempo then
        tex.sprint(string.format("\\textcolor{byzcolortempo}{\\char\"%s}", glyphNameToCodepointMap[martyria.tempo]))
    end

    if martyria.measureBarLeft and string.match(martyria.measureBarLeft, 'Above$') then
        tex.sprint(string.format("\\textcolor{byzcolormeasurebar}{\\char\"%s}", glyphNameToCodepointMap[martyria.measureBarLeft]))
    end

    if martyria.tempoRight then
        tex.sprint(string.format("\\textcolor{byzcolortempo}{\\char\"%s}", glyphNameToCodepointMap[martyria.tempoRight]))
    end

    if martyria.measureBarRight then
        tex.sprint(string.format("\\textcolor{byzcolormeasurebar}{\\char\"%s}", glyphNameToCodepointMap[martyria.measureBarRight]))
    end

    tex.sprint("}")
    tex.sprint(string.format("\\hspace{-%fbp}", martyria.width))         
    tex.sprint(string.format("\\hspace{%fbp}", -martyria.x)) 
    tex.sprint("}")
end

local function print_tempo(tempo, pageSetup) 
    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", tempo.x)) 
    tex.sprint(string.format("\\textcolor{byzcolortempo}{\\fontsize{\\byzneumesize}{\\baselineskip}\\byzneumefont"))
        
    tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[tempo.neume]))
    
    -- end \textcolor
    tex.sprint("}")
    tex.sprint(string.format("\\hspace{-%fbp}", tempo.width))         
    tex.sprint(string.format("\\hspace{%fbp}", -tempo.x)) 
    -- end \mbox
    tex.sprint("}")
end

local function print_drop_cap(dropCap, pageSetup) 
    local font_size = dropCap.fontSize and string.format("%fbp", dropCap.fontSize) or '\\byzdropcapsize' 
    local color = dropCap.color and string.format('\\textcolor[HTML]{%s}', dropCap.color) or '\\textcolor{byzcolordropcap}' 
    local default_weight = pageSetup.dropCapDefaultFontWeight and string.format('\\addfontfeatures{Weight=%s}', pageSetup.dropCapDefaultFontWeight) or ''
    local weight = dropCap.fontWeight and string.format('\\addfontfeatures{Weight=%s}', dropCap.fontWeight) or default_weight
    local style = dropCap.fontStyle and dropCap.fontStyle or pageSetup.dropCapDefaultFontStyle
    local content = style == 'italic' and string.format('\\textit{%s}', escape_latex(dropCap.content)) or escape_latex(dropCap.content)
    content = dropCap.fontFamily and string.format("{\\fontspec{%s}%s%s}", dropCap.fontFamily, weight, content) or string.format('\\byzdropcapfont{}{%s%s}', weight, content)

    local verticalAdjustment = dropCap.verticalAdjustment and dropCap.verticalAdjustment or 0 

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", dropCap.x)) 
    tex.sprint(string.format("\\raisebox{%fbp}{{%s{\\fontsize{%s}{\\baselineskip}%s}}}", pageSetup.lyricsVerticalOffset + verticalAdjustment, color, font_size, content))    
    tex.sprint(string.format("\\hspace{-%fbp}", dropCap.width))         
    tex.sprint(string.format("\\hspace{%fbp}", -dropCap.x)) 
    tex.sprint("}")
end

local function print_mode_key(modeKey, pageSetup)
    local font_size = modeKey.fontSize and string.format("%fbp", modeKey.fontSize) or '\\byzmodekeysize' 
    local color = modeKey.color and string.format('\\textcolor[HTML]{%s}', modeKey.color) or '\\textcolor{byzcolormodekey}' 
    
    if modeKey.marginTop then
        tex.sprint(string.format('\\vspace{-\\baselineskip}',  modeKey.marginTop))
        tex.sprint(string.format('\\vspace{%fbp}',  modeKey.marginTop))
        tex.sprint('\\newline')
    end

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\makebox[%fbp][%s]{", modeKey.width, modeKey.alignment))
    tex.sprint(string.format("%s{\\fontsize{%s}{\\baselineskip}\\byzneumefont", color, font_size))
        
    tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap['modeWordEchos']))
    if modeKey.isPlagal then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap['modePlagal'])) end
    if modeKey.isVarys then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap['modeWordVarys'])) end
    tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.martyria]))
    if modeKey.note then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.note])) end
    if modeKey.fthoraAboveNote then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.fthoraAboveNote])) end
    if modeKey.quantitativeNeumeAboveNote then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.quantitativeNeumeAboveNote])) end
    if modeKey.note2 then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.note2])) end
    if modeKey.fthoraAboveNote2 then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.fthoraAboveNote2])) end
    if modeKey.quantitativeNeumeAboveNote2 then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.quantitativeNeumeAboveNote2])) end
    if modeKey.quantitativeNeumeRight then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.quantitativeNeumeRight])) end
    if modeKey.fthoraAboveQuantitativeNeumeRight then tex.sprint(string.format("\\char\"%s", glyphNameToCodepointMap[modeKey.fthoraAboveQuantitativeNeumeRight])) end
    if modeKey.tempo and not modeKey.tempoAlignRight then tex.sprint(string.format("\\hspace{6bp}\\raisebox{0.45em}{\\char\"%s}", glyphNameToCodepointMap[modeKey.tempo])) end
    
    -- end \textcolor and \makebox
    tex.sprint("}}")
    tex.sprint(string.format("\\hspace{-%fbp}", modeKey.width))      
    
    if (modeKey.tempo and modeKey.tempoAlignRight) or modeKey.showAmbitus then 
        tex.sprint(string.format("\\makebox[%fbp][r]{", modeKey.width))
        tex.sprint(string.format("%s{\\fontsize{%s}{\\baselineskip}\\byzneumefont", color, font_size))

        if modeKey.showAmbitus then
            tex.sprint(string.format("\\raisebox{3bp}{{\\sffamily{}(}\\raisebox{0.45em}{\\char\"%s\\char\"%s}\\hspace{7.5bp}{\\sffamily{}-}\\hspace{1.5bp}\\raisebox{0.45em}{\\char\"%s\\char\"%s}\\hspace{3bp}{\\sffamily{})}}", 
                glyphNameToCodepointMap[modeKey.ambitusLowNote], 
                glyphNameToCodepointMap[modeKey.ambitusLowRootSign],
                glyphNameToCodepointMap[modeKey.ambitusHighNote], 
                glyphNameToCodepointMap[modeKey.ambitusHighRootSign]))

            if modeKey.tempo and modeKey.tempoAlignRight then tex.sprint("\\hspace{6bp}") end
        end

        if modeKey.tempo and modeKey.tempoAlignRight then tex.sprint(string.format("\\raisebox{0.45em}{\\char\"%s}", glyphNameToCodepointMap[modeKey.tempo])) end

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

    tex.sprint(string.format('\\vspace{-\\baselineskip}\\vspace{%fbp}', height))
end

local function print_text_box_inline(textBox, pageSetup)
    local font_size = textBox.fontSize and string.format('%fbp', textBox.fontSize) or '\\byzlyricsize'
    local color = textBox.color and string.format('\\textcolor[HTML]{%s}', textBox.color) or '\\textcolor{byzcolorlyrics}' 
    local default_weight = pageSetup.lyricsDefaultFontWeight and string.format('\\addfontfeatures{Weight=%s}', pageSetup.lyricsDefaultFontWeight) or ''
    local weight = textBox.fontWeight and string.format('\\addfontfeatures{Weight=%s}', textBox.fontWeight) or default_weight
    local style = textBox.fontStyle and textBox.fontStyle or pageSetup.lyricsDefaultFontStyle
    local content = style == 'italic' and string.format('\\textit{%s}', escape_latex(textBox.content)) or escape_latex(textBox.content)
    content = textBox.fontFamily and string.format("{\\fontspec{%s}%s%s}", textBox.fontFamily, weight, content) or string.format('\\byzlyricfont{}{%s%s}', weight, content)
    
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

    if textBox.content == '' then
        tex.sprint('\\vspace{-\\baselineskip}')
        tex.sprint(string.format('\\vspace{%fbp}', textBox.height))
        return
    end

    local font_size = textBox.fontSize and string.format('%fbp', textBox.fontSize) or '\\byztextboxsize'
    local color = textBox.color and string.format('\\color[HTML]{%s}', textBox.color) or '\\color{byzcolorlyrics}' 
    local default_weight = pageSetup.textBoxDefaultFontWeight and string.format('\\addfontfeatures{Weight=%s}', pageSetup.textBoxDefaultFontWeight) or ''
    local weight = textBox.fontWeight and string.format('\\addfontfeatures{Weight=%s}', textBox.fontWeight) or default_weight
    local style = textBox.fontStyle and textBox.fontStyle or pageSetup.textBoxDefaultFontStyle
    local content = style == 'italic' and string.format('\\textit{%s}', escape_latex(textBox.content)) or escape_latex(textBox.content)
    content = textBox.fontFamily and string.format("{\\fontspec{%s}%s%s}", textBox.fontFamily, weight, content) or string.format('\\byztextboxfont{}{%s%s}', weight, content)
    
    if textBox.marginTop then
        tex.sprint('\\vspace{-\\baselineskip}')
        tex.sprint(string.format('\\vspace{%fbp}',  textBox.marginTop))
        tex.sprint('\\newline')
    end

    tex.sprint("\\mbox{")
    tex.sprint(string.format("\\hspace{%fbp}", textBox.x)) 
    tex.sprint(string.format("\\parbox[b][%fbp][c]{%fbp}{", textBox.height, textBox.width))
    
    if (textBox.alignment == 'c') then tex.sprint('\\centering') end
    if (textBox.alignment == 'r') then tex.sprint('\\hfill') end
    
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

    tex.sprint(string.format('\\vspace{-\\baselineskip}\\vspace{%fbp}', height))
end

local function include_score(filename, sectionName)
    local data = json.decode(read_json(filename))

    -- Find the section(s)
    local sections = {}

    if sectionName == '*' then
        sections = data.sections
    else
        local section = nil

        for _, s in ipairs(data.sections) do
            if (sectionName == '' and s.default) or s.name == sectionName then
                section = s
                break
            end
        end

        if section == nil and sectionName == nil then 
            tex.error("Could not find default section")
        end

        if section == nil then 
            tex.error("Could not find section " .. sectionName)
        end

        sections[1] = section
    end

    -- Load the font metadata
    local font_metadata_filename = 'neanes.metadata.json'

    if data.pageSetup.fontFamilies.neume == 'Neanes' then
        font_metadata_filename = "neanes.metadata.json"
    elseif data.pageSetup.fontFamilies.neume == 'NeanesRTL' then
        font_metadata_filename = "neanesrtl.metadata.json"
    elseif data.pageSetup.fontFamilies.neume == 'NeanesStathisSeries' then
        font_metadata_filename = "neanesstathisseries.metadata.json"
    end

    font_metadata = json.decode(read_json(font_metadata_filename))

    glyphNameToCodepointMap = {}

    for glyph, data in pairs(glyphnames) do
        glyphNameToCodepointMap[glyph] = data.codepoint:sub(3)
    end

    for glyph, data in pairs(font_metadata.optionalGlyphs) do
        glyphNameToCodepointMap[glyph] = data.codepoint:sub(3)
    end

    -- open a new section so that our variables do not persist forever
    tex.sprint('{')

    tex.sprint(string.format("\\setlength{\\byzneumesize}{%fbp}", data.pageSetup.fontSizes.neume))
    tex.sprint(string.format("\\setlength{\\byzmodekeysize}{%fbp}", data.pageSetup.fontSizes.modeKey))
    tex.sprint(string.format("\\setlength{\\byzlyricsize}{%fbp}", data.pageSetup.fontSizes.lyrics))
    tex.sprint(string.format("\\setlength{\\byzdropcapsize}{%fbp}", data.pageSetup.fontSizes.dropCap))
    tex.sprint(string.format("\\setlength{\\byztextboxsize}{%fbp}", data.pageSetup.fontSizes.textBox))
    
    tex.sprint(string.format("\\renewfontfamily{\\byzneumefont}{%s}", data.pageSetup.fontFamilies.neume))
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
                if element.type == 'note' then print_note(element, data.pageSetup) end
                if element.type == 'martyria' then print_martyria(element, data.pageSetup) end
                if element.type == 'tempo' then print_tempo(element, data.pageSetup) end
                if element.type == 'dropcap' then print_drop_cap(element, data.pageSetup) end
                if element.type == 'modekey' then print_mode_key(element, data.pageSetup) end
                if element.type == 'textbox' then print_text_box(element, data.pageSetup) end
            end
        end
    end

    tex.sprint("\\par")
    -- close the section
    tex.sprint("}")
end

neanestex.include_score = include_score