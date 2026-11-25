# Install and update Blackbird

From this configured checkout:

```sh
./scripts/install-blackbird
blackbird --help
blackbird auth providers
blackbird
```

This host already includes `~/.local/bin` on `PATH`. Another host can select a
prefix with `--prefix DIRECTORY` and add its `bin` directory to `PATH`. The script
prints the installed command location; it never edits shell configuration.
`CMAKE=/absolute/path/to/cmake` selects the CMake executable. The repository's
portable `release` preset builds with Ninja and auto-discovers LLVM Clang 23 on
macOS (Homebrew `llvm`) and Linux (`clang++-23` or `clang++`, with libc++) unless
`CXX` is set explicitly. The installer itself does not install a compiler or
libraries: `scripts/bootstrap --check` reports what is missing, `scripts/bootstrap`
installs it (Homebrew or apt), and `nix build` / `nix develop` provide everything
without touching the host. The exact qualified patch releases remain pinned by
`scripts/rigor` ([tooling/README.md](../tooling/README.md)).

To build and activate the current local source again:

```sh
./scripts/install-blackbird --update
```

`--source CHECKOUT` chooses another configured local checkout; `--jobs N` controls
build parallelism (default 6). Update never fetches, resets, stashes or checks out
Git changes. Local edits are included in the build. Run source checks before
installing a changed checkout; the installer's offline smoke checks exercise
packaging, rather than replacing the development suite.

### Managing installed generations

```sh
./scripts/install-blackbird --list [--prefix DIR]
./scripts/install-blackbird --rollback [GENERATION] [--prefix DIR]
./scripts/install-blackbird --prune [--keep N] [--prefix DIR]
```

- `--list` prints all installed generations under `<prefix>/lib/blackbird/releases/`,
  marking the active `current` generation with `*` alongside its install timestamp
  and `MANIFEST` version.
- `--rollback [GENERATION]` atomically switches `current` back to the named
  generation (or the most recent previous runnable generation when `GENERATION` is
  omitted), serialized by `install.lock`.
- `--prune [--keep N]` removes older generations beyond the keep budget (default
  `3`), always preserving the active `current` generation even if it is the oldest.
  Do not prune a generation still used by a running process or a saved session
  workflow path.

The checkout's `./scripts/blackbird` also follows the managed installation at
`~/.local/bin/blackbird` when present, so an old checkout build cannot silently
replace the installed harness. Without that installation it uses the checkout's
`build/release/blackbird`. For source development, explicitly select the executable:

```sh
BLACKBIRD_EXECUTABLE="$PWD/build/debug/blackbird" ./scripts/blackbird
```

An installation under another prefix is selected through its `bin/blackbird`.
Packaged launchers stay within their own generation regardless of other installs.
An obsolete `blackbird-ui` sibling does not participate in executable selection.

Each installation builds production executables in a temporary `.build` directory
inside a fresh generation under `~/.local/lib/blackbird/releases/`, copies the lean
production binaries into `bin/` alongside copied Lua programs, assets and provider
profiles under `share/blackbird/`, and removes `.build` before activation.
This removes the running program's need for the source checkout's files. After
version, help, isolated provider-catalog and a local Lua/PTY-helper smoke succeed,
the script atomically switches `current`.
A failed build or smoke preserves the previous `current` generation. An unrelated
existing `bin/blackbird` is refused. Installations on the same prefix are serialized
with `lib/blackbird/install.lock`; remove an abandoned lock only after its installer
has exited.

The launcher preserves the working directory, exact arguments, and existing
executable or sprite environment overrides. It chooses no provider/model, reads
no other application's account cache, and changes no authentication settings.
Use the existing `blackbird auth ...` commands separately to select accounts.
Runtime state continues under `~/.local/state/blackbird`; account storage keeps
its existing location. The smoke uses its own temporary auth directory and makes
no provider request.

An invocation pins its generation for its entire lifetime, including `/restart`.
A new `blackbird` invocation uses the newly installed native program. Reopening
with `blackbird --session DIRECTORY` preserves that session's saved absolute
workflow path, which can still select the old generation's Lua. The installer
retains older generations; do not remove one used by a process or saved workflow.
To deliberately select the new packaged default for an existing conversation:

```sh
blackbird_release=$(CDPATH= cd -- "$HOME/.local/lib/blackbird/current" && pwd -P)
blackbird --session DIRECTORY --workflow "$blackbird_release/share/blackbird/programs/turn.lua"
```

Use the corresponding prefix when installing elsewhere. Resolving `current`
first pins the selected Lua to that generation. Keep an explicitly authored
workflow selected when that is the desired behavior.

Intermediate `.build` directories are pruned before activation; each generation
retains its packaged `bin/` executables, `share/blackbird/` resources, `scripts/`,
and `MANIFEST`. This is a host installation rather than a relocatable binary
distribution. macOS and Linux use their native atomic symlink-replacement flags;
other platforms are refused.

The runtime also resolves executable-owned programs/assets and helper siblings
when deliberately packaged or moved. See [portable runtime resources](PORTABLE_RUNTIME.md)
for the supported layouts, explicit overrides and saved-session limits. This does
not change the source installer or activate a new generation.
