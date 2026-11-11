---Read-only floating view for one Markdown pipe-table row.
---
---Responsibility:
---Show, focus, navigate, and close the read-only row view float.
local M = {}

local float = require('marktable.float')
local markdown_table = require('marktable.table')
local sections = require('marktable.sections')

local augroup_name = 'marktable_row_view'

---@class MarktableRowView
---@field source_buf integer Markdown buffer the shown row comes from.
---@field source_win integer Window that opened the view.
---@field source_cursor integer[] Source cursor position when the peek opened.
---@field source_tick integer Source `changedtick` when the peek opened.
---@field buf integer View buffer handle.
---@field win integer View window handle.
---@field line integer 1-based source line of the shown row.
---@field corner MarktableFloatCorner Anchor corner of the view window.
---@field max_width integer Width cap.
---@field max_height integer Height cap for the chosen placement.
---@field open_editor fun(opts: MarktableEditorOpenOpts): boolean Opens the row editor for the source cursor row.

---The single open row view, if any.
---@type MarktableRowView|nil
local current = nil

-- Forward declaration: the editor launched from a view reopens it on close.
local return_to_view

-- ============================================================================
-- Local helpers
-- ============================================================================

---Notify a predictable command failure without changing the source buffer.
---@param message string Message to show.
---@return nil
local function warn(message)
    vim.notify(message, vim.log.levels.WARN)
end

---Reset the view autocmd group, removing every view autocmd.
---@return integer group Autocmd group id.
local function reset_augroup()
    return vim.api.nvim_create_augroup(augroup_name, { clear = true })
end

---Format the view window title.
---@param index integer 1-based data-row index.
---@param count integer Number of data rows in the table.
---@return string title Window title.
local function view_title(index, count)
    return string.format(' Markdown Table Row %d/%d ', index, count)
end

