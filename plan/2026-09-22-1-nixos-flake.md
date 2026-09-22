---
status: draft
issue: 1
spec: spec/2026-09-22-1-nixos-flake.md
---

# Plan: Install Hyprflip on NixOS through a flake

Tracked as olafkfreund/nixarchy-hyprflip#1, on branch `build/1-nixos-flake`
(created from `main`). This is separate from nocstah/hyprflip#1, the
development-environment task.

## Approved decisions

- **Lua 5.5:** apply the `CMakeLists.txt` Lua hunk from
  `build/1-nix-development-environment` byte for byte, so the branches merge
  in either order:
  ```cmake
  pkg_search_module(LUA REQUIRED IMPORTED_TARGET lua5.5 lua55 lua-5.5 lua-55)
  if(LUA_VERSION VERSION_LESS 5.5 OR NOT LUA_VERSION VERSION_LESS 5.6)
    message(FATAL_ERROR "Hyprland 0.56.2 requires Lua 5.5")
  endif()
  ```
  The docs change `Lua 5.4` to `Lua 5.5`, and `lua5.4` to `lua5.5` in the
  pkg-config line, in the same places and with the same wording as that branch.
- **Flake inputs:**
  - `hyprland` pinned to `github:hyprwm/Hyprland/efb50993780079460b0cbed1363e2166a2de1d9f`
    (v0.56.2, the same pin as `devenv.yaml` and `hyprpm.toml`);
  - `nixpkgs.follows = "hyprland/nixpkgs"`;
  - systems `x86_64-linux` and `aarch64-linux`;
  - no other inputs.
- **Pinned Hyprland for `packages` and `checks`:**
  `inputs.hyprland.packages.${system}.hyprland.override { glaze-hyprland = glaze7; }`.
  `glaze7` is `(pkgs.glaze.override { enableSSL = false; }).overrideAttrs`
  with version `7.2.0`, source `stephenberry/glaze` tag `v7.2.0`, hash
  `sha256-f3NVRi3SXKo42hn0WCw7JsOK3EkdOVJIcuzhPorKjFY=`, and cmakeFlags
  `-Dglaze_ENABLE_SSL=OFF -Dglaze_DISABLE_SIMD_WHEN_SUPPORTED=ON`. This copies
  `devenv.nix` on #1.
- **Outputs:**
  - `packages.<system>.{hyprflip, hy3, default}`;
  - `overlays.default`, adding `hyprflip` and `hy3-hyprflip` built against
    `final.hyprland`;
  - `nixosModules.default` and `homeManagerModules.default`;
  - `checks.<system>`: both packages, plus both module evaluations;
  - `formatter.<system> = nixfmt-rfc-style`.
- **Package derivations:** take a `hyprland` argument and use
  `hyprland.stdenv.mkDerivation`.
  - `buildInputs`: `hyprland.dev`, `hyprland.buildInputs`, `lua5_5`, `libGL`.
  - `nativeBuildInputs`: `cmake`, `ninja`, `pkg-config`, plus `python3` for hy3.
- **`hyprflip` package:** runs the existing CMake build with
  `BUILD_TESTING=ON` and `doCheck = true`. Its `postInstall` adds the symlink
  `lib/libhyprflip.so` → `hyprland/plugins/hyprflip.so`.
- **`hy3` package** (`pname = "hy3"`):
  - source: `fetchFromGitHub` of `outfoxxed/hy3`, rev
    `42b7ed8fd9aefd3f36e5f617afd5071245c67853`, hash
    `sha256-iK0vERuy5aXisDXm/bzcJP0dgaIot5MLPoVG62DjqO4=` (prefetched);
  - builds `integrations/hy3` with `-DHY3_SOURCE_DIR=<src>` and
    `-DHY3_SOURCE_REV=<rev>`;
  - installs `libhy3.so` to `$out/lib/`.
- **`integrations/hy3/CMakeLists.txt`:** add the optional cache variable
  `HY3_SOURCE_REV`. When set, use it instead of `git rev-parse`. The
  comparison against `42b7ed8…` stays, and `scripts/build-containers` is
  unchanged.
- **Module options:** `programs.hyprflip.{enable, containers.enable,
  hyprlandPackage, package, hy3Package}`.
  - `hyprlandPackage` defaults to `config.programs.hyprland.package` (NixOS)
    or `config.wayland.windowManager.hyprland.package` (Home Manager).
  - `package` and `hy3Package` default to the derivations built with
    `hyprlandPackage`.
- **Home Manager module:** appends `[ package ] ++ optional containers.enable
  hy3Package` to `wayland.windowManager.hyprland.plugins`, hyprflip first.
