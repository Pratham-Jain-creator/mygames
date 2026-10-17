# Oroboros Protocol - Architecture

## Folder layout
- `autoload/`  one folder per singleton (EventBus, RunState, AudioService, SceneManager, PostFX, TooltipService)
- `scripts/enums|data|database|logic/`  pure rules, no UI: NodeData, Deck, DaemonDB (75), SubroutineDB, BossDB,
  TurnResolver, DaemonLogic, ServerLogic, ShopGenerator, ConsumableService
- `scenes/<screen>/`  one folder per screen (main_menu, network_map, server, shop, game_over)
- `scenes/components/<widget>/`  reusable widgets (scene + script together)
- `shaders/`, `theme/`, `tools/probe/` (dev smoke tests: probe.tscn loads everything, sim.tscn plays random runs)

## Inheritance
- `InteractiveControl` -> ActionButton, NodeCard, DaemonCard, ShopListing, WeaponBay, ServerCard
  (shared hover tooltip, click/tap, long-press tooltip on touch)
- `NodeCard` -> DataCacheCard, IceCard, BreachCard, CoolantCard (inherited scenes)
- `BaseScreen` -> server_screen, shop_screen, network_map (deck viewer, type picker, toast, consumable flow)

## Animation rule
All motion lives in each scene's AnimationPlayer (hover_in, hover_out, press, release, select, deal_in, hit,
resolve, ceiling_hit, shatter, ...). Scripts only call `play_anim(&"name")`. The score tick-up animates a
`progress` property from the AnimationPlayer.

## Interpretations of ambiguous design points
- Data node scores value x2 Base Data; other types add their value.
- Extra Subroutines added so every 3-node mix scores: Surgical Strike (needed by Logic Bomb), Fragment (fallback).
- Turns per Server: 4. Payout: $3/$4/$5 + $1 per unused turn.
- Face-down nodes (Cipher, Poltergeist) reveal when resolved.
- Debug keys (debug builds only): F1 +$50, F2 clear current server.
