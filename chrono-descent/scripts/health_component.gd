class_name HealthComponent
extends Node
## Reusable health pool. Emits health_changed on every change and died exactly once
## (until reset() is called, e.g. when the player respawns).

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 30

var current_health: int
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		is_dead = true
		died.emit()


func heal(amount: int) -> void:
	if is_dead:
		return
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


## Brings the owner back to full health and allows died to fire again.
func reset() -> void:
	is_dead = false
	current_health = max_health
	health_changed.emit(current_health, max_health)
