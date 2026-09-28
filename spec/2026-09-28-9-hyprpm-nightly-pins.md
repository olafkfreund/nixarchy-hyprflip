---
status: draft
issue: 9
intent: intent/2026-09-28-9-hyprpm-nightly-pins.md
---

# Spec: Keep hyprpm's commit pins in step with the nightly Hyprland lock

## Design

### Answers to the intent's open questions

The intent was approved with its recommendations standing:

1. `commit_pins` keeps **the latest `main` pair plus the 0.56.2 pair**. There
   is no history and no pruning.
2. The pin is rewritten **only when a bump lands** (the `land` step). A night
   where Hyprland did not move leaves `hyprpm.toml` alone.

### Which hyprflip commit a pin names

The `check` step builds the source at `github.sha` (the `main` commit the
workflow checked out) against the newly locked Hyprland `NEW`. The land commit
cannot name itself. Its squash commit on `main` only differs from `github.sha`
in `flake.lock`, `devenv.lock` and `hyprpm.toml`, and hyprpm ignores all three:
it builds with `cmake` against the headers of the Hyprland that is running.

The pin is therefore `[NEW, github.sha]`: exactly the pair `nix flake check`
passed. `github.sha` stays on `main` as the parent of the squash commit, so
`git reset --hard` in hyprpm always finds it
(`hyprpm/src/core/PluginManager.cpp`, the commit-pin loop).

### Rewriting the file: `scripts/hyprpm_pin.py`

A stdlib-only script, `python3 scripts/hyprpm_pin.py OLD NEW PLUGIN`:

- It finds the pin line whose Hyprland hash is `OLD`, the lock being replaced,
  and replaces it with `["NEW", "PLUGIN"]`. That line is by definition the
  current `main` pin. The 0.56.2 line never matches `OLD`, so it is never
  touched. No sentinel comment or line order is needed.
- If no line matches `OLD` (the first run, or a hand edit), it appends
  `["NEW", "PLUGIN"]` as the last pin.
- It rejects any argument that is not 40 lowercase hex characters. hyprpm
  refuses a malformed pin at install time (`isValidHash`), so CI must refuse it
  first.
- It edits the text, not a parsed tree, so comments and formatting survive. It
  then re-reads the result with `tomllib` and asserts that `commit_pins`
  contains `[NEW, PLUGIN]` and still contains the `efb5099…` pair. Otherwise it
  exits non-zero and writes nothing.

A text edit plus a `tomllib` check is used because stdlib Python can read TOML
but not write it, and the runner must not need a new dependency.

### Workflow change: `.github/workflows/nightly.yml`, `land` step

Before `git commit`:

```sh
python3 scripts/hyprpm_pin.py "$OLD" "$NEW" "$GITHUB_SHA"
git commit -m "build: nightly Hyprland main ${NEW:0:7}" -- flake.lock devenv.lock hyprpm.toml
```

The `devenv` step's stray-change guard runs before `land`, so it is unchanged
and still fails on anything except the two lock files at that point. The PR
body gains one line that names the new pin.

### Seeding the current pair

The implementation commit also adds the pair the rule would have written last
night: `["4bb6844b0351e4fbf2e3d4e46ae71b551a0e0a42",
"178885bd77a0f77765a31a21a75c6e14393a6718"]`. Nightly run 2026-09-28 checked
`main` at `178885b` against Hyprland `4bb6844`, passed, and landed `4b41e33`
(locks only). From the next bump on, the script replaces this line because its
Hyprland hash equals the next `OLD`.

If the lock moves before this merges, the seed uses whatever pair that night's
successful run verified.

### Docs

`docs/INSTALL.md#hyprpm` currently says `hyprpm add
https://github.com/nocstah/hyprflip`, the original project. That project's
manifest pins 0.56.2 only and never sees our nightly pins, so without a docs
change this work reaches nobody who follows the instructions. The section
becomes:

- On Hyprland `main`, run `hyprpm add
  https://github.com/olafkfreund/nixarchy-hyprflip`. It is pinned to the
  commit in `flake.lock`, and on any other `main` commit hyprpm builds the
  repository head.
- On Hyprland 0.56.2 releases, keep `nocstah/hyprflip`. Its 0.56.2 pin
  (`d3d4f24`, accent ring) is newer than ours (`429d523`, 0.2.0), because the
  fork has not synced the original project since.

Syncing the original project's 0.56.x work into the fork is out of scope here.

## Alternatives rejected

- **Pin the land commit itself.** Impossible: a commit cannot contain its own
  hash.
- **A second bot commit after the merge that pins the squash commit.** It
  doubles the `main` commits each night and races with anything merged in
  between, for no gain: the source is identical to `github.sha`.
- **Regenerate the whole array with the 0.56.2 pair hard-coded in the script.**
  A future release pin would need a script change. Replacing the `OLD` line
  leaves every other pin alone.
- **`sed` inline in the workflow.** The fallback append plus validation is
  branchy, and a `sed` script in YAML cannot be unit-tested in `checks.yml`.
- **A TOML library such as `tomlkit`.** It would be a new dependency for a
  one-line edit.
- **Keep N pins, or append every night** (intent option b or c). Rejected at
  intent approval.

## Risks

- **A malformed `hyprpm.toml` lands on `main`** and every hyprpm install fails.
  Mitigations: the script validates with `tomllib` before writing, and
  `checks.yml` already parses `hyprpm.toml` on every push.
- **The `land` step fails after `check` passed.** Cachix already has the builds
  but `main` does not move. The existing `report` step opens a "Nightly
  landing failed" issue, and the next night retries. This does not change.
- **Users on Hyprland `main` a night or more behind the lock** get no pin and
  build the repository head, which is today's behaviour for everyone.
  Accepted at intent approval.
- **Hyprland reports a different hash than `flake.lock`.** For example, a
  distro package built from a tarball without git metadata reports no commit.
  Then no pin matches and hyprpm uses the head. That is no worse than today and
  outside our control.
- Only the fork's CI is affected. No host is touched.

## Verification

- `tests/hyprpm_pin_test.py` (run by `checks.yml` through `unittest
  discover`):
  - replacing the `OLD` line keeps the 0.56.2 pin;
  - with no `OLD` line, the new pin is appended;
  - a bad hash exits non-zero and leaves the file unchanged;
  - the result parses with `tomllib`.
- Locally: `python3 -m unittest discover -s tests -p '*_test.py'` passes, and
  `nix flake check` still passes (source unchanged).
- The workflow: a `workflow_dispatch` from the branch is a dry run and never
  reaches `land`. So after merge, the first night with a Hyprland bump is
  checked: the landed commit contains `["NEW", "<its parent>"]` and still
  contains the `efb5099…` pin. The PR description records that check.
- Optional end-to-end: `hyprpm add` in the nested Hyprland session matches the
  pin ("commit pin … matched hl").
