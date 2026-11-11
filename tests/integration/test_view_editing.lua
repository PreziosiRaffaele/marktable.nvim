-- Editing rows from the row view. The editor closes on a scheduled callback,
-- so these cases drive a child Neovim whose event loop can run freely.
local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality

local source_lines = {
    '| Name | Notes |',
    '| --- | --- |',
    '| Alpha | one |',
    '| Beta | two |',
    '| Gamma | three |',
}

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            child.restart({ '-u', 'tests/minimal_init.lua' })
            child.lua([[require('marktable').setup()]])
            child.api.nvim_buf_set_lines(0, 0, -1, false, source_lines)
            child.api.nvim_win_set_cursor(0, { 3, 0 })
        end,
        post_once = child.stop,
    },
})

---Let the child run scheduled callbacks until `condition` (Lua expression) holds.
local function wait_until(condition)
    return child.lua_get(string.format('vim.wait(1000, function() return %s end, 10)', condition))
end

local function state()
    return child.lua_get([[(function()
        local win = vim.api.nvim_get_current_win()
        local is_float = vim.api.nvim_win_get_config(win).relative ~= ''
        local title = is_float and vim.api.nvim_win_get_config(win).title or nil
        local floats = 0
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(w).relative ~= '' then
                floats = floats + 1
            end
        end
        return {
            buftype = vim.bo.buftype,
            title = type(title) == 'table' and title[1][1] or title,
            floats = floats,
            cursor_row = vim.api.nvim_win_get_cursor(win)[1],
        }
    end)()]])
end

local function source()
    return child.lua_get('vim.api.nvim_buf_get_lines(1, 0, -1, false)')
end

local function focus_view()
    child.cmd('MarktableRowView')
    child.cmd('MarktableRowView')
end

local function wait_for_view()
    return wait_until([[vim.bo.buftype == 'nofile']])
end

T['saving the editor returns to the view with the updated row'] = function()
    focus_view()
    child.type_keys('A', ' plus', '<Esc>', ':w<CR>')

    eq(wait_for_view(), true)
    local current = state()
    eq(current.title, ' Markdown Table Row 1/3 ')
    eq(current.floats, 1)
    eq(current.cursor_row, 2)
    eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 0, 2, false)'), { '# Name', 'Alpha plus' })
    eq(source()[3], '| Alpha plus | one |')
end

T['the view keeps browsing and editing other rows'] = function()
    focus_view()
    child.type_keys('A', '!', '<Esc>', ':w<CR>')
    eq(wait_for_view(), true)

    child.type_keys(']r', 'A', '?', '<Esc>', ':w<CR>')
    eq(wait_for_view(), true)
    eq(state().title, ' Markdown Table Row 2/3 ')

    child.type_keys('q')
    local current = state()
    eq(current.floats, 0)
    eq(current.cursor_row, 4)
    eq(source(), {
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha! | one |',
        '| Beta? | two |',
        '| Gamma | three |',
    })
end

T['canceling the editor returns to the view unchanged'] = function()
    for _, cancel in ipairs({ { 'q' }, { ':q!<CR>' } }) do
        child.api.nvim_win_set_cursor(0, { 3, 0 })
        focus_view()
        child.type_keys('A', ' dropped', '<Esc>', unpack(cancel))

        eq(wait_for_view(), true)
        eq(state().title, ' Markdown Table Row 1/3 ')
        eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 1, 2, false)'), { 'Alpha' })
        eq(source(), source_lines)

        child.type_keys('q')
    end
end

T['MarktableRowEdit still closes back to the table'] = function()
    child.cmd('MarktableRowEdit')
    child.type_keys('A', ' direct', '<Esc>', ':w<CR>')

    eq(wait_until([[vim.bo.buftype == '' and #vim.api.nvim_list_wins() == 1]]), true)
    eq(state().floats, 0)
    eq(source()[3], '| Alpha direct | one |')
end

return T
