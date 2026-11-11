---Floating editor commands for one Markdown pipe-table row.
---
---Responsibility:
---Expose row-first Markdown table commands and own the floating row editor,
---delegating table parsing to `marktable.table`, the section format to
---`marktable.sections`, and the read-only view to `marktable.view`.
local M = {}

local float = require('marktable.float')
local markdown_table = require('marktable.table')
local sections = require('marktable.sections')

local namespace = vim.api.nvim_create_namespace('marktable')

---@class MarktableConfig
---@field width integer Width of the floating editor window, in columns.
---@field height integer Height of the floating editor window, in rows.

---Default plugin settings.
---@type MarktableConfig
local defaults = {
    width = 110,
    height = 16,
}

---Active plugin settings, overridden by `setup()`.
---@type MarktableConfig
local config = vim.deepcopy(defaults)

---@class MarkdownTableEditorContext
---@field source_buf integer Markdown buffer being edited.
---@field source_win integer Window that launched the editor.
---@field table_info MarkdownTable Parsed table metadata from editor open time.
---@field mark_id integer Extmark tracking the replacement or insertion anchor.
---@field mode 'edit'|'new' Submit behavior.
---@field written_line integer|nil 0-based source line written by a successful submit.

---@class MarktableEditorOpenOpts
---@field position MarktableFloatCorner|nil Open here instead of centered.
---@field cursor integer[]|nil Initial `{ row, col }` cursor in the editor buffer.
---@field on_close fun(cursor: integer[], line: integer|nil)|nil Called after the
---editor window closes, however it was closed, with the last editor cursor and
---the 1-based source line the anchor tracked (nil when it is gone).

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

    local position = vim.api.nvim_buf_get_extmark_by_id(context.source_buf, namespace, context.mark_id, {
        details = true,
    })
    -- The anchor is invalidated when its line is deleted.
    if #position == 0 or (position[3] and position[3].invalid) then
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
        context.written_line = anchor_line
    else
        vim.api.nvim_buf_set_lines(context.source_buf, anchor_line + 1, anchor_line + 1, false, { rendered_row })
        context.written_line = anchor_line + 1
    end

    return true, nil
end

---Submit the editor buffer, update the source row, and close on success.
---@param editor_buf integer Floating editor buffer handle.
---@param editor_win integer Floating editor window handle.
---@param context MarkdownTableEditorContext Editor context.
---@return boolean ok True when submission succeeded.
local function submit_editor(editor_buf, editor_win, context)
    -- The editor closes on a scheduled callback; a second write before then
    -- (`:w | w`) must not apply the row again.
    if context.written_line then
        vim.bo[editor_buf].modified = false
        return true
    end

    local lines = vim.api.nvim_buf_get_lines(editor_buf, 0, -1, false)
    local cells, parse_err = sections.parse_lines(lines, context.table_info.headers)
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
---
---Behavior:
---Centers the editor by default. With `position`, keeps that anchor corner,
---shifts left only as needed to fit the width, and caps the height to the room
---on the anchored side. When that room cannot show the whole content (or the
---full configured height), the editor is centered instead.
---@param position MarktableFloatCorner|nil Anchor corner to open at.
---@param line_count integer Number of editor content lines.
---@return table config Window config for `nvim_open_win`.
local function floating_window_config(position, line_count)
    local width, height = float.size_caps(config)
    local win_config = float.base_config()
    win_config.width = width
    win_config.height = height

    local room = position and float.room(position.anchor, position.row) or 0
    if position and room >= math.min(height, line_count) then
        win_config.anchor = position.anchor
        win_config.row = position.row
        win_config.col = math.min(position.col, float.max_col(width))
        win_config.height = math.min(height, room)
    else
        win_config.row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0)
        win_config.col = math.max(math.floor((vim.o.columns - width) / 2), 0)
    end

    return win_config
end

