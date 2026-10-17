class_name DaemonDB
extends RefCounted
## Static definitions for all 167 Daemons. Behaviour lives in DaemonLogic.
## Row: [id, name, rarity(0-4: Common, Uncommon, Rare, Epic, Legendary), description]

const RARITY_COST := [3, 5, 7, 9, 12]

const RAW := [
	# --- Economy & Meta (1-15) ---
	["vip_pass", "VIP Pass", 1, "Shop items are 25% cheaper."],
	["mining_rig", "Mining Rig", 0, "Earn Ø1 at the end of the turn for every Siphon resolved (max Ø6 per Server)."],
	["investment_bank", "Investment Bank", 1, "Doubles interest: Ø2 per Ø5 held when a Server is cleared (max Ø10, instead of Ø1 per Ø5, max Ø5)."],
	["spoofed_ip", "Spoofed IP", 0, "The first shop reroll each visit is free."],
	["packet_sniffer", "Packet Sniffer", 0, "Gain 1 extra Eject per Server."],
	["delete_key", "Delete Key", 0, "Purging Nodes in the shop has no scaling fee."],
	["glitch", "Ghost Write", 0, "When you leave a Siphon unresolved, a temporary ghost copy of it (value +4) goes on top of your Tailbytes. Max 2 per Server."],
	["smuggler", "Smuggler", 1, "Bypassing a Node (leaving it unresolved) permanently increases its value by +1."],
	["golden_ticket", "Golden Ticket", 1, "Resolving a Gold Node grants Ø3 instead of Ø1."],
	["bounty_hunter", "Bug Hunter", 0, "Containing a Glitch valued 12+ grants Ø1."],
	["crypto_miner", "Crypto-Miner", 1, "Sell value of this Daemon increases by Ø1 every turn."],
	["adware", "Adware", 0, "Receive a free random Executable when you enter the shop."],
	["ransomware", "Ransomware", 4, "x3 Overclock, but you earn Ø0 from this Server upon victory (no clear reward, no interest)."],
	["scalper", "Scalper", 2, "Firmware Updates cost double but level up twice."],
	["seed_capital", "Seed Capital", 1, "Start your next run with Ø10 extra."],
	# --- Base Bytes additions (16-35) ---
	["floppy_disk", "Floppy Disk", 0, "+4 Base Bytes for every Node resolved."],
	["binary_zero", "Binary Zero", 0, "+10 Base Bytes for each Even-valued Node resolved."],
	["binary_one", "Binary One", 0, "+10 Base Bytes for each Odd-valued Node resolved."],
	["overload", "Overload", 0, "+20 Base Bytes if you play Bulk Siphon."],
	["cache_clear", "Cache Clear", 0, "+25 Base Bytes on the first turn of a new Server."],
	["cloud_sync", "Cloud Sync", 0, "+10 Base Bytes if the Node held in your Stash is a Siphon."],
	["scraper_script", "Scraper Script", 1, "+5 Base Bytes every time the Server takes Integrity damage this turn."],
	["redundant_array", "Redundant Array", 1, "+10 Base Bytes for each resolved Node identical to a Stashed Node."],
	["low_level_format", "Low-Level Format", 0, "+8 Base Bytes for Nodes valued 2-5."],
	["mainframe_access", "Mainframe Access", 0, "+6 Base Bytes for Nodes valued 11-14."],
	["memory_leak", "Memory Leak", 0, "+0 to +23 random Base Bytes per turn."],
	["overwritten_file", "Overwritten File", 1, "Permanently gains +2 Base Bytes and +0.25 Overclock (max +5) every time you delete a Node."],
	["scrap_metal", "Scrap Metal", 1, "Containing a Glitch adds its value to your Base Bytes."],
	["bloatware", "Bloatware", 2, "+50 Base Bytes, but maximum Stash size is 0."],
	["syringe", "Syringe", 0, "+10 Base Bytes for every Patch resolved."],
	["heat_sink", "Heat-Sink", 1, "+30 Base Bytes if Integrity is below 5."],
	["flash_drive", "Flash Drive", 0, "+30 Base Bytes on turn 4 (the last turn)."],
	["fibonacci", "Fibonacci", 1, "+10 Base Bytes for every resolved Node that is a Fibonacci number (2, 3, 5, 8, or 13)."],
	["prime_directive", "Prime Directive", 1, "+8 Base Bytes for each Prime-valued Node."],
	["ram_check", "RAM Check", 1, "+60 Base Bytes if all 4 Node types were in the room."],
	# --- Overclock additions (36-55) ---
	["basic_overclock", "Basic Overclock", 0, "+3 Overclock on the first turn of every Server."],
	["masochist", "Stress Tester", 3, "+1 Overclock permanently every time the Server takes 4+ unmitigated damage in one hit."],
	["diamond_chip", "Diamond Chip", 1, "+4 Overclock if you resolve exactly one Siphon."],
	["gold_wire", "Gold Wire", 1, "+5 Overclock if you resolve zero Siphons."],
	["multi_thread", "Multi-Thread", 1, "+2 Overclock for every Firewall currently held in Stash."],
	["trojan", "Trojan", 2, "Permanently gains +0.5 Overclock every time you Eject."],
	["keylogger", "Keylogger", 2, "+10 Overclock on turn 4 (the last turn)."],
	["logic_bomb", "Logic Bomb", 1, "+4 Overclock if you resolve the Surgical Strike subroutine."],
	["proxy", "Proxy", 2, "+1 Overclock for every Ø5 you hold (max +8)."],
	["vampire", "Power Patch", 1, "+1 Overclock for every Patch used this turn."],
	["rust", "Rust", 2, "+50 Base Bytes. +5 Overclock on the first turn of each Server, 1 less each turn after (min 0)."],
	["echo", "Echo", 3, "Re-triggers the flat Overclock bonus of the previous turn."],
	["stutter", "Stutter", 0, "+4 Overclock if you resolve two Nodes of the exact same value."],
	["benchmark", "Benchmark", 1, "+4 Overclock if the turn's bytes are already above 500 at this point."],
	["cooling_paste", "Cooling Paste", 3, "+3 Overclock if Integrity is exactly at Max."],
	["blood_magic", "Thermal Runaway", 2, "+5 Overclock, but the Server loses 1 Integrity per turn."],
	["neon_sign", "Neon Sign", 1, "+2 Overclock for every modified / upgraded Node resolved."],
	["blueprint", "Blueprint", 3, "Copies the ability of the Daemon to its right."],
	["synergizer", "Synergizer", 2, "+1 Overclock for every Daemon you own of a different rarity."],
	["overvolt", "Overvolt", 1, "+2 Overclock when a Firewall degrades to 0."],
	# --- Overclock multipliers (56-65) ---
	["bottleneck", "Bottleneck", 1, "x2 Overclock if all 3 resolved Nodes are 6 or lower."],
	["spyware", "Spyware", 3, "Gains x0.1 Overclock permanently every time you resolve a 14-value Node."],
	["glass_cannon", "Glass Cannon", 3, "x2 Overclock. The Server's Maximum Integrity is permanently capped at 5 (overrides all other Max Integrity modifiers)."],
	["the_core", "The Core", 3, "x3 Overclock if you only play 1 Subroutine type the entire Server."],
	["black_hole", "Black Hole", 3, "x4 Overclock if Integrity is exactly 1."],
	["infinity_loop", "Infinity Loop", 3, "Eject on the first turn to gain x1.5 Overclock on every turn of this Server."],
	["quantum_chip", "Quantum Chip", 2, "x1, x1.25, x1.5 or x2 Overclock at random each turn."],
	["obelisk", "Obelisk", 4, "x0.3 Overclock per consecutive turn you DO NOT play your most used Subroutine (max x4)."],
	["poltergeist", "Poltergeist", 3, "x2 Overclock, but all drawn Nodes are face down."],
	["singularity", "Singularity", 4, "x4 Overclock. Costs Ø10 at the start of each Server. If you cannot pay, the x4 becomes x1 for that Server."],
	# --- Firewall & Integrity (66-75) ---
	["firewall", "Shock Absorber", 1, "Ignore the first 3 points of Glitch damage each turn. A hit it absorbs completely still gives +1 Overclock."],
	["brute_force", "Brute Force", 1, "Firewalls degrade by a flat -2 instead of adopting the contained Glitch's value."],
	["sharp_edge", "Sharp Edge", 0, "Newly equipped Firewalls gain +3 Base Strength."],
	["duct_tape", "Duct Tape", 1, "Each Firewall can contain one Glitch equal to its current Ceiling without degrading."],
	["antivirus", "Antivirus", 0, "Patch Nodes repair double their printed value."],
	["quarantine", "Quarantine", 1, "A Stashed Glitch's value is halved when it reappears."],
	["honeypot", "Honeypot", 1, "If two Glitches appear in a room, the weakest destroys itself."],
	["buffer_overflow", "Buffer Overflow", 3, "Fatal damage leaves the Server at 1 Integrity and destroys this Daemon."],
	["recycled_code", "Recycled Code", 1, "When a Firewall degrades to 0, repair 5 Integrity."],
	["failsafe", "Failsafe", 2, "+5 Max Integrity, but Firewalls degrade twice as fast."],

	# --- Perfect Block ---
	["clean_sweep", "Null Sweep", 0, "+15 Base Bytes for each Perfect Block this turn (a Glitch fully absorbed by your Firewall)."],
	["mirror_plating", "Parity Bit", 0, "+1 Overclock for each Perfect Block this turn."],
	["bounce_back", "Ping Reply", 1, "Each Perfect Block earns Ø1 (max Ø3 per Server)."],
	["hardened_core", "Hardened Kernel", 1, "A Firewall that Perfect Blocks gains +1 Ceiling (max +3 per Firewall)."],
	["reactive_patch", "Watchdog Timer", 1, "Each Perfect Block repairs 1 Integrity."],
	["streak_counter", "Uptime Counter", 1, "+0.5 Overclock for each consecutive turn with a Perfect Block. Resets when Integrity is lost (max +3)."],
	["aegis_protocol", "Air-Gap Protocol", 2, "x2 Overclock if two or more Glitches were all Perfectly Blocked this turn."],
	["deflector", "Reflection Attack", 2, "Each Perfect Block adds the Firewall's Strength to your Base Bytes."],
	["iron_ledger", "Immutable Ledger", 3, "Each Perfect Block permanently adds +2 Base Bytes (max +40)."],
	["spotless_record", "Pristine Logs", 3, "If the Server took no Integrity damage: x2 Overclock on turn 4 and +Ø3 when cleared."],
	# --- Fewer Tailbytes ---
	["lean_build", "Minified Build", 0, "+4 Overclock if you own 40 or fewer Tailbytes."],
	["dead_drop", "Cold Boot", 0, "+25 Base Bytes if fewer than 20 Tailbytes remain undealt."],
	["minimalist", "Tree Shaking", 1, "+0.1 Overclock for each Tailbyte below 52 (max +4 at 12)."],
	["skeleton_crew", "Stripped Binary", 1, "+2 Base Bytes for each Tailbyte below 52."],
	["pruning_shears", "Garbage Collector", 1, "The first Purge in each shop visit is free."],
	["razor_deck", "Occam's Compiler", 2, "x1.5 Overclock if you own 30 or fewer Tailbytes."],
	["zen_garden", "Zero Point", 3, "x(1 + 0.02) Overclock for each Tailbyte below 52 (max x1.8)."],
	["cutting_it_close", "Race Condition", 3, "x3 Overclock when 4 or fewer Tailbytes remain (the end of the deck)."],
	# --- Modified Nodes ---
	["chrome_plating", "Mod Layer", 0, "+8 Base Bytes for each modified Node resolved."],
	["hot_patch", "Script Kiddie", 1, "Executables cost Ø2 less in the shop (min Ø1)."],
	["custom_build", "Total Conversion", 1, "+3 Overclock if all 3 resolved Nodes are modified."],
	["showpiece", "Cached Mod", 1, "+10 Base Bytes if the Stash holds a modified Node."],
	["collectors_edition", "Mod Archive", 2, "+0.5 Overclock for each modified Node in your Tailbytes (max +5)."],
	["burn_in", "Overfit", 3, "A resolved modified Node (not a Glitch) gains +1 value permanently, once per Node each Server (max 14)."],
	# --- Glue ---
	["duo", "Fork Pair", 0, "+2 Overclock if you own two Daemons of the same rarity."],
	["anchor", "Kernel Pin", 0, "+10 Base Bytes for each Rare, Epic or Legendary Daemon you own."],
	["odd_couple", "Type Coercion", 0, "+20 Base Bytes if you own a Common and a Rare Daemon."],
	["neighbour_watch", "Mesh Network", 1, "+1 Overclock for each Daemon next to this one."],
	["chain_link", "Hash Chain", 1, "+5 Base Bytes for each Daemon to the left of this one."],
	["understudy", "Shadow Process", 1, "Copies the Base Bytes ability only of the Daemon to its left."],
	["full_house", "Full Stack", 2, "x2 Overclock if all 5 Daemon slots are filled."],
	["conductor", "Orchestrator", 2, "+1 Overclock for each other Daemon that triggered this turn (max +5)."],
	# --- Firewall support ---
	["spare_plating", "Failover Rule", 0, "A newly equipped Firewall loses 2 less Ceiling on its first hit."],
	["weld", "Handshake", 0, "Equipping a Firewall repairs 1 Integrity."],
	["hard_line", "Dedicated Channel", 0, "+6 Base Bytes per Node resolved while a Firewall is equipped."],
	["salvage", "Core Dump", 1, "When a Firewall breaks, earn Ø2."],
	["ablative_coating", "Rate Limiter", 1, "The first Firewall hit each turn costs 2 less Ceiling."],
	["heavy_gauge", "Strict Policy", 1, "Every Firewall hit costs 1 less Ceiling, but new Firewalls start with -1 Strength."],
	["rebound", "Reverse Shell", 3, "When a Glitch above your Firewall's Ceiling hits the Server, it also breaks the Firewall. Whenever a Firewall breaks, gain Base Bytes equal to the Glitch's value x5."],
	["overcharge", "Hash Rate", 2, "+1 Overclock for every 5 Strength on your equipped Firewall."],
	# --- Economy ---
	["loose_change", "Micro-Transaction", 0, "Earn Ø1 when a Server starts."],
	["coupon_book", "Promo Code", 0, "The first Purge each shop visit costs Ø1 less."],
	["tip_jar", "Donation Link", 0, "Earn Ø1 each time a Patch is resolved (max Ø3 per Server)."],
	["pawn_shop", "Fence Protocol", 1, "Selling a Daemon earns Ø2 extra."],
	["dividend", "Staking Rewards", 1, "Earn Ø1 per 2 Daemons owned when a Server is cleared."],
	["haggler", "Price Oracle", 1, "Rerolls cost Ø1 less (min Ø1)."],
	["layaway", "Escrow", 1, "When you leave the shop, earn Ø1 per Ø4 held (max Ø4)."],
	["black_market", "Darknet Deal", 2, "Shop Daemons cost 50% less, but each one you buy adds a Glitch to your Tailbytes."],
	# --- Subroutines & Firmware ---
	["macro", "Batch Script", 0, "+10 Base Bytes for each different Subroutine played this Server."],
	["habit", "Loop Counter", 0, "+2 Overclock for each turn in a row you play the same Subroutine as the turn before (max +6)."],
	["cycle", "Cron Job", 1, "+2 Overclock the first time each Subroutine is played in a Server."],
	["firmware_discount", "Patch Notes", 1, "Firmware Updates cost Ø2 less (min Ø1)."],
	["variety_pack", "Polyglot", 2, "x2 Overclock if three different Subroutines were played this Server."],
	["overclocked_firmware", "Bleeding Edge", 2, "+0.5 Overclock per Firmware level across all Subroutines (max +6)."],
	["hotfix", "Zero-Day Patch", 1, "The first Firmware Update each shop visit gains one extra level."],
	# --- Executables ---
	["power_user", "Sudo", 0, "+3 Overclock on a turn when you use an Executable."],
	["stockpile", "Script Library", 0, "+5 Base Bytes for each Executable you hold."],
	["spare_slot", "Swap Space", 1, "You can carry 1 more piece of software (4 total)."],
	["recycler", "Reusable Function", 1, "An Executable has a 1 in 3 chance of not being used up."],
	["vending_unit", "Script Generator", 1, "Earn a random Executable when you clear a Server without Ejecting."],
	["double_dose", "Dual Execute", 2, "Encrypt and Clone take effect twice, but you can hold only 1 piece of software."],
	# --- Stash ---
	["pocket_space", "Hidden Partition", 0, "+2 Overclock if you Stash a Glitch."],
	["safe_deposit", "Cold Storage", 0, "A Stashed Node gains +1 value for each turn it stays (max +3)."],
	["dead_letter", "Dead Letter Queue", 1, "Earn Ø1 when you Stash a Glitch instead of resolving it (max Ø2 per Server). Does nothing under The Lock."],
	["time_capsule", "Retention Policy", 1, "+3 Base Bytes for each turn the Stashed Node has been held."],
	["mirror_cache", "Mirror Table", 1, "+10 Base Bytes if a Stashed Node is the same type as a resolved Node."],
	["shell_game", "Persistent Shell", 2, "x2 Overclock if the Stash holds the same Node as last turn."],
	["lockbox", "Encrypted Volume", 2, "+4 Overclock if your Stash capacity is 2 or more."],
	# --- Integrity ---
	["thick_skin", "Backup Image", 1, "+2 Max Integrity."],
	["steady_hand", "Health Check", 0, "+2 Base Bytes for each point of current Integrity."],
	["triage", "Boot Repair", 1, "Repair 2 Integrity when a Server starts."],
	["scar_tissue", "Error Log", 1, "After the Server loses Integrity, +1 Overclock for the rest of that Server (max +4)."],
	["pain_tolerance", "Fault Tolerance", 1, "Ignore any single hit of 1 damage, +1 for every boss defeated this run (max 3)."],
	["overheal", "Buffer Surplus", 2, "Integrity repaired above Max becomes 5 Base Bytes per point."],
	["redline", "Edge Case", 3, "x1.5 Overclock while Integrity is 4 or lower, x1.5 more for each point lower (x2.25 at 3, x3.4 at 2, max x4)."],
	# --- Eject & tempo ---
	["escape_hatch", "Exit Code", 0, "+10 Base Bytes on the turn after you Eject."],
	["clean_exit", "Graceful Shutdown", 1, "Ejecting repairs 1 Integrity."],
	["second_wind", "Hot Standby", 1, "Once per Server, you may Eject two turns in a row."],
	["panic_button", "Kernel Panic", 2, "Each Eject gives +1 Overclock for the rest of this Server (max +4)."],
	["tempo", "Pulsar", 3, "x1.25 Overclock after a turn without an Eject, +0.25 more for every turn in a row (x2 on turn 4). An Eject resets it."],
	# --- Face-down ---
	["gamblers_eye", "Monte Carlo", 0, "+12 Base Bytes for each Glitch you resolve without a Firewall protecting you, +12 more if it was face down."],
	["blind_trust", "Blind Injection", 1, "One random Node is dealt face down each turn. +3 Overclock if you resolve it."],
	["peek", "Rewind Buffer", 1, "Nodes you Eject go to the bottom of your Tailbytes instead of being lost for this Server."],
	["hunch", "Heuristic", 3, "x2 Overclock if all 3 resolved Nodes were face down."],
	# --- Legendary (new) ---
	["perfect_mirror", "Recursive Reflection", 3, "x1.25 Overclock for each Perfect Block this turn (max x2). Glitches deal +1 damage."],
	["hollow_crown", "Rootkit", 4, "x3 Overclock while you own 20 or fewer Tailbytes."],
	["ironclad", "Zero Trust", 3, "A Firewall loses at most 1 Ceiling per Glitch. Max Integrity -3."],
	["hall_of_mirrors", "Infinite Recursion", 4, "Copies every other Daemon's flat Overclock bonus once at half value. You can own only 4 Daemons."],
	["overdrive", "Hypergiant", 4, "x2.5 Overclock. Every Threshold is 20% higher."],
	["last_stand_protocol", "Supernova", 4, "x4 Overclock when Integrity is 3 or lower and 6 or fewer Tailbytes remain (the end of the deck)."],
	["ledger_of_souls", "Tombstone Records", 4, "Permanently gain +3 Base Bytes for each Node purged (max +36). Purging costs double."],
	["compound_interest", "Yield Farm", 4, "At the end of each Server, +1 Overclock permanently per Ø10 held (max +3 total)."],
]

static var _defs: Dictionary = {}
static var _order: Array = []


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	for row in RAW:
		_defs[row[0]] = {
			"id": row[0], "name": row[1], "rarity": row[2],
			"desc": row[3], "cost": RARITY_COST[row[2]],
		}
		_order.append(row[0])


static func get_def(id: String) -> Dictionary:
	_ensure()
	return _defs.get(id, {})


static func all_ids() -> Array:
	_ensure()
	return _order.duplicate()


static func ids_with_rarity(min_rarity: int, max_rarity: int) -> Array:
	_ensure()
	var out: Array = []
	for id in _order:
		var r: int = _defs[id].rarity
		if r >= min_rarity and r <= max_rarity:
			out.append(id)
	return out
