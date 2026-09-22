---
status: draft
issue: 3
intent: intent/2026-09-22-3-hyprland-main-port.md
---

# Spec: Run Hyprflip on the Hyprland main build the desktop uses

## Target

The single supported compositor is Hyprland `github:hyprwm/Hyprland`
`23118f9f7f24db7447069949c2df7fcd8ba380d0`, the revision p620 has locked
(package `hyprland-0.56.0+date=2026-09-22_23118f9`). Its version string
still reads 0.56.0, so all version checks key on the **commit**, not the
version number. Hyprland 0.56.2 support is dropped (intent decision 1).

## Design

### Findings that shape the design

A scratch build against the exact desktop package, run layer by layer,
found the following breaks. Scratch logs are in the session scratchpad.

- **Moved headers:**
  - `desktop/view/Window.hpp` → `desktop/view/window/Window.hpp`;
  - `desktop/Workspace.hpp` → `workspace/HLWorkspace.hpp`
    (`CWorkspace` → `Workspace::CHLWorkspace`).
- **hyprctl commands:** `SHyprCtlCommand` and `eHyprCtlOutputFormat` →
  `IPC::Socket1::SCommand{name, match, handler(const SRequest&) -> SResponse}`.
  `.exact = false` becomes `.match = COMMAND_MATCH_PREFIX`.
- **Window transformer:** `transform(fb)` →
  `SWindowTransformBuffer transform(const SWindowTransformBuffer&, const SWindowTransformContext&)`,
  plus seven new virtual hooks, all with defaults.
- **`CWindow` split into sub-objects:** `effects()`, `presentation()`,
  `grouping()`, `fullscreenPolicy()`, `backend()` and `metadata()`. Members
  Hyprflip used directly are private or gone. Public replacements found:

  | 0.56.2 | main (`23118f9`) |
  | --- | --- |
  | `m_isMapped` | `mapped()` |
  | `m_isFloating` | `isFloating()` |
  | `m_target` (read) | `windowTarget()` / `layoutTarget()` |
  | `m_group` | `grouping()` |
  | `m_transformers` | `effects().transformers()` |
  | `resetMotionBlur()` | `effects().resetMotionBlur()` |
  | `m_windowDecorations`, `removeWindowDeco` | `presentation().add/containsDecoration/removeDecoration` |
  | `m_floatingOffset` | `presentation().floatingOffset()` |
  | `canBeGroupedInto` | `grouping().canBeGroupedInto()` |
  | `CGroup::m_target` | `CGroup::target()` |
  | workspace `m_id`, `m_space`, `m_visible` | `id()`, `space()`, `visible()` |
  | `m_isSpecialWorkspace` | `CWindow::onSpecialWorkspace()` / `CSpecialWorkspace` |
  | workspace query `.id(n)` | `.numbered(...)` / `.identity(...)` |

- **Eligibility checks without a confirmed 1:1 replacement yet:** `m_pinned`,
  `m_groupRules & GROUP_DENY`, `isModal()`, `isX11OverrideRedirect()`,
  `m_xdgSurface->m_toplevel` (parent or modal child) and `popupsCount()`.
  Candidates:
  - pinned: pinned state in `WindowFullscreenPolicy`;
  - group rules: `WindowGroupMembership` rules (`parseGroupRules`);
  - modal and override-redirect: `backend()` (X11 and Wayland backends,
    `parent()`);
  - popup count: the `CPopup` tree (`popupHead()`).
- **The single real blocker:** floating cards replace each member window's
  `m_target` with a `PaneTarget` wrapper (`FloatingCards.cpp:69, 207, 348, 521,
  632`). That field is private on main and has no setter.

### Core port (`src/`, `tests/motion_probe.cpp`)

- Apply the header, IPC, workspace and accessor mappings above everywhere they
  occur. This is a mechanical rewrite; behaviour must not change.
- **`FlipTransformer`** implements the new `transform(in, context)` by running
  the existing framebuffer logic and returning `{fb, in.box, true}`. This keeps
  the card inside the window box, as today. Whether the new
  `transformedExtents` hook is needed, so perspective can draw outside the box,
  is decided by the runtime captures in verification. It is added only if the
  captures show clipping.
- **Every eligibility check is preserved.** Each gets a public equivalent from
  the candidates above. If one has none, implementation stops and reports it;
  no check is silently dropped. These checks protect dialogs, popups and
  pinned windows from being captured into a card.

### Floating cards: native targets plus a group-target hook (option B)

Main routes every drag, move, resize and client geometry request for a
grouped window through its native group target. `CWindow::layoutTarget()`
returns `group->target()`, and `CWindowGroupTarget::updatePos` (called from
`setPositionGlobal`) gives each member the full group box.

New design:

- **Stop replacing window targets.** Delete `PaneTarget` and every
  `m_target` swap and restore. The window, group and layout targets all stay
  native and untouched.
- **Hook `Layout::CWindowGroupTarget::setPositionGlobal`.** Use the official
  plugin API: `HyprlandAPI::findFunctionsByName` + `createFunctionHook`.
  The hook calls the original first. If the group belongs to a live floating
  card, it then computes each visible face's pane rectangles (using the
  existing `faceBox`, ratios and gap logic) and calls
  `w->windowTarget()->setPositionGlobal(paneBox, flags)` on each member.
  Groups that aren't cards are left alone.
- Because the group target stays in the layout, native move, resize and drag
  from any pane keep working, with no custom input handling.
- The hook is removed in `PLUGIN_EXIT` with `removeFunctionHook`, before the
  controller is destroyed.
- **If the symbol can't be found or hooked at load,** the plugin still loads.
  It disables floating cards only, refuses floating-card actions with a clear
  message, and keeps native pairs and tiled cards working.
