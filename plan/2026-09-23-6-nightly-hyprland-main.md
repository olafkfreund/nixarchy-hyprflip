---
status: draft
issue: 6
spec: spec/2026-09-23-6-nightly-hyprland-main.md
---

# Plan: Build Hyprflip nightly against Hyprland main and serve it from Cachix

## Context

Hyprflip pins one Hyprland `main` commit (`23118f9`) in 7 places, CI never
runs Nix, and no cache serves the plugin. Issue #6 (intent and spec approved on
`ci/6-nightly-hyprland-main`) calls for a nightly GitHub Actions job. It moves
the Hyprland lock to the newest `main`, runs `nix flake check`, and only if
that passes pushes `hyprflip` and `hy3` to `nixarchy.cachix.org` and merges
the lock bump into `main`. NixOS users then install a prebuilt, known-good
plugin through the flake.

## Approved decisions (carried over from the spec)

- Cache `nixarchy` (`nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM=`);
  Hyprland is pulled from `hyprland` (`hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE=`).
- `flake.lock` is the only Hyprland pin. `flake.nix` and `devenv.yaml` track
  `github:hyprwm/Hyprland`. CMake reads the commit from `flake.lock`, and the
  docs point at the lock.
- The ABI hash check in `src/Plugin.cpp` and the CMake `version.h` commit check
  stay.
- The nightly job runs on schedule and `workflow_dispatch` only, with no PR
  trigger. It pushes explicitly after the checks pass (`skipPush: true`, no
  daemon). It lands the bump through a PR that it merges itself, and it runs
  on x86_64 only. A hy3 failure fails the whole night.
- A failure opens or comments on a `nightly-failure` issue. `main` and the cache
  are untouched.
- `checks.yml` gets a read-only `nix flake check` job for PRs and pushes.
- Consumer recipe: no `follows`; use this flake's Hyprland and `packages`.
  Switching p620 is out of scope.

## Steps

1. **`CMakeLists.txt:9-10`.** Replace the hard-coded commit with the following.
   The cache variable is renamed on purpose. Existing `build/` directories
   (the `Makefile` does not use `--fresh`) still cache
   `HYPRFLIP_HYPRLAND_COMMIT=23118f9…`, which would silently pin the old commit
   (found in review).
   ```cmake
   # Hyprland main still reports 0.56.0, so match the exact commit locked in flake.lock.
   set(HYPRFLIP_HYPRLAND_COMMIT_OVERRIDE "" CACHE STRING "Hyprland commit to target; empty reads flake.lock")
   set(HYPRFLIP_HYPRLAND_COMMIT "${HYPRFLIP_HYPRLAND_COMMIT_OVERRIDE}")
   if(NOT HYPRFLIP_HYPRLAND_COMMIT)
     if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/flake.lock")
       message(FATAL_ERROR "flake.lock is missing; set -DHYPRFLIP_HYPRLAND_COMMIT_OVERRIDE=<Hyprland commit>")
     endif()
     file(READ "${CMAKE_CURRENT_SOURCE_DIR}/flake.lock" HYPRFLIP_LOCK)
     string(JSON HYPRFLIP_HYPRLAND_COMMIT GET "${HYPRFLIP_LOCK}" nodes hyprland locked rev)
   endif()
   ```
   A normal variable shadows the stale cache entry of the same name, so no
   `unset` is needed.
   Lines 16-17 are unchanged, and they now read the normal variable.
   → verify: in `devenv shell`, `cmake --fresh -S . -B /tmp/hf-pin` passes;
   the same with `-DHYPRFLIP_HYPRLAND_COMMIT_OVERRIDE=deadbeef` fails with
   "Hyprflip targets Hyprland deadbeef". Configuring an existing `build/` that
   was made before the change also passes and uses the lock value.
2. **`nix/hyprflip.nix`.** Add `../flake.lock` to the `fileset` unions.
   → verify: `nix build .#hyprflip -L` passes (the lock is still at `23118f9`).
