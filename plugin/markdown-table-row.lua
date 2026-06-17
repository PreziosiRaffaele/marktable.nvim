if vim.g.loaded_markdown_table_row == 1 then
    return
end

vim.g.loaded_markdown_table_row = 1

require('markdown_table_row').setup()
