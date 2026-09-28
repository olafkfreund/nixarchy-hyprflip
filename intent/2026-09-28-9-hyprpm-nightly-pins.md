---
status: approved
issue: 9
author: olafkfreund
---

# Intent: Keep hyprpm's commit pins in step with the nightly Hyprland lock

Tracked as olafkfreund/nixarchy-hyprflip#9.

## Problem

`hyprpm.toml` has one entry in `commit_pins`: Hyprland 0.56.2 (`efb5099…`)
maps to hyprflip `429d523` (the 0.2.0 release). Since #3 and #6, `main` targets
Hyprland `main`, and the nightly workflow (`.github/workflows/nightly.yml`)
moves `flake.lock` to a new Hyprland commit most nights (`4bb6844` today).
Nothing updates `hyprpm.toml`.

hyprpm matches the running Hyprland commit against `commit_pins`. A user on
Hyprland `main` who runs `hyprpm add` finds no pin for their commit. They get
whatever the head of the repository is, whether or not it was ever built
against their Hyprland. The Nix path already guarantees a matching pair
(`flake.lock` plus Cachix). The hyprpm path guarantees nothing.

## Proposed outcome

- After each night that lands, `hyprpm.toml` has a pin that maps the locked
  Hyprland commit to a hyprflip commit that `nix flake check` passed against
  that commit.
- A hyprpm user whose Hyprland matches the lock gets that verified commit.
- Users on Hyprland 0.56.2 keep getting `429d523`. Today `main` does not build
  against the 0.56 API, so losing that pin would break them.
- No human edits `hyprpm.toml` for a routine nightly bump.

## Affected users and systems

- hyprpm users of `olafkfreund/nixarchy-hyprflip` (non-Nix installs, see
  `docs/INSTALL.md#hyprpm`).
- `.github/workflows/nightly.yml`: the `land` step and its stray-change guard
  in the `devenv` step.
- `hyprpm.toml`.
- Not affected: Nix and NixOS users, Cachix, and the `hy3` provider (hyprpm only
  builds `hyprflip`).

## Constraints

- A pin may only name a pair that the nightly `check` step actually verified.
  The land commit cannot name itself, so the pin must name a commit whose
  plugin source is identical.
- The nightly workflow must still land only `flake.lock`, `devenv.lock` and now
  `hyprpm.toml`, and must still fail on any other change.
- The 0.56.2 pin stays.
- There is no hyprpm on the CI runner, so whatever rewrites the file must keep
  it valid TOML that hyprpm parses.

## Open questions

1. **How many main pins to keep.** Options:
   - (a) Only the latest main pair, plus 0.56.2. The file stays small. A user a
     night or more behind the lock gets no match and falls back to the head of
     the repository, which is what everyone gets today.
   - (b) Append one pair each night. Every locked commit stays reproducible, but
     the list grows by one line a night with no bound.
   - (c) Keep the latest N pairs, e.g. 30.

   I recommend (a). The Nix lock also keeps only the latest pair, a user who
   updates Hyprland usually updates hyprflip too, and it adds no pruning logic.
2. Should a night where Hyprland did not move, but the check passed, also
   refresh the pin? I recommend no. The pin is written only when a bump lands,
   so it always matches `flake.lock` on `main`.