3. **`flake.nix`.** Set `hyprland.url = "github:hyprwm/Hyprland"` and update the
   comment. Add `nixConfig.extra-substituters` and
   `nixConfig.extra-trusted-public-keys` for the two caches. `flake.lock` is
   untouched (the rev stays `23118f9`). → verify: `nix flake metadata` shows
   Hyprland `23118f9`; `nix flake check -L` passes.
4. **`devenv.yaml`.** Set `url: github:hyprwm/Hyprland`; `devenv.lock` is
   untouched. → verify: `jq -r .nodes.hyprland.locked.rev devenv.lock` is
   still `23118f9…`, and `devenv shell -- true` works.
5. **`README.md` (about lines 21, 66, 251) and `docs/INSTALL.md` (lines 3, 23,
   60, 157).** Replace the commit literals with "the Hyprland `main` commit
   locked in `flake.lock`" plus the `nix flake metadata --json | jq -r
   .locks.nodes.hyprland.locked.rev` command. Add an INSTALL section,
   "NixOS with prebuilt plugins (Cachix)", containing the spec's consumer
   recipe with the full keys. Leave `TESTING.md` alone.
   → verify: `grep -rn 23118f9 README.md docs/` is empty.
6. **`.github/workflows/checks.yml`.** Add a `nix` job: `ubuntu-24.04`,
   `timeout-minutes: 60`, `permissions: contents: read`. Its steps are checkout
   (`persist-credentials: false`), `cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24 # v31.11.1`,
   `cachix/cachix-action@38b082610b782e7e93e209c35fd730d399dee866 # v17` with
   `name: nixarchy`, `extraPullNames: hyprland` and `skipPush: true`
   (no token), then `nix flake check -L`. → verify: `actionlint`, and the job
   is green on the PR.
7. **`.github/workflows/nightly.yml` (new).** `on: schedule: cron: "17 3 * * *"`
   and `workflow_dispatch`, with `concurrency: nightly`. It has one job on
   `ubuntu-24.04` with `timeout-minutes: 90`, and permissions
   `contents: write`, `pull-requests: write`, `issues: write`. Its env holds
   `GH_TOKEN: ${{ github.token }}`. Uses the same two pinned actions, with
   `authToken: ${{ secrets.CACHIX_AUTH_TOKEN }}` and `skipPush: true`.
   Steps, each with an `id`:
   1. `bump`: `old=$(jq -r .nodes.hyprland.locked.rev flake.lock)`; run
      `nix flake update hyprland`; `new=…`; write `old`, `new` and
      `changed=$([ "$old" != "$new" ] && echo true || echo false)` to
      `$GITHUB_OUTPUT`.
   2. `devenv` (only if `changed`): `nix run nixpkgs#devenv -- update hyprland`,
      then fail unless the Hyprland rev in `devenv.lock` equals `new`. Also fail
      if `git status --porcelain -- . ':!flake.lock' ':!devenv.lock'` is
      non-empty.
   3. `check` (only if `changed`): `nix flake check -L`.
   4. `push` (only if `changed` and `github.ref == 'refs/heads/main'`):
      `cachix push nixarchy $(nix build .#hyprflip .#hy3 --no-link
      --print-out-paths)`. The cache only ever receives builds that passed
      `check`. Pushing before `land` means a bump that lands is always cached.
      If `land` then fails, the pushed paths are verified but unreferenced,
      which is harmless.
   5. `land` (only if `changed` and `github.ref == 'refs/heads/main'`): set the
      git identity to `github-actions[bot]`, then
      `git switch -C bot/nightly-hyprland`, commit `flake.lock devenv.lock` as
      `build: nightly Hyprland main ${new:0:7}`, and `git push -f origin HEAD`.
      Then run `gh pr create --base main --title … --body "<old>…<new> compare
      link, run URL>"` and `gh pr merge --squash --delete-branch`. Finally,
      close any open `nightly-failure` issue with a comment linking the PR.
   6. `report` (`if: failure()`): run `gh label create nightly-failure --force`.
      If an issue labelled `nightly-failure` is open, comment on it; otherwise
      open one titled "Nightly build failed against Hyprland main". The body
      holds the `new` rev with a link (or "unknown" if `bump` did not finish),
      the outcome of each step (`steps.{bump,devenv,check,push,land}.outcome`,
      passed in through `env:`), and
      `$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID`.
      A `land`-only failure is titled "Nightly landing failed" (the build was
      good), so a merge blocked by future branch protection is not mistaken
      for a Hyprland break.
   Every `${{ }}` value reaches `run:` through `env:`, never inlined.
   A `workflow_dispatch` from a non-`main` ref is a dry run: bump, devenv
   and check only. `push` and `land` are gated on `main`.
   → verify: `actionlint .github/workflows/nightly.yml` is clean.
