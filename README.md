# nvim-flow

`nvim-flow` is a Lua-only Neovim port of `vim-flow`.

## Motivation

I wanted to keep the same workflow as `vim-flow`, but remove the Python dependency and simplify maintenance.
The old extra runners (tmux + remote runners) were too complicated for my day-to-day usage, so this port focuses on the core Neovim terminal runner and debug integration.

## Features

- Pure Lua plugin (no Python provider required)
- YAML config (`.flow.yml`)
- Recursive flow discovery + merge (file dir -> `$HOME`, closer wins)
- Optional `match` arrays for reusable command definitions
- File lock support (`:FlowToggleLock`)
- Command preview in a floating window (`:FlowPreview`)
- Python traceback -> quickfix parser (`:FlowQuickfix`)
- Configurable keymaps through `setup()`

## Installation (lazy.nvim)

```lua
return {
  "mikeboiko/nvim-flow",
  dir = "~/git/OpenSource/nvim-flow",
  cmd = { "FlowRun", "FlowDebug", "FlowToggleLock", "FlowPreview", "FlowQuickfix" },
  opts = {
    config_file = ".flow.yml",
    terminal_height = 15,
    stop_at_home = true,
    show_command = true,
    keymaps = {
      run = "<CR>",
      debug = "<leader>df",
      toggle_lock = "<leader>fl",
      preview = "<leader>fp",
      quickfix = "<leader>fq",
    },
  },
}
```

## Setup

```lua
require("nvim-flow").setup({
  config_file = ".flow.yml",
  terminal_height = 15,
  stop_at_home = true,
  show_command = true,
  keymaps = {
    run = nil,
    debug = nil,
    toggle_lock = nil,
    preview = nil,
    quickfix = nil,
  },
})
```

## Commands

- `:FlowRun` - run resolved flow command in a terminal split
- `:FlowDebug` - run resolved command using your `config.dap.functions.flow_debug()` integration
- `:FlowToggleLock[ {filepath}]` - toggle lock (or set lock to explicit path)
- `:FlowSet {filepath}` - compatibility alias for setting lock directly
- `:FlowPreview` - show resolved command for current (or locked) file
- `:FlowQuickfix` - parse the last flow output as Python traceback and fill quickfix

## `.flow.yml` format

### Legacy style (still supported)

```yaml
default:
  cmd: '{{filepath}}'

py:
  cmd: python "{{filepath}}"

main.py:
  cmd: python "{{filepath}}" --mode=dev
```

### New `match` style (optional)

```yaml
python-group:
  match: [py, pyw, "test_*.py", "scripts/"]
  cmd: python "{{filepath}}"
```

If `match` is omitted, the top-level key is used as before.

### Match priority

1. basename (e.g., `main.py`)
2. `match` entries
3. folder name
4. repo name
5. filename without extension
6. extension (`.py` then `py`)
7. `default`

## Recursive merge behavior

When running from `/a/b/c/file.py`, `nvim-flow` searches for `.flow.yml` in:

- `/a/b/c/.flow.yml`
- `/a/b/.flow.yml`
- `/a/.flow.yml`
- ... up to `$HOME/.flow.yml` (if `stop_at_home = true`)

All found configs are merged. Closer files override farther files.

## Template variables

`nvim-flow` expands these variables in `cmd`:

- `{{filepath}}`
- `{{dir}}`
- `{{filename}}`
- `{{ext}}`
- `{{repo}}`
- `{{folder}}`

## Runner behavior

- Default runner: terminal split (`runner: vim` or omitted)
- Debug runner: `runner: debug` or `:FlowDebug`
- Removed from this Lua port: tmux runner, remote runners

## Quickfix behavior

`FlowQuickfix` parses the **last** `FlowRun` terminal output and extracts Python traceback lines:

`File "/path/file.py", line 42, in ...`

Then it populates and opens the quickfix list.

## Testing

This plugin uses plenary's busted harness.

Run tests:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/nvim-flow { minimal_init = 'tests/minimal_init.lua' }" \
  -c "qa"
```
