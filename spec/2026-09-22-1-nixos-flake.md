---
status: draft
issue: 1
intent: intent/2026-09-22-1-nixos-flake.md
---

# Spec: Install Hyprflip on NixOS through a flake

## Design

### Answers to the intent's open questions (defaults, override at review)

1. **Lua 5.5:** this branch applies the Lua requirement change from
   `build/1-nix-development-environment` exactly as that branch has it: the
   `CMakeLists.txt` hunk that replaces `lua5.4` with a Lua 5.5 search and a
   version guard. Because the hunk is identical, the two branches merge in
   either order without conflict. This task does not wait on nocstah/hyprflip#1.
2. **Default Hyprland:** the flake pins Hyprland to the same revision as
   `devenv.yaml` (`efb50993780079460b0cbed1363e2166a2de1d9f`, v0.56.2) and
   uses it for `packages` and `checks`. The NixOS and Home Manager modules
   ignore that pin and build against the consumer's own Hyprland package.

### Flake layout

New files:

- `flake.nix` and `flake.lock`
- `nix/hyprflip.nix`: builds the core plugin
- `nix/hy3.nix`: builds the patched hy3 provider
- `nix/nixos.nix`: NixOS module
- `nix/home-manager.nix`: Home Manager module

Inputs: `hyprland` pinned to the revision above, with `nixpkgs.follows =
"hyprland/nixpkgs"`, the same graph as `devenv.yaml`. Supported systems are
`x86_64-linux` and `aarch64-linux`, the systems the Hyprland flake exposes.

Outputs:

- `packages.<system>.{hyprflip, hy3, default = hyprflip}`, built against the
  pinned Hyprland. That compositor needs Glaze 7.2.0 rather than the Glaze 8
  in upstream's lock, so the flake applies the same `glaze-hyprland` override
  that `devenv.nix` uses on the #1 branch.
- `overlays.default`, which adds `hyprflip` and `hy3-hyprflip` built against
  `final.hyprland`. Users who already overlay Hyprland get a matching build.
- `nixosModules.default` and `homeManagerModules.default`.
- `checks.<system>`: both packages, plus evaluation of each module.
- `formatter.<system>`: `nixfmt-rfc-style`.

### Packages

Both derivations take `hyprland` as an argument and build with
`hyprland.stdenv`. That is the compiler the compositor was built with, and it
is required for the ABI match. Build inputs come from `hyprland.dev`,
`hyprland.buildInputs`, `lua5_5` and `libGL`. Native inputs are `cmake`,
`ninja` and `pkg-config`, plus `python3` for hy3.

- **`hyprflip`** runs the existing `CMakeLists.txt` with `BUILD_TESTING=ON`,
  and `doCheck` runs CTest (`core_test`). The CMake `install` rule puts the
  library at `lib/hyprland/plugins/hyprflip.so`. A `postInstall` symlink adds
  `lib/libhyprflip.so`, the path Home Manager derives from
  `"${pkg}/lib/lib${pname}.so"`.
- **`hy3`** (`pname = "hy3"`) fetches hy3 `42b7ed8fd9aefd3f36e5f617afd5071245c67853`
  (tag `hl0.56.0.1`) with `fetchFromGitHub` and a fixed hash. It builds
  `integrations/hy3` with `-DHY3_SOURCE_DIR` and installs `libhy3.so` to
  `lib/`. The existing `HY3_NO_VERSION_CHECK=OFF` ABI check and
  `prepare-source.py` patching stay unchanged.

**One required source change for hy3:** `integrations/hy3/CMakeLists.txt`
reads the revision with `git rev-parse`, and a Nix fetch has no `.git`.
Add an optional cache variable `HY3_SOURCE_REV`. When it is set, CMake uses
it instead of running git. The comparison against the pinned revision is
unchanged, so a wrong revision still fails. The Nix build passes the rev it
fetched, and the fixed-output hash guarantees the contents.
`scripts/build-containers` does not set the variable, so it behaves exactly
as before.

### Modules

Both modules expose `programs.hyprflip` with these options:

| Option | Default |
| --- | --- |
| `enable` | `false` |
| `containers.enable` | `false`; also builds and loads the hy3 provider |
| `hyprlandPackage` | NixOS: `config.programs.hyprland.package`. Home Manager: `config.wayland.windowManager.hyprland.package` |
| `package`, `hy3Package` | the derivations above, built with `hyprlandPackage` |

