# Spec: marktable.nvim

## Problem

Markdown pipe tables are useful in notes, but individual rows become hard to
edit when cells contain prose, escaped pipes, or line breaks. The table itself
should remain the source of truth, but editing one row should feel like editing
plain text fields.

Use a row-first workflow:

1. Detect the Markdown table under the cursor.
2. Expand one table row into a temporary sectioned source buffer.
3. Submit the source buffer to replace or insert exactly one Markdown table row.

The feature is generic. It does not know about decisions, scores, options, or
any domain-specific table schema. Column headers define the editable fields.

## Commands

- `:MarktableNew`: find the table under the cursor, open a floating row
  editor with one empty field per header, then insert a generated row.
- `:MarktableEdit`: find the data row under the cursor, reconstruct an
  editable source buffer from that row, then replace only that row.

Submit the floating editor with `:w` or `:wq`. Cancel with `q`.

The feature is local to the current Markdown buffer and has no external file
dependency.

## Table Shape

Supported tables are ordinary Markdown pipe tables:

```markdown
| Option | Description | Recommendation |
| --- | --- | --- |
| SQLite | Embedded relational database. | Preferred |
```

Rules:

- The cursor must be inside a contiguous Markdown table block.
- The first row is the header row.
- The second row is the separator row.
- Remaining rows are data rows.
- Each data row must have the same cell count as the header.
- Header labels must be non-empty after trimming.
- Duplicate header labels are not supported.

## Source Format

The row editor uses a first-level heading for row context, then one second-level
heading per table column:

```markdown
# Row 1

## Option
SQLite

## Description
Embedded relational database in a single file.
Useful for local notes.

## Recommendation
Preferred
```

Parsing rules:

- The first non-empty line must be a `# Row N` or `# New row` heading.
- The first-level heading is editor context only; it is not written to the
  table.
- Column sections start with `## <column header>`.
- Column heading matching is case-sensitive after trimming.
- Each table column must appear exactly once, in table order.
- A cell value is the full section body until the next known `## <column
  header>` section.
- Leading and trailing blank lines inside a section are ignored.
- Internal line breaks are preserved as cell line breaks.
- Empty fields render as empty cells.

New row template:

```markdown
# New row

## Option

## Description

## Recommendation
```

## Generated Row

Submitting the editor renders exactly one Markdown table row:

```markdown
| SQLite | Embedded relational database in a single file.<br>Useful for local notes. | Preferred |
```

Cell rendering rules:

- Cell text escapes `|` as `\|`.
- Cell line breaks in the edit buffer render as `<br>`.
- Existing escaped pipes and `<br>` line breaks in table cells are normalized
  back into plain text and real line breaks when editing.
- No marker comments or hidden metadata are written.

## Row Detection

From the cursor row:

1. Require the cursor line to be a Markdown table row.
2. Walk upward while lines remain Markdown table rows.
3. Walk downward while lines remain Markdown table rows.
4. Parse the first row as headers.
5. Validate the second row as the separator.
6. Validate row widths.
7. For edit, require the cursor to be a data row, not the header or separator.

## Insert Behavior

For `:MarktableNew`:

- If the cursor is on the header or separator row, insert after the separator.
- If the cursor is on a data row, insert below the cursor row.
- If the submitted source is invalid, keep the editor open and notify with
  `ERROR`.

For `:MarktableEdit`:

- Replace only the row under the cursor.
- If the cursor is outside a supported data row, notify with `WARN` and leave
  the buffer unchanged.

## Implementation

The reusable Markdown table helper module lives at:

```text
lua/marktable/table.lua
```

Responsibilities:

- Detect contiguous Markdown pipe-table blocks.
- Split and render table rows.
- Escape and unescape table cells.
- Validate separator rows and row widths.

The command module lives at:

```text
lua/marktable/init.lua
```

Register it from the Neovim startup shim:

```lua
require('marktable').setup()
```

Follow the local Lua conventions: module responsibility comment, local helpers
before public `M.*`, contract comments on non-trivial functions, and verb names
for side-effecting functions.

## Edge Cases

- Canceling the editor leaves the buffer unchanged.
- Header or separator edit attempts warn and do not modify the buffer.
- Tables with duplicate or empty headers warn and do not modify the buffer.
- Malformed rows warn and do not modify the buffer.
- Empty submitted fields render as empty cells.

## Out of Scope

- Creating whole tables from scratch.
- Spreadsheet/grid editing.
- Domain-specific table generators.
- Scores, sorting, formulas, or column type inference.
- Separate source files, TSV, CSV, or build tools.
