# neanes
# ~/Projects/neanes/release/neanes-cli --silent-latex ~/Projects/neanes-examples/kontakion_prophet_elias/kontakion_prophet_elias_almouzios.byzx
~/Projects/neanes/release/neanes-cli --silent-latex --latex-include-mode-keys --latex-include-text-boxes ~/Projects/neanes-examples/kontakion_prophet_elias/kontakion_prophet_elias_almouzios.byzx

# neanes-examples
cp -f ~/Projects/neanes-examples/kontakion_prophet_elias/kontakion_prophet_elias_almouzios.byzx ~/Projects/neanestex/examples/kontakion_prophet_elias_almouzios.byzx
cp -f ~/Projects/neanes-examples/kontakion_prophet_elias/kontakion_prophet_elias_almouzios.byztex ~/Projects/neanestex/examples/kontakion_prophet_elias_almouzios.byztex

# LaTeX package (neanestex.sty)
# sudo cp ~/Projects/neanestex/tex/* /usr/share/texlive/texmf-dist/tex/neanestex/
# sudo mktexlsr

# neanestex (lualatex)
# lualatex ~/Projects/neanestex/examples/kontakion_prophet_elias_almouzios_latex.tex
lualatex kontakion_prophet_elias_almouzios_latex.tex

# neanes-examples
cp -f ~/Projects/neanestex/examples/kontakion_prophet_elias_almouzios_latex.pdf ~/Projects/neanes-examples/kontakion_prophet_elias/kontakion_prophet_elias_almouzios_latex.pdf
