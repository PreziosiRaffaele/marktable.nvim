# markdowntablerow.nvim

Row-first editor for Markdown pipe-table rows.

## Commands

- `:MarkdownTableRowNew` opens a floating editor with one empty section per table header and inserts the generated row.
- `:MarkdownTableRowEdit` opens the data row under the cursor in the floating editor and replaces only that row.

Submit with `:w` or `:wq`. Cancel with `q`.

## Development

- `make quality` runs `luacheck`, `stylua --check`, and `lua-language-server`.
- `make test` runs the pinned `mini.test` suite in headless Neovim.
- `make check` runs both gates.
