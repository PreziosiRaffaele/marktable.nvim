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

local function focus_view_on_row(source)
    eq(vim.api.nvim_get_current_buf(), source)
    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    return vim.api.nvim_get_current_win()
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
    eq(window_title(wins[1]), ' View Markdown Table Row 1/3 ')
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
    eq(win_config.width, #' View Markdown Table Row 1/3 ')
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
    eq(window_title(view_win), ' View Markdown Table Row 1/3 ')

    press(']r')
    eq(window_title(view_win), ' View Markdown Table Row 2/3 ')
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
    eq(window_title(view_win), ' View Markdown Table Row 3/3 ')
    eq(lines(0)[2], 'Gamma')
    eq(vim.api.nvim_win_get_cursor(source_win), { 5, 0 })

    press('[r')
    eq(window_title(view_win), ' View Markdown Table Row 2/3 ')
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

T['Commands inside the view warn even when the view text is a table'] = function()
    -- The Notes cell holds a whole escaped table, so the view shows real
    -- table lines that could be mistaken for a source table.
    source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| T | \\| h \\| g \\|<br>\\| --- \\| --- \\|<br>\\| 1 \\| 2 \\| |',
    }, 3)

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    local view_win = vim.api.nvim_get_current_win()
    eq(lines(0)[7], '| 1 | 2 |')
    vim.api.nvim_win_set_cursor(0, { 7, 0 })

    for _, command in ipairs({ 'MarktableRowView', 'MarktableRowEdit', 'MarktableRowNew' }) do
        local messages = capture_warnings(function()
            vim.cmd(command)
        end)

        eq(#messages, 1)
        eq(messages[1].message, 'Run Marktable commands from the Markdown buffer, not from a Marktable window')
        eq(vim.api.nvim_get_current_win(), view_win)
        eq(#floating_windows(), 1)
    end
end

T['MarktableRowView peek closes when the source text changes'] = function()
    local source = source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')

    -- A TextChanged for a change made before the peek opened keeps it open.
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = source })
    eq(#floating_windows(), 1)

    vim.api.nvim_buf_set_text(source, 2, 2, 2, 7, { '' })
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = source })
    eq(#floating_windows(), 0)
end

T['MarktableRowView edit keys keep the view open when the row is no longer valid'] = function()
    local source = source_buffer(view_table, 3)
    local view_win = focus_view_on_row(source)

    -- Break the table while the view is open: the row loses a cell.
    vim.api.nvim_buf_set_lines(source, 2, 3, false, { '| Alpha |' })
    local messages = capture_warnings(function()
        press('i')
    end)

    eq(#messages, 1)
    eq(messages[1].level, vim.log.levels.WARN)
    eq(vim.api.nvim_get_current_win(), view_win)
    eq(window_title(0), ' View Markdown Table Row 1/3 ')
    eq(#floating_windows(), 1)
end

T['Canceling the editor removes its anchor extmark'] = function()
    local source = source_buffer(view_table, 3)
    local namespace = vim.api.nvim_get_namespaces().marktable

    vim.cmd('MarktableRowEdit')
    eq(#vim.api.nvim_buf_get_extmarks(source, namespace, 0, -1, {}), 1)
    press('q')
    eq(#vim.api.nvim_buf_get_extmarks(source, namespace, 0, -1, {}), 0)

    local view_win = focus_view_on_row(source)
    press('e')
    press('q')
    eq(#vim.api.nvim_buf_get_extmarks(source, namespace, 0, -1, {}), 0)
    eq(vim.api.nvim_win_is_valid(view_win), false)
end

T['Writing the editor twice before it closes applies the row once'] = function()
    local source = source_buffer({ '| A | B |', '| --- | --- |', '| 1 | 2 |' }, 3)

    vim.cmd('MarktableRowNew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# A', 'x', '', '# B', 'y' })
    -- The editor closes on a scheduled callback, so both writes run first.
    vim.cmd('write')
    vim.cmd('write')

    eq(lines(source), { '| A | B |', '| --- | --- |', '| 1 | 2 |', '| x | y |' })
end

T['Saving after the edited row was deleted fails instead of overwriting'] = function()
    local source = source_buffer({ '| A | B |', '| --- | --- |', '| 1 | 2 |', '| 3 | 4 |' }, 3)

    vim.cmd('MarktableRowEdit')
    vim.api.nvim_buf_set_lines(source, 2, 3, false, {})
    local ok, err = write_editor({ '# A', 'Z', '', '# B', 'Z' })

    eq(ok, false)
    eq(err:find('Table row target is no longer available', 1, true) ~= nil, true)
    eq(lines(source), { '| A | B |', '| --- | --- |', '| 3 | 4 |' })
end

T['MarktableRowView peek can be entered by switching windows'] = function()
    source_buffer(view_table, 3)
    local source_win = vim.api.nvim_get_current_win()

    vim.cmd('MarktableRowView')
    local view_win = floating_windows()[1]
    vim.cmd('wincmd w')

    eq(vim.api.nvim_get_current_win(), view_win)
    press(']r')
    eq(window_title(0), ' View Markdown Table Row 2/3 ')

    -- Once entered it behaves like a focused view: leaving closes it.
    vim.api.nvim_set_current_win(source_win)
    eq(#floating_windows(), 0)
end

T['MarktableRowView peek closes and reopens per window in splits'] = function()
    local source = source_buffer(view_table, 3)
    local first_win = vim.api.nvim_get_current_win()
    vim.cmd('split')
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(first_win)

    vim.cmd('MarktableRowView')
    eq(#floating_windows(), 1)

    -- Moving to the other split closes the first window's peek.
    vim.api.nvim_set_current_win(second_win)
    eq(#floating_windows(), 0)

    vim.api.nvim_win_set_cursor(second_win, { 5, 0 })
    vim.cmd('MarktableRowView')
    eq(vim.api.nvim_get_current_win(), second_win)
    eq(window_title(floating_windows()[1]), ' View Markdown Table Row 3/3 ')

    vim.cmd('MarktableRowView')
    press('[r')
    eq(vim.api.nvim_win_get_cursor(second_win)[1], 4)
    eq(vim.api.nvim_win_get_cursor(first_win)[1], 3)
    eq(vim.api.nvim_win_get_buf(first_win), source)

    -- Run in the other split without entering it (as :windo or a plugin
    -- would): it must not focus this split's peek.
    press('q')
    vim.api.nvim_set_current_win(second_win)
    vim.cmd('MarktableRowView')
    vim.api.nvim_win_set_cursor(first_win, { 3, 0 })
    vim.api.nvim_win_call(first_win, function()
        vim.cmd('MarktableRowView')
    end)
    eq(vim.api.nvim_get_current_win(), second_win)
    eq(window_title(floating_windows()[1]), ' View Markdown Table Row 1/3 ')
    vim.api.nvim_win_close(second_win, true)
end

T['MarktableRowView editor opens centered when the view side is too small'] = function()
    local original_lines = vim.o.lines
    -- With 11 screen lines and the cursor on screen row 5, the view goes below
    -- with 3 rows of room: too small for the 5-line editor content.
    vim.o.lines = 11
    local ok, err = pcall(function()
        source_buffer({ 'note', '', '| A | B |', '| --- | --- |', '| 1 | 2 |' }, 5)
        vim.cmd('MarktableRowView')
        vim.cmd('MarktableRowView')
        local view_config = vim.api.nvim_win_get_config(0)
        eq({ view_config.anchor, view_config.height }, { 'NW', 3 })

        press('e')
        local editor_config = vim.api.nvim_win_get_config(0)
        eq(vim.bo.buftype, 'acwrite')
        eq(editor_config.height, 8)
    end)
    vim.o.lines = original_lines
    if not ok then
        error(err)
    end
end

T['MarktableRowView stores a column that keeps the view on screen'] = function()
    local long = string.rep('x', 70)
    source_buffer({ '| A | B |', '| --- | --- |', '| ' .. long .. ' | 2 |' }, 3)
    vim.api.nvim_win_set_cursor(0, { 3, 72 })

    vim.cmd('MarktableRowView')
    local view_config = vim.api.nvim_win_get_config(floating_windows()[1])

    eq(view_config.col + view_config.width + 2 <= vim.o.columns, true)
end

T['MarktableRowView peek closes when its window switches to another buffer'] = function()
    local source = source_buffer(view_table, 3)
    local source_win = vim.api.nvim_get_current_win()
    vim.cmd('split')
    vim.api.nvim_set_current_win(source_win)
    local other = source_buffer({ '| X | Y |', '| --- | --- |', '| other | row |' }, 3)
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_win_set_cursor(source_win, { 3, 0 })

    vim.cmd('MarktableRowView')
    eq(#floating_windows(), 1)

    -- The source stays visible in the other split, so BufWinLeave never fires.
    vim.api.nvim_set_current_buf(other)
    eq(#floating_windows(), 0)

    vim.cmd('MarktableRowView')
    eq(window_title(floating_windows()[1]), ' View Markdown Table Row 1/1 ')
    eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(floating_windows()[1]), 1, 2, false), { 'other' })
end

T['MarktableRowView does not focus a peek left stale by typeahead'] = function()
    local source = source_buffer(view_table, 3)
    local source_win = vim.api.nvim_get_current_win()

    -- Moving the cursor without running the event loop is what a macro or
    -- mapping does: CursorMoved has not closed the peek yet.
    vim.cmd('MarktableRowView')
    vim.api.nvim_win_set_cursor(source_win, { 4, 0 })
    vim.cmd('MarktableRowView')
    eq(vim.api.nvim_get_current_win(), source_win)
    eq(window_title(floating_windows()[1]), ' View Markdown Table Row 2/3 ')

    -- Same for a text change that TextChanged has not reported yet.
    vim.api.nvim_buf_set_text(source, 3, 2, 3, 6, { 'Bet' })
    vim.cmd('MarktableRowView')
    eq(vim.api.nvim_get_current_win(), source_win)
    eq(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(floating_windows()[1]), 1, 2, false), { 'Bet' })
end

T['MarktableRowNew still inserts after its anchor row was deleted'] = function()
    local source = source_buffer({ '| A | B |', '| --- | --- |', '| 1 | 2 |', '| 3 | 4 |' }, 3)

    vim.cmd('MarktableRowNew')
    vim.api.nvim_buf_set_lines(source, 2, 3, false, {})
    local ok = write_editor({ '# A', 'x', '', '# B', 'y' })

    eq(ok, true)
    eq(lines(source), { '| A | B |', '| --- | --- |', '| 3 | 4 |', '| x | y |' })
end

T['MarktableRowView moves back right after a wide row'] = function()
    local padding = string.rep(' ', 48)
    source_buffer({
        '| A | B |',
        '| --- | --- |',
        '| a' .. padding .. '| b |',
        '| ' .. string.rep('w', 60) .. ' | b |',
        '| c | d |',
    }, 3)
    vim.api.nvim_win_set_cursor(0, { 3, 45 })

    vim.cmd('MarktableRowView')
    vim.cmd('MarktableRowView')
    local wanted = vim.api.nvim_win_get_config(0).col
    eq(wanted, 45)

    press(']r')
    eq(vim.api.nvim_win_get_config(0).col < wanted, true)
    press(']r')
    eq(vim.api.nvim_win_get_config(0).col, wanted)
end

T['MarktableRowView opens below every screen line of a wrapped row'] = function()
    -- 3 rows; the first data row wraps over 3 screen lines (screen rows 3-5).
    source_buffer({
        '| A | B |',
        '| --- | --- |',
        '| ' .. string.rep('word ', 40) .. '| b |',
        '| c | d |',
    }, 3)
    eq(vim.fn.screenpos(0, 3, 1).row, 3)

    vim.cmd('MarktableRowView')
    local view_config = vim.api.nvim_win_get_config(floating_windows()[1])

    eq({ view_config.anchor, view_config.row }, { 'NW', 5 })
end

T['MarktableRowView ]r and [r take a count'] = function()
    focus_view_on_row(source_buffer(view_table, 3))

    press('2]r')
    eq(window_title(0), ' View Markdown Table Row 3/3 ')
    press('5[r')
    eq(window_title(0), ' View Markdown Table Row 1/3 ')
end

local function footer_text(win)
    local footer = vim.api.nvim_win_get_config(win).footer
    if type(footer) == 'table' then
        return footer[1] and footer[1][1] or ''
    end

    return footer or ''
end

T['MarktableRowView shows when it has focus'] = function()
    source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    local view_win = floating_windows()[1]
    eq(vim.wo[view_win].winhighlight, 'FloatBorder:MarktableViewBorder')
    eq(footer_text(view_win), '')

    vim.cmd('MarktableRowView')
    eq(vim.wo[view_win].winhighlight, 'FloatBorder:MarktableViewFocusBorder')
    eq(footer_text(view_win), ' ]r [r · e edit · q ')

    -- The hint never widens the view: it is shorter than the title.
    eq(vim.fn.strdisplaywidth(' ]r [r · e edit · q ') < vim.fn.strdisplaywidth(window_title(view_win)), true)
end

T['MarktableRowView entered with a window command shows focus too'] = function()
    source_buffer(view_table, 3)

    vim.cmd('MarktableRowView')
    vim.cmd('wincmd w')

    eq(vim.wo.winhighlight, 'FloatBorder:MarktableViewFocusBorder')
    eq(footer_text(0), ' ]r [r · e edit · q ')
end

T['MarktableRowView highlight groups survive a color scheme change'] = function()
    source_buffer(view_table, 3)
    vim.cmd('MarktableRowView')

    vim.cmd('colorscheme default')

    eq(vim.api.nvim_get_hl(0, { name = 'MarktableViewBorder' }).link, 'FloatBorder')
    eq(vim.api.nvim_get_hl(0, { name = 'MarktableViewFocusBorder' }).link, 'Special')
end

return T
