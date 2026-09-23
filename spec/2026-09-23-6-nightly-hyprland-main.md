---
status: approved
issue: 6
intent: intent/2026-09-23-6-nightly-hyprland-main.md
---

# Spec: Build Hyprflip nightly against Hyprland main and serve it from Cachix

## Design

### Answers to the intent's open questions (defaults, override at review)

The intent was approved without answers, so the recommendations given at
intent review apply:

1. **Cache:** push to the existing `nixarchy` cache
   (`nixarchy.cachix.org`, key `nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM=`),
   already trusted on p620.
2. **Cache hits:** option (b). Consumers who want prebuilt plugins use this
   flake's locked Hyprland as their compositor and this flake's packages, with
   no `follows`. The `follows` route keeps working, but it builds locally and
   fails at build time on a commit mismatch, as it does today. Switching p620 is
   a separate change in `~/.config/nixos`, not part of this task (intent
   constraint).
3. **Landing:** the job opens a PR and merges it itself. The bump is
   already verified, and a PR opened with `GITHUB_TOKEN` does not trigger other
   workflows, so the job cannot wait for them.
4. **Architectures:** `x86_64-linux` only.
5. **hy3:** all or nothing. If `hyprflip` or `hy3` fails, the night fails.

### One pin: `flake.lock`

- `flake.nix`: `hyprland.url = "github:hyprwm/Hyprland"`, tracking `main`.
  The locked revision in `flake.lock` is the pin. Add
  `nixConfig.extra-substituters`/`extra-trusted-public-keys` for
  `hyprland.cachix.org` and `nixarchy.cachix.org`. They take effect for direct
  `nix build github:olafkfreund/nixarchy-hyprflip` use; NixOS consumers set the
  substituters in their own config.
- `CMakeLists.txt`: `HYPRFLIP_HYPRLAND_COMMIT` keeps its cache variable, and
  its default comes from `flake.lock`:
  `string(JSON … GET "${lock}" nodes hyprland locked rev)`. The existing
  `version.h` comparison and its fatal error are unchanged. A manual
  `-DHYPRFLIP_HYPRLAND_COMMIT=…` still overrides it.
- `nix/hyprflip.nix`: add `../flake.lock` to the source fileset so the
  CMake check can read it.
- `devenv.yaml`: `hyprland.url = github:hyprwm/Hyprland`. `devenv.lock` stays
  the devenv pin. The nightly job refreshes it and asserts that its Hyprland rev
  equals the one in `flake.lock`.
- `README.md` and `docs/INSTALL.md` stop naming a commit. They say "the
  Hyprland commit locked in `flake.lock`" and give the command to read it
  (`nix flake metadata --json | jq -r .locks.nodes.hyprland.locked.rev`).
  `TESTING.md` keeps its commit, because it records a past manual validation,
  not the pin.

### `.github/workflows/nightly.yml` (new)

Triggers: `schedule: cron "17 3 * * *"` (03:17 UTC, off the hour) and
`workflow_dispatch`. It has no pull-request trigger, so the Cachix token never
reaches fork code. `concurrency: nightly`, and one job on `ubuntu-24.04` with a
90-minute timeout.
Permissions: `contents: write`, `pull-requests: write`, `issues: write`.

Actions are pinned by commit SHA, following `checks.yml`:
`actions/checkout`, `cachix/install-nix-action` (v31), and
`cachix/cachix-action` (v17) with `name: nixarchy`,
`extraPullNames: hyprland`, `authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}` and
**`skipPush: true`**.

Steps:

1. `nix flake update hyprland`. If `flake.lock` did not change, the job
   stops with success. Nothing moved, so there is nothing to publish.
2. `nix run nixpkgs#devenv -- update hyprland`. Assert that the Hyprland
   rev in `devenv.lock` equals the one in `flake.lock`.
3. `nix flake check -L`. This builds `hyprflip` (with CTest) and `hy3`, and
   evaluates the NixOS and Home Manager modules against the new Hyprland.
   Hyprland itself is substituted from `hyprland.cachix.org`.
4. Success only: `cachix push nixarchy` the two output paths from
   `nix build .#hyprflip .#hy3 --print-out-paths`, which are already built.
5. Success only: commit both locks to `bot/nightly-hyprland`
   (`build: nightly Hyprland main <short rev>`), then `gh pr create`,
   `gh pr merge --squash --delete-branch`, and close any open
   `nightly-failure` issue with a comment linking the merged PR.
6. Failure only: open an issue labelled `nightly-failure`, or comment on the
   open one, with the Hyprland commit, the failing step and the run URL.
   `main` and the cache are not touched.

### `.github/workflows/checks.yml`

Add a read-only `nix` job on push and pull request: install Nix, pull from
`hyprland` and `nixarchy`, and run `nix flake check -L`. It has no secrets
and never pushes. This catches plugin changes that break the locked
combination before they land.

