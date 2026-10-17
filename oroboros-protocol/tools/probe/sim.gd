extends Node
## Dev helper: plays random runs without any UI to shake out logic errors.
## Every Daemon and every boss gets exercised. Output lines start with SIM.


func _ready() -> void:
	seed(12345)
	var turns := 0
	var errors := 0
	for run_i in 36:
		RunState.start_new_run()
		# Force-feed daemons / bosses so every code path runs across the sims.
		var ids := DaemonDB.all_ids()
		for i in 5:
			RunState.add_daemon(ids[(run_i * 5 + i) % ids.size()])
		RunState.money = 100
		var bks: Array = BossDB.BOSSES.keys()
		RunState.boss_order = []
		for bi in 8:
			RunState.boss_order.append(bks[(run_i * 8 + bi) % bks.size()])
		for net in range(1, 9):
			RunState.network = net
			for k in 3:
				RunState.server_index = k
				var sv := ServerLogic.begin_server()
				var guard := 0
				while sv.turns_left > 0 and guard < 12:
					guard += 1
					var d := ServerLogic.deal_room()
					if randi() % 6 == 0 and ServerLogic.can_flee() == "":
						ServerLogic.flee()
						continue
					var room: Array = d.room.duplicate()
					room.shuffle()
					var req: int = d.required
					var sel := room.slice(0, req)
					var rest := room.slice(req)
					var res := TurnResolver.resolve(sel, rest)
					turns += 1
					if res.died or RunState.health <= 0:
						break
					if sv.score >= sv.quota:
						break
				ServerLogic.payout()
				RunState.leave_shop()
				if RunState.health <= 0:
					RunState.health = RunState.get_max_health()
				# shop + consumables
				RunState.begin_shop_visit()
				RunState.purge_cost()
				RunState.reroll_cost()
				RunState.price(5, Enums.ItemKind.FIRMWARE)
				RunState.price(5, Enums.ItemKind.DAEMON)
				RunState.shop_listings = ShopGenerator.generate()
				DaemonLogic.fire("shop_enter")
				for l in RunState.shop_listings:
					ShopGenerator.cost_of(l)
					ItemDB.get_item(l.kind, l.id)
		# consumables
		for id in ItemDB.EXECUTABLES.keys():
			RunState.consumables.clear()
			RunState.consumables.append({"kind": Enums.ItemKind.EXECUTABLE, "id": id})
			var item: Dictionary = RunState.consumables[0]
			var tgt: Array = RunState.deck.all_nodes.slice(0, 2)
			var r := ConsumableService.use(item, tgt, {"type": Enums.NodeType.DATA})
			if not bool(r.get("ok", false)): print("SIM exe FAIL ", id, " ", r)
	print("SIM DONE turns=", turns)
