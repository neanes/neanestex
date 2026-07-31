# NeanesTeX

NeanesTeX is a LuaLaTeX package that allows Byzantine Chant scores designed in [Neanes](https://github.com/neanes/neanes) to be inserted into a LaTeX document.

## Basic Usage

Install [TeX Live](https://www.tug.org/texlive/).

Create a TeX document. See the `examples/` directory for a starting point.

Either copy the contents of `tex/` to your TeX Live local packages folder, or copy the contents to the same location as your TeX document.

Download the engraving neume fonts and metadata JSON files from the [Neanes repository](https://github.com/neanes/neanes/tree/master/src/assets/fonts) and place them in the same location as your TeX document. Also download and install any additional text fonts that you want to use from the repository and install them in your operating system, or in TeX Live.

Specify the font and metadata files in your document.

```latex
\byzsetneumefontfile{Neanes}{NeanesEngraving.otf}
\byzsetneumefontmetadatafile{Neanes}{neanesengraving.metadata.json}
```

In Neanes, export your scores by choosing `File -> Export As -> Export as Latex` in the file menu. Save the exported `.byztex` files in the same directory as your TeX document.

Insert the score into the document.

```latex
\neanesscore{my-score.byztex}{}
```

Generate a PDF with `lualatex my-doc.tex`.

> [!TIP]
> Files can be exported on the command line or in a batch/shell script by launching Neanes with the `--silent-latex` option followed by a list of files to export.

## Finer Points

### Supported Score Elements

When exporting a score from Neanes, mode keys and text boxes are not exported by default, although you can choose to do so. However, it is recommended that you instead use LaTeX to create your own text boxes and mode key signatures.

Rich text boxes and images do not currently export. This will probably not be included in this package since LaTeX handles rich text and images better than Neanes. Also note that text boxes with multiple blank lines will not export properly.

### Score Sections

In order to insert a larger score into your document that contains many text breaks between parts, you may either create multiple Neanes files and insert each one at the correct location, or you may use a single file and assign section names in Neanes. To assign a section name, click on a text box and set the Running Marker Role to `Section` in the properties pane toolbar. The section name will be the text in the text box, unless you specify Override Text.

You can then insert a single section of a larger score into your document.

```latex
\neanesscore{score.byztex}{Section Name}
```

Note that you may place a section name on a text box even if you choose not to export those elements. The exported file will still correctly generate the sections.