---Replace the read-only view buffer content.
---@param buf integer View buffer handle.
---@param lines string[] Sectioned row lines.
---@return nil
local function set_view_lines(buf, lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
end

---Compute the view width that fits its content and title.
---@param lines string[] Sectioned row lines.
---@param title string Window title.
---@param max_width integer Width cap.
---@return integer width View width, in columns.
local function content_width(lines, title, max_width)
    local width = vim.fn.strdisplaywidth(title)
    for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end

    return math.max(math.min(width, max_width), 1)
end

---Estimate the displayed height of lines soft-wrapped at `width`.
---@param lines string[] Sectioned row lines.
---@param width integer View width, in columns.
---@return integer height Estimated displayed lines.
local function estimated_height(lines, width)
    local height = 0
    for _, line in ipairs(lines) do
        height = height + math.max(math.ceil(vim.fn.strdisplaywidth(line) / width), 1)
    end

    return height
end

---Place the view below the source cursor, or above it when there is not enough room below.
---
---Behavior:
---Uses editor-relative coordinates so the view keeps its position after it
---takes focus, is resized during navigation, or is reopened after editing.
---@param source_win integer Source window handle.
---@param height integer Estimated content height.
---@param height_cap integer Configured height cap.
---@return MarktableFloatCorner corner Anchor corner for the view.
---@return integer max_height Height cap for the chosen side.
local function placement(source_win, height, height_cap)
    local cursor = vim.api.nvim_win_get_cursor(source_win)
    local screen = vim.fn.screenpos(source_win, cursor[1], cursor[2] + 1)
    -- `screen.row` is 1-based, so it is also the 0-based row below the cursor.
    local below = { anchor = 'NW', row = math.max(screen.row, 1), col = math.max(screen.col - 1, 0) }
    local above = { anchor = 'SW', row = below.row - 1, col = below.col }
    local room_below = float.room(below.anchor, below.row)
    local room_above = float.room(above.anchor, above.row)

    if room_below >= math.min(height, height_cap) or room_below >= room_above then
        return below, math.max(math.min(height_cap, room_below), 1)
    end

    return above, math.max(math.min(height_cap, room_above), 1)
end

---Cursor on the first section value, where editing usually starts.
---@param lines string[] Sectioned row lines.
---@return integer[] cursor `{ row, col }` view cursor.
local function first_value_cursor(lines)
    return { math.min(2, #lines), 0 }
end

---Shrink or grow the view height to its soft-wrapped content.
---@param view MarktableRowView Open view.
---@return nil
local function fit_height(view)
    local text_height = vim.api.nvim_win_text_height(view.win, {}).all
    vim.api.nvim_win_set_config(view.win, {
        height = math.max(math.min(text_height, view.max_height), 1),
    })
end

---Close a view, optionally returning focus to its source window.
---
---Behavior:
---Idempotent. Autocmd-driven closes pass `restore_focus = false` so the user's
---own window or buffer change is not overridden.
---@param view MarktableRowView View to close.
---@param restore_focus boolean Focus the source window when the view had focus.
---@return nil
local function close_view(view, restore_focus)
    if current ~= view then
        return
    end

    current = nil
    reset_augroup()

    local had_focus = vim.api.nvim_get_current_win() == view.win
    if vim.api.nvim_win_is_valid(view.win) then
        vim.api.nvim_win_close(view.win, true)
    end

    if restore_focus and had_focus and vim.api.nvim_win_is_valid(view.source_win) then
        vim.api.nvim_set_current_win(view.source_win)
    end
end

---Check whether the view's source window still shows the source buffer.
---@param view MarktableRowView Open view.
---@return boolean ok True when the source window can be used.
local function source_window_ready(view)
    return vim.api.nvim_win_is_valid(view.source_win) and vim.api.nvim_win_get_buf(view.source_win) == view.source_buf
end

---Show a different data row in an open view.
---@param view MarktableRowView Open view.
---@param table_info MarkdownTable Freshly parsed source table.
---@param index integer 1-based data-row index to show.
---@return nil
local function render_row(view, table_info, index)
    local lines = sections.build_lines(table_info.headers, table_info.rows[index].cells)
    local title = view_title(index, #table_info.rows)

    local width = content_width(lines, title, view.max_width)
    view.corner.col = math.min(view.corner.col, float.max_col(width))

    set_view_lines(view.buf, lines)
    vim.api.nvim_win_set_config(view.win, {
        relative = 'editor',
        anchor = view.corner.anchor,
        row = view.corner.row,
        col = view.corner.col,
        width = width,
        title = title,
        title_pos = 'center',
    })
    fit_height(view)
    vim.api.nvim_win_set_cursor(view.win, first_value_cursor(lines))
end

---Move the view by `step` data rows, stopping at the table bounds.
---@param view MarktableRowView Open view.
---@param step integer Row offset, `1` for next or `-1` for previous.
---@return nil
local function step_row(view, step)
    if current ~= view then
        return
    end

    local table_info, index, err = markdown_table.find_data_row(view.source_buf, view.line)
    if not table_info or not index then
        warn(err or 'Markdown table row is no longer available')
        close_view(view, true)
        return
    end

    local target = index + step
    local row = table_info.rows[target]
    if not row then
        return
    end

    view.line = row.line
    if source_window_ready(view) then
        vim.api.nvim_win_set_cursor(view.source_win, { row.line, 0 })
    end

    render_row(view, table_info, target)
end

---Close the view and open the row editor for the shown row in its place.
---
---Behavior:
---The editor opens at the view's anchor corner with the view's cursor, and the
---view comes back when the editor closes. When `insert_key` is given, it is
---replayed in the editor as a builtin normal-mode command, so `o` opens a line
---and `A` appends exactly as they would there.
---@param view MarktableRowView Open view.
---@param insert_key string|nil Key that entered insert mode from the view.
---@return nil
local function edit_shown_row(view, insert_key)
    if current ~= view then
        return
    end

    -- Check everything the editor needs before closing the view, so a failure
    -- leaves the view open instead of dropping it.
    if not source_window_ready(view) then
        warn('Source window is no longer available')
        return
    end

    local table_info, _, err = markdown_table.find_data_row(view.source_buf, view.line)
    if not table_info then
        warn(err or 'Markdown table row is no longer available')
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(view.win)
    close_view(view, true)
    vim.api.nvim_set_current_win(view.source_win)
    vim.api.nvim_win_set_cursor(view.source_win, { view.line, 0 })
    local opened = view.open_editor({
        position = view.corner,
        cursor = cursor,
        on_close = function(editor_cursor, line)
            return_to_view(view, editor_cursor, line)
        end,
    })
    if opened and insert_key then
        -- Insert at the front of typeahead so keys typed right after the
        -- insert key are inserted as text, not run as normal-mode commands.
        vim.api.nvim_feedkeys(insert_key, 'ni', false)
    end
end

---Install browse-mode keymaps on the view buffer.
---@param view MarktableRowView Open view.
---@return nil
local function set_view_keymaps(view)
    local function map(lhs, rhs, desc)
        vim.keymap.set('n', lhs, rhs, {
            buffer = view.buf,
            desc = desc,
            nowait = true,
            silent = true,
        })
    end

    map(']r', function()
        step_row(view, 1)
    end, 'Show next Markdown table row')
    map('[r', function()
        step_row(view, -1)
    end, 'Show previous Markdown table row')
    map('e', function()
        edit_shown_row(view, nil)
    end, 'Edit shown Markdown table row')

    for _, key in ipairs({ 'i', 'a', 'o', 'I', 'A', 'O' }) do
        map(key, function()
            edit_shown_row(view, key)
        end, 'Edit shown Markdown table row in insert mode')
    end
    map('q', function()
        close_view(view, true)
    end, 'Close Markdown table row view')
    map('<Esc>', function()
        close_view(view, true)
    end, 'Close Markdown table row view')
end

---Close the view when focus leaves it in browse mode.
---@param view MarktableRowView Focused view.
---@return nil
local function set_browse_autocmds(view)
    local group = reset_augroup()

    vim.api.nvim_create_autocmd('WinLeave', {
        group = group,
        buffer = view.buf,
        callback = function()
            close_view(view, false)
        end,
    })
end

---Close the peek when the user moves on in the source, or switch it to browse
---mode when the user enters it directly (`<C-w>w`, mouse click).
---@param view MarktableRowView Open, unfocused view.
---@return nil
local function set_peek_autocmds(view)
    local group = reset_augroup()

    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
        group = group,
        buffer = view.source_buf,
        callback = function()
            -- CursorMoved can fire for a move that happened before the peek
            -- opened; only a real change from the opening position closes it.
            local cursor = vim.api.nvim_win_get_cursor(0)
            if cursor[1] ~= view.source_cursor[1] or cursor[2] ~= view.source_cursor[2] then
                close_view(view, false)
            end
        end,
    })

    vim.api.nvim_create_autocmd('TextChanged', {
        group = group,
        buffer = view.source_buf,
        callback = function()
            -- Same as CursorMoved: ignore a change made before the peek opened.
            if vim.b[view.source_buf].changedtick ~= view.source_tick then
                close_view(view, false)
            end
        end,
    })

    -- BufWinLeave rather than BufLeave: switching windows must not close the
    -- peek before WinEnter can tell whether the user entered it.
    vim.api.nvim_create_autocmd({ 'InsertEnter', 'BufWinLeave', 'BufHidden' }, {
        group = group,
        buffer = view.source_buf,
        callback = function()
            close_view(view, false)
        end,
    })

    vim.api.nvim_create_autocmd('WinEnter', {
        group = group,
        callback = function()
            if vim.api.nvim_get_current_win() == view.win then
                set_browse_autocmds(view)
            else
                close_view(view, false)
            end
        end,
    })
end

---Move focus into an open peek, switching it to browse mode.
---@param view MarktableRowView Open, unfocused view.
---@return nil
local function focus_view(view)
    -- Drop the peek triggers first; entering is handled explicitly here.
    reset_augroup()
    vim.api.nvim_set_current_win(view.win)
    set_browse_autocmds(view)
end

---@class MarktableViewPlacement
---@field corner MarktableFloatCorner Anchor corner of the view window.
---@field max_height integer Height cap for the anchored side.

---@class MarktableViewSpec
---@field source_buf integer Markdown buffer the row comes from.
---@field source_win integer Window that opened the view.
---@field line integer 1-based source line of the row to show.
---@field table_info MarkdownTable Freshly parsed source table.
---@field index integer 1-based data-row index to show.
---@field max_width integer Width cap.
---@field height_cap integer Configured height cap, used to place a new view.
---@field placement MarktableViewPlacement|nil Reuse a placement instead of
---placing the view at the source cursor.
---@field cursor integer[]|nil View cursor; defaults to the first value line.
---@field open_editor fun(opts: MarktableEditorOpenOpts): boolean Opens the row editor for the source cursor row.

---Create an unfocused view window and make it the current view.
---@param spec MarktableViewSpec What to show and where.
---@return MarktableRowView view New current view.
local function create_view(spec)
    if current then
        close_view(current, false)
    end

    local lines = sections.build_lines(spec.table_info.headers, spec.table_info.rows[spec.index].cells)
    local title = view_title(spec.index, #spec.table_info.rows)
    local width = content_width(lines, title, spec.max_width)

    local corner, max_height
    if spec.placement then
        corner, max_height = vim.deepcopy(spec.placement.corner), spec.placement.max_height
    else
        corner, max_height = placement(spec.source_win, estimated_height(lines, width), spec.height_cap)
    end
    -- Store the position Neovim will actually use, so the editor opens there.
    corner.col = math.min(corner.col, float.max_col(width))

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    float.mark_plugin_buffer(buf)
    set_view_lines(buf, lines)
    vim.bo[buf].filetype = 'markdown'

    local win_config = float.base_config()
    win_config.anchor = corner.anchor
    win_config.row = corner.row
    win_config.col = corner.col
    win_config.width = width
    -- fit_height sets the real height once the window can measure its text.
    win_config.height = 1
    win_config.focusable = true
    win_config.title = title
    local win = vim.api.nvim_open_win(buf, false, win_config)
    float.set_window_options(win)

    ---@type MarktableRowView
    local view = {
        source_buf = spec.source_buf,
        source_win = spec.source_win,
        source_cursor = vim.api.nvim_win_get_cursor(spec.source_win),
        source_tick = vim.b[spec.source_buf].changedtick,
        buf = buf,
        win = win,
        line = spec.line,
        corner = corner,
        max_width = spec.max_width,
        max_height = max_height,
        open_editor = spec.open_editor,
    }
    current = view

    fit_height(view)
    local cursor = spec.cursor or first_value_cursor(lines)
    vim.api.nvim_win_set_cursor(win, { math.min(cursor[1], #lines), cursor[2] })
    set_view_keymaps(view)

    return view
end

---Open a peek for the data row under the source cursor.
---@param config MarktableConfig Active plugin settings.
---@param open_editor fun(opts: MarktableEditorOpenOpts): boolean Opens the row editor for the source cursor row.
---@return nil
local function open_peek(config, open_editor)
    local source_buf = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    local line = vim.api.nvim_win_get_cursor(source_win)[1]
    local table_info, index, err = markdown_table.find_data_row(source_buf, line)
    if not table_info or not index then
        warn(err or 'Cursor must be on a Markdown table data row')
        return
    end

    local max_width, height_cap = float.size_caps(config)
    local view = create_view({
        source_buf = source_buf,
        source_win = source_win,
        line = line,
        table_info = table_info,
        index = index,
        max_width = max_width,
        height_cap = height_cap,
        open_editor = open_editor,
    })
    set_peek_autocmds(view)
end

---Reopen a closed view, focused, after the editor launched from it closes.
---
---Behavior:
---Shows the current content of the edited row, at the same position, with the
---cursor where the editor left it. The row is the one the editor's anchor
---tracked, so it is still right when lines above the table changed meanwhile.
---Warns and stays in the source window when the row was deleted or is no
---longer a data row.
---@param previous MarktableRowView The view that launched the editor.
---@param cursor integer[] Last editor cursor.
---@param line integer|nil 1-based source line of the edited row; nil when the
---row was deleted.
---@return nil
return_to_view = function(previous, cursor, line)
    if not source_window_ready(previous) then
        return
    end

    vim.api.nvim_set_current_win(previous.source_win)
    if not line then
        warn('Markdown table row is no longer available')
        return
    end

    local table_info, index, err = markdown_table.find_data_row(previous.source_buf, line)
    if not table_info or not index then
        warn(err or 'Markdown table row is no longer available')
        return
    end

    vim.api.nvim_win_set_cursor(previous.source_win, { line, 0 })
    local view = create_view({
        source_buf = previous.source_buf,
        source_win = previous.source_win,
        line = line,
        table_info = table_info,
        index = index,
        max_width = previous.max_width,
        height_cap = previous.max_height,
        placement = { corner = previous.corner, max_height = previous.max_height },
        cursor = cursor,
        open_editor = previous.open_editor,
    })
    focus_view(view)
end

-- ============================================================================
-- Public API
-- ============================================================================

---Peek at the data row under the cursor, or focus the open peek.
---
---Behavior:
---When a peek opened from the current window is open, focus it for browsing.
---Otherwise open a new peek, replacing any previous view. Warns and keeps any
---open view when the cursor is not on a supported data row.
---@param config MarktableConfig Active plugin settings.
---@param open_editor fun(opts: MarktableEditorOpenOpts): boolean Opens the row editor for the source cursor row.
---@return nil
function M.open_or_focus(config, open_editor)
    local view = current
    if view and vim.api.nvim_win_is_valid(view.win) and view.source_win == vim.api.nvim_get_current_win() then
        focus_view(view)
        return
    end

    open_peek(config, open_editor)
end

return M
