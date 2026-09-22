---
status: draft
issue: 1
author: olafkfreund
---

# Intent: Install Hyprflip on NixOS through a flake

Tracked as olafkfreund/nixarchy-hyprflip#1. Not to be confused with the
development-environment task nocstah/hyprflip#1
(`intent/2026-09-22-1-nix-development-environment.md`).

## Problem

NixOS users cannot install Hyprflip declaratively. The only Nix support is a
project-local devenv shell for contributors. The documented install paths are
`scripts/install.py`, hyprpm and manual loading. All three build into, or
edit files under, the user's home directory outside the Nix store, so the
result is not reproducible and a rollback does not undo it.

The plugin enforces an exact compositor version and ABI match when it loads.
A plugin built against a different Hyprland than the one the system runs is
rejected. Today, NixOS users have no packaged way to get a build that matches
their own compositor.

## Proposed outcome

- A NixOS or Home Manager configuration can add this repository as a flake
  input and get the Hyprflip core plugin as a package.
- The experimental hy3 containers provider is available the same way, as a
  separate, opt-in output.
- A NixOS module and a Home Manager module let users enable Hyprflip, and
  optionally the provider, without hand-editing plugin paths.
- The packages are built against the Hyprland package the consumer actually
  runs, so the load-time ABI check passes on their system.
- The existing devenv, installer, hyprpm and manual paths keep working
  unchanged.

## Affected users and systems

NixOS and Home Manager users of Hyprland, including Nixarchy. Affects the
repository root (new flake files), the installation documentation, and the
Nix build of the core plugin and the hy3 provider patch process in
`scripts/build-containers`.

## Constraints

- Keep the Hyprland 0.56.2 requirement and every runtime ABI and version guard.
- Never ship a Hyprland built privately by the flake that differs from the
  one the user runs. Consumers must be able to supply their own Hyprland package.
- Keep the hy3 source pin and patch set used by `scripts/build-containers`.
- Building the flake must not modify the user's home directory, desktop
  configuration or running compositor.
- Omarchy menus, OmaCards panel integration and the Python helper scripts
  are out of scope.
- Follow the approved intent → spec → plan stages before implementing.

## Open questions

1. `main` still requests Lua 5.4, but Hyprland 0.56.2 requires Lua 5.5. That
   fix is on the unmerged `build/1-nix-development-environment` branch
   (nocstah/hyprflip#1). Should this task wait for that branch to merge, be
   rebased onto it, or carry the Lua fix itself?
2. Should the flake reuse the Hyprland 0.56.2 pin from `devenv.yaml` as its
   default for building and checks, or leave Hyprland entirely to the consumer?
