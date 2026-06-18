---Floating editor commands for one Markdown pipe-table row.
---
---Responsibility:
---Expose row-first Markdown table editing commands while keeping parsing and
---rendering delegated to `marktable.table`.
local M = {}

local markdown_table = require('marktable.table')

local namespace = vim.api.nvim_create_namespace('marktable')

---@class MarkdownTableEditorContext
---@field source_buf integer Markdown buffer being edited.
---@field source_win integer Window that launched the editor.
---@field table_info MarkdownTable Parsed table metadata from editor open time.
---@field mark_id integer Extmark tracking the replacement or insertion anchor.
---@field mode 'edit'|'new' Submit behavior.

-- ============================================================================
-- Local helpers
-- ============================================================================

---Notify a predictable command failure without changing the source buffer.
---@param message string Message to show.
---@return nil
local function warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

---Notify a submit failure while keeping the row editor open.
---@param message string Message to show.
---@return nil
local function error_notify(message)
    vim.notify(message, vim.log.levels.ERROR)
end

---Split a possibly multi-line cell value into editor lines.
---@param value string Cell value.
---@return string[] lines Editor lines.
local function split_cell_lines(value)
    if value == '' then
        return {}
    end

    return vim.split(value, '\n', { plain = true })
end

---Build row-editor source lines from table headers and optional cell values.
---@param headers string[] Table headers in order.
---@param cells string[]|nil Existing cell values, or nil for a new row.
---@return string[] lines Editor buffer lines.
local function build_editor_lines(headers, cells)
    local lines = {}

    for index, header in ipairs(headers) do
        table.insert(lines, '# ' .. header)

        for _, value_line in ipairs(split_cell_lines(cells and cells[index] or '')) do
            table.insert(lines, value_line)
        end

        if index < #headers then
            table.insert(lines, '')
        end
    end

    return lines
end

---Map a known section heading line back to its table column index.
---@param headers string[] Table headers in order.
---@param line string Editor line.
---@return integer|nil index Matching header index, or nil for non-section lines.
local function known_heading_index(headers, line)
    local label = line:match('^#%s+(.+)%s*$')
    if not label then
        return nil
    end

    label = vim.trim(label)
    for index, header in ipairs(headers) do
        if label == header then
            return index
        end
    end

    return nil
end

---Copy a line range into a new table.
---@param lines string[] Source lines.
---@param first integer First 1-based line index.
---@param last integer Last 1-based line index.
---@return string[] slice Copied lines.
local function slice_lines(lines, first, last)
    local slice = {}

    if first > last then
        return slice
    end

    for index = first, last do
        table.insert(slice, lines[index])
    end

    return slice
end

---Trim leading and trailing blank lines from a section body.
---@param lines string[] Section body lines.
---@return string[] trimmed Body lines without outer blanks.
local function trim_section_body(lines)
    local first = 1
    local last = #lines

    while first <= last and vim.trim(lines[first]) == '' do
        first = first + 1
    end

    while last >= first and vim.trim(lines[last]) == '' do
        last = last - 1
    end

    return slice_lines(lines, first, last)
end

---Describe an expected section heading for errors.
---@param header string Header label.
---@return string text Formatted section heading.
local function section_name(header)
    return '# ' .. header
end

---Parse editor source lines back into one table row's cell values.
---
---Behavior:
---Accepts the row-editor source format only. Unknown `#` headings remain part
---of the current section body; known headings must appear exactly once in table
---order.
---@param lines string[] Editor buffer lines.
---@param headers string[] Table headers in order.
---@return string[]|nil cells Parsed cell values.
---@return string|nil err Error message for invalid source format.
local function parse_editor_lines(lines, headers)
    local cells = {}
    local cursor = 1

    for expected_index, header in ipairs(headers) do
        while cursor <= #lines and vim.trim(lines[cursor]) == '' do
            cursor = cursor + 1
        end

        if cursor > #lines then
            return nil, 'Missing section: ' .. section_name(header)
        end

        local heading_index = known_heading_index(headers, lines[cursor])
        if not heading_index then
            return nil, 'Expected section: ' .. section_name(header)
        end

        if heading_index ~= expected_index then
            if heading_index < expected_index then
                return nil, 'Duplicate section: ' .. section_name(headers[heading_index])
            end

            return nil,
                string.format(
                    'Expected section %s before %s',
                    section_name(header),
                    section_name(headers[heading_index])
                )
        end

        cursor = cursor + 1
        local body_start = cursor

        while cursor <= #lines and not known_heading_index(headers, lines[cursor]) do
            cursor = cursor + 1
        end

        local body = trim_section_body(slice_lines(lines, body_start, cursor - 1))
        cells[expected_index] = table.concat(body, '\n')
    end

    while cursor <= #lines do
        local duplicate_index = known_heading_index(headers, lines[cursor])
        if duplicate_index then
            return nil, 'Duplicate section: ' .. section_name(headers[duplicate_index])
        end

        cursor = cursor + 1
    end

    return cells, nil
