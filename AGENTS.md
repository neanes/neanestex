# Repository workflow

- After changing `Makefile`, Lua, TeX, or LaTeX test sources, run `make fmt` before validation.
- Run `make check` after formatting and before reporting the work complete.
- If the full targets cannot run because a tool is unavailable, run the applicable configured formatter directly (`mbake`, `tex-fmt`, or `stylua`) and clearly report the missing check.
- Do not manually preserve formatting that conflicts with the configured formatter output.
