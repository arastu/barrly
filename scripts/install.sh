#!/usr/bin/env bash
# Release build, bundle to ~/.local/share/barrly/Barrly.app, launch.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/dev.sh release
echo
echo "Installed. Optional:"
echo "  • Launch at login: Barrly Settings › Advanced (or AeroSpace after-startup-command = ['exec-and-forget open -a ~/.local/share/barrly/Barrly.app'])"
echo "  • Hotkeys: open barrly://mode/zen   open barrly://refresh   open barrly://settings"
