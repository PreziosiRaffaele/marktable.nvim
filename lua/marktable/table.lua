---Markdown pipe-table parsing and rendering helpers.
---
---Responsibility:
---Detect contiguous Markdown pipe-table blocks, validate their shape, and
---convert between Markdown table rows and plain Lua cell values.
local M = {}

---@class MarkdownTableDataRow
---@field line integer 1-based source buffer line number.
---@field cells string[] Parsed table cells.

---@class MarkdownTable
---@field start_line integer 1-based table start line.
---@field end_line integer 1-based table end line.
---@field header_line integer 1-based header line.
---@field separator_line integer 1-based separator line.
---@field headers string[] Header labels in table order.
---@field rows MarkdownTableDataRow[] Data rows in table order.

-- ============================================================================
-- Local helpers
-- ============================================================================

---Check whether the pipe at `index` is escaped by an odd number of backslashes.
---@param text string Text containing the pipe.
---@param index integer 1-based byte index of the pipe character.
---@return boolean escaped True when the pipe is escaped.
local function is_escaped_pipe(text, index)
    local backslashes = 0
    local cursor = index - 1

    while cursor >= 1 and text:sub(cursor, cursor) == '\\' do
        backslashes = backslashes + 1
        cursor = cursor - 1
    end

    return backslashes % 2 == 1
end

---Count unescaped pipes in a line.
---@param text string Text to inspect.
---@return integer count Number of unescaped pipe characters.
local function count_unescaped_pipes(text)
    local count = 0

    for index = 1, #text do
        if text:sub(index, index) == '|' and not is_escaped_pipe(text, index) then
            count = count + 1
        end
    end

    return count
end

