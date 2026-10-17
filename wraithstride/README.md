# Wraithstride

First-person dungeon parkour: **Ghost Runner** speed, **FFT** job classes with charge-time abilities, **Sekiro** posture combat.
Open `project.godot` in Godot 4.4+ and press F5 (main scene: `scenes/main.tscn`).

## Controls
| Key | Action |
|---|---|
| WASD / mouse | move / look |
| Space | jump. Hold W against a wall in mid-air to wall-run, tap Space to wall-jump |
| Shift | dash toward where you look (i-frames). Kills refund it |
| Ctrl | slide (jump out of it for a boost). Dragoon mid-"Jump": dive |
| LMB | attack |
| RMB | deflect. Tap just before a hit lands = perfect deflect (job-specific window) |
| Q / E | job abilities (some have a charge time, taking damage interrupts) |
| F | change job while standing in a Job Crystal |
| R | instant restart at the last shrine. Esc frees the mouse |

## Flow (speed is power)
Flow fills while you run fast, wall-run, slide and dash, and from kills (+15, deathblow +25), perfect deflects (+12), mikiri (+20) and wall-jumps. It drains when you stand still and drops when you are hit (-35) or your posture breaks (-50).

| Tier | Flow | Effect |
|---|---|---|
| 1 | 33+ | charge times -20%, +10% damage, +15% posture damage, cooldowns 15% faster |
| 2 | 67+ | charge -45%, +25% damage, +40% posture damage, cooldowns 40% faster, **job perk** |
| 3 Wraith | 99+ | instant casts, +40% damage, +75% posture damage, cooldowns 2x |

Job perks (tier 2+): Knight takes 25% less damage, White Mage heals +50%, Black Mage's Blink grants i-frames and refunds air dashes, Thief backstabs for x2, Dragoon slam radius 10m, Monk attacks 40% faster.
Enemies also turn slowly while winding up an attack, so circling at speed makes their swings miss.

## The dungeon
`scripts/dungeon.gd` stitches a seeded sequence of chunk scenes (`scenes/levels/chunks/`) end to end: 150 chunks, about 6.7 km, a shrine every 5th chunk, and a final hall with the elite and exit gate. Only the chunks near you (and back to the last shrine) are loaded. Change `chunk_count` or `seed_value` on the Dungeon01 node. To add a chunk: build it so it starts at z=0 with floor top at y=0, ends at z=-length, then add its length to `LENGTHS` and its name to `POOL`.

## Combat rules
- Yellow `!` slash: deflect it. Red `!!` thrust: unblockable, dash into it for a mikiri (instant posture break).
- Enemy posture full: it kneels, and any hit is a deathblow. Deathblows heal you.
- Kills refund your dash. Falling or traps kill you, and respawn is instant.

## Jobs
Knight (tank), White Mage (healer), Black Mage (ranged + blink), Thief (speed), Dragoon (jump + slam), Monk (brawler).
Edit stats and abilities in `scripts/job_data.gd`.

## Structure
- `scenes/` holds every look: models, lights, particles, HUD layout and all animation (AnimationPlayer).
- `scripts/` holds only input and mechanics. Animations call back into scripts through method tracks (`_on_swing_hit`, `_on_attack_hit`).

## Vector ops used (quick guide)
- Move wish direction: `basis * Vector3(input.x, 0, input.y)`, then `.normalized()`.
- Momentum-preserving air control: `hv += wish * accel * dt`, then `hv.limit_length(max(speed, prev_speed))`.
- Wall-run direction: `n.cross(Vector3.UP)`, flipped if `along.dot(forward) < 0`.
- Wall side (camera roll): sign of `(-n).dot(basis.x)`.
- Dash: `-camera.basis.z * speed`; flatten `y` when on the floor.
- Wall-jump: `normal * 7.5 + forward * 5`.
- Front check for deflect/attacks: `forward.dot(to_target.normalized()) > threshold`.
- Cone (Wave Fist): `dot > cos(15 deg)` = 0.966.
- Enemy facing: `atan2(-to.x, -to.z)` with `lerp_angle`.
- Beam: `look_at(to)`, then `scale.z = distance`.

## Rooms, seals and enemies (v2)

The dungeon is now ~50 room designs chained with transforms, so it **turns** (left/right corner rooms) as well as running straight.

| Kind | Count | Notes |
|---|---|---|
| Parkour (`p01`-`p15`) | 15 | stepping stones, wall-run gaps, ledge hills, pendulums, blades, moving platforms, spike hurdles, checker spike tiles, crushers, dash leaps... |
| Fight (`f01`-`f10`) | 10 | sentinel yard, spider nest, wisp cloister, turret gallery, brute island, ambush, web arena, duelists, tower turrets, war hall |
| Key/puzzle (`k01`-`k12`) | 12 | multi-seal rooms, mazes, vaults, hazard sampler, rest hall (crystal + checkpoint) |
| Corner (`c01`-`c10`) | 10 (+ mirrored right-hand variants) | pit bend, spider corner, crusher corner, ledge turn... |
| Start / shrine / final | 3 | hand-built chunks in `scenes/levels/chunks/` |

**Gating (Ghost Runner style):** every room ends in a portcullis. Touch the glowing **SEAL** orb(s) in the room to open it. Fight rooms put the seal behind/among enemies, but killing is never required - dash past if you like. Solved rooms stay open.

**Spikes everywhere:** pits have a visible spike bed, forbidden walls are spiked (touching = death), some floors are spike tiles.

**New enemies:** Spider (bite + web bolt that snares: slow, no jump; *dash* tears you free), Wisp (flies, telegraphs a straight dive), Brute (huge Sentinel), Sentry Totem (turret; deflect its bolts with RMB). **Webs** are static snares - dash through them.

### Editing / regenerating rooms
Room scenes are generated text `.tscn` files: `python3 tools/gen_assets.py && python3 tools/gen_rooms.py`
(edit `tools/rooms_*.py` to change layouts; `scripts/room_catalog.gd` is regenerated). Debug scenes: `tools/load_test.tscn` (loads every scene), `tools/dungeon_test.tscn` (walks the whole plan).
The old straight chunks (`hall`, `chasm`, `arena`, ...) are no longer used by the dungeon.
