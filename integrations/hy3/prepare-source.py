#!/usr/bin/env python3
"""Build a patched copy of pinned hy3: the Hyprland API port, then the bounded lifetime fix."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source, output, port_patch = map(Path, sys.argv[1:])


def replace(text, old, new):
    if text.count(old) != 1:
        raise SystemExit('Pinned hy3 source changed; review the lifetime patch: ' + old[:100])
    return text.replace(old, new)


with tempfile.TemporaryDirectory() as scratch:
    tree = Path(scratch) / 'hy3'
    shutil.copytree(source, tree, ignore=shutil.ignore_patterns('.git'))
    for path in tree.rglob('*'):
        path.chmod(path.stat().st_mode | 0o200)  # Nix store copies are read-only
    subprocess.run(['patch', '-p1', '--forward', '--batch', '-d', str(tree), '-i', str(port_patch.resolve())],
                   check=True)

    layout = (tree / 'src/Hy3Layout.cpp').read_text()
    node = (tree / 'src/Hy3Node.cpp').read_text()
    layout = '#include "HyprflipSafety.hpp"\n' + layout
    for signature in (
        'void Hy3Layout::insertNode(UP<Hy3Node> node_up, std::optional<Vector2D> focalPoint) {',
        'void Hy3Layout::recalcGeometry(bool no_animation) {',
        'Hy3Node* Hy3Layout::getNodeFromWindow(const CWindow* window) {',
        'Hy3Node* Hy3Layout::getNodeFromTarget(SP<Layout::ITarget> target) {',
    ):
        layout = replace(layout, signature, signature + '\n\thyprflipPruneExpiredTargets(this->root.get());')
    layout = replace(layout, 'if (node->is_target() && node->as_target() == target)',
                     'if (node->is_target() && node->valid() && node->as_target() == target)')
    node = replace(node, 'co_yield *this->as_window();',
                   'if (this->valid()) {\n\t\t\tif (auto window = this->as_window()) co_yield *window;\n\t\t}')
    (tree / 'src/Hy3Layout.cpp').write_text(layout)
    (tree / 'src/Hy3Node.cpp').write_text(node)

    # Rewrite only changed files so incremental builds stay incremental.
    for path in tree.rglob('*'):
        if path.is_dir():
            continue
        target = output / path.relative_to(tree)
        data = path.read_bytes()
        if not target.exists() or target.read_bytes() != data:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
