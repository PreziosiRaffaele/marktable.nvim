---Floating window layout shared by the row editor and the row view.
---
---Responsibility:
---Size, place, style, and identify the plugin's floating windows.
local M = {}

---@class MarktableFloatCorner
---@field anchor 'NW'|'SW' Window corner placed at `row`/`col`.
---@field row integer Editor-relative 0-based row of the anchor corner.
---@field col integer Editor-relative 0-based column of the anchor corner.

-- Rows (or columns) taken by the single-line border, both sides together.
local border_size = 2

-- Buffer variable set on every editor and view buffer.
local plugin_buffer_var = 'marktable_float'

-- ============================================================================
-- Public API
-- ============================================================================

---Content size caps for a floating window under the current UI.
---@param config MarktableConfig Active plugin settings.
---@return integer max_width Width cap, in columns.
---@return integer max_height Height cap, in rows.
function M.size_caps(config)
    local max_width = math.min(config.width, math.max(vim.o.columns - 4, 20))
    local max_height = math.min(config.height, math.max(vim.o.lines - 6, 8))
    return max_width, max_height
end

---Content rows available to a float anchored at `row` on the given side.
---@param anchor 'NW'|'SW' `NW` grows down from `row`, `SW` grows up to it.
---@param row integer Editor-relative 0-based anchor row.
---@return integer rows Available content rows; may be less than 1.
function M.room(anchor, row)
    if anchor == 'SW' then
        return row - border_size
    end

    return vim.o.lines - vim.o.cmdheight - row - border_size
end

---Rightmost column at which a float of `width` still fits on screen.
---@param width integer Content width, in columns.
---@return integer col Editor-relative 0-based column.
function M.max_col(width)
    return math.max(vim.o.columns - width - border_size, 0)
end

---Base `nvim_open_win` config shared by every plugin float.
---@return table config Editor-relative, minimal, bordered window config.
function M.base_config()
    return {
        relative = 'editor',
        style = 'minimal',
        border = 'single',
        title_pos = 'center',
    }
end

---Apply the window options shared by every plugin float.
---@param win integer Floating window handle.
---@return nil
function M.set_window_options(win)
    vim.wo[win].linebreak = true
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].wrap = true
end

---Mark a buffer as an editor or view buffer of this plugin.
---@param buf integer Buffer handle.
---@return nil
function M.mark_plugin_buffer(buf)
    vim.b[buf][plugin_buffer_var] = true
end

---Check whether a buffer is an editor or view buffer of this plugin.
---@param buf integer Buffer handle.
---@return boolean owned True for the plugin's own float buffers.
function M.is_plugin_buffer(buf)
    return vim.b[buf][plugin_buffer_var] == true
end

return M
