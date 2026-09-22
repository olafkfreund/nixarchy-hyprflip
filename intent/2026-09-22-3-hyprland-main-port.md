---
status: approved
issue: 3
author: olafkfreund
---

# Intent: Run Hyprflip on the Hyprland main build the desktop uses

Tracked as olafkfreund/nixarchy-hyprflip#3.

## Problem

The p620 desktop runs Hyprland from `github:hyprwm/Hyprland/main`, locked at
`23118f9f7f24db7447069949c2df7fcd8ba380d0` (reported as
`0.56.0+date=2026-09-22`). It is newer than 0.56.2, despite its version string.
Hyprflip and its flake support only Hyprland 0.56.2, so the NixOS flake merged in
#2 cannot be enabled on this machine.

A build against the installed package, with only the version check loosened,
fails to compile. Plugin APIs have changed on Hyprland main since 0.56.2:

- window and workspace headers moved (`desktop/Workspace.hpp`,
  `desktop/view/Window.hpp`);
- hyprctl command registration changed (`SHyprCtlCommand` became
  `IPC::Socket1::SCommand`);
- the render transformer override signature in `FlipTransformer` changed.

The pinned hy3 provider (`hl0.56.0.1`) fails on the same header move.
Compilation stops at the first missing header in each file, so the full extent
is not yet known.

## Proposed outcome

- The core plugin builds against the exact Hyprland package p620 runs, and passes
  its C++ test and the 18 native nested integration checks on that compositor.
- The experimental hy3 provider does the same with the 13 container checks, or
  the decision to defer it is explicit (see open questions).
- The flake's pinned Hyprland and its checks match the desktop's locked revision,
  so `nix flake check` validates what the desktop will load.
- p620 can enable `programs.hyprflip` through the flake, and the plugin loads in
  the real session with no ABI rejection.

## Affected users and systems

The p620 desktop and its NixOS configuration (`~/.config/nixos`), the plugin
source under `src/` and `tests/motion_probe.cpp`, the hy3 bridge under
`integrations/hy3`, the flake and its pins, and the install and testing
documentation.

## Constraints

- Keep the runtime ABI hash check in `src/Plugin.cpp`. Never bypass it to force
  a load.
- Compile against the exact desktop Hyprland revision, with its own stdenv.
- Validate in disposable nested sessions running that same revision before
  anything loads into the live desktop.
- Loading into the live desktop is a separate, explicit step that needs your
  go-ahead. A failure must be recoverable by removing the plugin and rebuilding.
- Do not change the desktop's Hyprland input as part of this task.
- Follow the approved intent → spec → plan stages before implementing.

## Decisions (answered at intent review)

1. **0.56.2 support:** replaced. The single supported target is the Hyprland
   main revision the desktop runs. No compile-time version switches.
2. **hy3:** in scope. This task carries whatever patches hy3 needs to build and
   pass the container checks on that revision.
3. **Keeping in step:** the desktop's NixOS config makes its `hyprflip` input
   follow its own `hyprland` input, so one lock controls both and a mismatch
   fails the rebuild instead of the session.
