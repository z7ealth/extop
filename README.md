<p align="center">
  <img src="priv/images/extop-logo-dark.png" alt="extop - live system monitoring, brewed in elixir" width="520">
</p>

<p align="center">
  A system monitor for Linux, built in Elixir with <a href="https://hex.pm/packages/ex_ratatui">ex_ratatui</a>.
</p>

<p align="center">
  Catppuccin Macchiato theme · live CPU/GPU/memory charts · process management · BEAM runtime stats
</p>

---

## Features

- **Dashboard** - CPU cores, memory/swap/disk gauges, GPU usage (NVIDIA, AMD, Intel), and live charts
- **Processes** - sortable table, name/user/PID filter, send signals (TERM, KILL, STOP, CONT, HUP, INT)
- **Network** - per-interface throughput and history graph
- **System** - native host info (OS, kernel, desktop, battery, IPs, …) plus live BEAM/OTP runtime metrics

## Requirements

- Linux with `/proc` and `/sys` (tested on Ubuntu)
- A terminal with true-color support
- Elixir 1.20+ (for development)

Optional: `gsettings` for GTK theme details on the System tab.

## Development

```bash
git clone <repo-url>
cd extop
mix deps.get
mix run
```

Press `q` or `Esc` to quit.

## Release

Build a standalone release:

```bash
MIX_ENV=prod mix release
```

Run it directly - no `start` subcommand needed:

```bash
./_build/prod/rel/extop/bin/extop
```

Copy `_build/prod/rel/extop` anywhere and run `bin/extop` from that directory.

Release management commands still work when passed explicitly:

```bash
./bin/extop stop
./bin/extop remote
./bin/extop version
```

## Keybindings

| Key | Action |
|-----|--------|
| `1`–`4` / `Tab` | Switch tabs |
| `q` / `Esc` | Quit |
| `↑` `↓` `j` | Scroll / select process |
| `/` | Filter processes |
| `p` `u` `n` `c` `m` | Sort by PID / user / name / CPU / mem |
| `t` `k` `s` `r` `h` `i` | Send signal to selected process |
| `r` | Refresh System tab info |

## License

See [LICENSE](LICENSE) if present.