- `Card::valid()` drops its `m_target` identity check. It checks group
  membership through `grouping()` instead.

### hy3 provider (`integrations/hy3`)

- **New base:** upstream hy3 `master` `12a73ab0`, newer than `hl0.56.0.1`.
  It still fails on the moved `desktop/Workspace.hpp`, which hides every later
  error, so the size of the hy3 port is unknown.
- **Our port as a patch:** a new `integrations/hy3/hyprland-main.patch`
  holds the edits hy3 needs for `23118f9`. It is applied to the fetched source
  before `prepare-source.py`, so the Hyprflip lifetime patches stay separate
  and reviewable.
  - `prepare-source.py` gets an optional patch-file argument and applies it
    with `patch -p1`.
  - The string-anchored lifetime replacements are re-verified against the new
    base. If an anchor no longer matches exactly once, the script already
    fails loudly.
- **Revision pins:** `HY3_SOURCE_REV` checks and `nix/hy3.nix` move to
  `12a73ab0` with its prefetched hash. `scripts/build-containers` clones that
  rev and applies the same patch.
- The bridge ABI (`hyprflip_hy3_bridge_v6`) and its behaviour are unchanged.
  Only its Hyprland API calls are ported, using the same mappings as the core.

### Pins, flake and devenv

- **`CMakeLists.txt`:** replace `hyprland=0.56.2` with the bare `hyprland`
  module. The exact match is enforced by the commit check below and the
  existing runtime hash check (`src/Plugin.cpp:76`), not the version number.
  Add a configure-time check that `hyprland.pc`'s include path belongs to
  `23118f9` (the Nix store name contains it), overridable with
  `-DHYPRFLIP_HYPRLAND_COMMIT=<rev>` for non-Nix builds.
- **`flake.nix`:** the `hyprland` input moves to `23118f9`, with nixpkgs still
  following `hyprland/nixpkgs`. The Glaze 7 override is removed if the pinned
  package builds without it, which the desktop already does. It stays only if
  the build proves otherwise.
- **`devenv.yaml`:** moves to the same revision, so nested tests run the same
  compositor. `devenv.lock` is regenerated.
- **`hyprpm.toml`:** unchanged. Its existing pin still correctly maps 0.56.2
  to the last 0.56.2-compatible commit.

### Desktop integration (p620, `~/.config/nixos`)

- The `hyprflip` input is added with `inputs.hyprland.follows = "hyprland"`,
  so one lock controls both and a mismatch fails `nixos-rebuild`
  (intent decision 3).
- **Loading:** `nixosModules.default` with `programs.hyprflip.enable` (and
  `containers.enable`), plus `hl.plugin.load("/etc/hyprflip/…")` in the
  desktop's Hyprland Lua config. The plan names the exact file after reading
  the nixarchy layout.
- This step changes the live system. It runs only after nested verification
  passes and after your explicit go-ahead. Rollback is the previous generation
  plus removing the load line.

### Documentation

- `README.md` and `docs/INSTALL.md` now state the target as Hyprland main
  `23118f9`, not 0.56.2, and say that the flake input should follow the
  consumer's `hyprland` input.
- `TESTING.md` gets a dated section with the results.

## Alternatives rejected

- **Private-member access workaround (option A):** fragile and relies on
  internals. Rejected at review.
- **Disabling floating cards (option C):** rejected at review in favour of B.
- **A custom `CardTarget` in the layout with the group target ghosted:**
  grouped windows resolve `layoutTarget()` to the native group target, so
  drags and resizes would bypass it.
- **Keeping 0.56.2 support behind version switches:** rejected in intent
  decision 1.
- **Upstream hy3 unchanged:** it doesn't compile against `23118f9`.

## Risks

- **Hidden layers.** The compiler stops per file, so fixing these errors may
  reveal more, in both the core and hy3.
- **hy3 port size is unknown** until its first layer is fixed. If it turns out
  to be very large, I'll stop and report before continuing.
- **The hook depends on Hyprland internals.** A rename or inlining of
  `CWindowGroupTarget::setPositionGlobal` disables floating cards, visibly and
  safely.
- **Positioning order.** The hook runs right after `updatePos`, so members
  briefly get the full box within the same call. Nothing renders between the
  two, but the verification captures check for flicker.
- **Hyprland main keeps moving.** The `follows` rule turns a future break into
  a failed rebuild, not a broken session, but each break needs another port.
- **Live load.** Only after nested checks pass on the identical compositor.
  The runtime hash check remains the last guard.

## Verification

1. The flake's pinned Hyprland output path equals the desktop's package
   (`/nix/store/…-hyprland-0.56.0+date=2026-09-22_23118f9`), or the difference
   is explained. Then `nix flake check` passes on x86_64-linux: both packages,
   CTest, and both module evaluations.
2. `readelf` shows Lua 5.5 linkage, and `pluginInit` and the bridge symbol are
   exported.
3. A deliberately different Hyprland commit fails CMake configure.
4. `devenv shell` reports compositor `23118f9`. `scripts/build-containers`
   builds, and the Python unit tests pass.
5. In fresh nested sessions on `23118f9`, with the Nix-built libraries: all
   **18 native** checks and all **13 container** checks pass. One new check is
   added: a floating multi-app card moved and resized through the native
   dispatcher keeps each pane's rectangle and flips correctly. Captures from
   each suite are inspected for clipping or flicker.
6. The floating-card hook is removed on unload: an unload during a floating
   turn leaves windows accessible and a reload works.
7. The desktop step, after go-ahead: `nixos-rebuild` succeeds with the
   `follows` input, the plugin loads in the live session with no ABI
   rejection, and `hyprctl hyprflip status` responds. Rollback is tested to
   the point of confirming the previous generation is available.
