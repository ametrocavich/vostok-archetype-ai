extends Node

enum Phase { PROFESSIONAL, COMMANDER, DESPERATE }

var current_phase: Phase = Phase.PROFESSIONAL
var ai: Node = null
var spawner: Node = null

var _entered_commander: bool = false
var _entered_desperate: bool = false

var _minion_cooldown: float = 0.0
var _minions_spawned_total: int = 0
const MINION_COOLDOWN: float = 15.0
const MAX_MINIONS_PER_WAVE: int = 3

var _settings: Resource = null


func setup(boss_ai: Node, ai_spawner: Node, settings: Resource):
	ai = boss_ai
	spawner = ai_spawner
	_settings = settings
	if ai_spawner == null:
		push_warning("[AIOverhaul] BossController has no spawner")


func update_phase():
	if ai == null or not is_instance_valid(ai):
		return
	if ai.get("dead") == true:
		return

	var hp_pct = ai.health / 300.0

	if hp_pct > _settings.bossPhase2Threshold:
		current_phase = Phase.PROFESSIONAL
	elif hp_pct > _settings.bossPhase3Threshold:
		if not _entered_commander:
			_enter_commander_phase()
			_entered_commander = true
		current_phase = Phase.COMMANDER
	else:
		if not _entered_desperate:
			_enter_desperate_phase()
			_entered_desperate = true
		current_phase = Phase.DESPERATE


func tick(delta: float):
	if current_phase == Phase.DESPERATE:
		_minion_cooldown -= delta
		if _minion_cooldown <= 0.0 and _minions_spawned_total < MAX_MINIONS_PER_WAVE:
			_spawn_minion()
			_minion_cooldown = MINION_COOLDOWN


func _enter_commander_phase():
	if ai == null or spawner == null:
		return

	if _settings != null and _settings.debugEnabled:
		print("[AIOverhaul] BOSS: Commander phase — rallying + spawning minions")

	if spawner.has_method("CreateHotspot"):
		spawner.CreateHotspot(ai.global_position, true)

	var pos1 = _find_offscreen_spawn()
	var pos2 = _find_offscreen_spawn()
	_spawn_minion_at(pos1)
	_spawn_minion_at(pos2)


func _enter_desperate_phase():
	if ai == null:
		return

	if _settings != null and _settings.debugEnabled:
		print("[AIOverhaul] BOSS: Desperate phase — full aggression")

	if "speed" in ai:
		ai.speed = 4.0

	ai.ChangeState("Attack")

	_minion_cooldown = 5.0
	_minions_spawned_total = 0


func _spawn_minion():
	if ai == null or spawner == null:
		return
	var pos = _find_offscreen_spawn()
	_spawn_minion_at(pos)


func _find_offscreen_spawn() -> Vector3:
	if ai == null:
		return Vector3.ZERO

	var player_pos = Vector3.ZERO
	if "playerPosition" in ai:
		player_pos = ai.playerPosition

	var player_forward = Vector3(0, 0, -1)
	if ai.get("gameData") != null and "playerVector" in ai.gameData:
		player_forward = ai.gameData.playerVector.normalized()

	var best_point = Vector3.ZERO
	var best_score = -999.0

	var spawn_points = ai.get_tree().get_nodes_in_group("AI_SP")
	for pt in spawn_points:
		if not is_instance_valid(pt):
			continue
		var dist_to_player = pt.global_position.distance_to(player_pos)
		var dist_to_boss = pt.global_position.distance_to(ai.global_position)

		if dist_to_player < 60.0 or dist_to_player > 200.0:
			continue
		if dist_to_boss > 150.0:
			continue

		var dir_to_point = (pt.global_position - player_pos).normalized()
		var behind_score = -dir_to_point.dot(player_forward)

		var score = behind_score * 10.0 - dist_to_boss * 0.05 + randf_range(-2, 2)

		if score > best_score:
			best_score = score
			best_point = pt.global_position

	if best_point == Vector3.ZERO:
		var behind = -player_forward
		best_point = player_pos + behind * 80.0 + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))

	return best_point


func _spawn_minion_at(pos: Vector3):
	if spawner == null or not is_instance_valid(spawner):
		return
	if spawner.has_method("SpawnMinion"):
		spawner.SpawnMinion(pos)
		_minions_spawned_total += 1
		if _settings != null and _settings.debugEnabled:
			print("[AIOverhaul] Boss spawned minion at (%.0f,%.0f,%.0f)" % [pos.x, pos.y, pos.z])


func get_boss_decision() -> String:
	match current_phase:
		Phase.PROFESSIONAL:
			return _professional_decision()
		Phase.COMMANDER:
			return _commander_decision()
		Phase.DESPERATE:
			return "Attack"
	return "Combat"


func _professional_decision() -> String:
	var dist = ai.playerDistance3D if ai != null else 50.0

	if dist < 20.0:
		var choices = ["Defend", "Combat", "Defend"]
		return choices[randi() % choices.size()]
	elif dist < 60.0:
		var choices = ["Cover", "Defend", "Vantage", "Shift"]
		return choices[randi() % choices.size()]
	else:
		var choices = ["Vantage", "Cover", "Shift", "Hunt"]
		return choices[randi() % choices.size()]


func _commander_decision() -> String:
	var dist = ai.playerDistance3D if ai != null else 50.0

	if dist < 20.0:
		var choices = ["Attack", "Defend", "Combat"]
		return choices[randi() % choices.size()]
	elif dist < 60.0:
		var choices = ["Shift", "Cover", "Attack", "Defend"]
		return choices[randi() % choices.size()]
	else:
		var choices = ["Attack", "Shift", "Vantage"]
		return choices[randi() % choices.size()]


func get_phase_name() -> String:
	match current_phase:
		Phase.PROFESSIONAL: return "BOSS P1"
		Phase.COMMANDER: return "BOSS P2"
		Phase.DESPERATE: return "BOSS P3"
	return "BOSS"
