class_name Progression
extends RefCounted
## 8 Networks x 3 Servers (Proxy 1.0x, Mainframe 1.5x, Black-ICE 2.0x).

const BASE_QUOTAS := [300, 800, 2800, 6000, 14000, 35000, 90000, 250000]
const KIND_MULT := [1.0, 1.5, 2.0]
const KIND_NAMES := ["PROXY SERVER", "MAINFRAME SERVER", "SENTINEL SERVER"]
const KIND_REWARD := [3, 4, 5]


static func quota_for(network: int, kind: int) -> int:
	var q: float = float(BASE_QUOTAS[network - 1]) * float(KIND_MULT[kind])
	if kind == Enums.ServerKind.BLACK_ICE:
		q *= BossDB.quota_mult(RunState.boss_for(network))
	if RunState.has_daemon("overdrive"):
		q *= 1.2
	return int(q)


static func server_title(network: int, kind: int) -> String:
	return "NETWORK %d // %s" % [network, KIND_NAMES[kind]]