---Open the floating row editor for a prepared context.
---@param context MarkdownTableEditorContext Editor context.
---@param title string Floating window title.
---@param lines string[] Initial editor source lines.
---@param opts MarktableEditorOpenOpts|nil Position and cursor overrides.
---@return nil
local function open_row_editor(context, title, lines, opts)
    opts = opts or {}

    local editor_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(editor_buf, 'Marktable-' .. tostring((vim.uv or vim.loop).hrtime()))

    vim.bo[editor_buf].buftype = 'acwrite'
    vim.bo[editor_buf].bufhidden = 'wipe'
    vim.bo[editor_buf].filetype = 'markdown'
    vim.bo[editor_buf].swapfile = false
    float.mark_plugin_buffer(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, 0, -1, false, lines)
    vim.bo[editor_buf].modified = false

    local win_config = floating_window_config(opts.position, #lines)
    win_config.title = ' ' .. title .. ' '

    local editor_win = vim.api.nvim_open_win(editor_buf, true, win_config)
    float.set_window_options(editor_win)

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

    -- However the editor closes, drop its anchor extmark and report back.
    local on_close = opts.on_close
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(editor_win),
        once = true,
        callback = function()
            local ok, cursor = pcall(vim.api.nvim_win_get_cursor, editor_win)
            -- Saving replaces the anchor's line, which invalidates the anchor.
            local row_line = context.written_line or get_anchor_line(context)
            if vim.api.nvim_buf_is_valid(context.source_buf) then
                pcall(vim.api.nvim_buf_del_extmark, context.source_buf, namespace, context.mark_id)
            end

            if on_close then
                -- Window layout changes are not allowed inside WinClosed.
                vim.schedule(function()
                    on_close(ok and cursor or { 1, 0 }, row_line and row_line + 1)
                end)
            end
        end,
    })

    local cursor = opts.cursor or sections.first_value_cursor(lines)
    vim.api.nvim_win_set_cursor(editor_win, { math.min(cursor[1], #lines), cursor[2] })
end

---Refuse to run a command from one of the plugin's own floats.
---
---Behavior:
---Editor and view text can look like a table, but it is never a source table.
---@return boolean refused True when the command must not run.
local function refuse_in_plugin_float()
    if float.is_plugin_buffer(vim.api.nvim_get_current_buf()) then
        warn('Run Marktable commands from the Markdown buffer, not from a Marktable window')
        return true
    end

    return false
end

---Set an extmark used as the source table row anchor.
---@param buf integer Source buffer handle.
---@param line_number integer 1-based source line number.
---@param invalidate boolean Invalidate the anchor when its line is deleted.
---Edited rows use it; a new row only needs a position to insert after.
---@return integer mark_id Extmark id.
local function set_anchor_mark(buf, line_number, invalidate)
    return vim.api.nvim_buf_set_extmark(buf, namespace, line_number - 1, 0, {
        right_gravity = false,
        invalidate = invalidate,
    })
end

---Open a new-row editor for the Markdown table under the cursor.
---@return nil
local function open_new_row_editor()
    if refuse_in_plugin_float() then
        return
    end

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
        mark_id = set_anchor_mark(source_buf, insert_after_line, false),
        mode = 'new',
    }

    open_row_editor(context, 'New Markdown Table Row', sections.build_lines(table_info.headers, nil))
end

---Open an editor for the Markdown table data row under the cursor.
---@param opts MarktableEditorOpenOpts|nil Position and cursor overrides.
---@return boolean opened True when the editor opened.
local function open_current_row_editor(opts)
    if refuse_in_plugin_float() then
        return false
    end

    local source_buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1]
    local table_info, data_row_index, err = markdown_table.find_data_row(source_buf, cursor_line)
    if not table_info or not data_row_index then
        warn(err or 'Cursor must be on a Markdown table data row')
        return false
    end

    local context = {
        source_buf = source_buf,
        source_win = source_win,
        table_info = table_info,
        mark_id = set_anchor_mark(source_buf, cursor_line, true),
        mode = 'edit',
    }

    open_row_editor(
        context,
        'Edit Markdown Table Row ' .. tostring(data_row_index),
        sections.build_lines(table_info.headers, table_info.rows[data_row_index].cells),
        opts
    )
    return true
end

---Peek at the data row under the cursor, or focus an already open peek.
---@return nil
local function open_row_view()
    if refuse_in_plugin_float() then
        return
    end

    -- Loaded on first use to keep startup cheap.
    require('marktable.view').open_or_focus(config, open_current_row_editor)
end

-- ============================================================================
-- Public API
-- ============================================================================

---Register Marktable editor commands.
---
---Side effects:
---Merges `opts` into the active settings and creates the `:MarktableRowNew`,
---`:MarktableRowEdit`, and `:MarktableRowView` user commands.
---@param opts MarktableConfig|nil User settings overriding the defaults.
---@return nil
function M.setup(opts)
    config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

    vim.api.nvim_create_user_command('MarktableRowNew', open_new_row_editor, {
        desc = 'Insert a new row into the Markdown table under the cursor',
    })

    vim.api.nvim_create_user_command('MarktableRowEdit', function()
        open_current_row_editor()
    end, {
        desc = 'Edit the Markdown table data row under the cursor',
    })

    vim.api.nvim_create_user_command('MarktableRowView', open_row_view, {
        desc = 'View the Markdown table data row under the cursor',
    })
end

return M
