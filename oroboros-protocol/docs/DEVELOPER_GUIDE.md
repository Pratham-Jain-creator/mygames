# Oroboros Protocol: The Complete Developer Guide

Written so that someone who has **never programmed** can still find things, change text, tweak numbers, and add new cards. Where code is unavoidable, it is shown as a copy-and-adapt template.

> **How to use this guide.** Part 1 explains the game. Part 2 explains the project folders and how Godot works in 5 minutes. Part 3 describes every screen. Part 4 describes every reusable widget. Part 5 is the **cookbook**: step-by-step recipes ("I want to change a button's text", "I want to add a new Daemon"...). Part 6 is the reference for the game's rules in code. Part 7 covers testing, building and the icon. Part 8 is troubleshooting.
>
> If you only want to do something specific, jump to Part 5 and use the table of contents below.

---

## Table of contents

1. [What the game is](#part-1-what-the-game-is)
2. [Project layout and Godot basics](#part-2-project-layout-and-godot-basics)
3. [Every screen, in detail](#part-3-every-screen-in-detail)
4. [Reusable widgets (components)](#part-4-reusable-widgets-components)
5. [The Cookbook: how to change and add things](#part-5-the-cookbook)
6. [Rules reference: how the game works in code](#part-6-rules-reference)
7. [Testing, building, icon, audio](#part-7-testing-building-icon-audio)
8. [Troubleshooting and gotchas](#part-8-troubleshooting-and-gotchas)
9. [Glossary: fiction names vs code names](#part-9-glossary)

---

# Part 1: What the game is

**Oroboros Protocol** is a roguelike card game (think Balatro with a hacking theme). Godot 4.7, GL Compatibility renderer, 1280x720, runs on PC and Android.

You are an **Operator** breaking into **Servers**. You plant a program, your **OROBOROS PROTOCOL**, that siphons **bytes** (the score) out of the Server. The catch: the Protocol is a snake eating its own tail. It can drain the Server, or it can corrupt and destroy it. You are managing the damage your own Protocol causes.

## The core loop

1. A run has **8 Networks**. Each Network has **3 Servers**: Proxy (1x threshold), Mainframe (1.5x), Sentinel (2x, with a special "boss" rule).
2. In a Server you have **4 turns**. Every turn you are dealt a **room** of 4 **Nodes** (cards) from your **Tailbytes** (your deck).
3. You choose **exactly 3 Nodes** and the order to resolve them. The 4th goes into your **Stash** and is forced into the next room.
4. Press **EXECUTE**. Nodes resolve in order, then bytes are counted: **Base Bytes x Overclock**.
5. Reach the Server's **Threshold** (the quota of bytes) to clear it. Money is paid and you visit the **Black Market** (shop).
6. You lose if the Server's **Integrity** (health) reaches 0, or if you run out of Nodes before reaching the Threshold.

## The four Node types

| Name in game | Code name | Colour | What it does when resolved |
|---|---|---|---|
| **Siphon** | `DATA` | cyan | Adds its value x2 to Base Bytes |
| **Glitch** | `ICE` | red | Damages Server Integrity by its value (minus Firewall strength) |
| **Firewall** | `BREACH` | amber | Equips as your barrier (blocks Glitch damage) |
| **Patch** | `COOLANT` | green | Repairs Integrity by its value |

Every unblocked point of damage "overclocks" the Server: **+1 Overclock for the rest of that Server**. Taking damage on purpose and then repairing it is the heart of the game.

## Core rules that must never be changed for a single card

These are written in `CLAUDE.md` (at the project root) and are the owner's standing guardrail:

- Exactly **3 Nodes** are resolved per turn.
- Room size = 3 + Stash capacity. Deal 4 / resolve 3 / stash 1.
- Base Server Integrity is **10**.
- You lose only at 0 Integrity, or when the Tailbytes run out without meeting the Threshold.

**If a new card/Daemon would need one of these rules to change, change the card's own text or behaviour instead.** The card adapts to the engine, never the other way round.

---

# Part 2: Project layout and Godot basics

## Godot in 5 minutes (for non-developers)

- A **scene** (`.tscn` file) is a **tree of nodes**: a layout. Example: a button scene has a root, a label, a coloured bar.
- A **script** (`.gd` file) is code attached to a scene (or used on its own). Scripts make things happen.
- The **Scene dock** (top-left in the editor) shows the node tree of the open scene. Click a node and the **Inspector** (right side) shows its properties: text, colour, size, position.
- **You can change almost all visuals without code**: open the `.tscn` file by double-clicking it in the **FileSystem dock** (bottom-left), click a node, edit it in the Inspector, press **Ctrl+S**.
- Press **F5** to run the whole game, **F6** to run just the open scene.
- A node with a **film-clapper icon** is a scene instanced inside another. Right-click it and choose **Editable Children** to edit inside it, or open its own `.tscn`.
- **"Unique name" nodes** show a `%` after their name in the Scene dock (for example `%NewRunButton`). Scripts find them by that name, so **never rename a `%` node** unless you also update the script that mentions it.

## Folder map

```
oroboros-protocol/
  project.godot            Project settings (name, icon, autoloads, key bindings)
  export_presets.cfg       Android export settings
  CLAUDE.md                Design guardrails + terminology (read this first)
  icon.svg                 Old placeholder icon (the real icon is in assets/gameIcon)
  assets/
    gameIcon/              Game icon PNGs (also Android launcher sizes)
    music/                 Background music (mp3)
  autoload/                "Singletons": always-on services (see below)
  scenes/                  Everything you can see
    main_menu/ network_map/ server/ shop/ game_over/ pause_menu/
    daemon_sell_popup/ tutorial/
    components/            Reusable widgets (cards, buttons, bars, overlays)
  scripts/
    enums/enums.gd         Colours, type names, rarity names (shared everywhere)
    data/                  Plain data classes (Deck, NodeData, ServerState, tutorial script)
    database/              The content tables: Daemons, Subroutines, Bosses, Items, Progression
    logic/                 Game rules with NO UI: scoring, turn resolving, shop generator
  shaders/post_fx.gdshader CRT/scanline screen effect
  theme/oroboros_theme.tres Fonts, button and panel styles used by every screen
  tools/probe/             Developer test scenes (not shipped)
  docs/                    Documentation (this file, ARCHITECTURE.md)
  builds/                  Export output (empty until you export)
```

**Rule of thumb:** *what something looks like* lives in `scenes/`. *What something is worth / does* lives in `scripts/database` and `scripts/logic`. *Words the player reads* live in a handful of known places (see the table in Section 5.1).

## The autoloads (always-running services)

Defined in `project.godot` under `[autoload]`. They are available by name from any script.

| Name | File | What it does |
|---|---|---|
| `EventBus` | `autoload/event_bus/event_bus.gd` | A message board. Signals such as `money_changed`, `health_changed`, `daemons_changed`, `toast_requested`, `daemon_popup`. Screens listen to it so logic never touches UI directly. |
| `RunState` | `autoload/run_state/run_state.gd` | **The whole current run**: money, health, Tailbytes (deck), Daemons, consumables, Root Access ("vouchers"), Subroutine levels, which Network/Server you are on. Also constants like `BASE_MAX_HEALTH = 20`, `START_MONEY = 4`, `MAX_DAEMONS = 5`, `MAX_CONSUMABLES = 3`, `TURNS_PER_SERVER = 4`, `MIN_DECK_SIZE = 12`. Most "change a number" requests are here. |
| `AudioService` | `autoload/audio_service/audio_service.gd` | Plays sound effects (generated by code, no sound files) and the looping music. `AudioService.play("click")`. |
| `SceneManager` | `autoload/scene_manager/scene_manager.gd` + `.tscn` | Changes screens with a fade. `SceneManager.go(SceneManager.SERVER)`. Holds the path constants of every screen. |
| `PostFX` | `autoload/post_fx/post_fx.gd` + `.tscn` | The CRT screen effect, screen shake and the red "impact" flash. |
| `TooltipService` | `autoload/tooltip_service/tooltip_service.gd` + `.tscn` | The one shared hover tooltip (long-press on phones). |

---

# Part 3: Every screen, in detail

All screens share this skeleton: a root `Control`, a `Background` (solid dark `ColorRect`), a `HexBackdrop` (the faint falling hex numbers, now with the game emblem), then a `SafeArea` (keeps content away from phone notches) holding the real layout.

Navigation flow:

```
Main Menu --New Run--> Network Map --Connect--> Server --(cleared)--> Shop --Leave--> Network Map ...
Main Menu --Tutorial--> Server (scripted) ----------------------------------------> Main Menu
Server --(lost or won run)--> Game Over --> Network Map (new run) or Main Menu
```

## 3.1 Main Menu

- Scene: `scenes/main_menu/main_menu.tscn`   Script: `scenes/main_menu/main_menu.gd`
- Contains: `TitleLabel`, `SubLabel` (the title text), `NewRunButton`, `TutorialButton`, `RulesButton`, `CrtButton`/`SfxButton`/`MusicButton` (toggles), `QuitButton` (hidden on phones/web), `StatsLabel` (runs/wins/best network from the save file), and `HowToPanel` (the written rules overlay with `Text` and `CloseButton`).
- **To change a button's label:** open the scene, select the button, change **Text** in the Inspector. (The tutorial button's label is overwritten in the script to say "START HERE" until the tutorial is done; see `_ready`.)
- **To change the hover tip of a button:** in `main_menu.gd`, find the `set_tip("TITLE", "text")` line for that button.
- **To change the written Rules ("?" screen):** the whole text is the function `_rules_text()` at the bottom of `main_menu.gd`. It uses BBCode (see 5.1). The Subroutine list in it is generated from `SubroutineDB`, so numbers there never go out of date.
- **To change a toggle's behaviour:** `_on_crt`, `_on_sfx`, `_on_music`, and `_refresh_toggles` in the same script.
- Animations: an `AnimationPlayer` with `intro`, `how_show`, `how_hide`.

## 3.2 Network Map

- Scene/Script: `scenes/network_map/network_map.tscn` / `network_map.gd` (extends `BaseScreen`).
- Layout: `Header` (title "NETWORK n / 8", money, `GearSpacer` that reserves room for the Settings gear), `Cards` (three `ServerCard`s), `RigRow` (a one-line stat label, **DECK** button, **CONNECT** button), `Bottom` (the `DaemonRack` of 5 Daemon slots and the `ConsumableBox` of 3 software slots).
- Built in code: `_ready()` makes the 3 server cards; `_build_rig()` makes the Daemon and consumable rows. The stats label text ("INTEGRITY ... | TAILBYTES ... | STASH SLOTS ... | EJECTS ...") is in `_build_rig`.
- You can use consumables (Executables/Corruptions) from here.

## 3.3 Server screen (where the game is played)

- Scene: `scenes/server/server_screen.tscn`   Script: `scenes/server/server_screen.gd` (about 770 lines; extends `BaseScreen`)
- Layout from top to bottom:
  - **TopBar**: `QuotaBlock` (server name, threshold, progress bar, progress text, **BossButton** shows the boss rule), `ScoreDisplay` (the live `[Base] x [Overclock]` equation), `RigBlock` (Integrity label + the LED health bar).
  - **MiddleZone**: `Room` (the 4 or 5 cards, laid out in one row), `StashRow` (the Stash tray + the `WeaponBay` showing your equipped Firewall), `ActionRow` (**CLEAR**, **FIREWALL: AUTO/OFF**, **EJECT**, **EXECUTE**).
  - **BottomZone**: `CreditsLabel` (money), **TAILBYTES** button, **SUBROUTINES** button, `DaemonRack` (5 slots), `ConsumableBox` (3 slots).
  - Overlays (hidden until needed): `ClearedPanel` (payout), `BossBanner` (boss intro), `DeckViewer`, `SubPanel`, `TypePicker`, `Toast`, `PauseMenu`.
- **Phases** (`enum Phase`): `INTRO` (banner) -> `DRAFT` (you choose) -> `RESOLVING` (animation playing) -> `ENDED`.
- **Keyboard**: Space/Enter = Execute, **F** = Eject, **Esc** = clear selection/close overlay, **D** = Tailbytes tracker, **S** = Subroutines. Debug builds only: **F1** +$50, **F2** instantly clears the Server. (Key bindings are in `project.godot` under `[input]`; the handler is `_unhandled_input`.)
- **Important functions** in `server_screen.gd`:
  - `_deal()` deal a room, `_build_room_cards()` spawns the cards (the Room is widened so 5 Nodes stay on one row after RAM Expansion).
  - `_on_card_activated()` click a card to select/deselect; the order you click is the resolve order.
  - `_refresh_preview()` the live equation while selecting (only Subroutine values are shown while selecting).
  - `_on_execute()` calls the rules engine (`TurnResolver.resolve`), then `_play_events()` replays what happened (damage, healing, etc.), then `_play_cascade()` shows the score being added Node by Node with each Daemon trigger.
  - `_on_flee()` is the Eject button (the code still calls it "flee").
  - `_on_daemon_activated()` / `_on_sell_confirmed()` the click-to-sell bubble on Daemons (only while drafting; disabled in the tutorial).
  - `_server_cleared()`, `_game_over()` end-of-server handling.
  - `tut_target(key)` returns the UI element the tutorial can spotlight.
- **Boss banner/boss rules** come from `BossDB` (see 5.9).

## 3.4 Black Market (Shop)

- Scene/Script: `scenes/shop/shop_screen.tscn` / `shop_screen.gd` (extends `BaseScreen`)
- Layout: `Header` (title, sub-title, money, gear spacer); `Body` has a **left pane** (scrolling list of listings, `ListingsBox`) and **right pane** (`DetailPanel` with kind, name, description and the **DetailAction** BUY/SELL/USE button, plus "YOUR RIG" list of your Daemons and consumables); `Footer` with **REROLL**, **PURGE**, **TAILBYTES**, **LEAVE**.
- Stock is generated by `ShopGenerator` (2 Daemon slots, 2 item slots (3 with Backdoor), and one Root Access offer that is fixed for the whole Network).
- Buying is handled in `_buy()`; the `match l.kind` block decides what each kind of item does.
- Selling a Daemon here pays the full sell value (half of buy price + sell bonus); selling mid-Server pays half of that.
- The sub-title text ("UNREGISTERED VENDORS, NO REFUNDS") is in `_ready`.

## 3.5 Game Over

- Scene/Script: `scenes/game_over/game_over.tscn` / `game_over.gd`
- Title is "CORE BREACHED" (win) or "SERVER DESTROYED" (loss); both strings are in `_ready()`. Stats lines are the `"\n".join([...])` block. Buttons: **NEW RUN**, **MAIN MENU**.

## 3.6 Pause / Settings overlay

- Scene/Script: `scenes/pause_menu/pause_menu.tscn` / `pause_menu.gd`
- A **GearButton** in the top-right corner of Map, Server and Shop opens a panel with Resume, CRT/SFX/Music toggles, **New Game** and **Main Menu** (these two need a second click to confirm: "armed" state). The **P** key also opens it, and Esc closes it. The owning screen decides when it may open through `can_open_settings()`.
- Screens that have a header include a `GearSpacer` (an empty 118px-wide control) so the money label never sits under the gear. If you add a new header, add the same spacer.

## 3.7 Daemon sell bubble

- Scene/Script: `scenes/daemon_sell_popup/daemon_sell_popup.tscn` / `.gd` (no `class_name`, on purpose).
- Click a Daemon on the Server screen: a small panel appears beside it with the Daemon's name, "SELL $n" and "half price". Click outside or press Esc to close. Dragging a Daemon to reorder still works (drag handled by `DaemonCard`).
- To change its wording, edit the labels in the scene (`NameLabel`, `SellButton`, `Note`).

## 3.8 Tutorial

- Overlay scene: `scenes/tutorial/tutorial_overlay.tscn`   Director: `scenes/tutorial/tutorial_director.gd`   **Content: `scripts/data/tutorial_script.gd`**
- The tutorial runs on the **real Server screen** with a fixed card order and a bot called **NODE-9**. Everything except the highlighted control is blocked.
- Full editing instructions are in Section 5.10.

---

# Part 4: Reusable widgets (components)

All live in `scenes/components/<name>/` (scene and script together).

## The inheritance tree (important when making new things)

```
InteractiveControl            (hover tooltip, click, long-press; "Visual" child + AnimationPlayer)
  |- ActionButton             every button in the game
  |- NodeCard                 the Node cards
  |     |- DataCacheCard (Siphon)   |- IceCard (Glitch)
  |     |- BreachCard (Firewall)    |- CoolantCard (Patch)
  |- DaemonCard               Daemon slot / installed Daemon (drag to reorder)
  |- ShopListing              a row in the shop, owned list, consumable slot
  |- WeaponBay                the equipped-Firewall display
  |- ServerCard               one of the 3 Servers on the map
BaseScreen                    (deck viewer, type picker, toast, consumable flow)
  |- server_screen, shop_screen, network_map
```

| Widget | What it is |
|---|---|
| `InteractiveControl` | Base for anything hoverable/clickable. Emits `activated`. **Override `get_tip_data()`** to return `{title, body, color}` for the tooltip. Plays animations by name: `hover_in`, `hover_out`, `press`, `release`, `disabled`, `enabled`. A child named `Visual` is what those animations move/scale. |
| `ActionButton` | Keyboard-key style button. Properties **Text**, **Accent** (bottom bar colour), `tip_title`/`tip_body`. Call `set_tip(title, body)` from scripts. |
| `NodeCard` (+4 variants) | The Node card (224x126). Shows value, type, icon, modifier badges (E/Z/H/$), order badge, face-down cover. Animations: `deal_in`, `select`, `deselect`, `hit`, `resolve`, `deny`, `pulse`, `reveal`, `ceiling_hit`. |
| `NodeCardFactory` | `NodeCardFactory.spawn(parent, node_data, scale)` builds the right card variant. Maps type -> variant scene. |
| `NodeIcon` | The vector icon on each card (drawn by code, no image files). |
| `DaemonCard` | Daemon slot. `bind(instance)` shows a Daemon; empty slots show "[ SLOT n ]". Drag to reorder. Tooltip shows description and sell value. |
| `ShopListing` | A wide row. `setup(kind, name, price_text, colour, tip, affordable)`, `set_empty(text)`, `set_sold(bool)`, `set_selected(bool)`. `compact = true` for small rows. |
| `WeaponBay` | Shows Firewall strength and ceiling; animates ceiling drops and a shatter. |
| `ServerCard` | A Server tile on the map (locked/current/cleared). |
| `ScoreDisplay` | The `Base x Overclock = Total` equation with tick-up animation. Methods: `set_static`, `begin_cascade`, `animate_to`, `bump_mult`, `pop_total`. |
| `SubPanel` | The Subroutines list overlay (always up to date with Firmware levels). |
| `DeckViewer` | The Tailbytes overlay. View mode (tracker) or pick mode (`await viewer.pick(title, min, max)`). |
| `TypePicker` | Small popup to choose a Node type (used by Reformat). |
| `Toast` | The one-line banner at the top ("DAEMON INSTALLED..."). |
| `FloatingText` | Rising numbers like "-3" or "+$1". |
| `LedHealthBar` / `LedBlock` | The Integrity LEDs. |
| `HexBackdrop` | The falling hex numbers, waveform and the faint game emblem in the background. Properties: `column_count`, `base_alpha`, `emblem_alpha`. |
| `SafeAreaContainer` | Root margin container of each screen; respects phone notches. |

**The animation rule:** *all* motion is authored in each scene's `AnimationPlayer` (open the scene, open the Animation panel at the bottom). Scripts only say "play the animation called X". So to change how something moves, edit its animation in the editor, not the script.

---

# Part 5: The Cookbook

## 5.1 Where does every piece of text live? (cheat sheet)

| I want to change... | Go to |
|---|---|
| A **button's label** | Open the screen's `.tscn`, select the button, edit **Text** in Inspector. |
| A **button's hover tip** | In the screen's `.gd`, search for `set_tip(` |
| **Game title / subtitle** on main menu | `main_menu.tscn` -> `TitleLabel`, `SubLabel` -> Text |
| **The "?" Rules text** | `main_menu.gd` -> `_rules_text()` |
| **Tutorial words** | `scripts/data/tutorial_script.gd` -> `steps()` |
| **Daemon name / description / rarity** | `scripts/database/daemon_db.gd` -> `RAW` list |
| **Executable / Corruption / Root Access name, description, price** | `scripts/database/item_db.gd` |
| **Subroutine names, recipes, values** | `scripts/database/subroutine_db.gd` |
| **Boss names and descriptions** | `scripts/database/boss_db.gd` |
| **Node card tooltip text** | `scenes/components/node_card/variants/*_card.gd` -> `_describe()` |
| **Threshold numbers, rewards, server names** | `scripts/database/progression.gd` |
| **Toast messages ("SOLD FOR $..")** | Search the project for the text (Ctrl+Shift+F in Godot's Script editor). |
| **Game over wording** | `scenes/game_over/game_over.gd` |
| **Shop sub-title** | `scenes/shop/shop_screen.gd` -> `_ready()` |
| **Starting money / health / Daemon slots / Eject count** | `autoload/run_state/run_state.gd` (constants at the top) |
| **Colours of everything** | `scripts/enums/enums.gd` (palette) and `theme/oroboros_theme.tres` |
| **Fiction names** (Siphon, Glitch, ...) | `scripts/enums/enums.gd` -> `TYPE_NAMES` / `TYPE_SHORT`; plus any hand-written text |

**Tip:** to find any text the player sees, copy a few words and use **Search in Files** (Ctrl+Shift+F in the Godot editor, or Ctrl+Shift+F in VS Code). It will show you the file and line.

**Automatic keyword colours.** `Fmt.rich(text)` (in `scripts/logic/fmt.gd`) turns every mention of Siphon, Glitch, Firewall and Patch (singular, plural, any case) into bold text in that Node type's colour. It is already applied to tooltips, the Black Market detail pane and rows, the Rules text, the tutorial, the boss banner and the Subroutines panel. Text already inside a `[color]` span is left alone. To use it on a new text box, the box must be a **RichTextLabel with BBCode enabled**, and you set `label.text = Fmt.rich("your text")`. It will not work on a plain `Label`. To add another word (for example a new Node type) edit the `words` list in that function.

**BBCode (text styling) cheat sheet.** Descriptions and tooltips use BBCode:
`[b]bold[/b]`, `[i]italic[/i]`, `[color=#FF003C]red text[/color]`. Palette: Siphon cyan `#66FCF1`, Glitch red `#FF003C`, Firewall amber `#FFB400`, Patch green `#00FA9A`, Daemon magenta `#FF00FF`, money gold `#FFD866`. Plain `Label` nodes do **not** understand BBCode; only `RichTextLabel` ones do.

## 5.2 Change a number (balance)

| Number | File and name |
|---|---|
| Start money ($4) | `run_state.gd` -> `START_MONEY` |
| Base Integrity (10; Cooling System, Failsafe +5, Glass Cannon caps at 5) | `run_state.gd` -> `BASE_MAX_HEALTH` (also update tutorial text and CLAUDE.md guardrail if you do) |
| Daemon slots (5) | `MAX_DAEMONS` (also: scenes show 5 slots because they loop over this constant) |
| Software slots (3) | `MAX_CONSUMABLES` |
| Turns per Server (4) | `TURNS_PER_SERVER` |
| Base Ejects (2) | `BASE_FLEES` |
| Smallest Tailbytes allowed (12) | `MIN_DECK_SIZE` |
| Number of Networks (8) | `FINAL_NETWORK` plus add a threshold to `BASE_QUOTAS` in `progression.gd` |
| Thresholds | `progression.gd` -> `BASE_QUOTAS` (one per Network); `KIND_MULT` (1.0 / 1.5 / 2.0 for Proxy/Mainframe/Sentinel) |
| Server clear reward ($3/$4/$5) | `progression.gd` -> `KIND_REWARD` |
| Interest ($1 per $5, max $5) | `scripts/logic/server_logic.gd` -> `payout()` |
| Unused-turn bonus ($1 per turn) | same function, `UNUSED TURNS` line |
| Daemon price by rarity | `daemon_db.gd` -> `RARITY_COST` = `[3, 5, 7, 9, 12]` (Common, Uncommon, Rare, Epic, Legendary) |
| How often each rarity appears in the shop | `scripts/logic/shop_generator.gd` -> `RARITY_WEIGHTS = [52, 28, 13, 5, 2]` |
| Shop Daemon slots (2) | `shop_generator.gd` -> `DAEMON_SLOTS` |
| Reroll cost | `run_state.gd` -> `reroll_cost()` |
| Purge cost | `run_state.gd` -> `purge_cost()` |
| Firmware price ($4) | `item_db.gd` -> `FIRMWARE_COST` |
| Executable/Corruption/Root Access prices | `item_db.gd` (the `cost` field) |
| Subroutine base bytes and Overclock | `subroutine_db.gd` -> `SUBS` (`base`, `mult`, and `lvl_base`/`lvl_mult` = gain per Firmware level) |
| Chance mix of shop items | `shop_generator.gd` -> `_roll_item()` (45% Executable, 30% Firmware, 25% Corruption) |
| What a Daemon's effect is worth ("+10 Base Bytes" etc.) | `daemon_logic.gd`: **and** update its text in `daemon_db.gd` so they match |

> **Always keep the description text and the number in code in sync.** The description is only text; the real effect is in `daemon_logic.gd`.

## 5.3 Add a new **Daemon**

A Daemon is a permanent upgrade. Adding one takes **two files**.

### Step 1: define it in `scripts/database/daemon_db.gd`

Add one row to the `RAW` list, in the format `[id, "Display Name", rarity, "Description"]`:

```gdscript
["lucky_charm", "Lucky Charm", 1, "+2 Overclock if you resolve a Node valued 7."],
```

- `id`: unique, lowercase with underscores. Never change it later (it is saved in logic).
- Rarity: `0` Common, `1` Uncommon, `2` Rare, `3` Epic, `4` Legendary. Price and shop frequency come from rarity automatically.
- It will automatically appear in the shop and in the sell list. **No scene changes are needed.** (Also update the "75 Daemons" counts in comments if you care.)

### Step 2: give it behaviour in `scripts/logic/daemon_logic.gd`

Pick **one** of three places depending on *when* the Daemon acts:

**A. It adds to the turn's total (once per turn)** -> inside `score(inst, ctx)`, add a `match` entry:

```gdscript
"lucky_charm":
    if ctx.nodes.any(func(n): return n.eff_value == 7):
        _mult(ctx, inst, 2.0)      # +2 Overclock
```

Helpers: `_chips(ctx, inst, amount)` adds Base Bytes; `_mult(ctx, inst, amount)` adds Overclock; `_xmult(ctx, inst, x)` multiplies Overclock. These also write the line that appears in the score cascade animation.

**B. It reacts to each Node individually** (Balatro "per card") -> inside `score_node(inst, node, ctx)`:

```gdscript
"lucky_charm":
    if node.eff_value == 7:
        _mult(ctx, inst, 2.0)
```

These fire right after each Node is added, in Node order, so the cascade shows them one by one.

**C. It reacts to an event (money, healing, growth, etc.)** -> inside `_on_event(d, ev, p, pops, is_copy)`, in the `match ev:` block. Events: `server_start`, `flee` (Eject), `damage`, `node_resolved`, `ice_destroyed`, `node_deleted`, `bypass`, `weapon_break`, `turn_end`, `shop_enter`. Example (earn $1 each Eject):

```gdscript
"flee":
    if d.id == "lucky_charm":
        RunState.money += 1
        pops.append(_pop(d, "+$1", 1))
```

`_pop(d, "text", money)` makes the Daemon flash with a small text in the UI. Pass the money amount as the third argument if money changed so the HUD balance updates at the right moment.

### Remembering things (growing Daemons)

Every Daemon instance has a private notebook `inst.s` (a dictionary) that persists for the run. `s.n` starts at `0.0`. Example from Trojan: `s.n += 0.5` on each Eject, then `_mult(ctx, inst, s.n)` when scoring. Reset it in the `server_start` event if it should reset each Server (see `rust`).

### Daemons that change core numbers

Max Integrity, Stash size, Eject count, prices: those are checked in `RunState` (`get_max_health()`, `get_stash_capacity()`, `get_flee_limit()`, `price()`, `reroll_cost()`, `purge_cost()`). Add your condition there.

### Special mention: Blueprint

`blueprint` copies the Daemon to its right. Copies only repeat **income-style triggers** (see the `is_copy` block at the start of `_on_event`). If your new Daemon's event should also be copyable, add it there too.

### Test it
Run `tools/probe/sim.tscn` (see 7.1): it plays random runs and prints errors with a `SIM` prefix.

## 5.4 Add a new **Subroutine** (a "poker hand")

In `scripts/database/subroutine_db.gd`:

1. Add its id to the `ORDER` list. **Order matters**: the first matching recipe wins, so put more specific recipes before general ones.
2. Add to `SUBS`:
```gdscript
"pincer": {"name": "Pincer", "recipe": [0, 2, 0, 1], "base": 12, "mult": 2, "lvl_base": 10, "lvl_mult": 1, "text": "2 Glitches, 1 Patch"},
```
`recipe` is `[Siphons, Glitches, Firewalls, Patches]` and must add up to 3. `base`/`mult` are the values at level 0; `lvl_*` is added per Firmware level. `text` is shown in lists.

It automatically appears in the Subroutines panel, in the Rules text, and in Firmware shop offers. Every 3-Node mix of the 4 types must still be covered by *some* Subroutine or fall to `fragment`, the fallback.

## 5.5 Add an **Executable** or **Corruption** (one-use items)

1. `scripts/database/item_db.gd`: add to `EXECUTABLES` (or `CORRUPTIONS`):
```gdscript
"swap": {"name": "Swap", "desc": "Swap the values of two Nodes.", "cost": 4, "min": 2, "max": 2},
```
`min`/`max` = how many Nodes the player must pick as targets (0/0 for items that need no target).
2. `scripts/logic/consumable_service.gd`: in `use()`, add a `match` entry that does the work (targets are in `targets`). In `why_not()`, add a rule if the item can't always be used (return a message string to refuse).
3. Done: it will appear in the shop (shop picks from this table) and can be used from the Server/Map/Shop screens.

## 5.6 Add a **Root Access** (permanent upgrade)

1. `item_db.gd` -> `ROOT_ACCESS`: add an entry (`name`, `desc`, `cost`).
2. Make it do something by checking `RunState.has_voucher("your_id")` where the effect should apply. Examples already in the code: `get_max_health()` (Cooling System), `get_stash_capacity()` (RAM Expansion), `payout()` (Offshore Account raises the interest cap), `reroll_cost()` (Admin Privileges).
3. One Root Access offer is chosen per Network from the ones you do not own yet.

## 5.7 Add a new **Node card** (a new visual/behavioural variant)

There are **two different meanings** of "new card":

### (a) A new *kind of Node* (a fifth type next to Siphon/Glitch/Firewall/Patch)
This is a **big change** and touches the core rules. Read the warning in Part 1 first: the game is balanced around 4 types and 3-Node Subroutines. If you still want it, you need to edit all of these:

1. `scripts/enums/enums.gd`: add to `NodeType`, and add entries to `TYPE_COLORS`, `TYPE_NAMES`, `TYPE_SHORT`.
2. `scripts/data/deck.gd`: `build_standard()` (the 52-card deck) and `remaining_counts()`.
3. **Card scene (inherit from NodeCard):** in the editor: *Scene -> New Inherited Scene -> choose `scenes/components/node_card/node_card.tscn`*, save as `scenes/components/node_card/variants/my_card.tscn`. Attach a script that starts with:
```gdscript
class_name MyCard
extends NodeCard

func _ready() -> void:
    super()
    node_type = Enums.NodeType.MY_TYPE

func _describe() -> String:           # the tooltip text
    return "What this Node does. Value [b]%d[/b]." % data.eff_value
```
Optional override: `_on_refreshed()` for extra read-outs (see `breach_card.gd`), `_hover_animation()` (see `ice_card.gd`).
4. `scenes/components/node_card/node_card_factory.gd`: add the scene to `SCENES`.
5. `scenes/components/node_card/node_icon.gd`: add an icon drawing for the new type (it is drawn with code lines).
6. `scripts/logic/turn_resolver.gd`: add a branch in `resolve()` (`match node.type`) for what it does.
7. `scripts/database/subroutine_db.gd`: the recipes are 4 numbers; a 5th type needs 5-number recipes and `identify()` changes.
8. Tutorial, rules text, `ConsumableService` (`format_c`, `reformat`) and the type-picker should be reviewed.

### (b) A new *modifier on existing Nodes* (like Zipped, Overclocked, Gold)
Much easier and the recommended way to add variety. See how `gold` works:
1. `scripts/data/node_data.gd`: add a variable (e.g. `var frozen := false`), include it in `duplicate_node()`, `is_modified()` and `mod_tags()` (the letter shown on the card).
2. Apply its effect in `turn_resolver.gd` (when resolved), or in the scoring loop, or via Daemon logic.
3. Give the player a way to get it: add an Executable (5.5) that sets it.

### (c) A new look for an existing type
Edit the existing variant scene (e.g. `variants/ice_card.tscn`) in the editor. All four variants inherit the structure from `node_card.tscn`, so changes made in `node_card.tscn` affect all of them.

## 5.8 Add a new **kind of consumable slot item / shop item kind**

Rare. `Enums.ItemKind` lists the kinds (`DAEMON, EXECUTABLE, FIRMWARE, CORRUPTION, ROOT_ACCESS`). A new kind needs: an enum entry and `KIND_NAMES`/`KIND_COLORS` in `enums.gd`; a case in `ItemDB.get_item()`; stock generation in `ShopGenerator`; and a case in `shop_screen.gd -> _buy()`.

## 5.9 Add or change a **Boss** (Sentinel Server rule)

1. `scripts/database/boss_db.gd`: add to `BOSSES` and to `ORDER`:
```gdscript
"frost": {"name": "The Frost", "desc": "Your first Node each turn is face down."},
```
2. Implement the rule where it applies by checking `RunState.is_boss("frost")`. Existing examples: node values (`ServerLogic.effective_value` for Wall/Mirror), Eject damage (`ServerLogic.flee` for Needle), Base Bytes (`TurnResolver.resolve` for Void), Patch (`resolve` for Leech), face-down (`ServerLogic.deal_room` for Cipher), Stash (`resolve`/`_cleanup` for Lock), Firewall wear (`TurnResolver._fight` for Furnace).
3. There are 8 bosses and 8 Networks; one boss is used per Network in shuffled order (`RunState.boss_order`). If you add more bosses than Networks, some will not appear in a run.

## 5.10 Edit the **Tutorial**

All words and the scripted flow live in **`scripts/data/tutorial_script.gd`**. Nothing in it touches the UI.

- `deck_order()` is the fixed order the cards are drawn: `[type, value]` pairs, first drawn first.
- `steps()` is a list; each step is a dictionary. Keys:

| Key | Meaning |
|---|---|
| `text` | What the bot says (BBCode). `{score}`, `{quota}`, `{health}` are filled in live. |
| `expect` | What the player must do: `next` (press NEXT), `card` (click the card in `card`), `execute`, `skip` (the Eject button), `weapon` (the Firewall toggle), `deck_open`, `deck_close`, `subs_open`, `subs_close`, `turn_done` (wait for animation). Default is `next`. |
| `target` | What to spotlight: `quota`, `score`, `rig`, `progress`, `room`, `stash`, `weapon`, `execute`, `skip`, `clear`, `weapon_toggle`, `credits`, `deck`, `subs`, `daemons`, `consumables`, `card`, or `none`. The list is built in `server_screen.gd -> tut_target()`. |
| `lit` | Card steps only: an extra area kept bright, e.g. `"lit": "room"` so the player sees every Node they are choosing among (the pulsing frame still marks the one to click). Same keys as `target`. |
| `card` | `[NodeType, value]` of the card to spotlight/require. |
| `dock` | `"top"` or `"bottom"`: where the bot panel sits. |
| `do` | An action when the step starts: `deal` (deal the next room) or `level_skirmish`. |
| `hide` | `true` hides the bot during the step. |

**To reword a step:** edit its `text`. **To add a step:** copy an existing step dictionary into the list in the right position. **To change the bot's look/name:** open `tutorial_overlay.tscn` (the bot is built from coloured rectangles; the name is `NameLabel`). The tutorial quota is `QUOTA := 600`.
**Focus dimming:** everything except the bot panel (and, on "your move" steps, the control to use) is dimmed to near-black by `shaders/tutorial_dim.gdshader`, driven by `_focus_rects()` in `tutorial_director.gd`. Dimming is off while an animation plays (`turn_done`), when the bot is hidden, and while the Tailbytes / Subroutines windows are open. `DIM_ALPHA` sets how dark it is.
The tutorial starts with `Floppy Disk` installed (`RunState.start_new_run(true)`).

## 5.11 Change how a screen looks

1. Open the screen's `.tscn` (double-click in FileSystem).
2. Select a node in the Scene dock. In the Inspector you can change **Text**, **Theme Overrides -> Font Size / Colors**, **Custom Minimum Size**, **Visible**, etc.
3. To add something: right-click the parent node -> *Add Child Node*, or drag a scene (e.g. `action_button.tscn`) from the FileSystem into the Scene dock.
4. Containers (VBox/HBox/Margin/Center) arrange their children automatically; use *Layout -> Container Sizing* instead of dragging positions.
5. **If you add a new button, it also needs wiring:** in the screen's `.gd`, add `@onready var _my_button: ActionButton = %MyButton` (make the node "Access as Unique Name": right-click -> *Access as Unique Name*) and in `_ready()` add `_my_button.activated.connect(_on_my_button)`.

**Fonts / panel and button styles:** `theme/oroboros_theme.tres` (double-click to edit in the Inspector). Changes apply everywhere.

## 5.12 Add a brand-new screen

1. Create a folder `scenes/my_screen/` with `my_screen.tscn` (root `Control`) and `my_screen.gd`.
2. Copy the skeleton from `game_over.tscn` (Background, HexBackdrop, SafeArea).
3. Add a path constant in `autoload/scene_manager/scene_manager.gd`: `const MY_SCREEN := "res://scenes/my_screen/my_screen.tscn"`.
4. Open it from anywhere with `SceneManager.go(SceneManager.MY_SCREEN)`.
5. If it needs the deck viewer/type picker/toast, extend `BaseScreen` and include nodes named `DeckViewer`, `TypePicker`, `Toast` (unique names).
6. **Do not use `class_name`** in new scene scripts (the project's convention is "duck typing" so a fresh checkout works without the editor rebuilding its class cache).

## 5.13 Change the background emblem or the falling hex numbers

`scenes/components/hex_backdrop/hex_backdrop.gd`:
- `emblem_alpha` (default 0.09): emblem strength. `base_alpha` (0.07): number brightness. `column_count` (22): number of columns.
- The emblem image is `assets/gameIcon/ouroboros_dragon_icon.png` (constant `EMBLEM_PATH`).
- It affects **all** screens because every screen includes the `HexBackdrop` scene.

## 5.13b Gloss on modified Nodes

**Modified Nodes** (Encrypted, Zipped, Overclocked, Gold) show a soft light sweep ("gloss") so they stand out (`shaders/idle_sheen.gdshader`, added by `InteractiveControl.set_idle(on, tint, strength, glossy)`; only `glossy` cards show anything). Every other card, Daemon and row is clean. To change it, edit the shader: `period` = seconds between sweeps, `0.2` = brightness. To use it on another widget that extends `InteractiveControl`, call `set_idle(true, some_colour, 1.0, true)` when it is shown.

## 5.14 Change sounds and music

- **Music:** put an mp3 in `assets/music/` and change `MUSIC_PATH` (and `MUSIC_DB` for volume) in `autoload/audio_service/audio_service.gd`.
- **Sound effects** are generated by code (no files). Each line in `_ready()` is `_make(duration, frequency, noise, decay)`. Change the numbers to change the sound; add a new line for a new sound; play it with `AudioService.play("name")`. If you want real sound files later, replace the `_streams[...]` entries with `load("res://assets/sfx/x.wav")`.

## 5.15 Change the CRT / screen effect

`shaders/post_fx.gdshader` (parameters) and `autoload/post_fx/post_fx.tscn` (the overlay and its "impact" / "glitch_small" animations). Players can turn it off with the CRT toggle (saved in settings).

## 5.16 Save data

`scripts/logic/meta_save.gd` stores settings and lifetime stats in `user://meta.cfg` (a small text file in Godot's user folder). In-run state is **not** saved: closing the game ends the run. Keys in use: `settings/sfx`, `settings/music`, `settings/crt`, `stats/runs`, `stats/wins`, `stats/best_network`, `run/start_bonus` (Seed Capital), `tutorial/done`.

---

# Part 6: Rules reference

## 6.1 Order of events in a turn (`TurnResolver.resolve`)

1. **Execute Nodes in click order.** For each Node: Firewall -> equips; Glitch -> `_fight` (use Firewall if enabled and the Glitch is within its ceiling, subtract strength, lower the ceiling to value-1, then `hurt`); Patch -> heal (unless The Leech); Siphon -> nothing yet. Gold Nodes pay money; Holo Nodes are counted. The `node_resolved` event fires for Daemons.
2. **Score.** Start from the Subroutine: Base Bytes and `Overclock = 1 + bandwidth_bonus + subroutine mult`. Then **for each Node, in order**: add the Node's bytes (Siphon x2, +10 if Zipped), +1 Overclock if Holo, then every Daemon's `score_node` left to right. After the 3 Nodes, every Daemon's `score` runs left to right.
3. **Total = floor(Base x max(1, Overclock)).** Added to the Server's bytes.
4. **Turn end** (`_cleanup`): leftover Node(s) go to the Stash (revealed if they were face-down), played Nodes are discarded, `turn_end` Daemon events fire (Mining Rig income etc.), turn counter advances.

`hurt()` is where damage happens: Shock Absorber absorbs first, health is lowered, **`bandwidth_bonus` goes up by 1** (the overclock), and `damage` Daemon events fire.

> **Order of Daemons matters** because they run left to right: put "+" effects before "x" effects. The player reorders by dragging.

## 6.2 Rooms, Stash, Eject (`ServerLogic`)

- `begin_server()`: builds the `ServerState`, shuffles the Tailbytes, fires `server_start`.
- `deal_room()`: previous Stash + draws until the room is `get_room_size()` (3 + stash capacity). Applies face-down (Cipher/Poltergeist), Quarantine, Honeypot.
- `flee()` (Eject): discards the whole room for the rest of the Server, optional boss damage (The Needle).
- `payout()`: reward + unused turns + interest.
- No mid-Server reshuffle: running out of Nodes in the draw pile ends the Server in a loss.

## 6.3 Data classes (`scripts/data`)

- `NodeData`: one card. `base_value` (permanent), `eff_value` (after boss effects), flags `zipped`, `holo`, `gold`, `encrypted`, `temporary`, `face_down`.
- `Deck`: `all_nodes` (the Tailbytes), `draw_pile`, `discard_pile`. Standard deck = 4 types x values 2..14 = **52 Nodes**.
- `ServerState`: everything that lives for one Server (threshold, score, turns left, ejects left, stash, room, equipped weapon, `bandwidth_bonus`...).
- `WeaponState`: equipped Firewall (`strength`, `ceiling`).

## 6.4 Shop generation (`ShopGenerator`)

2 Daemons (weighted by rarity, skipping ones you own), 2 items (3 with Backdoor), 1 Root Access (fixed per Network). Reroll keeps the Root Access offer. Prices go through `RunState.price()` (VIP Pass -25%, Scalper doubles Firmware).

## 6.5 Daemon list

The full list with descriptions is the `RAW` array in `scripts/database/daemon_db.gd`: currently 75 Daemons in six groups (Economy & Meta, Base Bytes, Overclock additions, Overclock multipliers, Firewall & Integrity). Open that file to read, edit or balance them. Remember to change `daemon_logic.gd` when you change what one does.

## 6.6 Interest and economy summary

- Clear reward: $3 / $4 / $5 (Proxy / Mainframe / Sentinel), +$1 per unused turn.
- Interest after each Server: $1 per $5 held, capped at $5. Investment Bank doubles both (max $10). Offshore Account adds +$10 to the cap.
- Ransomware voids the entire payout.

---

# Part 7: Testing, building, icon, audio

## 7.1 Developer probes (`tools/probe`)

Run a probe scene with **F6** in the Godot editor (open the `.tscn`), then read the **Output** panel.

| Probe | Purpose |
|---|---|
| `probe.tscn` | Loads every script and scene one by one so a typo shows its real error message. **Run this after any edit** if the game does not start. |
| `sim.tscn` | Plays random runs with no UI; every Daemon and boss gets exercised. Search the Output for lines beginning `SIM`. |
| `tutorial_probe`, `pause_probe`, `layout`, `ram_probe`, `sell_probe` | Targeted checks (tutorial flow, pause menu, layout, 5-Node room screenshot, sell popup). Screenshots go in `tools/probe/shots/`. |

These are development tools; they are not part of the player experience.

## 7.2 Debug keys
Only in debug builds (running from the editor): **F1** = +$50, **F2** = clear the current Server instantly (Server screen).

## 7.3 The game icon

- Source image: `assets/gameIcon/ouroboros_dragon_icon.png` (1024x1024).
- Project icon: `project.godot` -> `config/icon`. Godot uses it for the window and the editor.
- Android launcher icons: `export_presets.cfg` -> `launcher_icons/*` point to `assets/gameIcon/android_launcher_192.png`, `android_adaptive_fg_432.png`, `android_adaptive_bg_432.png`. In the editor these are in *Project -> Export -> Android -> Icons*. The adaptive foreground is the dragon scaled to fit Android's safe zone on a dark square.
- **To change the icon:** replace the PNG files in `assets/gameIcon/` keeping the same file names (same sizes for the Android ones), or change the paths in the settings above.
- For a Windows build, set the exe icon in a Windows export preset (*Project -> Export -> Add -> Windows Desktop -> Application -> Icon*, requires an `.ico` file).

## 7.4 Building the game

1. Install the export templates: *Editor -> Manage Export Templates -> Download*.
2. **Android:** needs the Android SDK and a JDK configured in *Editor -> Editor Settings -> Export -> Android*, plus a keystore (debug keystore works for testing). Then *Project -> Export -> Android -> Export Project*. Output to `builds/`. The preset is set to arm64 only. Orientation is landscape.
3. **PC:** *Project -> Export -> Add -> Windows Desktop* (or Linux/macOS), then Export.
4. Window: 1280x720 base, stretch mode `canvas_items`, aspect `expand`; the layout is built from containers so different aspect ratios work.

## 7.5 Controls summary

| Action | PC | Phone |
|---|---|---|
| Select Node | click | tap |
| Read a description | hover | long-press |
| Execute | Space / Enter | EXECUTE button |
| Eject | F | EJECT button |
| Clear selection / close overlay | Esc | CLEAR / CLOSE |
| Tailbytes tracker | D | TAILBYTES button |
| Subroutines | S | SUBROUTINES button |
| Settings | P or the gear (Esc closes) | gear |
| Reorder Daemons | drag | drag |
| Sell Daemon mid-Server | click it, press SELL | tap it, tap SELL |

---

# Part 8: Troubleshooting and gotchas

- **"Identifier not declared" / red errors on start:** you probably renamed a `%UniqueName` node or removed a node a script expects. Undo the rename or update the script. Run `tools/probe/probe.tscn` to see the exact error.
- **New script with `class_name` gives "hides a global script class":** don't use `class_name` in new scene scripts (see 5.12). Existing ones with `class_name` are fine.
- **A new image doesn't show:** open the Godot editor once so it imports the file; check the path starts with `res://`.
- **A tooltip shows old text:** tooltips are written in code (`set_tip`, `_describe`, `get_tip_data`), not in the scene.
- **I changed a Daemon description but the effect didn't change (or vice versa):** the text is in `daemon_db.gd` and the real effect is in `daemon_logic.gd`. Edit both.
- **A new card/Daemon "breaks" the turn rule (needs 4 Nodes etc.):** do not change the core rule. Rewrite the card's behaviour (see Part 1 guardrail and `CLAUDE.md`).
- **Layout looks wrong on phone or with 5 Nodes:** the Server screen's `Room` is a flow container that is widened to fit all cards in one row (`_build_room_cards`). If you change `CARD_SIZE` (in `node_card_factory.gd`) the room width follows automatically.
- **Settings gear overlaps something:** the header needs a `GearSpacer` (118px) like the other screens.
- **Files named `.fuse_hidden...`** in the project are leftovers created by the sync layer; they are safe to delete from your own computer (they are not used by the game).
- **`docs/ARCHITECTURE.md`** is the older short overview; this guide supersedes it where they disagree (for example the Subroutine count and the Eject wording).
- **Always search the whole project** (Ctrl+Shift+F) for an old term when renaming a word, since text is spread over several files.

---

# Part 9: Glossary

Display names were changed during development, but **code identifiers were not**, to avoid breaking things. When reading code, translate:

| In the game (what players see) | In the code |
|---|---|
| Tailbytes (the deck) | `Deck`, `deck` |
| Siphon (data node) | `NodeType.DATA` |
| Glitch (enemy node, "ICE") | `NodeType.ICE` |
| Firewall (weapon node) | `NodeType.BREACH`, "weapon", "Breach Protocol" |
| Patch (heal node) | `NodeType.COOLANT`, "coolant" |
| Server Integrity (health) | `health`, `get_max_health()` |
| Bytes / Base Bytes | `chips` / `base` ("data") |
| Overclock (multiplier) | `mult`, `bandwidth_bonus`, "Bandwidth" |
| Threshold (the quota to reach) | `quota` |
| Eject | `flee`, `fled_this_turn`, `flee_room` (input action) |
| Sentinel Server | `ServerKind.BLACK_ICE` |
| Stash | `stash`, `get_stash_capacity()` |
| Black Market | the shop; `ShopGenerator`, `shop_screen` |
| Executable / Corruption | `ItemKind.EXECUTABLE` / `ItemKind.CORRUPTION` (one-use items) |
| Firmware Update | `ItemKind.FIRMWARE` (levels up a Subroutine) |
| Root Access | `ItemKind.ROOT_ACCESS`, "vouchers" in `RunState` |
| Subroutine (combo) | `SubroutineDB`, "poker hand" |
| Hyperdrive (executable) | id `overclock_exe` |
| Ghost Write (Daemon) | id `glitch` |
| Shock Absorber (Daemon) | id `firewall` |
| Bulk Siphon (Subroutine) | id `data_dump` |
| Full Spectrum (Subroutine) | id `overclock` |
| Operator | the player |
| NODE-9 | the tutorial bot |

*(This guide reflects the project as of the current version. When you add systems, add a short section here so the next person finds it.)*

## 5.14 Node card look: one generator for every kind

The four Node cards (Siphon, Glitch, Patch, Firewall) are NOT hand-built. They share ONE scene
(`scenes/components/node_card/node_card.tscn`) and the look comes from three small scripts:

| File | Job |
|------|-----|
| `node_style.gd` (`NodeStyle`) | The style table: outline shape per kind, texture per kind, role tag (MINE / VIRUS / HEAL / GUARD) and the icon paths. **Edit this to change how a kind looks, or to add a new kind.** |
| `node_face.gd` (`NodeFace`) | Draws the card body in code: halo, gradient fill, texture (dots / diagonals / grid / crosshatch, top 72% only), gradient border, divider, 14 value pips. Also used as the face-down `Cover` (`unknown = true`). |
| `node_icon.gd` (`NodeIcon`) | Draws the glyph from `NodeStyle.icon_parts()`. |

Design reference: `assets/nodes/` (a React/HTML mockup; it cannot run in Godot, so its numbers
were copied into `node_style.gd`). Values come from the Enums colours, so card colours always
match the coloured words in text (`Fmt.rich`).

How to change things:
- Different shape: edit the matching branch of `NodeStyle.shape()`.
- Different icon: edit `NodeStyle.icon_parts()` (points are on a 120x120 grid, same as the SVG).
- Different texture: change `NodeStyle.TEXTURES` or add a branch in `NodeFace._build_texture()`.
- New kind: add it to `Enums.NodeType`, then one entry in each table in `node_style.gd`
  (ROLES, TEXTURES, shape, icon_parts) and a variant scene as before (see 5.x "add a card").
- Card is still landscape 224x126 (`NodeCardFactory.CARD_SIZE`); the mockup is portrait, so the
  layout was adapted: value + pips left, icon right, name under the divider.
- Fonts: the mockup uses Chakra Petch / JetBrains Mono; they are not in the project, so the
  theme font is used. Drop `.ttf` files in and set them in `theme/oroboros_theme.tres` to match.

### 5.14b PNG frame version of the Node cards (current)

The Node cards now use the painted art in `assets/nodes/` (`card_*.png`, `card_*_selected.png`,
`icon_*.png`, `pip_*_lit/off.png`). The art contains NO text. Everything on top is placed by script:
- `node_style.gd`: `ART_SETS` maps each kind to an art set (Siphon->siphon, Glitch->glitch, Patch->patch,
  Firewall->ice) and exposes `card_tex / icon_tex / pip_tex`.
- `node_face.gd`: draws the frame PNG (selected version when selected), the QUEUE tab, the role tag box,
  the divider and the vertical pip column (lit from the bottom; more than 14 = one pip per point, smaller).
- `node_card.tscn` labels: value (`ValueLabel`), role (`RoleLabel`), name (`TypeLabel`), effect line
  (`StrengthLabel`, set by variants through `_set_effect(effect, sub)`), small grey line (`CeilingBadge`),
  mod letters (`Badges`), Glitch damage preview (`DamagePreview`), QUEUE text (`OrderLabel`).
- Card size is portrait: `NodeCardFactory.CARD_SIZE` = 160x227 (PNG body 480x680 / 3). Room cards are drawn at
  `ROOM_CARD_SCALE` (server_screen.gd).
- To change the text a card shows, edit `_on_refreshed()` in its variant (`variants/*_card.gd`).
- The old code-drawn landscape cards are saved in `backups/node_cards_v1_procedural/` (see RESTORE.md there).


## Sentinels (BossDB)
32 Sentinels in `scripts/database/boss_db.gd`, each with a `tier` (0 simple, 1 hard, 2 very hard). `BossDB.build_order()` gives Networks 1-3 simple, 4-6 hard, 7-8 very hard, no repeats. Past Network 8, `RunState.boss_for(n)` draws from the whole pool without repeats until all have appeared. Add a Sentinel: add a row, then check `RunState.is_boss("id")` where the rule applies. Optional `quota` multiplies the Threshold.
