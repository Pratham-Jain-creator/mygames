# Abyssal Extraction: where things live

## The loop in one paragraph
You wake in the **base**, craft at the **workbench** (armor, forged charms, memory echoes; uses banked materials and
**ash as fuel**), then take the stairs into **floor 1 of 10**. Every floor has a 15-minute timer. Loot is **carried**
(lost on death) until you **extract**: at the terminal in the floor's start room, or by climbing back to the base.
When the timer ends the floor reshuffles: safe in the start/boss room, crushed anywhere else. Beat the floor's boss
to open the stairs down. Floor 10's boss is Count Dracula (he and his vampire minions summon bats).

## Code map
| What | Where |
|---|---|
| All fixed data: materials, armor, charms, grafts, sword forms, modules, blueprints, recipes, boss schedule | `scripts/run/run_data.gd` |
| Live state: carried / banked loot, loadout, stat totals, extraction, death penalty, saving | `scripts/run/run_state.gd` (autoload `Run`) |
| What enemies / chests / bosses drop, pickups | `scripts/run/loot.gd`, `scripts/run/pickup.gd`, `scripts/chest.gd` |
| The prisoner, his sword and its three forms | `scripts/player.gd`, `scripts/blade.gd`, `scripts/sprite_lib.gd` (frames are built from the sheets in code) |
| Floor size, special-room quotas, boss list | `scripts/level_config.gd` |
| Room placement (WFC) and the special-room planner | `scripts/level_generator.gd` |
| Every special room | `scripts/rooms/` (`special_rooms.gd` is the registry; `boon_room.gd`, `curse_room.gd`, `hidden_room.gd`, `elite_room.gd`, `survival_room.gd`) |
| Menus | `scripts/ui/` (`ui_kit.gd` = the look, `workbench_screen.gd`, `loadout_screen.gd`, `choice_menu.gd`, `run_hud.gd`) |
| Bosses | `scripts/slime_queen.gd`, `golem_boss.gd`, `mimic_boss.gd`, `dracula_boss.gd` (all `BossBase`), `scripts/boss_room.gd` |

## How to add...
* **A charm / graft / armor set / module**: one dictionary entry in `run_data.gd` (plus a recipe line for charms and armor).
  Stats are summed by `Run.stat()`; see the stat list at the top of `run_data.gd`.
* **A boon room**: add the kind to `SpecialRooms.KINDS` and a `_build_<kind>()` function in `boon_room.gd`.
  Curses and hidden rooms work the same way in their own files.
* **A new sword / weapon**: the sword's forms are `RunData.FORMS`; a new archetype is a new row (and an attack animation).
* **A new enemy sheet**: add a builder to `sprite_lib.gd`; scenes only need an empty `AnimatedSprite2D`.

## Notes
* New PNG sheets are read straight from the file until the editor imports them, so they work immediately.
* The profile (stash, blueprints, forged charms, armor) is saved to `user://profile.json`.
* Anything removed from the old sandbox game was moved (not deleted) to `_chrono_backup_before_redesign/`, next to the project folder.