- **Home Manager:** appends to `wayland.windowManager.hyprland.plugins`,
  hyprflip first and then hy3, the order `examples/containers-trial.lua`
  requires. Home Manager already renders these as `hl.plugin.load(...)` when
  `configType = "lua"`, and as `hyprctl plugin load` for hyprlang.
- **NixOS:** nixpkgs has no Hyprland plugin option, so this module links
  `/etc/hyprflip/hyprflip.so` and `/etc/hyprflip/libhy3.so`. Users point
  `hl.plugin.load` at those stable paths. It does not edit any user config.
  A rebuild swaps the symlink to a new, immutable store path, so a library
  that is already loaded is never overwritten.

Neither module writes settings or keybindings. Users take those from
`examples/hyprflip.lua` without its `hl.plugin.load` line, as in the existing
hyprpm instructions.

If `hyprlandPackage` is not 0.56.2, CMake's `hyprland=0.56.2` check fails the
**build** with a clear message. Failing at build time is intended: it is
better than a plugin that the compositor rejects when it loads.

### Documentation

Add a "NixOS flake" section to `docs/INSTALL.md`, linked from the README's
Install section. It covers the input, the overlay, both modules, the
requirement that users run Hyprland 0.56.2, and the load snippet. Update the
Lua prerequisite to 5.5 with the same wording as the #1 branch.

## Alternatives rejected

- **Bundling the pinned Hyprland in the modules:** the plugin would not load
  into the user's actual compositor. This violates the intent.
- **`fetchgit` with `leaveDotGit = true` to satisfy `git rev-parse`:**
  a `.git` directory makes the hash non-deterministic, which nixpkgs
  documents as unreliable.
- **Dropping the hy3 revision check under Nix:** it guards the patch set.
  The cache variable keeps the check.
- **Rebasing onto the #1 branch:** you chose to branch from main. The
  identical Lua hunk achieves the same without coupling the branches.
- **A NixOS module that writes into the user's Hyprland config:** the config
  lives in `$HOME`, which is Home Manager's job.
- **Packaging the Python helpers or the OmaCards panel:** out of scope in the
  intent.

## Risks

- **This host cannot load the build.** It runs Hyprland 0.56.0 (`23118f9`),
  so with the host's package the modules fail the build by design. Runtime
  proof comes from a nested 0.56.2 session, not the desktop.
- **Glaze workaround in two places.** The override is duplicated between the
  flake and `devenv.nix` on #1. If the Hyprland pin moves, both must change.
  A follow-up could make `devenv.nix` consume `overlays.default`.
- **Docs merge conflict.** Both branches edit `docs/INSTALL.md` and
  `README.md`, so merging the second one needs a small manual resolution.
- **Cold builds are expensive.** Without binary substitutes, the pinned
  Hyprland builds from source; `hyprland.cachix.org` may cover it.
- **hy3 build in the sandbox is untested.** Its upstream CMake has never been
  built under Nix here and may need extra build inputs.

## Verification

1. `nix flake check` passes on x86_64-linux. This builds both packages, runs
   CTest and evaluates both modules.
2. `nix build .#hyprflip .#hy3`, then:
   - `lib/libhyprflip.so` and `lib/libhy3.so` exist;
   - `readelf -d` shows Lua 5.5 and no Lua 5.4;
   - `nm -D` shows the plugin entry points.
3. `scripts/build-containers` still works unchanged in the devenv shell from
   #1, which proves the `HY3_SOURCE_REV` change is backward compatible.
4. Module evaluation:
   - a minimal Home Manager evaluation with `configType = "lua"` yields
     `hl.plugin.load` lines in hyprflip-then-hy3 order;
   - a NixOS evaluation yields both `/etc/hyprflip` entries;
   - `hyprlandPackage` set to a non-0.56.2 package fails with the CMake
     version message.
5. In a fresh nested 0.56.2 session (`tests/nested_session.py`), load both
   store-built libraries and run `tests/integration.py` and
   `tests/containers.py`. Check `hyprctl hyprflip status`, then shut down
   cleanly with no surviving processes.
6. `nix fmt` leaves no diff. No host plugin or configuration is changed.
