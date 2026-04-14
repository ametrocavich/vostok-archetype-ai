extends "res://Scripts/AISpawner.gd"

var _settings: Resource = preload("res://VostokAIOverhaul/Settings.tres")
var _dormant_count: int = 0
var _active_count: int = 0
var _perf_check_timer: float = 0.0

enum PacingState { BUILD, PEAK, BREATHE }
var _pacing_state: int = PacingState.BUILD
var _tension: float = 0.0
var _tension_check_timer: float = 0.0
var _breathe_timer: float = 0.0
var _peak_timer: float = 0.0
var _original_frequency: int = -1

const TENSION_CHECK_INTERVAL: float = 0.5
const TENSION_PEAK_THRESHOLD: float = 0.7
const TENSION_RELAX_THRESHOLD: float = 0.3
const BREATHE_DURATION: float = 35.0
const MIN_PEAK_DURATION: float = 8.0

var alert_propagation: Node = null
const AlertPropagation = preload("res://VostokAIOverhaul/Systems/AlertPropagation.gd")

const PERF_CHECK_INTERVAL: float = 10.0


func _ready():
	var mult = int(_settings.aiCountMultiplier)

	if mult > 1:
		var orig_pool = spawnPool
		var orig_limit = spawnLimit
		spawnPool = spawnPool * mult
		spawnLimit = spawnLimit * mult
		if mult >= 4:
			spawnFrequency = 3
		elif mult >= 2:
			spawnFrequency = 2
		if _settings.debugEnabled:
			print("[AIOverhaul] AI count %dx: pool %d→%d, limit %d→%d, freq=%d" % [
				mult, orig_pool, spawnPool, orig_limit, spawnLimit, spawnFrequency
			])

	super()

	alert_propagation = AlertPropagation.new()
	alert_propagation.setup(self)
	alert_propagation.name = "AlertPropagation"
	add_child(alert_propagation)

	if _settings.debugEnabled:
		print("[AIOverhaul] AISpawner active (zone=%d, pool=%d, limit=%d)" % [zone, spawnPool, spawnLimit])


func _physics_process(delta):
	super(delta)

	if _settings.pacingEnabled:
		_tension_check_timer += delta
		if _tension_check_timer >= TENSION_CHECK_INTERVAL:
			_tension_check_timer = 0.0
			_update_pacing()

	if _settings.debugEnabled:
		_perf_check_timer += delta
		if _perf_check_timer >= PERF_CHECK_INTERVAL:
			_perf_check_timer = 0.0
			_update_perf_stats()


func _update_pacing():
	var tension_input = _calculate_tension()

	if tension_input > _tension:
		_tension = lerpf(_tension, tension_input, 0.3)
	else:
		_tension = lerpf(_tension, tension_input, 0.05)

	if _original_frequency < 0:
		_original_frequency = spawnFrequency

	match _pacing_state:
		PacingState.BUILD:
			spawnFrequency = _original_frequency
			if _tension >= TENSION_PEAK_THRESHOLD:
				_pacing_state = PacingState.PEAK
				_peak_timer = 0.0
				if _settings.debugEnabled:
					print("[AIOverhaul] Pacing: BUILD → PEAK (tension=%.0f%%)" % (_tension * 100))

		PacingState.PEAK:
			_peak_timer += TENSION_CHECK_INTERVAL
			spawnFrequency = 0
			if _tension < TENSION_RELAX_THRESHOLD and _peak_timer > MIN_PEAK_DURATION:
				_pacing_state = PacingState.BREATHE
				_breathe_timer = 0.0
				if _settings.debugEnabled:
					print("[AIOverhaul] Pacing: PEAK → BREATHE")

		PacingState.BREATHE:
			_breathe_timer += TENSION_CHECK_INTERVAL
			spawnFrequency = 0
			if _breathe_timer >= BREATHE_DURATION:
				_pacing_state = PacingState.BUILD
				spawnFrequency = _original_frequency
				if _settings.debugEnabled:
					print("[AIOverhaul] Pacing: BREATHE → BUILD")


func _calculate_tension() -> float:
	if not is_instance_valid(agents):
		return 0.0

	var game_data = _try_get_gamedata()
	var tension_val = 0.0

	if game_data != null and "health" in game_data:
		var hp_ratio = clampf(game_data.health / 100.0, 0.0, 1.0)
		tension_val += (1.0 - hp_ratio) * 0.3

	var combat_count = 0
	var total_active = 0
	for child in agents.get_children():
		if not is_instance_valid(child) or child.get("dead") == true:
			continue
		total_active += 1
		var awareness_node = child.get_node_or_null("AwarenessSystem")
		if awareness_node != null and "awareness" in awareness_node:
			if awareness_node.awareness >= 0.5:
				combat_count += 1

	if total_active > 0:
		tension_val += (float(combat_count) / float(total_active)) * 0.5

	if game_data != null and "damage" in game_data and game_data.damage:
		tension_val += 0.2

	return clampf(tension_val, 0.0, 1.0)


var _gamedata_cache: Resource = null

func _try_get_gamedata() -> Resource:
	if _gamedata_cache != null:
		return _gamedata_cache
	if ResourceLoader.exists("res://Resources/GameData.tres"):
		_gamedata_cache = load("res://Resources/GameData.tres")
	return _gamedata_cache


func _update_perf_stats():
	if not is_instance_valid(agents):
		return
	_dormant_count = 0
	_active_count = 0
	for child in agents.get_children():
		if not is_instance_valid(child):
			continue
		if child.get("dead") == true:
			continue
		_active_count += 1
		if child.get("_perf_perception_dormant") == true:
			_dormant_count += 1

	if _active_count > 0:
		print("[AIOverhaul] PERF: %d/%d AI active, %d dormant (saving ~%d raycasts/sec)" % [
			_active_count - _dormant_count, _active_count, _dormant_count,
			_dormant_count * 3
		])
		var pacing_names = ["BUILD", "PEAK", "BREATHE"]
		print("[AIOverhaul] PACING: %s tension=%.0f%% freq=%d" % [
			pacing_names[_pacing_state] if _pacing_state < 3 else "?",
			_tension * 100, spawnFrequency
		])
