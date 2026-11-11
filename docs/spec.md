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

- `:MarktableRowNew`: find the table under the cursor, open a floating row
  editor titled `New Markdown Table Row` with one empty field per header, then
  insert a generated row.
- `:MarktableRowEdit`: find the data row under the cursor, reconstruct an
  editable source buffer from that row, show its table data-row index in the
  `Edit Markdown Table Row N` editor title, then replace only that row.
- `:MarktableRowView`: show the data row under the cursor in a read-only
  floating view without changing the buffer. If a view opened from the current
  window is already open, focus it instead. See
  [View Behavior](#view-behavior).

Submit the floating editor with `:w` or `:wq`. Cancel with `q`.

The plugin defines no default keymaps; users map the commands themselves.

The feature is local to the current Markdown buffer and has no external file
dependency.

## Configuration

`setup()` accepts an optional settings table controlling the floating window
size. Each option is optional and falls back to its default:

| Option   | Type      | Default | Meaning                                   |
| -------- | --------- | ------- | ----------------------------------------- |
| `width`  | `integer` | `110`   | Width of the floating editor, in columns. |
| `height` | `integer` | `16`    | Height of the floating editor, in rows.   |

```lua
require('marktable').setup({
  width = 110,
  height = 16,
})
```

Both values are clamped to the available UI space so the window never overflows
the screen. Content taller than the window scrolls.

The row view uses `width` and `height` as maximums and shrinks to fit its
content.

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

The row editor uses one top-level heading per table column. Row context is
shown in the floating window title rather than in the editable buffer:

```markdown
# Option
SQLite

# Description
Embedded relational database in a single file.
Useful for local notes.

# Recommendation
Preferred
```

Parsing rules:

- Leading blank lines before the first column section are ignored.
- Column sections start with `# <column header>`.
- Column heading matching is case-sensitive after trimming.
- Each table column must appear exactly once, in table order.
- A cell value is the full section body until the next known `# <column
  header>` section.
- Leading and trailing blank lines inside a section are ignored.
- Internal line breaks are preserved as cell line breaks.
- Empty fields render as empty cells.

New row template:

```markdown
# Option

# Description

# Recommendation
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

## View Behavior

The row view shows the same section format as the editor (see
[Source Format](#source-format)) in a read-only buffer (`buftype=nofile`,
`filetype=markdown`, `modifiable=false`), so it cannot be edited or written.
Its title is `Markdown Table Row N/M`, where `N` is the data-row index and `M`
is the number of data rows.

### Peek

The first `:MarktableRowView` opens the view without entering it; the cursor
stays in the source window.

- The view opens below the cursor line, or above it when there is not enough
  room below.
- Width fits the longest line and the title; height fits the soft-wrapped
  content. Both are capped by the configured `width` and `height` and by the
  available UI space.
- The view closes when, in the source buffer, the cursor moves, the text
  changes, insert mode starts, or the buffer leaves its window or is hidden.
  It also closes when focus moves to any other window.
- Only one view is open at a time; opening a new one closes the previous one.

### Browse

Running `:MarktableRowView` again from the same window while the peek is open
focuses the view. Entering the peek directly (`<C-w>w`, a mouse click) does the
same. The peek close triggers stop applying, and these buffer-local
normal-mode keys are available:

| Key                     | Action                                                            |
| ----------------------- | ----------------------------------------------------------------- |
| `]r`                    | Show the next data row.                                           |
| `[r`                    | Show the previous data row.                                       |
| `e`                     | Edit the shown row (see [Switching to edit](#switching-to-edit)). |
| `i` `a` `o` `I` `A` `O` | Edit the shown row and run the key there, entering insert mode.   |
| `q`                     | Close the view.                                                   |
| `<Esc>`                 | Close the view.                                                   |

Other normal-mode editing commands (`x`, `dd`, `p`, ...) fail because the view
buffer is not modifiable.

- Navigation stops at the first and last data rows; it does not wrap. At a
  boundary the key does nothing.
- Each step re-reads the table from the source buffer. If the table is no
  longer valid, notify with `WARN` and close the view.
- The source window cursor follows the shown row, so after closing the view the
  cursor is on the last row viewed.
- The view resizes to the new row's content and keeps its position.
- The cursor starts on the first section value (line 2), where editing usually
  starts.
- The view closes when focus leaves it.

### Switching to edit

`e` and the insert keys close the view, put the source cursor on the shown row,
and run the `:MarktableRowEdit` flow with two differences:

- The editor opens where the view was: it keeps the view's anchor corner (top
  left when the view was below the cursor, bottom left when above), uses the
  configured `width` and `height`, shifts left only as needed to fit the
  screen, and caps its height to the room on the anchored side. When that room
  cannot show the whole row (or the full configured height), the editor opens
  centered instead.
- The editor cursor starts at the view's cursor position. The editor buffer has
  the same lines as the view, so the position maps one to one.

For the insert keys, the key is then replayed in the editor as the builtin
command, so `o` opens a line below the cursor and `A` appends to it. Keys typed
right after the insert key are inserted as text.

Viewing and editing stay separate modes: the view never holds unsaved changes,
and saving and canceling follow the editor rules.

When an editor opened from the view closes, however it closes (`:w`, `:wq`,
`q`, `:q!`), the view reopens focused at the same position, showing the current
content of the edited row, with the cursor where the editor left it. The row is
tracked by the editor's anchor, so it stays correct when lines above the table
change while the editor is open. Editing several rows is then a loop of `]r`,
an insert key, the edit, and `:w`; `q` leaves the view. If the row is no longer
a supported data row, notify with `WARN` and stay in the source window. An
editor opened with `:MarktableRowEdit` still closes back to the table.

## Row Detection

From the cursor row:

1. Require the cursor line to be a Markdown table row.
2. Walk upward while lines remain Markdown table rows.
3. Walk downward while lines remain Markdown table rows.
4. Parse the first row as headers.
5. Validate the second row as the separator.
6. Validate row widths.
7. For edit and view, require the cursor to be a data row, not the header or
   separator.

## Insert Behavior

For `:MarktableRowNew`:

- If the cursor is on the header or separator row, insert after the separator.
- If the cursor is on a data row, insert below the cursor row.
- If the submitted source is invalid, keep the editor open and notify with
  `ERROR`.

For `:MarktableRowEdit`:

- Replace only the row under the cursor.
- If the cursor is outside a supported data row, notify with `WARN` and leave
  the buffer unchanged.

## Implementation

The reusable Markdown table helper module lives at:

```text
lua/marktable/table.lua
```

Responsibilities:

- Detect contiguous Markdown pipe-table blocks and the data row under a line.
- Split and render table rows.
- Escape and unescape table cells.
- Validate separator rows and row widths.

The section format module lives at:

```text
lua/marktable/sections.lua
```

It converts between one row's cell values and the sectioned `# <column header>`
lines shared by the editor and the view.

