---
status: draft
issue: 9
spec: spec/2026-09-28-9-hyprpm-nightly-pins.md
---

# Plan: Keep hyprpm's commit pins in step with the nightly Hyprland lock

## Context

The nightly workflow (`.github/workflows/nightly.yml`, #6) moves `flake.lock`
to a new Hyprland `main` commit most nights. `hyprpm.toml` still pins only
Hyprland 0.56.2 (`efb5099…` → `429d523`), so hyprpm users on Hyprland `main`
get an untested repository head. `docs/INSTALL.md` also points hyprpm at the
original project (`nocstah/hyprflip`), which never sees this fork's pins.

## Approved decisions (carried over from the spec)

1. `commit_pins` holds the 0.56.2 pair plus exactly one `main` pair, for the
   Hyprland commit in `flake.lock`. There is no history and no pruning.
2. The pin is rewritten only in the nightly `land` step, so only when a bump
   lands.
3. The pin is `[NEW, github.sha]`: the Hyprland commit just locked, and the
   `main` commit whose source `nix flake check` built against it. The squash
   commit differs from `github.sha` only in `flake.lock`, `devenv.lock` and
   `hyprpm.toml`, and hyprpm ignores all three.
4. `scripts/hyprpm_pin.py OLD NEW PLUGIN`, stdlib only:
   - replace the pin line whose Hyprland hash is `OLD` with `["NEW", "PLUGIN"]`;
   - if no line matches `OLD`, append the new pin as the last entry;
   - reject any argument that is not 40 lowercase hex characters;
   - edit the text, not a parsed tree, so comments and formatting survive;
   - re-read the result with `tomllib` and require `[NEW, PLUGIN]` and the
     `efb5099…` pair; on any failure exit non-zero and write nothing.
5. The `devenv` stray-change guard is unchanged. The `land` commit adds
   `hyprpm.toml`, and the PR body names the pin.
6. Seed now: `["4bb6844b0351e4fbf2e3d4e46ae71b551a0e0a42",
   "178885bd77a0f77765a31a21a75c6e14393a6718"]`, the pair nightly run
   2026-09-28 verified. If the lock has moved by the time this merges,
   re-seed from that night's run.
7. `docs/INSTALL.md` `## hyprpm`: Hyprland `main` users add
   `olafkfreund/nixarchy-hyprflip`. Hyprland 0.56.2 users keep
   `nocstah/hyprflip`, whose pin (`d3d4f24`) is newer than the fork's
   (`429d523`). Other `nocstah` links are out of scope, and so is syncing the
   original project.

Rejected: pinning the land commit (a commit cannot contain its own hash), a
second bot commit after the merge, hard-coding 0.56.2 in the script, inline
`sed` in YAML, `tomlkit`, and keeping N pins or appending every night.

## Steps

1. `tests/hyprpm_pin_test.py`: write the tests first, using `unittest` and a
   temporary copy of a fixture manifest.
   - Replacing the `OLD` line changes that line and keeps the `efb5099…` pin.
   - With no `OLD` line, the new pin is appended after existing pins.
   - A short, uppercase or non-hex hash exits non-zero and leaves the file
     byte-identical.
   - Every successful result parses with `tomllib` and has two pins.

   → verify by running it. It fails because the script is missing.
2. `scripts/hyprpm_pin.py`: implement decision 4. Take the path from `--file`,
   defaulting to `hyprpm.toml`, so the tests can use a temporary file. Write
   atomically: a temporary file in the same directory, then `os.replace`.
   → verify by
   `python3 -m unittest discover -s tests -p '*_test.py'`: all green.
3. `hyprpm.toml`: seed the `main` pin (decision 6) as the second entry.
   → verify with `python3 scripts/hyprpm_pin.py
   4bb6844b0351e4fbf2e3d4e46ae71b551a0e0a42
   4bb6844b0351e4fbf2e3d4e46ae71b551a0e0a42
   178885bd77a0f77765a31a21a75c6e14393a6718`: an idempotent replace, no diff.
   The `checks.yml` manifest parse also passes.
4. `.github/workflows/nightly.yml`, `land` step: run
   `python3 scripts/hyprpm_pin.py "$OLD" "$NEW" "$GITHUB_SHA"` before the
   commit, add `hyprpm.toml` to the `git commit -- …` paths, and append
   ``hyprpm pin: `NEW` → `GITHUB_SHA` `` to the PR body.
   → verify by re-reading the step. Also run the rewrite locally: a scratch
   copy with `OLD=4bb6844…` and a fake `NEW`/sha gives exactly one changed
   line.
5. `docs/INSTALL.md` `## hyprpm`: implement decision 7. Show two `hyprpm add`
   commands, one per Hyprland line, and say what happens with no matching pin
   (the head is built). → verify by reading the rendered section. No other
   `nocstah` URL changes.
6. Full local check: `nix flake check -L`. The plugin source is unchanged, so
   it should pass from cache. → verify by exit code 0.
7. Commit each step as a Conventional Commit tagged `(#9)`, push, and open a
   PR linking the intent, spec and plan, with "Fixes #9". → verify that the
   `checks` and `nix` jobs in `checks.yml` are green.
8. After merge, on the first night with a Hyprland bump: the landed commit
   changes `hyprpm.toml` to `["NEW", "<its parent sha>"]` and keeps the
   `efb5099…` pin. Record the run URL on #9.
   → verify with `git show <land commit> -- hyprpm.toml`.

## Tests

| Command | Expected |
| --- | --- |
| `python3 -m unittest discover -s tests -p '*_test.py'` | all pass, including `hyprpm_pin_test` |
| `python3 -c 'import pathlib, tomllib; tomllib.loads(pathlib.Path("hyprpm.toml").read_text())'` | exit 0 |
| `python3 scripts/hyprpm_pin.py 4bb6844… 4bb6844… 178885b…` then `git diff --exit-code hyprpm.toml` | no diff |
| `python3 scripts/hyprpm_pin.py abc 4bb6844… 178885b…` | non-zero exit, file untouched |
| `nix flake check -L` | exit 0 |
| First nightly land after merge | `hyprpm.toml` diff is one line: the `main` pin |

## Rollback

- Revert the PR. `nightly.yml` stops touching `hyprpm.toml`, and the file goes
  back to the single 0.56.2 pin.
- If a bad pin landed overnight, revert that land commit or hand-edit the pin
  line. `checks.yml` parses the manifest on the push, so a malformed file shows
  up at once.
- Nothing is deployed to hosts, and Cachix is unaffected.

## Follow-ups (not in this task)

- Sync the original project's 0.56.x work (`nocstah/hyprflip`, 11 commits
  ahead) into the fork, after which the fork could serve 0.56.2 users too.
- The remaining `nocstah` links in `README.md` and `docs/INSTALL.md` (clone
  URL, issues link).
