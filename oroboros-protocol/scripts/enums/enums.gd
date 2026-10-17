class_name Enums
extends RefCounted
## Shared enums, palette and lookup tables. Pure data, no behaviour.

enum NodeType { DATA, ICE, BREACH, COOLANT }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum ItemKind { DAEMON, EXECUTABLE, FIRMWARE, CORRUPTION, ROOT_ACCESS }
enum ServerKind { PROXY, MAINFRAME, BLACK_ICE }

# --- Palette (from the Aesthetic & Interface document) ---
const COL_BG := Color("0B0C10")
const COL_PANEL := Color("1F2833")
const COL_DATA := Color("66FCF1")
const COL_ICE := Color("FF003C")
const COL_BREACH := Color("FFB400")
const COL_COOLANT := Color("00FA9A")
const COL_DAEMON := Color("FF00FF")
const COL_TEXT := Color("C5C6C7")
const COL_DIM := Color("5B6470")
const COL_MONEY := Color("FFD866")

const TYPE_COLORS := {
	NodeType.DATA: COL_DATA,
	NodeType.ICE: COL_ICE,
	NodeType.BREACH: COL_BREACH,
	NodeType.COOLANT: COL_COOLANT,
}
const TYPE_NAMES := {
	NodeType.DATA: "SIPHON",
	NodeType.ICE: "GLITCH",
	NodeType.BREACH: "FIREWALL",
	NodeType.COOLANT: "PATCH",
}
const TYPE_SHORT := {
	NodeType.DATA: "SIPHON",
	NodeType.ICE: "GLITCH",
	NodeType.BREACH: "FIREWALL",
	NodeType.COOLANT: "PATCH",
}
const RARITY_NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COLORS := [Color("8A8F98"), Color("C5C6C7"), Color("45C8DC"), Color("FF4FD8"), Color("FFFFFF")]
const KIND_NAMES := {
	ItemKind.DAEMON: "DAEMON",
	ItemKind.EXECUTABLE: "EXECUTABLE",
	ItemKind.FIRMWARE: "FIRMWARE",
	ItemKind.CORRUPTION: "CORRUPTION",
	ItemKind.ROOT_ACCESS: "ROOT ACCESS",
}
const KIND_COLORS := {
	ItemKind.DAEMON: COL_DAEMON,
	ItemKind.EXECUTABLE: COL_DATA,
	ItemKind.FIRMWARE: COL_BREACH,
	ItemKind.CORRUPTION: COL_ICE,
	ItemKind.ROOT_ACCESS: COL_COOLANT,
}