end

---Move focus back to the launching window when it still exists.
---@param context MarkdownTableEditorContext Editor context.
---@return nil
local function focus_source_window(context)
    if vim.api.nvim_win_is_valid(context.source_win) then
        vim.api.nvim_set_current_win(context.source_win)
    end
end

---Close the floating editor window without submitting.
---@param win integer Floating editor window handle.
---@param context MarkdownTableEditorContext Editor context.
---@return nil
local function close_editor(win, context)
    if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
    end

    focus_source_window(context)
end

---Resolve the source-buffer anchor extmark to a 0-based line number.
---@param context MarkdownTableEditorContext Editor context.
---@return integer|nil line Zero-based anchor line.
---@return string|nil err Error when the target cannot be resolved.
local function get_anchor_line(context)
    if not vim.api.nvim_buf_is_valid(context.source_buf) then
        return nil, 'Source buffer is no longer valid'
    end

    local position = vim.api.nvim_buf_get_extmark_by_id(context.source_buf, namespace, context.mark_id, {})
    if #position == 0 then
        return nil, 'Table row target is no longer available'
    end

    return position[1], nil
end

---Apply generated cells to the source Markdown buffer.
---@param context MarkdownTableEditorContext Editor context.
---@param cells string[] Plain cell values in table order.
---@return boolean ok True when the source buffer was modified.
---@return string|nil err Error when the source buffer could not be updated.
local function apply_row(context, cells)
    local anchor_line, err = get_anchor_line(context)
    if not anchor_line then
        return false, err
    end

    local line_count = vim.api.nvim_buf_line_count(context.source_buf)
    if anchor_line < 0 or anchor_line >= line_count then
        return false, 'Table row target is outside the source buffer'
    end

    local rendered_row = markdown_table.render_row(cells)

    if context.mode == 'edit' then
        vim.api.nvim_buf_set_lines(context.source_buf, anchor_line, anchor_line + 1, false, { rendered_row })
    else
        vim.api.nvim_buf_set_lines(context.source_buf, anchor_line + 1, anchor_line + 1, false, { rendered_row })
    end

    pcall(vim.api.nvim_buf_del_extmark, context.source_buf, namespace, context.mark_id)
    return true, nil
end

---Submit the editor buffer, update the source row, and close on success.
---@param editor_buf integer Floating editor buffer handle.
---@param editor_win integer Floating editor window handle.
---@param context MarkdownTableEditorContext Editor context.
---@return boolean ok True when submission succeeded.
local function submit_editor(editor_buf, editor_win, context)
    local lines = vim.api.nvim_buf_get_lines(editor_buf, 0, -1, false)
    local cells, parse_err = parse_editor_lines(lines, context.table_info.headers)
    if not cells then
        error_notify(parse_err or 'Invalid Markdown table row source')
        return false
    end

    local ok, apply_err = apply_row(context, cells)
    if not ok then
        error_notify(apply_err or 'Failed to update Markdown table row')
        return false
    end

    vim.bo[editor_buf].modified = false
    vim.schedule(function()
        close_editor(editor_win, context)
    end)

    return true
end

---Compute floating editor dimensions for the current Neovim UI.
---@param line_count integer Number of editor source lines.
---@return table config Window config for `nvim_open_win`.
local function floating_window_config(line_count)
    local max_width = math.max(vim.o.columns - 4, 20)
    local max_height = math.max(vim.o.lines - 6, 8)
    local width = math.min(96, max_width)
    local height = math.min(math.max(line_count + 2, 12), max_height)

    return {
        relative = 'editor',
        width = width,
        height = height,
        row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0),
        col = math.max(math.floor((vim.o.columns - width) / 2), 0),
        style = 'minimal',
        border = 'single',
    }
