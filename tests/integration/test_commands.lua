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

local function write_editor(replacement)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, replacement)
    local ok, err = pcall(vim.cmd, 'write')
    vim.wait(500, function()
        return vim.bo.buftype ~= 'acwrite'
    end, 10)

    return ok, err
end

T['MarktableEdit opens the current row in a section editor'] = function()
    local source = source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one<br>two |',
    }, 3)

    vim.cmd('MarktableEdit')

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

T['MarktableNew inserts after the separator when launched from the header'] = function()
    local source = source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one |',
    }, 1)

    vim.cmd('MarktableNew')

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

T['MarktableEdit keeps the editor open on invalid section order'] = function()
    local source = source_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha | one |',
    }, 3)

    vim.cmd('MarktableEdit')
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

return T
