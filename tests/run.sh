#!/bin/bash
# Runs the headless tests against the decompiled game:  ./tests/run.sh
# Needs Godot 3.5.3 headless and the decompiled game (git clone --depth 1 https://github.com/Blizzardfur-Maxxx/Webfishing-Decompiled).
#   GODOT=/path/to/Godot_v3.5.3-stable_linux_headless.64 GAME=/path/to/decomp ./tests/run.sh
# Against the built pck instead of the source (checks that nothing is missing from the pack):
#   AQ_PCK=/abs/path/package/Aquarium/Aquarium.pck ./tests/run.sh
# (the game's Steam library is missing here, so a few "Steam" errors at the start are normal)
set -e
cd "$(dirname "$0")"
export GAME=${GAME:-/home/claude/wf-game/decomp}
GODOT=${GODOT:-/home/claude/godot/Godot_v3.5.3-stable_linux_headless.64}
./make_stubs.sh
T=$(pwd)
cd "$GAME"
TESTS_DIR=$T timeout 300 "$GODOT" --path . -s "$T/e_aq.gd" 2>&1 | grep -E "^(ok|FAIL|---|SUMMARY|note)|SCRIPT ERROR|Parse Error"
