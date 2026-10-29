# Tests

- `run.sh` runs `e_aq.gd` headless (Godot 3.5.3) inside the decompiled game project (`GAME=...`, default `/home/claude/wf-game/decomp`; get it with `git clone --depth 1 https://github.com/Blizzardfur-Maxxx/Webfishing-Decompiled`). Nothing from the game is stored in this repo: `make_stubs.sh` generates `stubs/world.gd` from the game's `world.gd` and links the mod into the game project as `mods/Aquarium`.
- `AQ_PCK=/abs/path/package/Aquarium/Aquarium.pck ./run.sh` runs the same checks against the built pck alone.
- The game's Steam library is missing, so the game's `Network` stops initialising partway; `e_aq.gd` sets the few variables the mod touches. One "LOBBY_TYPE_PUBLIC" error at the start is expected.
- `v_aq.gd` renders the list at 1920x1080 with the game's own HUD theme (windowed Godot build under `xvfb-run`, see the comment at the top of the file); pictures go to `tests/shots/` (ignored by git).
- Covers: the tank hook, filling the tank to 5 and refusing a 6th, take / swap / compaction, the file (saved, loaded, damaged, unknown or duplicate fish, other save slots, new game), which fish are real announced actors and which stay local, that local fish send nothing, the join resend, visibility by zone, and the game's own limit of 2 aquarium fish per other player. Mutation-checked: breaking the mod's local-only handling or the join takeover makes the suite fail.
- Not covered (needs the real game): GDWeave loading the pck, the game's compiled scripts, real multiplayer.