The read-only row view module lives at:

```text
lua/marktable/view.lua
```

It shows, focuses, navigates, and closes the row view float.

The floating window layout module lives at:

```text
lua/marktable/float.lua
```

It sizes, places, and styles the editor and view floats, so both use the same
size caps, border math, and window options. It also marks their buffers, so
commands can refuse to treat a plugin window as a source table.

The command module lives at:

```text
lua/marktable/init.lua
```

It registers the commands and owns the floating row editor.

Register it from the Neovim startup shim, optionally passing settings (see
[Configuration](#configuration)):

```lua
require('marktable').setup()
```

Follow the local Lua conventions: module responsibility comment, local helpers
before public `M.*`, contract comments on non-trivial functions, and verb names
for side-effecting functions.

## Edge Cases

- Canceling the editor leaves the buffer unchanged, including its anchor
  extmark, which is removed whenever the editor closes.
- Writing the editor again before it closes (`:w | w`) does not apply the row
  a second time.
- If the edited row is deleted from the source while the editor is open,
  submitting fails with `ERROR` and the editor stays open; it never writes over
  a neighboring row. An editor opened from the view that then closes warns
  instead of reopening the view on another row.
- Header or separator edit attempts warn and do not modify the buffer.
- Tables with duplicate or empty headers warn and do not modify the buffer.
- Malformed rows warn and do not modify the buffer.
- Empty submitted fields render as empty cells.
- `:MarktableRowView` on the header or separator row, outside a table, or on a
  malformed table warns and opens nothing.
- Any Marktable command run from inside an editor or view window warns and does
  nothing, even when that window's text itself looks like a table.
- If the row is no longer a supported data row when `e` or an insert key is
  pressed, the view warns and stays open instead of opening the editor.
- A table with a single data row can be viewed; `]r` and `[r` do nothing.
- Viewing never modifies the source buffer.

## Out of Scope

- Creating whole tables from scratch.
- Spreadsheet/grid editing.
- Domain-specific table generators.
- Scores, sorting, formulas, or column type inference.
- Separate source files, TSV, CSV, or build tools.