- **NixOS module:** sets `environment.etc."hyprflip/hyprflip.so".source` and,
  when containers are enabled, `"hyprflip/libhy3.so"`. It writes no user
  config, settings or keybindings.
- **Version mismatch:** a consumer Hyprland that isn't 0.56.2 fails at CMake
  configure. This is intended.
- **Out of scope:** the Python helpers, OmaCards, Omarchy menus, and any
  change to the host desktop.

## Steps

1. **`CMakeLists.txt`:** apply the Lua 5.5 hunk.
   - Verify: `git diff build/1-nix-development-environment -- CMakeLists.txt`
     is empty.
2. **`integrations/hy3/CMakeLists.txt`:** wrap the `execute_process(git …)`
   in `if(HY3_SOURCE_REV)` … `else()`, setting `HY3_REV` from the variable.
   - Verify: a CMake configure with a wrong `-DHY3_SOURCE_REV` still fails
     with the existing revision message (checked in step 7).
3. **`nix/hyprflip.nix`:** write the core derivation.
   - Verify: `nix build .#hyprflip` succeeds, CTest runs in `checkPhase`, and
     both `lib/libhyprflip.so` and `lib/hyprland/plugins/hyprflip.so` exist.
4. **`nix/hy3.nix`:** write the provider derivation.
   - Verify: `nix build .#hy3` succeeds and `lib/libhy3.so` exists.
5. **`nix/nixos.nix` and `nix/home-manager.nix`:** write the two modules.
   - Verify: the module checks in step 6 evaluate.
6. **`flake.nix`:** add inputs, packages, overlay, modules, formatter and
   checks, then generate `flake.lock`.
   - NixOS check: `nixpkgs.lib.nixosSystem` with the module enabled and
     containers on, with `boot.isContainer = true` and `fileSystems` stubbed.
     Assert both `environment.etc` entries point into the package outputs.
   - Home Manager check: `lib.evalModules` over the module plus a stub
     declaring `wayland.windowManager.hyprland.{package, plugins}`. Assert
     the plugins order. The flake gets no home-manager input.
   - Verify: `nix flake check` passes, and `flake.lock` pins Hyprland to
     `efb5099` and nixpkgs to `e72e4f2`.
7. **hy3 backward compatibility:** in a worktree of
   `build/1-nix-development-environment`, copy the updated
   `integrations/hy3/CMakeLists.txt` in, then run `./scripts/build-containers`
   inside `devenv shell`. Then configure once with
   `-DHY3_SOURCE_REV=0000000000000000000000000000000000000000`.
   - Verify: the build succeeds without the variable, and fails with the
     revision message when the variable is wrong. Remove the worktree afterwards.
8. **`docs/INSTALL.md` and `README.md`:** add the "NixOS flake" section
   (input, overlay, both modules, the 0.56.2 requirement, the `hl.plugin.load`
   snippet for `/etc/hyprflip/…`), link it from the README Install section,
   and apply the Lua 5.5 wording.
   - Verify: every link anchor resolves (`grep` for the heading), and
     `nix fmt` leaves no diff.
9. **Runtime check** in a nested 0.56.2 session, using the #1 worktree's
   `devenv shell` for the compositor. Start
   `tests/nested_session.py --directory /tmp/hfn-<n>`, then run
   `tests/integration.py <session> --plugin <store>/lib/libhyprflip.so`.
   In a fresh session, run `tests/containers.py <session> --plugin … --hy3
   <store>/lib/libhy3.so`.
   - Verify: both pass, `hyprctl hyprflip status` responds, and no nested
     processes are left afterwards. Record the results in `TESTING.md`.

## Tests

| Command | Expected |
| --- | --- |
| `nix flake check` | passes (both packages including CTest, both module evaluations) |
| `nix build .#hyprflip .#hy3` | succeeds |
| `readelf -d result*/lib/*.so \| grep -i lua` | only `liblua5.5` / `liblua.so.5.5`, no 5.4 |
| `nm -D result/lib/libhyprflip.so \| grep -i pluginInit` | entry point present |
| `nix build .#hyprflip --override-input hyprland github:hyprwm/Hyprland/v0.56.0` | fails at configure, `hyprland=0.56.2` not found |
| Step 7 commands | pass without the variable, fail with a wrong `HY3_SOURCE_REV` |
| Step 9 nested tests | pass, clean shutdown |

## Rollback

All changes are additive, apart from the Lua hunk and the optional CMake
variable. `git revert` the implementation commit, or delete the branch. Nothing
is installed on the host, and no host configuration or running compositor is
touched. Test worktrees and `/tmp/hfn-*` session directories are removed at
the end of steps 7 and 9.
