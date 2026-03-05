# Copilot instructions for `nvim-flow`

## Project purpose

`nvim-flow` is a Neovim workflow runner for resolving and executing file-scoped commands from YAML.
It resolves a command for the current file from YAML config and runs it in a Neovim terminal (or debug runner).

## Core architecture

- `lua/nvim-flow/init.lua`
  - public API and `setup(opts)`
  - command entrypoints (`run`, `debug`, `preview`, `quickfix`, `toggle_lock`)
  - keymap registration
- `lua/nvim-flow/config.lua`
  - config file discovery and merge
  - match resolution and command normalization
- `lua/nvim-flow/yaml.lua`
  - lightweight YAML parser used by the plugin (no Python dependency)
  - stores map insertion order in `__order` for deterministic match behavior
- `lua/nvim-flow/path.lua`
  - shared path/context helpers (`normalize`, `build_context`, repo detection)
- `lua/nvim-flow/runner.lua`
  - terminal split execution, script creation, output capture
  - split position controlled by `terminal_position` (`top` default, `bottom` optional)
  - flow terminal buffers are tagged with `b:nvim_flow_terminal = 1` for reliable external cleanup integrations
- `lua/nvim-flow/debug_runner.lua`
  - built-in flow command parser + nvim-dap launch config assembly
  - recognizes `python`/`python3`, `uv`, and node commands for automatic DAP config generation
  - for unrecognized commands (e.g. `dotnet run`), falls through to `dap.continue()` so existing user-configured `dap.configurations` are used
- `lua/nvim-flow/preview.lua`
  - floating command preview window
- `lua/nvim-flow/quickfix.lua`
  - Python traceback parser -> quickfix list
- `plugin/nvim-flow.lua`
  - user command registration (`FlowRun`, `FlowDebug`, `FlowEdit`, etc.)

## Config behavior (important)

- Config file name defaults to `.flow.yml` (configurable).
- Discovery walks from current file's directory upward to `$HOME` (if `stop_at_home = true`).
- All found files are merged.
- Closer files take precedence over farther files.
- `FlowEdit` uses resolved `source_key` + nearest defining config file to jump to the matched `.flow.yml` line.
- Matching priority:
  1. basename
  2. `match:` entries
  3. folder name
  4. repo name
  5. extension (`.py`, then `py`)
  6. `default`
- `match` is optional.
  - If omitted, legacy key-based matching is used.
  - If present, should be string or array.

## Deterministic matching notes

- `yaml.lua` tracks key order in `__order`.
- `config.lua` uses that order when evaluating `match` entries.
- For merged files, closer file keys are promoted ahead of farther keys to keep "closer wins" deterministic.
- Parser edge-case coverage lives in `tests/nvim-flow/yaml_spec.lua`; resolution/merge behavior lives in `tests/nvim-flow/config_spec.lua`.

## Template variables

Supported command templates:

- `{{filepath}}`
- `{{dir}}`
- `{{filename}}`
- `{{ext}}`
- `{{repo}}`
- `{{folder}}`

## Runners and scope

- Supported runners:
  - terminal (`vim`/`terminal`/default)
  - debug (`debug`)
- Intentionally not supported in this project:
  - tmux runner
  - remote runners

Do not reintroduce deprecated runners without updating README, setup docs, and tests.

## Output formatting expectations

- When `show_command = true`, command text is printed followed by a separator line.
- Separator width is dynamic: command width, capped by terminal width (`tput cols` fallback).

## Testing and validation workflow

From repo root:

1. Syntax-check Lua modules:

```bash
find lua plugin tests -name '*.lua' -print | while read -r f; do lua -e "assert(loadfile('$f'))"; done
```

2. Run test suite:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/nvim-flow { minimal_init = 'tests/minimal_init.lua' }" \
  -c "qa"
```

3. Optional real-world config parse check (for local environment):

```bash
nvim --headless -u tests/minimal_init.lua -c "lua local y=require('nvim-flow.yaml'); local files=vim.fn.glob('/home/mike/git/**/.flow.yml', false, true); table.insert(files, '/home/mike/.flow.yml'); for _,f in ipairs(files) do assert(y.decode_file(f), f) end" -c "qa"
```

## Editing guidelines for contributors/LLMs

- Keep changes minimal and behavior-safe.
- Preserve backward compatibility for existing `.flow.yml` unless explicitly changing spec.
- Prefer extending tests before/with behavior changes.
- If adding new config semantics, document them in README and this file.
- Avoid adding heavy dependencies unless clearly necessary.

## Known parser boundaries

`yaml.lua` is intentionally lightweight and supports the project's real configs (maps, scalars, inline lists, block-style commands).
If advanced YAML features are required (anchors/tags/complex collections), add tests first and then decide whether to extend parser or swap parser implementation.
