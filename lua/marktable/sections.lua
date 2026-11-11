---Row source format shared by the row editor and row view.
---
---Responsibility:
---Convert between one table row's cell values and the sectioned
---`# <column header>` buffer lines used to show and edit it.
local M = {}

-- ============================================================================
-- Local helpers
-- ============================================================================

---Split a possibly multi-line cell value into editor lines.
---@param value string Cell value.
---@return string[] lines Editor lines.
local function split_cell_lines(value)
    if value == '' then
        return {}
    end

    return vim.split(value, '\n', { plain = true })
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

-- ============================================================================
-- Public API
-- ============================================================================

---Build sectioned source lines from table headers and optional cell values.
---@param headers string[] Table headers in order.
---@param cells string[]|nil Existing cell values, or nil for a new row.
---@return string[] lines Sectioned buffer lines.
function M.build_lines(headers, cells)
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

---Cursor on the first section value, where editing a row usually starts.
---@param lines string[] Sectioned buffer lines.
---@return integer[] cursor `{ row, col }` cursor on line 2, or line 1 for a
---single-line buffer.
function M.first_value_cursor(lines)
    return { math.min(2, math.max(#lines, 1)), 0 }
end

---Parse sectioned source lines back into one table row's cell values.
---
---Behavior:
---Accepts the row-editor source format only. Unknown `#` headings remain part
---of the current section body; known headings must appear exactly once in table
---order.
---@param lines string[] Editor buffer lines.
---@param headers string[] Table headers in order.
---@return string[]|nil cells Parsed cell values.
---@return string|nil err Error message for invalid source format.
function M.parse_lines(lines, headers)
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

return M
