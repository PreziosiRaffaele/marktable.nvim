# marktable.nvim

Row-first editor for Markdown pipe-table rows.

## Commands

- `:MarktableRowNew` opens a floating editor with one empty section per table header and inserts the generated row.
- `:MarktableRowEdit` opens the data row under the cursor, shows its row number in the floating editor title, and replaces only that row.

Submit with `:w` or `:wq`. Cancel with `q`.

## Development

- `make quality` runs `luacheck`, `stylua --check`, and `lua-language-server`.
- `make test` runs the pinned `mini.test` suite in headless Neovim.
- `make check` runs both gates.
