extends Node

var _settings: Resource = preload("res://VostokAIOverhaul/Settings.tres")
var _gameData: Resource = null
var _hud_label: Label = null


func _ready():
	if ResourceLoader.exists("res://Resources/GameData.tres"):
		_gameData = load("res://Resources/GameData.tres")


func _show_hud_message(msg: String):
	if _hud_label == null:
		_hud_label = Label.new()
		_hud_label.position = Vector2(20, 60)
		_hud_label.add_theme_font_size_override("font_size", 18)
		_hud_label.add_theme_color_override("font_color", Color.YELLOW)
		_hud_label.text = ""
		get_tree().root.add_child(_hud_label)

	_hud_label.text = msg
	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(_hud_label): _hud_label.text = ""
	)


func _unhandled_input(event):
	if not event is InputEventKey or not event.pressed:
		return

	if event.keycode == _settings.keyGodMode:
		_toggle_god_mode()
		return
	if event.keycode == _settings.keyHeal:
		_heal_player()
		return

	if not _settings.debugEnabled:
		return
	if event.keycode == _settings.keySpawnAI:
		_spawn_ai_nearby()
	elif event.keycode == _settings.keySpawnBoss:
		_spawn_boss_nearby()


func _spawn_ai_nearby():
	var spawner = _find_node_by_script("AISpawner")
	if spawner == null:
		return
	if _gameData == null or not "playerPosition" in _gameData:
		return

	var player_pos: Vector3 = _gameData.playerPosition
	var forward = Vector3(0, 0, -1)
	if "playerVector" in _gameData:
		forward = _gameData.playerVector.normalized()

	var spawn_pos = player_pos + forward * 15.0
	if spawner.has_method("SpawnMinion"):
		spawner.SpawnMinion(spawn_pos)
		_show_hud_message("[AI Overhaul] Spawned AI 15m ahead")
	elif spawner.has_method("SpawnWanderer"):
		spawner.SpawnWanderer()
		_show_hud_message("[AI Overhaul] Spawned AI")


func _toggle_god_mode():
	_settings.godModeActive = not _settings.godModeActive
	var state = "ON" if _settings.godModeActive else "OFF"
	_show_hud_message("[AI Overhaul] God Mode: %s" % state)


func _spawn_boss_nearby():
	var spawner = _find_node_by_script("AISpawner")
	if spawner == null:
		return
	if _gameData == null or not "playerPosition" in _gameData:
		return

	var player_pos: Vector3 = _gameData.playerPosition
	var forward = Vector3(0, 0, -1)
	if "playerVector" in _gameData:
		forward = _gameData.playerVector.normalized()

	var spawn_pos = player_pos + forward * 30.0
	if spawner.has_method("SpawnBoss"):
		spawner.SpawnBoss(spawn_pos)
		_show_hud_message("[AI Overhaul] Spawned BOSS 30m ahead")


func _heal_player():
	if _gameData != null and "health" in _gameData:
		_gameData.health = 100.0
		_show_hud_message("[AI Overhaul] Healed")


func _find_node_by_script(script_hint: String) -> Node:
	var root = get_tree().current_scene
	if root == null:
		root = get_tree().root
	return _search_recursive(root, script_hint, 0)


func _search_recursive(node: Node, hint: String, depth: int) -> Node:
	if depth > 5 or node == null:
		return null
	if node.name.contains(hint) or (node.get_script() != null and node.get_script().resource_path.contains(hint)):
		return node
	for child in node.get_children():
		var result = _search_recursive(child, hint, depth + 1)
		if result != null:
			return result
	return null
