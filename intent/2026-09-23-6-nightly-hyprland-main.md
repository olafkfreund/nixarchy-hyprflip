---
status: approved
issue: 6
author: olafkfreund
---

# Intent: Build Hyprflip nightly against Hyprland main and serve it from Cachix

Tracked as olafkfreund/nixarchy-hyprflip#6.

## Problem

Hyprflip targets one hand-picked Hyprland `main` commit, hard-coded in
`flake.nix`, `devenv.yaml`, `CMakeLists.txt` and the docs (now `23118f9`).
Hyprland `main` moves daily (today `e368c13`), and a plugin loads only into the
exact compositor it was built against. Moving to a new commit is a manual job
across 7 files: see the unmerged `build/hyprland-e368c13` branch. Nobody learns
that Hyprland broke the plugin API until someone tries.

The repository runs no Nix build in CI. `checks.yml` runs g++ and unittest
only, so `nix flake check` is never run automatically.

No binary cache serves the plugin. Every NixOS consumer compiles `hyprflip`
and `hy3` locally.

## Proposed outcome

- Every night, GitHub Actions builds Hyprflip and hy3 against the newest
  Hyprland `main` commit and runs the flake checks: the build, CTest and the
  module evaluations.
- When the checks pass, the job pushes the outputs to Cachix and moves the
  flake's Hyprland lock on `main` to that commit. `main` then always points at a
  combination that is known to build and pass its tests.
- When they fail, `main` and the cache stay on the last good commit, and the
  failure is visible (a failed run and an issue), with the Hyprland commit that
  broke it.
- A NixOS user adds the cache and the flake and gets a prebuilt plugin, with no
  local compile, provided they run the same Hyprland commit.
- The pin is recorded in one place, so the nightly job does not rewrite docs
  and CMake files.

## Affected users and systems

`flake.nix` and `flake.lock`, `devenv.yaml` and `devenv.lock`, the version
check in `CMakeLists.txt`, `.github/workflows/`, `docs/INSTALL.md` and
`README.md`. Also a Cachix cache and its auth-token repository secret. It
affects the p620 desktop, whose `~/.config/nixos` flake makes `hyprflip`
follow `nixarchy/hyprland`, and any other NixOS consumer.

## Constraints

- Keep the runtime ABI hash check in `src/Plugin.cpp`, and keep building with
  Hyprland's own stdenv.
- Publish nothing that has not passed the flake checks. A red night changes
  nothing that consumers see.
- CI cannot run the nested Wayland integration tests (18 native, 13 container).
  "Works" here means it builds, CTest passes and the modules evaluate. Runtime
  validation on a real session stays a manual step.
- Least-privilege tokens: the Cachix token and the push rights are used only by
  the nightly job, never on pull requests or forks.
- Use Hyprland's cache (`hyprland.cachix.org`) for the compositor itself; do
  not rebuild Hyprland in CI.
- The desktop's own Hyprland input is not changed by this task.

## Open questions

1. **Cache:** push to your existing `nixarchy` cache, or create a dedicated
   `hyprflip` cache? The existing cache is already trusted on p620, and a new one
   keeps the plugin separate for other users.
2. **How consumers get cache hits.** Store paths depend on the exact Hyprland
   commit. p620 follows `nixarchy/hyprland`, so it only hits the cache when its
   Hyprland lock matches this flake's lock. The choices are:
   a. keep `follows`, and bump both locks together, so the cache hits only on
      matching nights;
   b. drop `follows` on consumers and use this flake's Hyprland as the
      compositor (`programs.hyprland.package = hyprflip's hyprland`), so the
      compositor and the plugin always match and both come from caches;
   c. the nightly job also opens a PR on `nixarchy` to move its Hyprland lock.
3. **Landing the bump:** commit the lock bump straight to `main`, or open an
   auto-merging PR (branch protection, visible history)?
4. **Architectures:** is `x86_64-linux` enough, or also `aarch64-linux` on the
   free GitHub ARM runners?
5. **hy3:** if a Hyprland change breaks only the hy3 patch, should the core
   still publish (partial success), or does the whole night fail?
