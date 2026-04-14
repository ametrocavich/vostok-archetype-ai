extends "res://Scripts/Character.gd"

var _settings: Resource = preload("res://VostokAIOverhaul/Settings.tres")


func _physics_process(delta):
	super(delta)
	if _settings.godModeActive:
		_maintain_god_mode()


func Health(delta):
	if _settings.godModeActive and gameData != null:
		gameData.health = 100.0
		gameData.damage = false
		return
	super(delta)


func WeaponDamage(damage: int, penetration: int):
	if _settings.godModeActive:
		return
	super(damage, penetration)


func ExplosionDamage():
	if _settings.godModeActive:
		return
	super()


func BurnDamage(delta):
	if _settings.godModeActive and gameData != null:
		gameData.isBurning = false
		gameData.burn = false
		gameData.damage = false
		return
	super(delta)


func FallDamage(distance: float):
	if _settings.godModeActive:
		return
	super(distance)


func Death():
	if _settings.godModeActive:
		_maintain_god_mode()
		return
	super()


func _maintain_god_mode():
	if gameData == null:
		return
	gameData.health = 100.0
	gameData.oxygen = 100.0
	gameData.damage = false
	gameData.impact = false
	gameData.isDead = false
