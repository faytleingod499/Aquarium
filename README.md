# Aquarium

The aquarium tank holds **up to 5 fish** instead of 1, and you choose which ones to keep.

*This mod was created with the assistance of AI.*

- Client side only: nothing to install on the server, and it works on any server.
- No menu and nothing to set up.

## How it works

Use the aquarium tank (the same interact key as before). A list opens with the five places in the tank:

- **Add held fish**: hold a fish (hotbar), use the tank, press the button. It goes into the first free place.
- **Take**: gives that fish back to your inventory. The fish after it move up.
- **Swap**: when the tank is full and you are holding a fish, each row says Swap: your fish goes in, the old one comes back to your inventory.
- Esc or Close shuts the list.

## Who sees what

The game only lets another player's game show **2 aquarium fish per player**. That is the game's own rule and it is the same with or without this mod, so:

- Fish **1 and 2** are shown to everybody, mod or not.
- Fish **3 to 5** are shown to other players **who also have this mod**. Players without the mod see only fish 1 and 2, and nothing can change that on your side.
- The list says which is which ("everyone can see this fish" / "players with this mod can see this fish").

Put the two fish you want everybody to see in the first two places (take a fish out and add it again to change the order).

How it works: fish 3 to 5 are written into your Steam lobby data (their type, size and quality, a few dozen characters), the same way other mods share small things, and the mod on the other side shows them while that player is in the aquarium. Everything read from another player is checked first (only fish the game knows, sizes the game can roll, at most 3 fish). Players you have hidden are not shown, and at most 24 players / 60 fish are shown at once.

## Your fish are safe

- Fish 1 is the game's own aquarium slot, kept in the game's own save. If you remove the mod, that fish is still there.
- Fish 2 to 5 are kept in your user folder, one file per save slot (`aquarium_slot_<number>.json`, next to the game's save files). If you remove the mod, they stay in that file and come back when you install it again. Take them out first if you won't be using the mod again.
- Starting a new game in a save slot clears that slot's extra fish.
- A fish can never be in your inventory and the aquarium at once: if the game's save and the mod's file ever disagree after a crash, the fish stays in your inventory.

## Also

The game re-sends your aquarium fish to everybody every 10 seconds. The mod also sends them the moment somebody joins (the game's own "send on join" call fails with an error), so a new player sees your fish at once instead of up to 10 seconds later.

Source and license (MIT): https://github.com/faytleingod499/Aquarium

## Building

```
godot --no-window -s pack.gd      # rebuilds package/Aquarium/Aquarium.pck (set PCK_OUT / PCK_SRC_DIR to absolute paths if you run it from another folder)
./build.sh                        # out/Aquarium-<version>.zip, the Thunderstore upload
```

For every upload bump `version_number` in `thunderstore/manifest.json`, `Version` in `package/Aquarium/manifest.json` and `VERSION` in `source/mods/Aquarium/main.gd`, and add a `thunderstore/CHANGELOG.md` entry.

## Tests

`tests/run.sh` runs `tests/e_aq.gd` headless in Godot 3.5.3 against the decompiled game (the game's real item code, networking singleton, aquarium fish scene and tank script; the world's `_instance_actor` is copied out of the game's own `world.gd`). See `tests/README.md`.