end

---Open the floating row editor for a prepared context.
---@param context MarkdownTableEditorContext Editor context.
---@param title string Floating window title.
---@param lines string[] Initial editor source lines.
---@return nil
local function open_row_editor(context, title, lines)
    local editor_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(editor_buf, 'Marktable-' .. tostring((vim.uv or vim.loop).hrtime()))

    vim.bo[editor_buf].buftype = 'acwrite'
    vim.bo[editor_buf].bufhidden = 'wipe'
    vim.bo[editor_buf].filetype = 'markdown'
    vim.bo[editor_buf].swapfile = false
    vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, lines)
    vim.bo[editor_buf].modified = false

    local config = floating_window_config(#lines)
    config.title = ' ' .. title .. ' '
    config.title_pos = 'center'

    local editor_win = vim.api.nvim_open_win(editor_buf, true, config)
    vim.wo[editor_win].linebreak = true
    vim.wo[editor_win].number = false
    vim.wo[editor_win].relativenumber = false
    vim.wo[editor_win].signcolumn = 'no'
    vim.wo[editor_win].wrap = true

    vim.api.nvim_create_autocmd('BufWriteCmd', {
        buffer = editor_buf,
        callback = function()
            submit_editor(editor_buf, editor_win, context)
        end,
    })

    vim.keymap.set('n', 'q', function()
        close_editor(editor_win, context)
    end, {
        buffer = editor_buf,
        desc = 'Cancel Marktable row editor',
        nowait = true,
        silent = true,
    })

    if #lines >= 2 then
        vim.api.nvim_win_set_cursor(editor_win, { 2, 0 })
    end
end

---Set an extmark used as the source table row anchor.
---@param buf integer Source buffer handle.
---@param line_number integer 1-based source line number.
---@return integer mark_id Extmark id.
local function set_anchor_mark(buf, line_number)
    return vim.api.nvim_buf_set_extmark(buf, namespace, line_number - 1, 0, {
        right_gravity = false,
    })
end

---Open a new-row editor for the Markdown table under the cursor.
---@return nil
local function open_new_row_editor()
    local source_buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1]
    local table_info, err = markdown_table.find_table(source_buf, cursor_line)
    if not table_info then
        warn(err or 'No supported Markdown table under cursor')
        return
    end

    local insert_after_line = cursor_line
    if cursor_line <= table_info.separator_line then
        insert_after_line = table_info.separator_line
    end

    local context = {
        source_buf = source_buf,
        source_win = source_win,
        table_info = table_info,
        mark_id = set_anchor_mark(source_buf, insert_after_line),
        mode = 'new',
    }

    open_row_editor(context, 'New Markdown Table Row', build_editor_lines(table_info.headers, nil))
end

---Open an editor for the Markdown table data row under the cursor.
---@return nil
local function open_current_row_editor()
    local source_buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1]
    local table_info, err = markdown_table.find_table(source_buf, cursor_line)
    if not table_info then
        warn(err or 'No supported Markdown table data row under cursor')
        return
    end

    if cursor_line <= table_info.separator_line then
        warn('Cursor must be on a Markdown table data row')
        return
    end

    local data_row_index = cursor_line - table_info.separator_line
    local data_row = table_info.rows[data_row_index]
    if not data_row then
        warn('Cursor must be on a Markdown table data row')
        return
    end

    local context = {
        source_buf = source_buf,
        source_win = source_win,
        table_info = table_info,
        mark_id = set_anchor_mark(source_buf, cursor_line),
        mode = 'edit',
    }

    open_row_editor(
        context,
        'Edit Markdown Table Row ' .. tostring(data_row_index),
        build_editor_lines(table_info.headers, data_row.cells)
    )
end

-- ============================================================================
-- Public API
-- ============================================================================

---Register Marktable editor commands.
---
---Side effects:
---Creates the `:MarktableRowNew` and `:MarktableRowEdit` user commands.
---@return nil
function M.setup()
    vim.api.nvim_create_user_command('MarktableRowNew', open_new_row_editor, {
        desc = 'Insert a new row into the Markdown table under the cursor',
    })

    vim.api.nvim_create_user_command('MarktableRowEdit', open_current_row_editor, {
        desc = 'Edit the Markdown table data row under the cursor',
    })
end

return M
