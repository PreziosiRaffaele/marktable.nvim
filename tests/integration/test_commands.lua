local plugin = require('marktable')
local expect = MiniTest.expect
local eq = expect.equality

local created_buffers = {}

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            created_buffers = {}
            plugin.setup()
        end,
        post_case = function()
            for _, win in ipairs(vim.api.nvim_list_wins()) do
                if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= '' then
                    pcall(vim.api.nvim_win_close, win, true)
                end
            end

            for _, buf in ipairs(created_buffers) do
                if vim.api.nvim_buf_is_valid(buf) then
                    pcall(vim.api.nvim_buf_delete, buf, { force = true })
                end
            end

            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match('/Marktable%-') ~= nil then
                    pcall(vim.api.nvim_buf_delete, buf, { force = true })
                end
            end
        end,
    },
})

local function source_buffer(lines, cursor_line)
    local buf = vim.api.nvim_create_buf(false, true)
    table.insert(created_buffers, buf)

    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

    return buf
end

local function lines(buf)
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function window_title(win)
    local title = vim.api.nvim_win_get_config(win).title
    if type(title) == 'string' then
        return title
    end

    local chunks = {}
    for _, chunk in ipairs(title or {}) do
        table.insert(chunks, chunk[1])
    end

    return table.concat(chunks)
end

-- Do not spin the event loop (`vim.wait`) in cases: mini.test schedules every
-- case up front, so waiting would run later cases nested inside this one.
local function write_editor(replacement)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, replacement)
    local ok, err = pcall(vim.cmd, 'write')
    if ok then
        return true, nil
    end

    return false, err
end

T['MarktableRowEdit opens the current row in a section editor'] = function()
    local source = source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one<br>two |',
    }, 3)

    vim.cmd('MarktableRowEdit')

    eq(vim.bo.buftype, 'acwrite')
    eq(window_title(0), ' Edit Markdown Table Row 1 ')
    eq(lines(0), {
        '# Name',
        'Alpha',
        '',
        '# Notes',
        'one',
        'two',
    })

    local ok, err = write_editor({
        '# Name',
        'Beta',
        '',
        '# Notes',
        'updated',
        'value',
    })

    eq(ok, true)
    eq(err, nil)
    eq(lines(source), {
        '| Name | Notes |',
        '| --- | --- |',
        '| Beta | updated<br>value |',
    })
end

T['MarktableRowNew inserts after the separator when launched from the header'] = function()
    local source = source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one |',
    }, 1)

    vim.cmd('MarktableRowNew')

    eq(vim.bo.buftype, 'acwrite')
    eq(window_title(0), ' New Markdown Table Row ')
    eq(lines(0), {
        '# Name',
        '',
        '# Notes',
    })

    local ok, err = write_editor({
        '# Name',
        'Inserted',
        '',
        '# Notes',
        'fresh',
    })

    eq(ok, true)
    eq(err, nil)
    eq(lines(source), {
        '| Name | Notes |',
        '| --- | --- |',
        '| Inserted | fresh |',
        '| Alpha | one |',
    })
end

T['MarktableRowEdit keeps the editor open on invalid section order'] = function()
    local source = source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one |',
    }, 3)

    vim.cmd('MarktableRowEdit')
    local ok, err = write_editor({
        '# Notes',
        'out of order',
        '',
        '# Name',
        'Alpha',
    })

    eq(ok, false)
    expect.equality(err:find('Expected section # Name before # Notes', 1, true) ~= nil, true)
    eq(vim.bo.buftype, 'acwrite')
    eq(lines(source), {
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one |',
    })
    eq(lines(0)[1], '# Notes')
end

local view_table = {
    '| Name | Notes |',
    '| --- | --- |',
    '| Alpha | one<br>two |',
    '| Beta | b\\|c |',
    '| Gamma | three |',
}

local function floating_windows()
    local wins = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
            table.insert(wins, win)
        end
    end

    return wins
end

local function press(keys)
    vim.api.nvim_feedkeys(vim.keycode(keys), 'mx', false)
end

local function capture_warnings(callback)
    local messages = {}
    local original = vim.notify
    vim.notify = function(message, level)
        table.insert(messages, { message = message, level = level })
    end

    local ok, err = pcall(callback)
    vim.notify = original
    if not ok then
        error(err)
    end

    return messages
end