### Consumer recipe (`docs/INSTALL.md`)

```nix
inputs.hyprflip.url = "github:olafkfreund/nixarchy-hyprflip";   # no follows

nix.settings.extra-substituters = [ "https://hyprland.cachix.org" "https://nixarchy.cachix.org" ];
nix.settings.extra-trusted-public-keys = [ "hyprland.cachix.org-1:…" "nixarchy.cachix.org-1:…" ];

programs.hyprland.package = hyprflip.inputs.hyprland.packages.${system}.hyprland;
programs.hyprland.portalPackage = hyprflip.inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
programs.hyprflip = {
  enable = true;
  package = hyprflip.packages.${system}.hyprflip;   # the cached build
  hy3Package = hyprflip.packages.${system}.hy3;
};
```

`package` has to be set explicitly. The module's default rebuilds against the
consumer's `pkgs`, which gives a different store path from the cached one.
Updating is `nix flake update hyprflip`, which moves the compositor and the
plugin together to the last good night.

### One-time setup (by you)

- Add the `CACHIX_AUTH_TOKEN` repo secret, a write token for `nixarchy`.
- Under Settings → Actions → General, enable "Allow GitHub Actions to create
  and approve pull requests".
- Create the `nightly-failure` label.

## Alternatives rejected

- **`DeterminateSystems/update-flake-lock`:** it opens a PR, but its checks
  would not run (a `GITHUB_TOKEN` PR), and it adds a dependency for one
  command.
- **cachix-action daemon push:** it pushes each path as it builds, so a night
  that fails on hy3 would still publish `hyprflip`. That breaks "publish
  nothing unverified".
- **Direct push to `main`:** no PR record of each bump. It would work, and is
  the fallback if you would rather not enable the Actions PR setting.
- **Rewriting the commit into CMake and the docs every night (the
  `build/hyprland-e368c13` approach):** 7 files of churn per night, and the
  docs drift.
- **A NixOS module option that adds the substituters:** it only takes effect
  after the first (uncached) build and silently changes trust settings.
  Documented config is clearer.
- **Changing the module's default `package` to `self.packages`:** it would
  hide a Hyprland mismatch for `follows` users, which is the failure the #3
  decision wants at build time.
- **A dedicated `hyprflip` cache:** it is cleaner for third parties, but it
  needs a new trust entry on p620. Easy to switch later, because only `name:`
  and the docs change.

## Risks

- **Storage in the `nixarchy` cache.** `cachix push` pushes the closure. Paths
  already on cache.nixos.org are skipped (Cachix upstream), but the Hyprland
  closure from `hyprland.cachix.org` is copied every night that Hyprland moves.
  Cachix evicts least-recently-used paths when the cache is full, which could
  also evict other nixarchy paths. Mitigation: watch usage, and switch to a
  dedicated cache if it grows.
- **Frequent red nights.** Hyprland `main` often changes plugin APIs. Each break
  needs a manual port, as in #3. `main` stays on the last good commit, so
  consumers are unaffected, but the build falls behind Hyprland until the port
  lands.
- **The build is green, but the plugin misbehaves at runtime.** CI does not run
  the nested Wayland tests (intent constraint), so a published night can build
  and still misbehave. The ABI hash check in `src/Plugin.cpp` stops a wrong
  load, not a logic regression.
- **p620 with `follows`.** Once this lands, `nix flake update hyprflip` on p620
  moves the expected commit away from `nixarchy/hyprland`, and the rebuild
  fails at the CMake check until p620 uses the recipe above or its Hyprland
  matches. That is the same failure mode as today, but it happens every night.
- **`nix run nixpkgs#devenv` is unpinned**, taken from the registry nixpkgs.
  If it ever breaks, step 2 fails the night. Pin it if that happens.
- **Stale `hyprpm.toml`** (it still pins 0.56.2) is out of scope and noted for a
  follow-up.

## Verification

1. `nix flake check -L` passes locally after the pin refactor, with the lock
   still at `23118f9` (no behavior change).
2. CMake reads the pin: configure outside Nix in `devenv shell`; the check
   passes. Configure with `-DHYPRFLIP_HYPRLAND_COMMIT=deadbeef`; it fails with
   the existing message.
3. `actionlint` passes on both workflow files.
4. On the branch, before merge: `workflow_dispatch` on the nightly workflow
   (`gh workflow run nightly.yml --ref ci/6-…`), with the merge step limited to
   `main` so the test run cannot merge. Expected: the lock moves to current
   Hyprland `main`, and the checks either pass (the push is logged) or fail
   (an issue is opened).
5. After merge, the first scheduled run either merges a bump PR or opens a
   `nightly-failure` issue, and after a green night
   `nix path-info --store https://nixarchy.cachix.org <hyprflip out path>`
   succeeds.
6. Consumer check: a throwaway NixOS evaluation with the recipe above builds
   with `--max-jobs 0`, which proves every path comes from a cache.
