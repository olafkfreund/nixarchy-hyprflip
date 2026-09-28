#!/usr/bin/env python3
"""Point hyprpm.toml's Hyprland main pin at the pair the nightly check verified.

usage: hyprpm_pin.py [--file hyprpm.toml] OLD NEW PLUGIN

The pin whose Hyprland hash is OLD (the lock being replaced) becomes
["NEW", "PLUGIN"]; with no such pin, one is appended. Every other pin, such as
the Hyprland 0.56.2 release pair, is left alone.
"""
import argparse
import os
from pathlib import Path
import re
import sys
import tempfile
import tomllib

# The 0.56.2 release pair must survive every rewrite; hyprpm users on releases depend on it.
RELEASE_HYPRLAND = "efb50993780079460b0cbed1363e2166a2de1d9f"
HASH = re.compile(r"[0-9a-f]{40}")


def rewrite(text, old, new, plugin):
    line = f'    ["{new}", "{plugin}"],'
    pin = re.compile(rf'^[ \t]*\["{old}",[ \t]*"[0-9a-f]{{40}}"\],?[ \t]*$', re.MULTILINE)
    text, replaced = pin.subn(line, text)
    if not replaced:
        # ponytail: assumes the array closes on its own line, as hyprpm.toml writes it
        close = re.compile(r"(^commit_pins = \[\n(?:.*\n)*?)(\]$)", re.MULTILINE)
        text, appended = close.subn(rf"\g<1>{line}\n\g<2>", text, count=1)
        if not appended:
            raise ValueError("no multi-line commit_pins array")
    pins = tomllib.loads(text)["repository"]["commit_pins"]
    if [new, plugin] not in pins:
        raise ValueError("new pin missing after rewrite")
    if not any(hyprland == RELEASE_HYPRLAND for hyprland, _ in pins):
        raise ValueError(f"release pin {RELEASE_HYPRLAND} missing")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--file", type=Path, default=Path("hyprpm.toml"))
    parser.add_argument("old")
    parser.add_argument("new")
    parser.add_argument("plugin")
    args = parser.parse_args()
    for value in (args.old, args.new, args.plugin):
        if not HASH.fullmatch(value):
            sys.exit(f"not a 40-character lowercase commit hash: {value!r}")
    try:
        text = rewrite(args.file.read_text(), args.old, args.new, args.plugin)
    except (ValueError, KeyError, tomllib.TOMLDecodeError) as error:
        sys.exit(f"{args.file}: {error}")
    with tempfile.NamedTemporaryFile("w", dir=args.file.parent, delete=False) as temporary:
        temporary.write(text)
    os.chmod(temporary.name, args.file.stat().st_mode & 0o777)
    os.replace(temporary.name, args.file)
    print(f"hyprpm pin: {args.new} -> {args.plugin}")


if __name__ == "__main__":
    main()