T['MarktableRowView peeks without taking focus'] = function()
    local source = source_buffer(view_table, 3)
    local source_win = vim.api.nvim_get_current_win()

    vim.cmd('MarktableRowView')

    eq(vim.api.nvim_get_current_win(), source_win)
    local wins = floating_windows()
    eq(#wins, 1)

    local view_buf = vim.api.nvim_win_get_buf(wins[1])
    eq(window_title(wins[1]), ' Markdown Table Row 1/3 ')
    eq(lines(view_buf), {
        '# Name',
        'Alpha',
        '',
        '# Notes',
        'one',
        'two',
    })
    eq(vim.bo[view_buf].modifiable, false)
    eq(vim.bo[view_buf].buftype, 'nofile')
    eq(vim.bo[view_buf].filetype, 'markdown')
    eq(lines(source), view_table)

    -- Sized to content: the title is the widest line, one row per line.
    local win_config = vim.api.nvim_win_get_config(wins[1])
    eq(win_config.width, #' Markdown Table Row 1/3 ')
    eq(win_config.height, 6)
end

T['MarktableRowView peek closes when the source cursor moves'] = function()
    local source = source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    eq(#floating_windows(), 1)

    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = source })

    eq(#floating_windows(), 0)
end

T['MarktableRowView twice focuses the view for browsing'] = function()
    source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    local view_win = floating_windows()[1]
    vim.cmd('MarktableRowView')

    eq(vim.api.nvim_get_current_win(), view_win)
end

T['MarktableRowView navigates rows and stops at the bounds'] = function()
    source_buffer(view_table, 3)
    local source_win = vim.api.nvim_get_current_win()

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    local view_win = vim.api.nvim_get_current_win()

    press('[r')
    eq(window_title(view_win), ' Markdown Table Row 1/3 ')

    press(']r')
    eq(window_title(view_win), ' Markdown Table Row 2/3 ')
    eq(lines(0), {
        '# Name',
        'Beta',
        '',
        '# Notes',
        'b|c',
    })
    eq(vim.api.nvim_win_get_cursor(source_win), { 4, 0 })

    press(']r')
    press(']r')
    eq(window_title(view_win), ' Markdown Table Row 3/3 ')
    eq(lines(0)[2], 'Gamma')
    eq(vim.api.nvim_win_get_cursor(source_win), { 5, 0 })

    press('[r')
    eq(window_title(view_win), ' Markdown Table Row 2/3 ')
end

local function anchor_corner(win)
    local win_config = vim.api.nvim_win_get_config(win)
    return { win_config.anchor, math.floor(win_config.row), math.floor(win_config.col) }
end

T['MarktableRowView e opens the editor in place of the view'] = function()
    source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    press(']r')
    local view_corner = anchor_corner(0)
    vim.api.nvim_win_set_cursor(0, { 5, 1 })
    press('e')

    eq(vim.bo.buftype, 'acwrite')
    eq(window_title(0), ' Edit Markdown Table Row 2 ')
    eq(lines(0)[2], 'Beta')
    eq(#floating_windows(), 1)
    eq(anchor_corner(0), view_corner)
    eq(vim.api.nvim_win_get_cursor(0), { 5, 1 })
end

T['MarktableRowView insert keys edit the shown row in insert mode'] = function()
    local cases = {
        { keys = 'Aend', cursor = { 5, 0 }, line = 5, expected = 'oneend' },
        { keys = 'iX', cursor = { 5, 1 }, line = 5, expected = 'oXne' },
        { keys = 'onew', cursor = { 5, 0 }, line = 6, expected = 'new' },
        { keys = 'Onew', cursor = { 5, 0 }, line = 5, expected = 'new' },
    }

    for _, case in ipairs(cases) do
        source_buffer(view_table, 3)
        vim.cmd('MarktableRowView')
        vim.cmd('MarktableRowView')
        vim.api.nvim_win_set_cursor(0, case.cursor)

        -- Typed in one go: text after the insert key must land in the editor.
        press(case.keys)

        eq(vim.bo.buftype, 'acwrite')
        eq(lines(0)[case.line], case.expected)
        vim.api.nvim_win_close(0, true)
    end
end

T['MarktableRowView q and Esc close the view and return to the source'] = function()
    source_buffer(view_table, 3)
    local source_win = vim.api.nvim_get_current_win()

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    press(']r')
    press('q')

    eq(#floating_windows(), 0)
    eq(vim.api.nvim_get_current_win(), source_win)
    eq(vim.api.nvim_win_get_cursor(source_win), { 4, 0 })

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    press('<Esc>')

    eq(#floating_windows(), 0)
    eq(vim.api.nvim_get_current_win(), source_win)
end

T['MarktableRowView closes when focus leaves the view'] = function()
    source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    vim.cmd('wincmd p')

    eq(#floating_windows(), 0)
end

T['MarktableRowView warns outside data rows and opens nothing'] = function()
    local cases = {
        { lines = view_table, cursor = 1, message = 'Cursor must be on a Markdown table data row' },
        { lines = view_table, cursor = 2, message = 'Cursor must be on a Markdown table data row' },
        { lines = { 'plain text' }, cursor = 1, message = 'Cursor line is not a Markdown table row' },
        {
            lines = { '| A | A |', '| --- | --- |', '| x | y |' },
            cursor = 3,
            message = nil,
        },
    }

    for _, case in ipairs(cases) do
        local source = source_buffer(case.lines, case.cursor)
        local messages = capture_warnings(function()
            vim.cmd('MarktableRowView')
        end)

        eq(#messages, 1)
        eq(messages[1].level, vim.log.levels.WARN)
        if case.message then
            eq(messages[1].message, case.message)
        end
        eq(#floating_windows(), 0)
        eq(lines(source), case.lines)
    end
end

T['MarktableRowView inside the view warns and keeps the view open'] = function()
    source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    local view_win = vim.api.nvim_get_current_win()

    local messages = capture_warnings(function()
        vim.cmd('MarktableRowView')
    end)

    eq(#messages, 1)
    eq(messages[1].level, vim.log.levels.WARN)
    eq(vim.api.nvim_win_is_valid(view_win), true)
    eq(vim.api.nvim_get_current_win(), view_win)
end

return T
