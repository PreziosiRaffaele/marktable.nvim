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

T['the view returns to the edited row when lines above the table change'] = function()
    child.api.nvim_win_set_cursor(0, { 4, 0 })
    focus_view()
    child.type_keys('A', '!', '<Esc>')

    -- Lines appear above the table while the editor is open.
    child.lua([[vim.api.nvim_buf_set_lines(1, 0, 0, false, { 'intro', '' })]])
    child.type_keys(':w<CR>')

    eq(wait_for_view(), true)
    eq(state().title, ' Markdown Table Row 2/3 ')
    eq(child.lua_get('vim.api.nvim_buf_get_lines(0, 1, 2, false)'), { 'Beta!' })
    eq(source()[6], '| Beta! | two |')
    eq(child.lua_get('vim.api.nvim_win_get_cursor(vim.fn.win_getid(1))[1]'), 6)
end

T['saving from the view leaves no anchor extmarks behind'] = function()
    focus_view()
    child.type_keys('A', '!', '<Esc>', ':w<CR>')
    eq(wait_for_view(), true)
    child.type_keys(']r', 'e', 'q')
    eq(wait_for_view(), true)

    local count =
        child.lua_get([[#vim.api.nvim_buf_get_extmarks(1, vim.api.nvim_get_namespaces().marktable, 0, -1, {})]])
    eq(count, 0)
end

T['the view warns instead of reopening on another row when the row was deleted'] = function()
    child.lua([[
        _G.messages = {}
        vim.notify = function(message) table.insert(_G.messages, message) end
    ]])
    focus_view()
    child.type_keys('e')

    -- The edited row (Alpha) is deleted while the editor is open.
    child.lua([[vim.api.nvim_buf_set_lines(1, 2, 3, false, {})]])
    child.type_keys('q')

    eq(wait_until([[#_G.messages > 0]]), true)
    eq(child.lua_get('_G.messages'), { 'Markdown table row is no longer available' })
    eq(state().floats, 0)
    eq(state().buftype, '')
end

T['the reopened view fits a terminal resized while the editor was open'] = function()
    child.api.nvim_buf_set_lines(0, 2, 3, false, { '| ' .. string.rep('w', 60) .. ' | one |' })
    focus_view()
    child.type_keys('e')

    child.o.columns = 40
    child.type_keys(':w<CR>')

    eq(wait_for_view(), true)
    local view_config = child.api.nvim_win_get_config(0)
    eq(view_config.width <= 36, true)
    eq(view_config.col + view_config.width + 2 <= 40, true)
end

T['MarktableRowEdit still closes back to the table'] = function()
    child.cmd('MarktableRowEdit')
    child.type_keys('A', ' direct', '<Esc>', ':w<CR>')

    eq(wait_until([[vim.bo.buftype == '' and #vim.api.nvim_list_wins() == 1]]), true)
    eq(state().floats, 0)
    eq(source()[3], '| Alpha direct | one |')
end

return T
