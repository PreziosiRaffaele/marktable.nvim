local table_row = require('marktable.table')
local expect = MiniTest.expect
local eq = expect.equality

local T = MiniTest.new_set()

local function with_buffer(lines, row)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local table_info, err = table_row.find_table(buf, row)
    vim.api.nvim_buf_delete(buf, { force = true })

    return table_info, err
end

T['is_row()'] = MiniTest.new_set()

T['is_row()']['matches rows with unescaped outer pipes'] = function()
    eq(table_row.is_row('| Key | Value |'), true)
    eq(table_row.is_row(' | Key | Value | '), true)
end

T['is_row()']['rejects non-table lines and escaped trailing pipes'] = function()
    eq(table_row.is_row('Key | Value'), false)
    eq(table_row.is_row('| Key | Value \\|'), false)
end

T['split_row()'] = MiniTest.new_set()

T['split_row()']['trims cells and unescapes pipes and line breaks'] = function()
    local cells, err = table_row.split_row('| Alpha\\|Beta | one<br>two | three<BR/>four |')

    eq(err, nil)
    eq(cells, { 'Alpha|Beta', 'one\ntwo', 'three\nfour' })
end

T['split_row()']['returns an error for malformed rows'] = function()
    local cells, err = table_row.split_row('not a row')

    eq(cells, nil)
    eq(err, 'Line is not a Markdown pipe-table row')
end

T['render_row()'] = MiniTest.new_set()

T['render_row()']['escapes pipes and renders multiline cells'] = function()
    eq(table_row.render_row({ 'Alpha|Beta', 'one\ntwo' }), '| Alpha\\|Beta | one<br>two |')
end

T['is_separator()'] = MiniTest.new_set()

T['is_separator()']['validates Markdown separator cells'] = function()
    eq(table_row.is_separator({ '---', ':---', '---:' }), true)
    eq(table_row.is_separator({ '--', '---' }), false)
    eq(table_row.is_separator({}), false)
end

T['find_table()'] = MiniTest.new_set()

T['find_table()']['parses the contiguous table under the cursor'] = function()
    local table_info, err = with_buffer({
        'before',
        '| Name | Notes |',
        '| --- | :--- |',
        '| Alpha | one<br>two |',
        '| Beta | escaped\\|pipe |',
        'after',
    }, 4)

    eq(err, nil)
    eq(table_info.start_line, 2)
    eq(table_info.end_line, 5)
    eq(table_info.headers, { 'Name', 'Notes' })
    eq(table_info.rows[1], { line = 4, cells = { 'Alpha', 'one\ntwo' } })
    eq(table_info.rows[2], { line = 5, cells = { 'Beta', 'escaped|pipe' } })
end

T['find_table()']['rejects duplicate headers'] = function()
    local table_info, err = with_buffer({
        '| Name | Name |',
        '| --- | --- |',
        '| Alpha | Beta |',
    }, 3)

    eq(table_info, nil)
    eq(err, 'Duplicate table header: Name')
end

T['find_table()']['rejects rows with the wrong width'] = function()
    local table_info, err = with_buffer({
        '| Name | Notes |',
        '| --- | --- |',
        '| Alpha |',
    }, 3)

    eq(table_info, nil)
    eq(err, 'Table row at line 3 has 1 cells; expected 2')
end

return T