---Check whether a line has the outer-pipe shape expected for a table row.
---@param line string Line to inspect.
---@return boolean is_row True when the line looks like a Markdown pipe-table row.
local function is_markdown_pipe_row(line)
    local trimmed = vim.trim(line or '')

    if #trimmed < 2 then
        return false
    end
    if trimmed:sub(1, 1) ~= '|' then
        return false
    end
    if trimmed:sub(-1) ~= '|' or is_escaped_pipe(trimmed, #trimmed) then
        return false
    end

    return count_unescaped_pipes(trimmed) >= 2
end

---Split a string on unescaped pipe characters.
---@param text string Text between a row's outer pipes.
---@return string[] parts Raw cell strings.
local function split_unescaped_pipes(text)
    local parts = {}
    local start_index = 1

    for index = 1, #text do
        if text:sub(index, index) == '|' and not is_escaped_pipe(text, index) then
            table.insert(parts, text:sub(start_index, index - 1))
            start_index = index + 1
        end
    end

    table.insert(parts, text:sub(start_index))
    return parts
end

---Normalize CRLF/CR text to LF.
---@param text string Text to normalize.
---@return string normalized Text with LF line endings.
local function normalize_line_endings(text)
    return (text or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
end

---Check whether one separator cell is valid Markdown table separator syntax.
---@param cell string Parsed separator cell.
---@return boolean valid True when the cell is a separator marker.
local function is_separator_cell(cell)
    cell = vim.trim(cell)

    if not cell:match('^:?-+:?$') then
        return false
    end

    local _, hyphen_count = cell:gsub('%-', '')
    return hyphen_count >= 3
end

---Validate parsed table headers.
---@param headers string[] Parsed header cells.
---@return string|nil err Error message when headers are invalid.
local function validate_headers(headers)
    local seen = {}

    for _, header in ipairs(headers) do
        if header == '' then
            return 'Table headers must not be empty'
        end
        if seen[header] then
            return 'Duplicate table header: ' .. header
        end
        seen[header] = true
    end

    return nil
end

---Validate that a row has the expected number of cells.
---@param cells string[] Parsed row cells.
---@param expected_width integer Expected cell count.
---@param line_number integer 1-based source line number.
---@return string|nil err Error message when the row width is invalid.
local function validate_row_width(cells, expected_width, line_number)
    if #cells == expected_width then
        return nil
    end

    return string.format('Table row at line %d has %d cells; expected %d', line_number, #cells, expected_width)
end

---Get one line from a buffer as a string.
---@param buf integer Buffer handle.
---@param line_number integer 1-based line number.
---@return string line Buffer line, or an empty string when unavailable.
local function get_line(buf, line_number)
    return vim.api.nvim_buf_get_lines(buf, line_number - 1, line_number, false)[1] or ''
end

-- ============================================================================
-- Public API
-- ============================================================================

---Check whether a line looks like a Markdown pipe-table row.
---@param line string Line to inspect.
---@return boolean is_row True when the line has leading and trailing table pipes.
function M.is_row(line)
    return is_markdown_pipe_row(line)
end

---Unescape one parsed table cell into plain editor text.
---
---Behavior:
---Converts Markdown `<br>` row breaks back to real line breaks and unescapes
---escaped pipe characters. Does not change editor state.
---@param cell string Table cell text.
---@return string text Plain cell text.
function M.unescape_cell(cell)
    local text = normalize_line_endings(cell)
    text = text:gsub('<[bB][rR]%s*/>', '\n')
    text = text:gsub('<[bB][rR]%s*>', '\n')
    text = text:gsub('\\|', '|')

    return text
end

---Escape one plain cell value for a generated Markdown table row.
---
---Behavior:
---Escapes literal pipes and renders real line breaks as `<br>`. Does not change
---editor state.
---@param cell string Plain cell text.
---@return string markdown_cell Escaped Markdown table cell text.
function M.escape_cell(cell)
    local text = normalize_line_endings(cell)
    text = text:gsub('|', '\\|')
    text = text:gsub('\n', '<br>')

    return text
end

---Split a Markdown pipe-table row into normalized cell values.
---@param line string Markdown table row.
---@return string[]|nil cells Parsed cell values on success.
---@return string|nil err Error message when the row is malformed.
function M.split_row(line)
    local trimmed = vim.trim(line or '')
    if not is_markdown_pipe_row(trimmed) then
        return nil, 'Line is not a Markdown pipe-table row'
    end

    local inner = trimmed:sub(2, -2)
    local raw_cells = split_unescaped_pipes(inner)
    local cells = {}

    for _, raw_cell in ipairs(raw_cells) do
        table.insert(cells, M.unescape_cell(vim.trim(raw_cell)))
    end

    return cells, nil
end

---Render plain cell values as exactly one Markdown pipe-table row.
---@param cells string[] Plain cell values in table order.
---@return string row Rendered Markdown table row.
function M.render_row(cells)
    local rendered_cells = {}

    for _, cell in ipairs(cells) do
        table.insert(rendered_cells, M.escape_cell(cell))
    end

    return '| ' .. table.concat(rendered_cells, ' | ') .. ' |'
end

---Validate a parsed separator row.
---@param cells string[] Parsed separator cells.
---@return boolean valid True when every cell is a valid separator marker.
function M.is_separator(cells)
    if #cells == 0 then
        return false
    end

    for _, cell in ipairs(cells) do
        if not is_separator_cell(cell) then
            return false
        end
    end

    return true
end

---Find and validate the contiguous Markdown table block under a buffer row.
---
---Behavior:
---Reads buffer lines only. It returns a parsed table on success and `(nil, err)`
---for predictable malformed-table cases.
---@param buf integer Buffer handle.
---@param row integer 1-based cursor row.
---@return MarkdownTable|nil table_info Parsed table metadata and rows.
---@return string|nil err Error message when no supported table is under `row`.
function M.find_table(buf, row)
    if not vim.api.nvim_buf_is_valid(buf) then
        return nil, 'Invalid buffer'
    end

    local line_count = vim.api.nvim_buf_line_count(buf)
    if row < 1 or row > line_count then
        return nil, 'Cursor is outside the buffer'
    end

    if not is_markdown_pipe_row(get_line(buf, row)) then
        return nil, 'Cursor line is not a Markdown table row'
    end

    local start_line = row
    while start_line > 1 and is_markdown_pipe_row(get_line(buf, start_line - 1)) do
        start_line = start_line - 1
    end

    local end_line = row
    while end_line < line_count and is_markdown_pipe_row(get_line(buf, end_line + 1)) do
        end_line = end_line + 1
    end

    if end_line - start_line + 1 < 2 then
        return nil, 'Markdown table must have a header and separator row'
    end

    local parsed_rows = {}
    local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    for offset, line in ipairs(lines) do
        local cells, err = M.split_row(line)
        if not cells then
            return nil, string.format('Malformed table row at line %d: %s', start_line + offset - 1, err)
        end
        table.insert(parsed_rows, cells)
    end

    local headers = parsed_rows[1]
    local header_err = validate_headers(headers)
    if header_err then
        return nil, header_err
    end

    local expected_width = #headers
    local separator = parsed_rows[2]
    local separator_width_err = validate_row_width(separator, expected_width, start_line + 1)
    if separator_width_err then
        return nil, separator_width_err
    end
    if not M.is_separator(separator) then
        return nil, 'Second table row must be a Markdown separator row'
    end

    local rows = {}
    for index = 3, #parsed_rows do
        local line_number = start_line + index - 1
        local row_width_err = validate_row_width(parsed_rows[index], expected_width, line_number)
        if row_width_err then
            return nil, row_width_err
        end

        table.insert(rows, {
            line = line_number,
            cells = parsed_rows[index],
        })
    end

    return {
        start_line = start_line,
        end_line = end_line,
        header_line = start_line,
        separator_line = start_line + 1,
        headers = headers,
        rows = rows,
    },
        nil
end

return M
