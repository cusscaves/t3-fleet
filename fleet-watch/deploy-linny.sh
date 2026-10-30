#!/bin/bash
# Push fleet-watch from this repo to Linny's always-on watcher and run it once.
set -euo pipefail
cd "$(dirname "$0")"
python3 -c 'import ast;ast.parse(open("fleet-watch").read())'
scp -q fleet-watch fleet.linny.conf fleet.conf README.md linny:.local/share/fleet-watch/
ssh -o BatchMode=yes linny 'systemctl --user start fleet-watch.service && ~/.local/bin/fleet-watch --status'
