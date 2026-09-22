---
status: approved
issue: 3
spec: spec/2026-09-22-3-hyprland-main-port.md
---

# Plan: Run Hyprflip on the Hyprland main build the desktop uses

Tracked as olafkfreund/nixarchy-hyprflip#3, on branch
`build/3-hyprland-main-port` (from `main` at `27ed6ab`).

## Approved decisions

- **Target:** Hyprland `23118f9f7f24db7447069949c2df7fcd8ba380d0` only
  (p620's lock; package `hyprland-0.56.0+date=2026-09-22_23118f9`). 0.56.2
  support is dropped. Version checks key on the commit.
- **Core port:** mechanical, with unchanged behaviour. Mappings:

  | 0.56.2 | main (`23118f9`) |
  | --- | --- |
  | `desktop/view/Window.hpp` | `desktop/view/window/Window.hpp` |
  | `desktop/Workspace.hpp` | `workspace/HLWorkspace.hpp` |
  | `CWorkspace` | `Workspace::CHLWorkspace` |
  | `SHyprCtlCommand{.exact=false,.fn}` | `IPC::Socket1::SCommand{.match=COMMAND_MATCH_PREFIX,.handler(const SRequest&)->SResponse}` |
  | `m_isMapped` | `mapped()` |
  | `m_isFloating` | `isFloating()` |
  | `m_target` (read) | `windowTarget()` / `layoutTarget()` |
  | `m_group` | `grouping()` |
  | `m_transformers` | `effects().transformers()` |
  | `resetMotionBlur()` | `effects().resetMotionBlur()` |
  | decorations | `presentation().add/containsDecoration/removeDecoration` |
  | `m_floatingOffset` | `presentation().floatingOffset()` |
  | `canBeGroupedInto` | `grouping().canBeGroupedInto()` |
  | `CGroup::m_target` | `target()` |
  | workspace `m_id`, `m_space`, `m_visible` | `id()`, `space()`, `visible()` |
  | `m_isSpecialWorkspace` | `onSpecialWorkspace()` / `CSpecialWorkspace` |
  | workspace query `.id(n)` | `.numbered(...)` / `.identity(...)` |

- **Eligibility checks are all preserved:** pinned, `GROUP_DENY`, modal,
  X11 override-redirect, a toplevel parent or modal child, and open popups.
  Candidates: `WindowFullscreenPolicy` pinned state, `WindowGroupMembership`
  rules, `backend()` (X11/Wayland, `parent()`), and the `CPopup` tree
  (`popupHead()`). **Any check without a public equivalent stops
  implementation and is reported.** None is dropped silently.
- **`FlipTransformer`:** the new `transform(in, ctx)` returns
  `{transformFramebuffer(in.framebuffer), in.box, true}`.
  `transformedExtents` is added only if captures show clipping.
- **Floating cards (option B):**
  - delete `PaneTarget` and every window-target swap;
  - hook `Layout::CWindowGroupTarget::setPositionGlobal` with
    `findFunctionsByName` + `createFunctionHook`. The hook calls the original,
    then, for groups owned by a live floating card, positions each member at
    its pane box with `windowTarget()->setPositionGlobal(box, flags)`;
  - remove the hook in `PLUGIN_EXIT` before the controller is destroyed;
  - if the hook fails, floating cards are disabled with a clear refusal, and
    everything else keeps working;
  - `Card::valid()` checks membership through `grouping()`.
- **hy3:**
  - base upstream `12a73ab0adddbc39f839da320dcc2b028769fc58`, hash
    `sha256-HCDDmRkDxQMWMIlTAjZ4vLIQ8e7VnHqBgaJ73u1ItnY=`;
  - our API port lives in `integrations/hy3/hyprland-main.patch`, which
    `prepare-source.py` applies with `patch -p1` before the lifetime
    replacements. Anchors that no longer match fail loudly;
  - `HY3_SOURCE_REV`, `nix/hy3.nix` and `scripts/build-containers` all move to
    that rev;
  - the bridge ABI (`hyprflip_hy3_bridge_v6`) is unchanged.
- **Pins:**
  - `CMakeLists.txt` uses the bare `hyprland` pkg-config module, plus a
    configure check that the `hyprland.pc` prefix contains `23118f9`
    (overridable with `-DHYPRFLIP_HYPRLAND_COMMIT=<rev>`);
  - the flake's `hyprland` input moves to `23118f9`, with nixpkgs still
    following `hyprland/nixpkgs`. The Glaze override is removed unless the
    build needs it;
  - `devenv.yaml` and `devenv.lock` move to the same rev;
  - `hyprpm.toml` is unchanged.
- **Desktop (p620):**
  - the `hyprflip` input in `~/.config/nixos/flake.nix` gets
    `inputs.hyprland.follows = "hyprland"`;
  - `nixosModules.default` with `programs.hyprflip.enable` and
    `containers.enable`;
  - a new `~/.config/hypr/hyprflip.lua` (settings and bindings from
    `examples/hyprflip.lua`, loading `/etc/hyprflip/hyprflip.so`), required
    from the personal section of `~/.config/hypr/hyprland.lua`;
  - runs only after nested verification passes, and with your explicit
    go-ahead.

## Deviations during implementation

- **Commit check (step 1):** CMake reads `GIT_COMMIT_HASH` from Hyprland's
  installed `src/version.h` instead of matching the `hyprland.pc` path. It is
  exact and works outside the Nix store. `HYPRFLIP_HYPRLAND_COMMIT` remains the
  expected commit.
- **Transformer removal (step 3):** `CWindowTransformerList` has no
  remove-by-pointer. `FlipTransformer` gained `active()`/`deactivate()`, and
  detaching deactivates it and calls `removeInactive()`.
- **Eligibility mappings (step 4):**
  - pinned → `m_state & WINDOW_STATE_PINNED`;
  - `GROUP_DENY` → `grouping().rules()`;
  - override-redirect/modal → `backend().traits()`;
  - toplevel parent/modal child → `backend().parent()` / `traits().hasModalChild`;
  - `popupsCount()` → `popupTreeSize()` (same "all children" semantics).

  `backend().parent()` also covers X11 transients, so non-modal X11 dialogs
  are now refused too. That is stricter, and it matches the existing
  "not transient or modal" message.
- **Workspace IDs:** the ID is now a variant, so comparisons use
  `numberedID()`. New workspaces come from
  `State::Workspace::state()->createNumbered`, on the card's focused window's
  monitor.
- **Hook lifetime (step 6):** installed by `FloatingCards::start` from the
  `Controller` constructor, and removed in `FloatingCards::shutdown`, which the
  controller destructor calls during `PLUGIN_EXIT` after cards are dissolved.
  Without the hook, `supports()` returns false and the float action reports
  that floating cards are unavailable.
- **Float toggle:** Hyprland asks the group's current window for a floating
  size, which is one pane. `toggle()` restores the card's previous box with
  `setTargetGeom` when the card becomes floating.

- **hy3 build shape (step 7):** the port patch touches five hy3 files, so
  `prepare-source.py` now builds a complete patched copy of hy3 in the build
  directory. It copies the pinned tree, applies `hyprland-main.patch` with
  `patch -p1`, then applies the lifetime edits in place, and `add_subdirectory`
  builds that copy. The header-only swap of two files is gone. The revision
  check on the pristine source is unchanged. `scripts/build-containers` fetches
  the untagged commit directly.
- **Bridge:** `Bridge.cpp` needed the same accessor and workspace-creation
  mappings as the core. The bridge ABI and exported symbol are unchanged.

## Steps

1. **`CMakeLists.txt`:** use the bare `hyprland` module and add the commit check.
   - Verify: configure succeeds with the desktop package, and fails with the
     0.56.2 package already in the store (`bdqs0p3…-hyprland-0.56.2…-dev`).
2. **Headers, IPC and workspace mappings** in `src/Plugin.cpp`,
   `src/Controller.cpp`, `src/FlipTransformer.*`, `src/FloatingCards.cpp` and
   `tests/motion_probe.cpp`.
   - Verify: those error classes disappear from a keep-going build in the
     desktop-Hyprland shell.
3. **Accessor mappings** (table above) in `Controller.cpp`,
   `FlipTransformer.cpp` and `FloatingCards.cpp`.
   - Verify: no private-member or missing-member errors remain outside the
     window-target swap sites.
4. **Eligibility checks** (`Controller.cpp:385-407, 541, 1006-1014`,
   `FlipTransformer.cpp:320`): map each check to its public equivalent.
   - Verify: each mapping is noted in the commit message. Stop and report if
     any check has no equivalent.
5. **`FlipTransformer`:** add the new `transform` adapter.
   - Verify: `FlipTransformer` compiles.
6. **`FloatingCards.cpp` and `Plugin.cpp`:** remove `PaneTarget` and the
   target swaps; add the group-target hook with its fallback and
   unload-time removal; update `valid()`.
   - Verify: the core builds with zero errors, and CTest passes.
7. **hy3:** move the pins to `12a73ab0`, write `hyprland-main.patch`, add the
   patch argument to `prepare-source.py`, update the CMake revision check, and
   update `scripts/build-containers` and `nix/hy3.nix`.
   - Verify: the provider builds against the desktop Hyprland.
   - Stop and report if the hy3 patch grows past what the spec's risk note
     anticipates (a rewrite rather than API mapping).
8. **`flake.nix` and `flake.lock`:** move the input to `23118f9`, and try
   without the Glaze override.
   - Verify: `nix flake check` passes. Compare the flake's Hyprland output path
     with the desktop's, and explain any difference.
9. **`devenv.yaml` and `devenv.lock`:** move to `23118f9`.
   - Verify: `devenv shell -- hyprctl version` inside a nested session reports
     `23118f9`. `scripts/build-containers` builds, and the Python unit tests pass.
10. **`tests/containers.py`:** add one check. A floating multi-app card is
    moved and resized through the native dispatcher, keeps each pane rectangle,
    and flips correctly.
    - Verify: the check fails against a stub that skips the hook (sanity),
      and passes with it.
11. **Nested runs** on `23118f9` with the Nix store libraries, each suite in a
    fresh session: the native suite and the container suite (13 + the new
    check). Inspect the captures for clipping and flicker. Then unload during a
    floating turn, and reload.
    - Verify: all pass, and no processes are left.
12. **Docs:** update `README.md` and `docs/INSTALL.md` (target text, and the
    advice to follow the consumer's `hyprland` input), and add a `TESTING.md`
    section.
    - Verify: anchors resolve and `nix fmt` leaves no diff.
13. **PR** to `olafkfreund/nixarchy-hyprflip` `main`, linking all three
    artifacts. Merge only when you say so.
14. **Desktop, after your go-ahead** (via the `nixos` and `nixarchy` skills):
    - add the input with `follows`, enable the module, write `hyprflip.lua`
      and the `require` line;
    - check shortcut conflicts against `~/.config/hypr/bindings.lua` before
      writing;
    - build first (`nixos-rebuild build`), then switch;
    - Verify: the plugin loads in the live session with no ABI rejection,
      `hyprctl hyprflip status` responds, and a native pair flips.

## Tests

| Command | Expected |
| --- | --- |
| keep-going build in the desktop-Hyprland shell | 0 errors (steps 2–6) |
| configure against the 0.56.2 dev package | fails on the commit check |
| `nix flake check` | passes (packages + CTest + module evaluations) |
| `readelf -d` / `nm -D` on both libraries | Lua 5.5 only; `pluginInit`, `hyprflip_hy3_bridge_v6` |
| `python3 -m unittest discover -s tests -p '*_test.py'` | passes |
| `tests/integration.py` (nested, `23118f9`) | 18 passed |
| `tests/containers.py` (nested, `23118f9`) | 13 + the new floating move/resize check pass |
| live desktop, after go-ahead | loads, `hyprctl hyprflip status` ok |

## Rollback

- **Repository:** revert the implementation commits or drop the branch.
  `main` keeps the 0.56.2 flake from #2.
- **hy3:** its port is isolated in one patch file.
- **Desktop:** boot or switch to the previous NixOS generation. Remove the
  `require("hypr.hyprflip")` line (and the new `hyprflip.lua`) to stop loading
  the plugin. The desktop's Hyprland input is never changed by this task.
