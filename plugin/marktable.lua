if vim.g.loaded_marktable == 1 then
    return
end

vim.g.loaded_marktable = 1

require('marktable').setup()