8. **Validation run (dry).** Push the branch, then run
   `gh workflow run nightly.yml --ref ci/6-nightly-hyprland-main`. `push` and
   `land` are skipped because the ref is not `main`. Expected: `bump` moves the
   lock to today's `main` (`e368c13` or newer), then `check` either passes, or
   fails and `report` opens an issue. Either result proves those steps. `push`
   and `land` are first exercised by a manual `gh workflow run nightly.yml` on
   `main` right after the merge (step 10).
9. **PR.** Open `ci/6-nightly-hyprland-main` → `main`, linking the intent, spec
   and plan, with `Closes #6`. Commits are split by step: `build:` for the pin,
   `docs:`, and `ci:` for the workflows.
10. **First real run (after you merge).** Run `gh workflow run nightly.yml` on
    `main`. Expected: a merged bot PR and pushed paths, or a
    `nightly-failure` issue. If `land` fails on permissions, the Actions PR
    setting is missing.

`main` currently has no branch protection and no rulesets (checked). If you
add required checks later, `land` has to switch to a PAT or app token, because
checks do not run on PRs opened with `GITHUB_TOKEN`.

## Review record

Plan reviewed read-only on 2026-09-23 by Codex (`gpt-5.6-luna`) and
Antigravity (model not reported). Claude checked every finding against the repo:

- Applied: a stale CMake cache pin (confirmed: the `Makefile` reuses `build/`);
  branch dispatch publishing; push-then-land wording; no record of which step
  failed; devenv dirtying other files; build failures and landing failures now
  reported separately.
- Refuted: devenv/flake transitive drift (the same Hyprland rev gives the same
  lock graph); hy3 following a separate Hyprland (`nix/hy3.nix` takes our
  `hyprland`); the `fileset` root (it is `../.`); the lock node name (root
  input `hyprland` → node `hyprland`).
- Out of scope, already decided: hy3 breaks blocking nights (spec decision 5);
  a merge blocked by protection (none exists; noted above).

## One-time setup (you, before step 10)

- `gh secret set CACHIX_AUTH_TOKEN`, a write token for `nixarchy`.
- Settings → Actions → General → "Allow GitHub Actions to create and approve
  pull requests" (needed by `land` from the first run on `main`).
- (The `nightly-failure` label is created by the job; that replaces the manual
  step in the spec.)

## Tests

- `nix flake check -L` passes locally after steps 1-4.
- The CMake override and fail check from step 1.
- `actionlint` is clean on both workflows.
- `grep -rn 23118f9 README.md docs/ CMakeLists.txt flake.nix devenv.yaml` is
  empty.
- The step 8 dispatch run finishes green, or red with a `nightly-failure`
  issue.
- After merge, a green night gives a merged bot PR, and
  `nix path-info --store https://nixarchy.cachix.org <out>` succeeds for both
  paths.
- A throwaway NixOS evaluation with the recipe:
  `nix build …toplevel --max-jobs 0` succeeds, so every path is substituted.

## Rollback

- Disable at once: `gh workflow disable nightly.yml`.
- Code: revert the PR's merge commit. `flake.lock` keeps its last good rev, so
  the pinned build still works.
- Bad nightly bump: revert that bot PR. Its cache paths are harmless because
  nothing references them.
- Remove the `CACHIX_AUTH_TOKEN` secret to cut push rights.

## Follow-ups (not in this task)

- Switch p620 (`~/.config/nixos`) to the no-`follows` recipe.
- Refresh the stale `hyprpm.toml` pins (still 0.56.2).
- A dedicated `hyprflip` cache if `nixarchy` storage grows.
