<p align="center">
  <img src="assets/blackbird-readme.png" alt="Blackbird — pixel-art SR-71 in afterburner" width="560">
</p>

# Blackbird

**A native C++23 + Lua 5.5.1 coding harness and sovereign multi-agent Command Post.**

Blackbird is built for operators who want full control over the machine, programmable turn loops, model-editable live context, and cross-harness multi-agent coordination—without a JavaScript runtime, approval pageants, or lock-in to a single model vendor.

> **Full user documentation:** [multiplayer.tech/blackbird](https://multiplayer.tech/blackbird/)  
> **Live 2-player multiplayer over SSH:** [Two-Player Quickstart](docs/TWO_PLAYER_QUICKSTART.md)

---

## Install

One command from a fresh shell. Pick the row that matches your machine.

| You have | Run | You get |
| --- | --- | --- |
| macOS arm64 or Linux x86_64 | `curl -fsSL https://raw.githubusercontent.com/antimemeai/blackbird/master/scripts/install-release.sh \| sh` | The SHA-256-verified prebuilt release at `~/.local/bin/blackbird` |
| Nix | `nix profile install github:antimemeai/blackbird` | A source build on `PATH` (any macOS or Linux) |
| Nix, just trying it | `nix run github:antimemeai/blackbird` | A source build, run once, nothing installed (`#blackbird-bin` for the prebuilt) |

Then:

```sh
blackbird auth providers   # which providers have credentials
blackbird                  # start a session
```

### From a checkout

```sh
git clone https://github.com/antimemeai/blackbird && cd blackbird
```

| Toolchain | Build and install | Develop |
| --- | --- | --- |
| Nix | `nix build` → `./result/bin/blackbird` | `nix develop`, or `direnv allow` once |
| mise | `mise install && mise run deps && mise run install` | `mise run build` · `mise run test` · `mise run run` |
| Homebrew / apt | `scripts/bootstrap && scripts/install-blackbird` | `cmake --preset dev && cmake --build --preset dev` |

A source build needs LLVM Clang 23 with libc++, Lua 5.5.1, OpenSSL 3, CMake ≥ 3.28,
Ninja and Python 3; Cargo is optional and adds the iroh P2P transport.
`scripts/bootstrap --check` reports what is missing and changes nothing;
`scripts/bootstrap` installs it with Homebrew on macOS, or apt (with apt.llvm.org and a
checksum-verified Lua build) on Debian and Ubuntu. Nix needs none of this.

Nix, direnv and mise are all opt-in. `.envrc` does nothing until you `direnv allow`;
it then loads the Nix dev shell if Nix is installed, otherwise mise's tools.

`scripts/install-blackbird` builds the `release` preset, smoke-checks it offline and
atomically activates a new generation under `~/.local/lib/blackbird/` (`--prefix DIR`
to put it elsewhere). `--update`, `--list`, `--rollback [GEN]` and `--prune [--keep N]`
manage generations; see [`docs/INSTALLING.md`](docs/INSTALLING.md). Contributors:
`scripts/rigor` is the exact-version qualification gate behind the pre-commit hook;
see [`tooling/README.md`](tooling/README.md).

---

## What Blackbird Is Today

### Native Core & Programmable Lua Turn Loops
- **C++23 native engine + Lua 5.5.1 VM:** Fast, low-overhead terminal harness with zero JS/TS runtime or terminal framework underneath the conversation.
- **Turn-as-a-program ([`programs/turn.lua`](programs/turn.lua)):** Each turn retains its effective Lua source and runs in a fresh VM. Edit the loop or switch programs live with `--workflow FILE` or `/workflow FILE`, and inspect lifecycle hooks and dispatch history in `/hooks`.
- **Audited Lua bridge:** Programs and the model's `lua` tool call `blackbird.request(...)`, `blackbird.call(...)`, `blackbird.blocks(...)`, `blackbird.compact(...)`, `blackbird.read_block(...)`, `blackbird.set_blocks(...)`, `blackbird.pin(...)`, `blackbird.flush_context()`, `blackbird.append(...)`, `blackbird.stats()`, `blackbird.display(...)`, `blackbird.hooks(...)`, `blackbird.json`, `blackbird.binary`, and a read-only `os` clock/time subset (`os.time`, `os.clock`, `os.difftime`).
- **Full retained audit & native host protocol:** Every request, streamed byte, context revision, effective program, and tool outcome is retained in a bounded BBM2 journal with causal linkage, recovery controls, and a framed stdio `--application` interface ([`docs/APPLICATION_INTERFACE.md`](docs/APPLICATION_INTERFACE.md)).
- **Self-development loop:** Edit, test, build, and `/restart NOTE` to resume the same session on the replacement binary with explicit boundary fences.

### Model-Editable Live Context & Context Workbench
- **First-class context tools:** Models and Lua workflows inspect and transform active context through `context_list`, `context_compact`, and `context_read` without losing original records.
- **Revision-checked `CompactOp` operations:**

| Operation | Effect on active provider context |
| --- | --- |
| `drop` | Remove selected blocks from the active view while preserving originals. |
| `summarize` | Replace selected blocks with a summary linked to retained ancestry. |
| `restore` | Reintroduce archived originals in capture order. |
| `pin` | Protect selected blocks from `drop` and `summarize`. |
| `unpin` | Clear pin protection on selected blocks. |

- **Interactive Context Workbench (`/workbench`):** Browse live and archived blocks directly in the TUI with `F5` (`DECISION_COMPANION` advisory), `F6` (pin/unpin), `F7` (drop/restore), `F8` (flush), and `F9` (toggle archived blocks).

### 9 Coding Providers & System One Decision Companions
- **Built-in coding providers:** `openai`, `anthropic` (API-key-only), `gemini`, `kimi`, `grok`, `deepseek`, `mimo`, `moonshot`, and `openrouter`—plus custom registered `responses`, `responses-portable`, `chat`, and `messages` routes.
- **Mid-session switching:** Change route, model, or reasoning effort live with `/provider`, `/model`, and `/effort` (`blackbird auth ...` owns provider credential storage and refresh).
- **System One decision companions:** Fast structured judgment endpoints (`jev`, `clef`, and custom registered `decision` providers) accessible via `decision_model`, `blackbird.decide(...)`, `/decision`, `/companion`, and Context Workbench `F5` advisories.

### Sovereign Multi-Agent Command Post
- **Heterogeneous platoons:** Coordinate mixed agent fleets through `PlatoonBoard`, `WorktreeLeaseManager`, and `PlatoonRunner` across `blackbird`, `claude_code`, `codex`, `pi`, `antigravity`, and `acp` peers with isolated environments and git worktree leases.
- **Local project state (zero daemons):**
  - `IssueStore` (`.blackbird/issues`) — file-backed local issue tracking and dependency DAGs.
  - `ProjectMemoryStore` (`.blackbird/memory`) — structured project memory with live SHA-256 source-file staleness verification (`[fresh]` / `[stale]` / `[missing_source]` / `[unpinned]`).
  - `CapabilityCatalog` — discoverable skills/capabilities with `project > user > builtin` precedence.
  - `MetricsConsumer` — strictly read-only tertiary metrics reader preserving tri-state unknown values and rendering Unicode sparklines.
  - `NativeModuleHost` — generation-leased native hot-reload module boundary.
- **Harness-agnostic Command Post CLI:** Every subsystem is scriptable as JSON stdout from any agent or shell:

```sh
blackbird mcp           # Stdio MCP server exposing board, leases, peers, issues, memory
blackbird platoon       # Board posts/reads, roster, worktree leases, heterogeneous peer runs
blackbird issues        # Zero-daemon issue create/list/ready/show/claim/close/dep-add
blackbird memory        # Project memory record/recall/recent/get/verify (SHA-256 freshness)
blackbird peer          # Peer Ed25519 identity, key pinning, revocation, detached signatures
blackbird bridge        # Stage 0 sovereign 2-player signed NDJSON bridge over SSH/pipes
blackbird capabilities  # Inspect/expand local & builtin capabilities
blackbird metrics       # Tertiary read-only usage summary and sparklines
```

- **Live TUI surfaces:** Inspect and steer the Command Post directly inside a session with `/platoon`, `/issues`, `/memory`, `/capabilities`, `/metrics`, and `/companion` (alongside `/workbench`, `/hooks`, `/jobs`, `/center`, and `/views`).
- **Stage 0 sovereign 2-player multiplayer (`BoardBridge`):** Exchange signed `PeerEnvelope`s, causal events, delivery/action receipts, and presence over plain SSH or pipes with action-time unread guards and quoted untrusted-peer framing. Follow [`docs/TWO_PLAYER_QUICKSTART.md`](docs/TWO_PLAYER_QUICKSTART.md) to pair two machines in minutes.

### Supported Terminal Multiplexer: `phux`
- Verified against **`phux 0.162.0`** ([github.com/no-phux/phux](https://github.com/no-phux/phux)) via [`scripts/blackbird-phux`](scripts/blackbird-phux) and [`docs/PHUX.md`](docs/PHUX.md).
- Supports atomic session creation, `--ephemeral` sessions, per-pane agent identity (`phux agent set`), and exclusive input handoff (`phux take` / `phux give`).

---

## Quick Usage

```sh
# Start an interactive TUI session (fresh session under ~/.local/state/blackbird/)
blackbird

# One-shot plain-mode turn
blackbird --once "Inspect this repository and summarize the build."

# Select provider, model, and reasoning effort explicitly
blackbird --provider anthropic --model claude-sonnet-4-6 --effort high

# List and resume saved sessions
blackbird --list-sessions
blackbird --session ~/.local/state/blackbird/session-XXXXXX
```

Run inside a persistent [`phux`](docs/PHUX.md) pane with `./scripts/blackbird-phux blackbird`.
From a checkout, run a dev build with `BLACKBIRD_EXECUTABLE="$PWD/build/dev/blackbird" ./scripts/blackbird`.

Essential TUI keys: `Enter` submits (or queues during a turn), `Shift-Enter` / `Alt-Enter` / `Ctrl-J` inserts a newline, `Ctrl-C` stops the active turn while preserving your draft, `Ctrl-Q` exits with recoverable drafts, `Ctrl-\` opens `/views`, `Ctrl-O` toggles `/jobs`, and `Ctrl-X` toggles `/center`.

---

## Documentation

Full user guides and reference documentation live at **[multiplayer.tech/blackbird](https://multiplayer.tech/blackbird/)**. Key repository documents:

| Document | Purpose |
| --- | --- |
| [`docs/USING_BLACKBIRD.md`](docs/USING_BLACKBIRD.md) | Everyday CLI flags, TUI controls, Lua bridge, context operations, and session recovery. |
| [`docs/INSTALLING.md`](docs/INSTALLING.md) | Managed generation installs, `--update`/`--list`/`--rollback`/`--prune`, and runtime packaging. |
| [`docs/TWO_PLAYER_QUICKSTART.md`](docs/TWO_PLAYER_QUICKSTART.md) | Step-by-step live 2-player setup with `blackbird peer` and `blackbird bridge` over SSH/pipes. |
| [`docs/PHUX.md`](docs/PHUX.md) | `phux 0.162.0` service setup, `scripts/blackbird-phux`, agent identity, and pane control. |
| [`docs/TOKENOMICS.md`](docs/TOKENOMICS.md) | Provider routing, prompt-cache policies, cache affinity, and tertiary usage reporting. |
| [`docs/APPLICATION_INTERFACE.md`](docs/APPLICATION_INTERFACE.md) | Framed BBM2 stdio `--application` protocol for native host integration. |
| [`docs/CORE_DESIGN.md`](docs/CORE_DESIGN.md) | Ground-up native engine architecture, audit invariants, and custody semantics. |

---

## Repository Layout

| Path | Contents |
| --- | --- |
| [`include/blackbird/`](include/blackbird/) & [`src/`](src/) | C++23 engine, BBM2 audit journal, providers, Lua bridge, TUI, Command Post, and `BoardBridge`. |
| [`programs/`](programs/) | Default Lua 5.5.1 turn loop (`turn.lua`) and companion workflow scripts. |
| [`tests/`](tests/) | Direct behavioral, protocol, recovery, Command Post, and TUI test suites. |
| [`scripts/`](scripts/) | Launchers (`blackbird`, `blackbird-phux`), installer (`install-blackbird`), and `rigor` build/check drivers. |
| [`tooling/`](tooling/) | Compiler/sanitizer profiles, lint configs, and check procedures ([`tooling/README.md`](tooling/README.md)). |
| [`docs/`](docs/) & [`papers/`](papers/) | Operational guides, design specifications, literature syntheses, and independent reviews. |

Before committing in a fresh clone, install the tracked pre-commit hook (`scripts/install-hooks`); see [`tooling/README.md`](tooling/README.md#required-pre-commit-checks) for source vs. documentation-only checks.

---

## License

Blackbird's original software and documentation are released under the [MIT License](LICENSE).  
Copyright © 2026 Antimeme AI LLC. Third-party material retains its original license.
