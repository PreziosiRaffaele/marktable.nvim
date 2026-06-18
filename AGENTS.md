# AGENTS.md

## Project

This is a local Neovim plugin for editing one Markdown pipe-table row through a
floating, section-based Markdown buffer.

- Plugin root: this repository.
- Main module: `lua/marktable/init.lua`
- Table parser/renderer: `lua/marktable/table.lua`
- Startup shim: `plugin/marktable.lua`

## Source of Truth

Use `docs/spec.md` as the source of truth for product behavior, command semantics,
daemon API usage, configuration, and user-facing data flow. Do not duplicate that
content here. When behavior changes, update the spec first, then keep this file
limited to contributor workflow and engineering practices.

`README.md` is the user-facing quickstart. Keep it concise and consistent with
the spec.

## Compatibility Policy

This project is in beta. By default, do not preserve backward compatibility; prefer always clean design.
When changing or removing public commands, flags, columns, or JSON fields, update the README, spec, and this file so the supported surface is explicit.


## Folder Structure

- `plugin/marktable.lua`: Neovim startup shim. Keep it minimal; require
  the Lua module and call `setup()` only.
- `lua/marktable/init.lua`: command registration, floating editor UI,
  source-buffer anchoring, and submit/cancel behavior.
- `lua/marktable/table.lua`: Markdown table detection, row
  parsing/rendering, validation, escaping, and unescaping.
- `tests/unit/`: pure table parser/renderer tests.
- `tests/integration/`: command and floating-editor behavior tests.
- `tests/minimal_init.lua`: headless Neovim test bootstrap.
- `docs/spec.md`: canonical product and integration spec.
- `README.md`: user-facing quickstart and development commands.
- `AGENTS.md`: contributor workflow, code quality, and development guardrails.

Avoid adding new top-level directories unless they have a clear role.

## Development Practices

- Keep startup cheap. Avoid expensive work in `plugin/marktable.lua` or
  during `setup()`.
- Prefer small, local helpers over broad abstractions. Extract only when it
  reduces real duplication or clarifies a boundary.
- Add comments only for non-obvious control flow or Neovim integration
  constraints.

When creating Lua modules:

- Group code by responsibility, not by generic file type.
- Do not create huge modules that take on multiple responsibilities.
- Prefer explicit exported functions over broad utility modules.
- Keep module APIs small; do not export internals just for tests unless there is
  a clear reason.
- Use domain names for files and functions, not vague names like `helpers`,
  `utils`, or `common` unless the code is truly cross-cutting.
- Prefer plain tables and simple functions before introducing classes.
- Avoid barrel files.
- Before adding a new module, define its owner responsibility in one sentence.
  If that sentence has multiple unrelated responsibilities, split the module.

## Feature Workflow

For every new feature, follow this sequence:

1. **Draft the feature spec** — create always `docs/<feature-name>.md` in the feature branch.
   Describe the goal, configuration, behavior, and what changes `docs/spec.md` will
   need. Do not modify `docs/spec.md` yet.
2. **Develop and test** — implement the feature and verify it against the feature spec.
3. **Update the main spec** — apply the changes described in the feature spec to
   `docs/spec.md`, then delete the feature spec file.

## Testing

Tests use [`mini.test`](https://github.com/echasnovski/mini.nvim) in headless
Neovim.

- `tests/unit/test_table.lua` covers Markdown table row detection, splitting,
  escaping, rendering, separator validation, and contiguous table parsing.
- `tests/integration/test_commands.lua` drives the real commands and floating
  editor behavior against temporary buffers.
- `tests/minimal_init.lua` bootstraps runtimepath and `mini.test`.

Run the full suite with:

```sh
make test
```

On first run, `make test` clones the test-only `mini.nvim` dependency into
`deps/` at the pinned `MINI_NVIM_REF` in `Makefile`. Bump that ref deliberately
when upgrading the test dependency.

Run one file with:

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/unit/test_table.lua')"
```

## Verification

After any edit to `*.lua` files, run `make quality` before finishing. This runs
`luacheck`, `stylua --check`, and `lua-language-server`.

Run `make test` when changing plugin behavior or tests. Run `make check` when a
change affects both implementation and behavior, or before handing off a larger
change.
