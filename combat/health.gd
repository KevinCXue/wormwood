class_name Health
extends Node
## Hit points, as a component: add a Health node as a child of anything that
## can be hurt (the player, villagers) and talk to it instead of keeping
## health in each script. Godot favours this kind of composition: behaviour
## lives in small child nodes, rather than in a deep class hierarchy.
##
## Others react through the signals: the HUD redraws its bar on `changed`,
## the owner falls down on `died`.

signal changed(health: int, max_health: int)
signal hurt(amount: int, attacker: Node)
signal died(attacker: Node)

const PUNCH_DAMAGE := 3  # a bare fist

@export var max_health := 20

var health := 20
var invulnerable := false  # console: god


func _ready() -> void:
	health = max_health


## How much a hit from `weapon` does: its damage, or a fist's if null.
static func damage_from(weapon: Equipable) -> int:
	return weapon.damage if weapon else PUNCH_DAMAGE


func is_dead() -> bool:
	return health <= 0


## Take `amount` damage from `attacker` (may be null).
func damage(amount: int, attacker: Node = null) -> void:
	if is_dead() or invulnerable or amount <= 0:
		return
	health = maxi(health - amount, 0)
	changed.emit(health, max_health)
	hurt.emit(amount, attacker)
	if health == 0:
		died.emit(attacker)


func heal(amount: int) -> void:
	if is_dead() or amount <= 0:
		return
	health = mini(health + amount, max_health)
	changed.emit(health, max_health)


## Set both, e.g. from a save or a villager's defaults.
func reset(new_max: int, current: int = -1) -> void:
	max_health = new_max
	health = new_max if current < 0 else clampi(current, 0, new_max)
	changed.emit(health, max_health)
