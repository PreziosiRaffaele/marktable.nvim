# marktable.nvim

Row-first editor for Markdown pipe-table rows.

## Commands

- `:MarktableNew` opens a floating editor with one empty section per table header and inserts the generated row.
- `:MarktableEdit` opens the data row under the cursor, shows its row number in the floating editor title, and replaces only that row.

Submit with `:w` or `:wq`. Cancel with `q`.

## Configuration

Call `setup()` to override the floating editor size. Defaults shown:

```lua
require('marktable').setup({
    width = 110,     -- maximum width of the floating editor, in columns
    min_height = 16, -- minimum height of the floating editor, in rows
})
```

Both values are clamped to the available UI space, so the window never overflows the screen.

## Development

- `make quality` runs `luacheck`, `stylua --check`, and `lua-language-server`.
- `make test` runs the pinned `mini.test` suite in headless Neovim.
- `make check` runs both gates.
