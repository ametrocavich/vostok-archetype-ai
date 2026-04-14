extends "res://Scripts/AI.gd"

var _settings: Resource = preload("res://VostokAIOverhaul/Settings.tres")

# Reaction delay
var _reaction_timer: float = 0.0
var _reaction_target: float = 0.0
var _is_reacting: bool = false
var _has_reacted: bool = false
var _delaying_decision: bool = false
var _reset_reaction_timer: float = 0.0

# Hit stagger
var _stagger_timer: float = 0.0
var _is_staggered: bool = false
var _stagger_cooldown_timer: float = 0.0

# Faction profiles
var _faction_profile: Resource = null
static var _faction_profiles: Dictionary = {
	"Bandit": preload("res://VostokAIOverhaul/Factions/Bandit.tres"),
	"Guard": preload("res://VostokAIOverhaul/Factions/Guard.tres"),
	"Military": preload("res://VostokAIOverhaul/Factions/Military.tres"),
	"Punisher": preload("res://VostokAIOverhaul/Factions/Punisher.tres"),
}

# Awareness
var _awareness: Node = null
const AwarenessSystem = preload("res://VostokAIOverhaul/Systems/AwarenessSystem.gd")

var _initialized: bool = false
var _logged_once: bool = false

# Cached property checks
var _has_playerHeard: bool = false
var _has_playerWasHeard: bool = false
var _has_fireDetected: bool = false
var _has_takingFire: bool = false

var _fire_alert_cooldown: float = 0.0
var _prev_awareness: float = 0.0

# Combat LOS tracking
var _los_lost_timer: float = 0.0
const COMBAT_LOS_GRACE: float = 3.0
var _below_combat_pullout_done: bool = false

# Boss
var _boss_controller: Node = null
const BossController = preload("res://VostokAIOverhaul/Systems/BossController.gd")

# Personality
enum Personality { NORMAL, COWARD, BERSERKER, LOOKOUT, ENFORCER, OPERATOR, SNIPER }
var _personality: int = Personality.NORMAL

# Suppressive fire
var _suppressive_fire: bool = false
var _suppressive_fire_timer: float = 0.0

# Damage reaction
var _took_damage_recently: bool = false
var _damage_react_timer: float = 0.0

# Cover cache (avoid scanning cover points every frame)
var _cover_cached: bool = false
var _cover_cd: float = 0.0

# Door closing
var _close_door: Node = null
var _close_door_timer: float = 0.0
const CLOSE_DOOR_TIME: float = 5.0

# World ref for weather visibility
var _world_node: Node = null
var _world_cached: bool = false

# Suppression (near-miss fire)
var _suppression: float = 0.0
const SUPPRESSION_DECAY: float = 0.12
const SUPPRESSION_RADIUS: float = 6.0
var _last_player_firing: bool = false
static var _gunfire_alert_cd: float = 0.0
static var _alert_last_frame: int = -1

# --- Stuck detection + dwell timer ---
var _stuck_check_pos: Vector3 = Vector3.ZERO
var _stuck_check_timer: float = 0.0
var _stuck_count: int = 0

# LKL dwell
var _lkl_dwell_timer: float = 0.0
var _lkl_dwelling: bool = false
var _silence_timer: float = 0.0

# Perf LOD
var _perf_perception_dormant: bool = false
var _perf_is_sniper: bool = false
var _perf_orig_sensor_cycle: float = -1.0
var _perf_extended_sensor: bool = false
var _cached_weapon_action: String = ""

# Predicted pursuit
var _predicted_velocity: Vector3 = Vector3.ZERO
var _predicted_pos_set: bool = false
var _last_pursuit_log: String = ""
var _pursuit_decided: bool = false

# First-shot near-miss
var _first_shot_fired: bool = false
var _first_shot_reset_timer: float = 0.0

# Speed modulation
var _speed_mode: int = 0
var _speed_base: float = -1.0

# Sniper relocation
var _sniper_shots_from_pos: int = 0
var _sniper_compromised: bool = false
var _sniper_pos_anchor: Vector3 = Vector3.ZERO
var _sniper_max_shots: int = 4

# Per-AI reaction jitter (0.7-1.4, set once)
var _reaction_jitter: float = 1.0

# Search pattern
var _search_origin: Vector3 = Vector3.ZERO
var _search_points_checked: int = 0
var _search_max_points: int = 3
var _search_radius: float = 25.0
var _search_active: bool = false
var _search_arrival_timer: float = 0.0

# Static arrays (avoid per-frame alloc)
static var _firing_states: Array = []
static var _pursuit_states: Array = []
static var _investigate_choices_alert: Array = ["Hunt", "Guard", "Cover"]
static var _investigate_choices_suspicious: Array = ["Guard", "Hunt"]
static var _hearing_interaction_props: Array = ["isReloading", "isChecking", "isInserting", "isInteracting", "isOccupied", "isCrafting"]
static var _passive_states: Array = []
static var _states_initialized: bool = false
static var _cached_waypoints: Array = []
static var _cached_waypoints_valid: bool = false

# Debug
var _debug_label: Label3D = null
var _debug_update_timer: float = 0.0
const DEBUG_UPDATE_INTERVAL: float = 0.15
var _debug_cached_text: String = ""
var _debug_cached_color: Color = Color.WHITE


func _ready():
	super()
	if not _states_initialized:
		_firing_states = [State.Combat, State.Defend, State.Shift, State.Vantage, State.Cover]
		_pursuit_states = [State.Hunt, State.Attack]
		_passive_states = [State.Wander, State.Patrol, State.Idle]
		_states_initialized = true
		if _settings.debugEnabled:
			print("[AIOverhaul] AI override active")


func _lazy_init():
	if _initialized:
		return
	if global_position.y > 500.0:
		return  # pooled at y=1000, not in game yet
	_initialized = true

	_determine_faction_profile()

	_has_playerHeard = "playerHeard" in self
	_has_playerWasHeard = "playerWasHeard" in self
	_has_fireDetected = "fireDetected" in self
	_has_takingFire = "takingFire" in self

	# Stagger sensor timers to avoid same-frame raycasts
	if "sensorTimer" in self:
		set("sensorTimer", randf_range(0.0, 0.1))

	_reaction_jitter = randf_range(0.7, 1.4)

	if _personality == Personality.SNIPER:
		_sniper_max_shots = randi_range(3, 5)

	if is_instance_valid(weaponData) and "weaponAction" in weaponData:
		_cached_weapon_action = str(weaponData.weaponAction)
		_perf_is_sniper = (_cached_weapon_action == "Bolt")

	if boss and _settings.bossPhaseEnabled:
		_boss_controller = BossController.new()
		_boss_controller.setup(self, AISpawner, _settings)
		_boss_controller.name = "BossController"
		add_child(_boss_controller)

	# Assign personality per faction
	if _faction_profile != null:
		var roll = randf()
		match _faction_profile.faction_name:
			"Bandit":
				if roll < 0.35:
					_personality = Personality.COWARD
				elif roll < 0.60:
					_personality = Personality.BERSERKER
				# else: NORMAL (40%)
			"Guard":
				if roll < 0.30:
					_personality = Personality.LOOKOUT
				elif roll < 0.55:
					_personality = Personality.ENFORCER
				# else: NORMAL (45%)
			"Military":
				if roll < 0.25:
					_personality = Personality.SNIPER
				elif roll < 0.50:
					_personality = Personality.OPERATOR
				# else: NORMAL (50%)


	if _settings.awarenessEnabled:
		_awareness = AwarenessSystem.new()
		_awareness.settings = _settings
		_awareness.name = "AwarenessSystem"
		add_child(_awareness)

	if _settings.debugEnabled:
		_setup_debug_label()

	var faction_name = "none"
	if _faction_profile != null:
		faction_name = _faction_profile.faction_name
	var pers_names = ["Normal", "Coward", "Berserker", "Lookout", "Enforcer", "Operator", "Sniper"]
	if _settings.debugEnabled:
		print("[AIOverhaul] AI init: %s %s boss=%s hp=%d pos=(%d,%d,%d)" % [
			faction_name, pers_names[_personality], boss, health,
			int(global_position.x), int(global_position.y), int(global_position.z)
		])



func Parameters(delta):
	super(delta)

	var has_memory = is_instance_valid(_awareness) and _awareness._combat_memory

	# Extend sensorCycle for distant AI; snipers get normal rates at longer ranges
	if not has_memory and "sensorCycle" in self:
		var dormant_dist = 200.0 if not _perf_is_sniper else 300.0

		if playerDistance3D > dormant_dist:
			if not _perf_extended_sensor:
				_perf_orig_sensor_cycle = sensorCycle
			sensorCycle = maxf(sensorCycle, 2.0)
			_perf_perception_dormant = true
			_perf_extended_sensor = true
		elif playerDistance3D > 150.0 and not _perf_is_sniper:
			if not _perf_extended_sensor:
				_perf_orig_sensor_cycle = sensorCycle
			sensorCycle = maxf(sensorCycle, 0.8)
			_perf_perception_dormant = false
			_perf_extended_sensor = true
		elif _perf_extended_sensor:
			if _perf_orig_sensor_cycle > 0:
				sensorCycle = _perf_orig_sensor_cycle
			_perf_perception_dormant = false
			_perf_extended_sensor = false


func Interactor(delta):
	super(delta)

	# Close doors 5s after AI opens them
	if _close_door != null and is_instance_valid(_close_door):
		_close_door_timer += delta
		if _close_door_timer > CLOSE_DOOR_TIME:
			var can_close = true
			if "speed" in self and speed >= 2.0:
				can_close = false
			elif playerVisible:
				can_close = false
			elif not _close_door.get("isOpen") == true:
				can_close = false
			elif _close_door.global_position.distance_to(global_position) < 1.5:
				can_close = false
			elif gameData != null and "playerPosition" in gameData:
				if _close_door.global_position.distance_to(gameData.playerPosition) < 5.0:
					can_close = false
			if can_close and _close_door.has_method("Interact"):
				if _settings.debugEnabled:
					print("[AI:%s] DOOR: closed" % name)
				_close_door.Interact()
			_close_door = null
			_close_door_timer = 0.0
	elif "interactDoor" in self:
		var door = get("interactDoor")
		if door != null and is_instance_valid(door) and door.get("isOpen") == true:
			_close_door = door
			_close_door_timer = 0.0


var _prof_state_changes: int = 0
var _prof_last_state: String = ""
var _prof_timer: float = 0.0


func ChangeState(state):
	# don't let vanilla go passive during combat
	if _initialized and is_instance_valid(_awareness):
		if _awareness.level >= AwarenessSystem.AwarenessLevel.COMBAT:
			if state in ["Wander", "Patrol", "Idle", "Ambush", "Return"]:
				state = "Guard"  # hold and scan, don't go passive

	if _initialized and state != _prof_last_state:
		_prof_state_changes += 1
		_prof_last_state = state

	super(state)

	# 25% chance to lose tracking on state change (skip during pursuit/suppression)
	if not _predicted_pos_set and not _suppressive_fire:
		if "speed" in self and speed > 0.0 and randi() % 4 == 0:
			if "currentPoint" in self and get("currentPoint") != null:
				if "playerPosition" in self and lastKnownLocation.distance_to(playerPosition) > 10.0:
					if has_method("ResetLKL"):
						if _settings.debugEnabled:
							print("[AI:%s] LKL_RESET: random tracking loss on state change" % name)
						call("ResetLKL")

	# Cap state cycle timers for snappier combat
	if "defendCycle" in self and state == "Defend":
		set("defendCycle", minf(get("defendCycle"), 6.0))
	if "combatCycle" in self and state == "Combat":
		set("combatCycle", minf(get("combatCycle"), 6.0))
	if "guardCycle" in self and state == "Guard":
		if is_instance_valid(_awareness) and _awareness.level >= AwarenessSystem.AwarenessLevel.COMBAT:
			set("guardCycle", randf_range(1.5, 2.5))


func Defend(delta):
	super(delta)
	if dead or not _initialized or _is_reacting:
		return
	if boss and _boss_controller != null and _boss_controller.current_phase == BossController.Phase.DESPERATE:
		return

	var timer = get("defendTimer") if "defendTimer" in self else 0.0

	# Condition-driven exits (not timer-based ceasefire)
	if _suppression > 0.5:
		if _settings.debugEnabled:
			print("[AI:%s] DEFEND: supp %.0f%% -> Cover" % [name, _suppression * 100])
		ChangeState("Cover")
		return

	if _took_damage_recently and not _has_cover():
		if _settings.debugEnabled:
			print("[AI:%s] DEFEND: damage+no cover -> Cover" % name)
		ChangeState("Cover")
		return

	# Lost sight for 5+ seconds → re-decide
	if not playerVisible and _los_lost_timer > 5.0:
		if _settings.debugEnabled:
			print("[AI:%s] DEFEND: LOS lost %.1fs -> Decision" % [name, _los_lost_timer])
		Decision()
		return

	# Safety-net timer (10-20s) so AI doesn't get permanently stuck
	if timer > 15.0:
		if _settings.debugEnabled:
			print("[AI:%s] DEFEND: timer %.1fs -> Decision" % [name, timer])
		Decision()
		return


func Combat(delta):
	super(delta)
	if dead or not _initialized or _is_reacting:
		return
	if boss and _boss_controller != null and _boss_controller.current_phase == BossController.Phase.DESPERATE:
		return

	var timer = get("combatTimer") if "combatTimer" in self else 0.0
	if timer < 3.0:
		return

	# Condition-driven exits
	if _took_damage_recently and not _has_cover():
		if _settings.debugEnabled:
			print("[AI:%s] COMBAT: damage+no cover -> Cover" % name)
		ChangeState("Cover")
		return

	if _suppression > 0.6:
		if _settings.debugEnabled:
			print("[AI:%s] COMBAT: supp %.0f%% -> Cover" % [name, _suppression * 100])
		ChangeState("Cover")
		return

	# Longer safety timer (vanilla is 4-10s, we extend to 8-15s)
	if timer > 12.0:
		if _settings.debugEnabled:
			print("[AI:%s] COMBAT: timer %.1fs -> Decision" % [name, timer])
		Decision()
		return


func Shift(delta):
	super(delta)
	if dead or not _initialized or _is_reacting:
		return
	if boss and _boss_controller != null and _boss_controller.current_phase == BossController.Phase.DESPERATE:
		return

	var timer = get("shiftTimer") if "shiftTimer" in self else 0.0
	if timer < 1.0:
		return

	if _suppression > 0.5:
		if randf() < 0.6:
			if _settings.debugEnabled:
				print("[AI:%s] SHIFT: supp %.0f%% -> Cover" % [name, _suppression * 100])
			ChangeState("Cover")
		else:
			if _settings.debugEnabled:
				print("[AI:%s] SHIFT: supp %.0f%% -> Defend" % [name, _suppression * 100])
			ChangeState("Defend")
		return

	if playerDistance3D < 12.0 and playerVisible:
		if _settings.debugEnabled:
			print("[AI:%s] SHIFT: close %.0fm+vis -> Defend" % [name, playerDistance3D])
		ChangeState("Defend")
		return


func _above_player() -> bool:
	if gameData == null or not "playerPosition" in gameData:
		return false
	return global_position.y - gameData.playerPosition.y > 3.0


func _physics_process(delta):
	super(delta)

	if not _initialized:
		_lazy_init()
		return

	# --- Awareness-gated state management ---
	if _settings.awarenessEnabled and is_instance_valid(_awareness):
		if _awareness.level >= AwarenessSystem.AwarenessLevel.COMBAT:
			_below_combat_pullout_done = false
			if not playerVisible:
				# 50% chance suppressive fire at LKL for 2-5s
				if _los_lost_timer == 0.0 and not _suppressive_fire:
					if _settings.suppressionEnabled and randf() < 0.5:
						_suppressive_fire = true
						_suppressive_fire_timer = randf_range(2.0, 5.0)
						if _settings.debugEnabled:
							print("[AI:%s] SUPPFIRE: started %.1fs" % [name, _suppressive_fire_timer])
				_los_lost_timer += delta
				if _los_lost_timer >= COMBAT_LOS_GRACE:
					if not _predicted_pos_set and _awareness.last_known_position != Vector3.ZERO:
						var predicted = _get_predicted_position()
						lastKnownLocation = predicted
						_awareness.last_known_position = predicted
						_predicted_pos_set = true
						if _settings.debugEnabled:
							print("[AI:%s] PURSUIT: predicted pos set" % name)

					# Hold position silently before pursuing
					if _silence_timer <= 0.0 and currentState in _firing_states and not _pursuit_decided:
						_silence_timer = randf_range(5.0, 8.0)
						if _settings.debugEnabled:
							var log_msg = "silence %.1fs from firing" % _silence_timer
							if log_msg != _last_pursuit_log:
								_last_pursuit_log = log_msg
								print("[AI:%s] PURSUIT: %s" % [name, log_msg])
						ChangeState("Guard")
					elif _silence_timer <= 0.0 and not _pursuit_decided:
						_pursuit_decided = true
						if _above_player():
							if currentState == State.Vantage:
								if _settings.debugEnabled:
									var log_msg = "above+vantage -> Guard"
									if log_msg != _last_pursuit_log:
										_last_pursuit_log = log_msg
										print("[AI:%s] PURSUIT: %s" % [name, log_msg])
								ChangeState("Guard")
							else:
								if _settings.debugEnabled:
									var log_msg = "above -> Vantage"
									if log_msg != _last_pursuit_log:
										_last_pursuit_log = log_msg
										print("[AI:%s] PURSUIT: %s" % [name, log_msg])
								ChangeState("Vantage")
						else:
							var pursuit_state = "Attack"
							if _personality in [Personality.COWARD, Personality.LOOKOUT]:
								pursuit_state = "Guard"
							elif _personality == Personality.SNIPER:
								pursuit_state = "Vantage"
							if _settings.debugEnabled:
								var log_msg = "LOS lost %.1fs -> %s" % [_los_lost_timer, pursuit_state]
								if log_msg != _last_pursuit_log:
									_last_pursuit_log = log_msg
									print("[AI:%s] PURSUIT: %s" % [name, log_msg])
							ChangeState(pursuit_state)
			else:
				_los_lost_timer = 0.0
				_predicted_pos_set = false
				_pursuit_decided = false
				_last_pursuit_log = ""
				# Re-engage immediately if visible in a non-combat state
				if currentState in [State.Guard, State.Wander, State.Patrol, State.Idle]:
					Decision()
				if gameData != null and "playerVector" in gameData:
					_predicted_velocity = gameData.playerVector

		else:
			_los_lost_timer = 0.0
			_pursuit_decided = false
			_silence_timer = 0.0
			_predicted_pos_set = false
			if currentState in _firing_states and not _below_combat_pullout_done:
				_below_combat_pullout_done = true
				if _above_player():
					if _settings.debugEnabled:
						print("[AI:%s] PULLOUT: below combat+above -> Guard" % name)
					ChangeState("Guard")  # Stay elevated, scan
				elif _awareness.level >= AwarenessSystem.AwarenessLevel.SUSPICIOUS:
					if _settings.debugEnabled:
						print("[AI:%s] PULLOUT: below combat+suspicious -> Hunt" % name)
					ChangeState("Hunt")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] PULLOUT: below combat -> Guard" % name)
					ChangeState("Guard")

			# Catch vanilla fallback to passive states during active awareness
			if _awareness.level >= AwarenessSystem.AwarenessLevel.SUSPICIOUS:
				if currentState in _passive_states:
					if _awareness.last_known_position != Vector3.ZERO:
						lastKnownLocation = _awareness.last_known_position
						if _settings.debugEnabled:
							print("[AI:%s] VIS_BLOCKED: passive+suspicious -> Hunt" % name)
						ChangeState("Hunt")
					else:
						if _settings.debugEnabled:
							print("[AI:%s] VIS_BLOCKED: passive+suspicious -> Guard" % name)
						ChangeState("Guard")

		if currentState in _pursuit_states and _awareness.last_known_position != Vector3.ZERO:
			lastKnownLocation = _awareness.last_known_position

	# --- Search pattern ---
	if is_instance_valid(_awareness) and currentState in _pursuit_states and not playerVisible \
			and _awareness.level < AwarenessSystem.AwarenessLevel.COMBAT:
		# Interrupt search if new sound from a different location
		if _search_active and _awareness.last_known_position != Vector3.ZERO:
			var dist_to_new_sound = _awareness.last_known_position.distance_to(_search_origin)
			if dist_to_new_sound > 10.0:
				_search_active = false
				_search_points_checked = 0
				lastKnownLocation = _awareness.last_known_position
				ChangeState("Attack")
				if _settings.debugEnabled:
					print("[AIOverhaul] Search INTERRUPTED — new sound detected!")

		var dist_to_target = global_position.distance_to(lastKnownLocation)

		if dist_to_target < 8.0:
			_search_arrival_timer += delta

			if not _search_active:
				_search_active = true
				_search_origin = lastKnownLocation
				_search_points_checked = 0
				_search_arrival_timer = 0.0

			if _search_arrival_timer > 2.5:
				_search_points_checked += 1

				if _search_points_checked < _search_max_points:
					var new_point = _generate_search_point(_search_origin)
					lastKnownLocation = new_point
					_awareness.last_known_position = new_point
					_search_arrival_timer = 0.0

					if _settings.debugEnabled:
						print("[AIOverhaul] Search point %d/%d at (%.0f,%.0f)" % [
							_search_points_checked, _search_max_points,
							new_point.x, new_point.z
						])
				else:
					_search_active = false
					_lkl_dwelling = true
					_lkl_dwell_timer = randf_range(5.0, 10.0)
					ChangeState("Guard")
					if _settings.debugEnabled:
						print("[AIOverhaul] Search complete — holding position %.0fs" % _lkl_dwell_timer)
		else:
			_search_arrival_timer = 0.0
	else:
		if _search_active and playerVisible:
			if _settings.debugEnabled:
				print("[AI:%s] SEARCH: cancelled, player visible" % name)
			_search_active = false
			_search_points_checked = 0

	# --- Stuck detection ---
	if _initialized and currentState in _pursuit_states:
		_stuck_check_timer += delta
		if _stuck_check_timer > 3.0:
			_stuck_check_timer = 0.0
			if global_position.distance_to(_stuck_check_pos) < 1.0:
				_stuck_count += 1
				if _stuck_count >= 2:
					_stuck_count = 0
					if _settings.debugEnabled:
						print("[AI:%s] STUCK: redirecting, vis=%s" % [name, playerVisible])
					if playerVisible:
						ChangeState("Defend")
					else:
						ChangeState("Guard")
			else:
				_stuck_count = 0
			_stuck_check_pos = global_position

	# --- LKL dwell ---
	if _lkl_dwelling:
		_lkl_dwell_timer -= delta
		if _lkl_dwell_timer <= 0.0:
			_lkl_dwelling = false

	if _silence_timer > 0.0:
		_silence_timer -= delta

	if boss and _boss_controller != null:
		_boss_controller.tick(delta)

	# --- Speed modulation ---
	# scale vanilla's speed for state
	if _initialized and "speed" in self and not dead:
		var new_context = 0
		if is_instance_valid(_awareness):
			if _lkl_dwelling or _silence_timer > 0.0:
				new_context = 3
			elif currentState == State.Hunt:
				new_context = 1
			elif currentState in [State.Attack, State.Shift, State.Cover]:
				if _awareness.level >= AwarenessSystem.AwarenessLevel.COMBAT or currentState != State.Attack:
					new_context = 2

		if new_context != _speed_mode:
			var prev = _speed_mode
			_speed_mode = new_context
			# Store base speed from vanilla's ChangeState, apply multiplier from that
			if prev == 0:
				_speed_base = speed  # capture vanilla's speed when leaving normal
			elif _speed_base > 0:
				speed = _speed_base  # restore base before applying new mult
			else:
				_speed_base = speed
			match new_context:
				0: speed = _speed_base
				1: speed = maxf(_speed_base * 0.65, 0.5)
				2: speed = _speed_base * 1.2
				3: speed = maxf(_speed_base * 0.4, 0.3)
			if _settings.debugEnabled:
				var mode_names = ["normal", "cautious", "sprint", "creep"]
				print("[AI:%s] SPEED: %s -> %s" % [name, mode_names[prev], mode_names[new_context]])

	if _cover_cd > 0.0:
		_cover_cd -= delta

	# Damage reaction timer
	if _took_damage_recently:
		_damage_react_timer -= delta
		if _damage_react_timer <= 0.0:
			_took_damage_recently = false

	# Suppressive fire decay
	if _suppressive_fire:
		_suppressive_fire_timer -= delta
		if _suppressive_fire_timer <= 0.0:
			_suppressive_fire = false
			if _settings.debugEnabled:
				print("[AI:%s] SUPPFIRE: ended" % name)

	if _fire_alert_cooldown > 0.0:
		_fire_alert_cooldown -= delta
	var current_frame = Engine.get_physics_frames()
	if _alert_last_frame != current_frame:
		_alert_last_frame = current_frame
		if _gunfire_alert_cd > 0.0:
			_gunfire_alert_cd -= delta

	# --- Suppression ---
	if _settings.suppressionEnabled and _initialized and gameData != null:
		_suppression = maxf(0.0, _suppression - SUPPRESSION_DECAY * delta)

		var player_firing = "isFiring" in gameData and gameData.isFiring
		if player_firing and not _last_player_firing:
			_check_suppression()
			if _gunfire_alert_cd <= 0.0:
				_gunfire_alert_cd = 3.0
				_alert_nearby("propagate_player_gunfire", [gameData.playerPosition])
		_last_player_firing = player_firing

	# Reset first-shot after 10s without LOS
	if _first_shot_fired:
		if not playerVisible:
			_first_shot_reset_timer += delta
			if _first_shot_reset_timer > 10.0:
				_first_shot_fired = false
				_first_shot_reset_timer = 0.0
		else:
			_first_shot_reset_timer = 0.0

	# --- Reaction delay tick ---
	if _settings.reactionDelayEnabled and _is_reacting:
		_reaction_timer += delta
		if _reaction_timer >= _reaction_target:
			_is_reacting = false
			_has_reacted = true
			_delaying_decision = false
			if not _logged_once:
				if _settings.debugEnabled:
						print("[AIOverhaul] Reaction delay complete")
				_logged_once = true
			Decision()

	# --- Reaction reset (only when fully out of combat, not during chase) ---
	if _settings.reactionDelayEnabled:
		var in_combat_memory = is_instance_valid(_awareness) and _awareness._combat_memory
		if not playerVisible and not in_combat_memory:
			_reset_reaction_timer += delta
			if _reset_reaction_timer > _settings.reactionResetTime:
				_has_reacted = false
				_reset_reaction_timer = 0.0
		else:
			_reset_reaction_timer = 0.0

	# --- Stagger tick ---
	if _settings.staggerEnabled and _is_staggered:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			_is_staggered = false
			_stagger_timer = 0.0

	if _stagger_cooldown_timer > 0.0:
		_stagger_cooldown_timer -= delta

	# --- Profiling summary ---
	if _settings.debugEnabled and _initialized:
		_prof_timer += delta
		if _prof_timer > 5.0:
			_prof_timer = 0.0
			if _prof_state_changes > 0:
				var sname = _state_names[currentState] if currentState >= 0 and currentState < _state_names.size() else "?"
				var pers_names_p = ["Norm", "Cow", "Bers", "Look", "Enf", "Op", "Snip"]
				var pname = pers_names_p[_personality] if _personality < pers_names_p.size() else "?"
				print("[AI:%s] PROF 5s: %s %d transitions, state=%s aware=%.0f%% supp=%.0f%% hp=%d" % [
					name, pname, _prof_state_changes, sname,
					_awareness.awareness * 100.0 if is_instance_valid(_awareness) else 0.0,
					_suppression * 100.0, health
				])
				_prof_state_changes = 0

	# --- Debug overlay ---
	if _settings.debugEnabled and _debug_label == null and _initialized:
		_setup_debug_label()

	# --- Debug overlay update ---
	if _settings.debugEnabled and is_instance_valid(_debug_label):
		_debug_update_timer += delta
		if _debug_update_timer >= DEBUG_UPDATE_INTERVAL:
			_debug_update_timer = 0.0
			_update_debug_label()


func LOSCheck(target: Vector3):
	super(target)

	# Foliage concealment
	if _settings.foliageConcealment:
		_apply_foliage_concealment()

	if not _settings.reactionDelayEnabled:
		return

	# Gate reaction delay behind awareness level
	if _settings.awarenessEnabled and is_instance_valid(_awareness):
		if _awareness.level < AwarenessSystem.AwarenessLevel.COMBAT:
			return

	if playerVisible and not _has_reacted and not _is_reacting:
		_is_reacting = true
		_delaying_decision = true
		_reaction_target = _calculate_reaction_delay()
		_reaction_timer = 0.0
		if _settings.debugEnabled:
			print("[AIOverhaul] Reaction: %.2fs at %.0fm" % [_reaction_target, playerDistance3D])


func Decision():
	if _delaying_decision:
		if _settings.debugEnabled:
			print("[AI:%s] DECISION: blocked by reaction delay" % name)
		return

	if _lkl_dwelling:
		if _settings.debugEnabled:
			print("[AI:%s] DECISION: blocked by LKL dwell %.1fs" % [name, _lkl_dwell_timer])
		ChangeState("Guard")
		return

	if _silence_timer > 0.0:
		if _settings.debugEnabled:
			print("[AI:%s] DECISION: blocked by silence %.1fs" % [name, _silence_timer])
		return

	# Below COMBAT awareness: investigate, don't fight
	if _settings.awarenessEnabled and is_instance_valid(_awareness) and not boss:
		if _awareness.level < AwarenessSystem.AwarenessLevel.COMBAT:
			if _awareness._combat_memory:
				# Search behavior respects personality
				var aggressive = _personality in [Personality.BERSERKER, Personality.OPERATOR]
				var passive = _personality in [Personality.COWARD, Personality.LOOKOUT]

				if _awareness._time_since_stimulus < 10.0:
					if playerVisible:
						if _settings.debugEnabled:
							print("[AI:%s] INV: fresh+vis -> Hunt" % name)
						ChangeState("Hunt")
					elif passive:
						if _settings.debugEnabled:
							print("[AI:%s] INV: fresh+passive -> Guard" % name)
						ChangeState("Guard")  # cowards/lookouts hold, don't push
					elif _awareness.last_known_position != Vector3.ZERO:
						if aggressive:
							if _settings.debugEnabled:
								print("[AI:%s] INV: fresh+aggressive -> Attack" % name)
							ChangeState("Attack")  # berserkers/operators sprint in
						else:
							if _settings.debugEnabled:
								print("[AI:%s] INV: fresh+normal -> Hunt" % name)
							ChangeState("Hunt")  # normals cautiously approach
					else:
						if _settings.debugEnabled:
							print("[AI:%s] INV: fresh+no LKL -> Guard" % name)
						ChangeState("Guard")
				elif _awareness._time_since_stimulus < 30.0:
					if playerVisible and playerDistance3D < 40.0:
						if _settings.debugEnabled:
							print("[AI:%s] INV: wary+vis -> Hunt" % name)
						ChangeState("Hunt")
					elif aggressive:
						if _settings.debugEnabled:
							print("[AI:%s] INV: wary+aggressive -> Hunt" % name)
						ChangeState("Hunt")
					else:
						if _settings.debugEnabled:
							print("[AI:%s] INV: wary -> Guard" % name)
						ChangeState("Guard")
				else:
					if aggressive:
						if _settings.debugEnabled:
							print("[AI:%s] INV: stale+aggressive -> Hunt" % name)
						ChangeState("Hunt")
					else:
						if _settings.debugEnabled:
							print("[AI:%s] INV: stale -> Guard" % name)
						ChangeState("Guard")
				return

			if _awareness.level >= AwarenessSystem.AwarenessLevel.ALERT:
				var choice = _investigate_choices_alert.pick_random()
				if _settings.debugEnabled:
					print("[AI:%s] INV: alert -> %s" % [name, choice])
				ChangeState(choice)
			elif _awareness.level >= AwarenessSystem.AwarenessLevel.SUSPICIOUS:
				if playerVisible or _awareness.awareness > 0.4:
					if _settings.debugEnabled:
						print("[AI:%s] INV: suspicious -> Guard" % name)
					ChangeState("Guard")
			return

	if boss and _boss_controller != null:
		var boss_state = _boss_controller.get_boss_decision()
		ChangeState(boss_state)
		return

	# If fully calmed down, let vanilla handle patrol/wander
	if is_instance_valid(_awareness) and _awareness.level == AwarenessSystem.AwarenessLevel.UNAWARE and not _awareness._combat_memory:
		super()
		return

	_pick_state()
	return


func _calculate_reaction_delay() -> float:
	var base_delay: float

	if boss:
		base_delay = _settings.reactionDelayBoss
	elif playerDistance3D < 20.0:
		base_delay = _settings.reactionDelayClose
	elif playerDistance3D < 50.0:
		base_delay = _settings.reactionDelayMid
	else:
		base_delay = _settings.reactionDelayFar

	if _faction_profile != null:
		base_delay *= _faction_profile.reaction_delay_mult

	var encounter_jitter = randf_range(0.85, 1.15)
	return base_delay * _reaction_jitter * encounter_jitter


func FireAccuracy() -> Vector3:
	if not _settings.weaponAccuracyEnabled:
		return super()

	var base_direction: Vector3 = super()

	if boss:
		if _boss_controller != null:
			if _boss_controller.current_phase == BossController.Phase.DESPERATE:
				var target_pos_b = playerPosition + Vector3(0, 1.5, 0)
				var offset_b = base_direction - target_pos_b
				return target_pos_b + offset_b * 1.4
			elif _boss_controller.current_phase == BossController.Phase.PROFESSIONAL:
				pass  # Fall through to normal accuracy
			else:
				return base_direction
		elif _settings.bossIgnoresWeaponPenalty:
			return base_direction

	# First shot intentionally near-misses (0.5-1.5m offset)
	if not _first_shot_fired:
		_first_shot_fired = true
		var target_pos_nm = playerPosition + Vector3(0, 1.5, 0)
		var miss_dir = Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 0.5), randf_range(-1.0, 1.0)).normalized()
		var miss_dist = randf_range(0.5, 1.5)
		if _settings.debugEnabled:
			print("[AI:%s] FIRE: near-miss offset %.1fm" % [name, miss_dist])
		return target_pos_nm + miss_dir * miss_dist

	var effective_range = _get_weapon_effective_range()

	var faction_acc = 1.0
	if _faction_profile != null and "accuracy_mult" in _faction_profile:
		faction_acc = _faction_profile.accuracy_mult

	var personality_acc = 1.0
	match _personality:
		Personality.BERSERKER:
			personality_acc = 0.8
		Personality.COWARD:
			personality_acc = 0.9
		Personality.LOOKOUT:
			personality_acc = 0.85
		Personality.SNIPER:
			personality_acc = 1.25
		Personality.OPERATOR:
			personality_acc = 1.1
		Personality.ENFORCER:
			personality_acc = 1.1

	var target_pos = playerPosition + Vector3(0, 1.5, 0)
	if not playerVisible:
		target_pos = lastKnownLocation + Vector3(0, 1.5, 0)

	var offset = base_direction - target_pos

	# LKL confidence decay: shooting without LOS gets less accurate over time.
	# Fresh LKL (<1s) is nearly precise. Stale LKL (3s+) adds significant spread.
	if not playerVisible and is_instance_valid(_awareness):
		var time_blind = _awareness._time_since_stimulus
		if time_blind > 0.5:
			var blind_spread = clampf(remap(time_blind, 0.5, 4.0, 0.3, 2.5), 0.3, 2.5)
			offset += Vector3(randf_range(-blind_spread, blind_spread), randf_range(-blind_spread * 0.3, blind_spread * 0.3), randf_range(-blind_spread, blind_spread))

	# Beyond effective range: amplify offset
	if effective_range > 0.0 and playerDistance3D > effective_range:
		var overshoot_ratio = playerDistance3D / effective_range
		var range_penalty = lerpf(1.0, _settings.beyondRangeSpreadMult, clampf((overshoot_ratio - 1.0) / 2.0, 0.0, 1.0))
		offset *= range_penalty

	# Faction + personality spread
	var total_acc = faction_acc * personality_acc
	if total_acc != 1.0:
		offset *= (1.0 / total_acc)

	# Moving accuracy penalty
	if "speed" in self and speed > 1.5:
		var move_penalty = remap(speed, 1.5, 5.0, 1.0, 1.8)
		offset *= move_penalty

	# Suppression penalty
	if _settings.suppressionEnabled and _suppression > 0.2:
		var supp_mult = remap(_suppression, 0.2, 1.0, 1.5, 3.0)
		offset *= supp_mult

	return target_pos + offset


func _get_weapon_effective_range() -> float:
	if not is_instance_valid(weaponData):
		return _settings.rifleEffectiveRange

	match _cached_weapon_action:
		"Semi":
			return _settings.pistolEffectiveRange
		"Semi-Auto":
			return _settings.rifleEffectiveRange
		"Pump":
			return _settings.shotgunEffectiveRange
		"Bolt":
			return 150.0
		"Manual":
			return _settings.shotgunEffectiveRange
		_:
			return _settings.rifleEffectiveRange


func WeaponDamage(hitbox: String, damage: float):
	super(hitbox, damage)

	# Damage reaction flag — drives "scramble for cover" in Decision()
	_took_damage_recently = true
	_damage_react_timer = 2.0
	if _settings.debugEnabled:
		print("[AI:%s] DAMAGE: %s %.0f hp=%d" % [name, hitbox, damage, health])

	if boss and _boss_controller != null and not dead:
		_boss_controller.update_phase()

	if not _settings.staggerEnabled:
		return
	if dead:
		return
	if _stagger_cooldown_timer > 0.0:
		return

	_is_staggered = true
	if hitbox == "Head":
		_stagger_timer = _settings.headStaggerDuration
	else:
		_stagger_timer = _settings.staggerDuration

	_stagger_cooldown_timer = _settings.staggerCooldown

	if is_instance_valid(_awareness):
		_awareness.awareness = 1.0
		_awareness.level = AwarenessSystem.AwarenessLevel.COMBAT

	if _personality == Personality.SNIPER:
		_sniper_compromised = true
		if _settings.debugEnabled:
			print("[AI:%s] SNIPER: compromised by damage" % name)


func Fire(delta):
	if _settings.staggerEnabled and _is_staggered:
		if _settings.debugEnabled:
			print("[AI:%s] FIRE: blocked by stagger" % name)
		return
	# Don't fire at stale LKL (except suppressive fire)
	if not playerVisible and not _suppressive_fire and "playerPosition" in self:
		if lastKnownLocation.distance_to(playerPosition) > 4.0:
			if _settings.debugEnabled:
				print("[AI:%s] FIRE: stale LKL blocked (%.0fm from player)" % [name, lastKnownLocation.distance_to(playerPosition)])
			return
	super(delta)
	# Alert nearby AI on gunfire
	if _initialized and _fire_alert_cooldown <= 0.0:
		_fire_alert_cooldown = 2.0
		_alert_nearby("propagate_gunfire", [self])

	# Sniper: count shots from position, compromise after threshold
	if _personality == Personality.SNIPER and _initialized:
		if _sniper_pos_anchor == Vector3.ZERO:
			_sniper_pos_anchor = global_position
		if global_position.distance_to(_sniper_pos_anchor) < 5.0:
			_sniper_shots_from_pos += 1
			if _sniper_shots_from_pos >= _sniper_max_shots:
				_sniper_compromised = true
				if _settings.debugEnabled:
					print("[AI:%s] SNIPER: compromised after %d shots" % [name, _sniper_shots_from_pos])



func _determine_faction_profile():
	var faction_name = _get_faction_name()
	if faction_name in _faction_profiles:
		_faction_profile = _faction_profiles[faction_name]


func _get_faction_name() -> String:
	if has_meta("enemy_ai_faction"):
		return str(get_meta("enemy_ai_faction"))
	if boss:
		return "Punisher"
	if AISpawner != null and "zone" in AISpawner:
		match AISpawner.zone:
			0: return "Bandit"
			1: return "Guard"
			2: return "Military"
	return "Bandit"


func _pick_state():
	var hp_pct = health / 100.0
	var covered = _has_cover()
	var pn_arr = ["Norm", "Cow", "Bers", "Look", "Enf", "Op", "Snip"]
	var pn = pn_arr[_personality] if _personality < pn_arr.size() else "?"

	var flee_threshold = 0.3
	match _personality:
		Personality.COWARD: flee_threshold = 0.4
		Personality.BERSERKER: flee_threshold = 0.0

	if hp_pct < flee_threshold:
		if _settings.debugEnabled:
			print("[AI:%s] DECIDE: hp %.0f%% < flee %.0f%% -> Hide" % [name, hp_pct * 100, flee_threshold * 100])
		ChangeState("Hide")
		return

	if _personality == Personality.SNIPER and _sniper_compromised:
		_sniper_compromised = false
		_sniper_shots_from_pos = 0
		_sniper_pos_anchor = Vector3.ZERO
		if _settings.debugEnabled:
			print("[AI:%s] DECIDE: sniper compromised -> Vantage" % name)
		ChangeState("Vantage")
		return

	if _took_damage_recently and not covered:
		if _personality == Personality.BERSERKER:
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: damage+berserker -> Attack" % name)
			ChangeState("Attack")
		elif _has_nearby_cover():
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: damage+no cover+nearby -> Cover" % name)
			ChangeState("Cover")
		else:
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: damage+no cover -> Defend" % name)
			ChangeState("Defend")  # no cover, shoot back
		return

	if _suppression > 0.6 and _personality != Personality.BERSERKER:
		if _suppression > 0.8 and _has_nearby_cover():
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: supp %.0f%% high -> Hide" % [name, _suppression * 100])
			ChangeState("Hide")
		elif _has_nearby_cover():
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: supp %.0f%% -> Cover" % [name, _suppression * 100])
			ChangeState("Cover")
		else:
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: supp %.0f%% no cover -> Defend" % [name, _suppression * 100])
			ChangeState("Defend")  # pinned but nowhere to go, keep shooting
		return

	if _above_player():
		if playerVisible:
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: above+vis -> Defend" % name)
			ChangeState("Defend")
		elif currentState == State.Vantage:
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: above+vantage -> Guard" % name)
			ChangeState("Guard")
		else:
			if _settings.debugEnabled:
				print("[AI:%s] DECIDE: above -> Vantage" % name)
			ChangeState("Vantage")
		return

	if playerVisible:
		match _personality:
			Personality.LOOKOUT:
				if playerDistance3D < 20.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis close -> Cover" % [name, pn])
					ChangeState("Cover")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis far -> Defend" % [name, pn])
					ChangeState("Defend")
			Personality.ENFORCER:
				if _settings.debugEnabled:
					print("[AI:%s] DECIDE: %s vis -> Defend" % [name, pn])
				ChangeState("Defend")
			Personality.SNIPER:
				if playerDistance3D < 15.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis close -> Cover" % [name, pn])
					ChangeState("Cover")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis far -> Defend" % [name, pn])
					ChangeState("Defend")
			Personality.BERSERKER:
				if playerDistance3D > 30.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis far -> Shift" % [name, pn])
					ChangeState("Shift")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis close -> Defend" % [name, pn])
					ChangeState("Defend")
			Personality.OPERATOR:
				if playerDistance3D > 40.0 and _suppression < 0.3:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis far -> Shift" % [name, pn])
					ChangeState("Shift")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis -> Defend" % [name, pn])
					ChangeState("Defend")
			Personality.COWARD:
				if covered:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: Cow vis+covered -> Defend" % name)
					ChangeState("Defend")
				elif _has_nearby_cover():
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: Cow vis exposed -> Cover" % name)
					ChangeState("Cover")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: Cow vis no cover -> Defend" % name)
					ChangeState("Defend")
			_:
				if covered:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis+covered -> Defend" % [name, pn])
					ChangeState("Defend")
				elif playerDistance3D > 40.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis far -> Vantage" % [name, pn])
					ChangeState("Vantage")
				elif _has_nearby_cover():
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis+nearby cover -> Cover" % [name, pn])
					ChangeState("Cover")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s vis no cover -> Defend" % [name, pn])
					ChangeState("Defend")  # no cover nearby, stand and fight
		return

	if is_instance_valid(_awareness) and _awareness.level >= AwarenessSystem.AwarenessLevel.COMBAT:
		if _los_lost_timer < 3.0:
			return

		match _personality:
			Personality.BERSERKER:
				if _settings.debugEnabled:
					print("[AI:%s] DECIDE: %s LOS lost -> Attack" % [name, pn])
				ChangeState("Attack")
			Personality.COWARD, Personality.ENFORCER:
				if _settings.debugEnabled:
					print("[AI:%s] DECIDE: %s LOS lost -> Guard" % [name, pn])
				ChangeState("Guard")
			Personality.OPERATOR:
				if playerDistance3D > 30.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s LOS lost far -> Shift" % [name, pn])
					ChangeState("Shift")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s LOS lost close -> Hunt" % [name, pn])
					ChangeState("Hunt")
			Personality.SNIPER:
				if _settings.debugEnabled:
					print("[AI:%s] DECIDE: %s LOS lost -> Vantage" % [name, pn])
				ChangeState("Vantage")
			_:
				if playerDistance3D < 15.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s LOS lost close -> Attack" % [name, pn])
					ChangeState("Attack")
				elif playerDistance3D > 30.0:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s LOS lost far -> Guard" % [name, pn])
					ChangeState("Guard")
				else:
					if _settings.debugEnabled:
						print("[AI:%s] DECIDE: %s LOS lost mid -> Hunt" % [name, pn])
					ChangeState("Hunt")
		return

	if _settings.debugEnabled:
		print("[AI:%s] DECIDE: fallback -> Guard" % name)
	ChangeState("Guard")


func _has_cover() -> bool:
	if _cover_cd > 0.0:
		return _cover_cached
	_cover_cd = 1.5

	if _above_player():
		_cover_cached = true
		return true

	var cover_points = get_tree().get_nodes_in_group("AI_CP")
	for pt in cover_points:
		if is_instance_valid(pt) and pt.global_position.distance_to(global_position) < 4.0:
			_cover_cached = true
			return true

	_cover_cached = false
	return false


func _has_nearby_cover() -> bool:
	# any cover/hide points within 30m?
	for group in ["AI_CP", "AI_HP"]:
		for pt in get_tree().get_nodes_in_group(group):
			if is_instance_valid(pt) and pt.global_position.distance_to(global_position) < 30.0:
				return true
	return false


func Sensor(delta):
	super(delta)

	# Skip awareness processing for very distant AI
	var skip_distance = 250.0 if not _perf_is_sniper else 350.0
	if playerDistance3D > skip_distance:
		if not is_instance_valid(_awareness) or not _awareness._combat_memory:
			return

	# weather visibility (must run before awareness update)
	if _settings.nightPenaltyEnabled and playerVisible:
		var vis_range = _get_visibility_distance()
		if playerDistance3D > vis_range:
			if _settings.debugEnabled:
				print("[AI:%s] VIS_BLOCKED: dist %.0fm > vis range %.0fm" % [name, playerDistance3D, vis_range])
			playerVisible = false

	if _settings.awarenessEnabled and is_instance_valid(_awareness):
		var player_heard: bool = false

		if _has_playerHeard and get("playerHeard") == true:
			player_heard = true
		elif _has_playerWasHeard and get("playerWasHeard") == true:
			player_heard = true

		if not player_heard and _has_fireDetected and get("fireDetected") == true:
			player_heard = true

		# Hearing multiplier based on awareness level
		var hear_mult = 1.0
		if _awareness._combat_memory:
			hear_mult = 2.5
		elif _awareness.level >= AwarenessSystem.AwarenessLevel.ALERT:
			hear_mult = 2.0
		elif _awareness.level >= AwarenessSystem.AwarenessLevel.SUSPICIOUS:
			hear_mult = 1.5

		if gameData != null:
			if "isFiring" in gameData and gameData.isFiring and playerDistance3D < 150.0 * hear_mult:
				player_heard = true

			if not player_heard:
				var hear_range = _get_hearing_distance() * hear_mult
				if hear_range > 0.0 and playerDistance3D < hear_range:
					player_heard = true

		var prox_range = 3.0
		if _awareness._combat_memory:
			prox_range = 5.0
		if playerDistance3D < prox_range:
			player_heard = true

		var taking_fire: bool = _has_takingFire and get("takingFire") == true

		if player_heard and gameData != null and "playerPosition" in gameData:
			_awareness.last_known_position = gameData.playerPosition

		var gain_mult = 1.0
		if _faction_profile != null and "awareness_gain_mult" in _faction_profile:
			gain_mult = _faction_profile.awareness_gain_mult
		if _personality == Personality.LOOKOUT:
			gain_mult *= 1.5
		elif _personality == Personality.SNIPER:
			gain_mult *= 1.3
		_awareness.update(delta, playerVisible, playerDistance3D, player_heard, taking_fire, gain_mult)

		if _settings.debugEnabled and _awareness.awareness > 0.0 and _prev_awareness == 0.0 and playerDistance3D > 1.0:
			print("[AI:%s] DETECTED: first awareness gain at %.0fm vis=%s heard=%s" % [
				name, playerDistance3D, playerVisible, player_heard])
		_prev_awareness = _awareness.awareness

		# Awareness-driven behavior
		if _awareness.last_known_position != Vector3.ZERO:
			lastKnownLocation = _awareness.last_known_position

		match _awareness.level:
			AwarenessSystem.AwarenessLevel.SUSPICIOUS:
				pass

			AwarenessSystem.AwarenessLevel.ALERT:
				if currentState in _passive_states:
					if _settings.debugEnabled:
						print("[AI:%s] ALERT: passive -> Hunt" % name)
					ChangeState("Hunt")

			AwarenessSystem.AwarenessLevel.COMBAT:
				if not _has_reacted and not _is_reacting:
					_is_reacting = true
					_delaying_decision = true
					_reaction_target = _calculate_reaction_delay()
					_reaction_timer = 0.0
					_alert_nearby("propagate_combat_alert", [self, playerPosition])
					if has_method("PlayCombat"):
						call("PlayCombat")
					if _settings.debugEnabled:
						print("[AIOverhaul] Awareness→COMBAT: reaction delay=%.2fs dist=%.0fm" % [
							_reaction_target, playerDistance3D
						])

			_:  # UNAWARE
				if not _is_reacting:
					_delaying_decision = false




func _get_predicted_position() -> Vector3:
	var base_pos = _awareness.last_known_position
	if base_pos == Vector3.ZERO:
		return base_pos

	if _predicted_velocity.length() < 0.5:
		var noise = Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		return base_pos + noise

	# 30% chance of bad guess — go wrong direction entirely
	var dir = _predicted_velocity.normalized()
	if randf() < 0.3:
		dir = dir.rotated(Vector3.UP, randf_range(-PI * 0.6, PI * 0.6))

	var predict_time = randf_range(1.5, 3.5)
	var predicted = base_pos + dir * predict_time * 4.0

	var noise = Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
	predicted += noise

	if _settings.debugEnabled:
		print("[AIOverhaul] Predicted pursuit: LKL+(%.0f,%.0f) vel=(%.1f,%.1f)" % [
			predicted.x - base_pos.x, predicted.z - base_pos.z,
			_predicted_velocity.x, _predicted_velocity.z
		])

	return predicted



func _generate_search_point(origin: Vector3) -> Vector3:
	var player_dir = Vector3.ZERO
	if gameData != null and "playerVector" in gameData:
		player_dir = gameData.playerVector.normalized()

	if not _cached_waypoints_valid:
		_cached_waypoints.clear()
		for group_name in ["AI_WP", "AI_CP", "AI_PP"]:
			_cached_waypoints.append_array(get_tree().get_nodes_in_group(group_name))
		_cached_waypoints_valid = true

	var best_point: Vector3 = Vector3.ZERO
	var best_score: float = -999.0

	for pt in _cached_waypoints:
		if not is_instance_valid(pt):
			continue
		var dist_from_origin = pt.global_position.distance_to(origin)
		var dist_from_self = pt.global_position.distance_to(global_position)

		if dist_from_origin < _search_radius and dist_from_origin > 5.0 and dist_from_self > 8.0:
			var score = 0.0
			if player_dir != Vector3.ZERO:
				var dir_to_point = (pt.global_position - origin).normalized()
				var alignment = dir_to_point.dot(player_dir)
				score = alignment * 10.0
			score += randf_range(-3.0, 3.0)
			score -= dist_from_origin * 0.1

			if score > best_score:
				best_score = score
				best_point = pt.global_position

	if best_point != Vector3.ZERO:
		return best_point

	# Fallback: geometric point
	var base_angle: float
	if player_dir != Vector3.ZERO:
		base_angle = atan2(player_dir.x, player_dir.z)
	else:
		base_angle = randf() * TAU

	var cone_offset = randf_range(-0.8, 0.8)
	var angle = base_angle + cone_offset
	var radius = randf_range(10.0, _search_radius)
	return origin + Vector3(sin(angle) * radius, 0, cos(angle) * radius)



func Death(direction, force):
	if _initialized and not dead:
		_propagate_death_morale()
	super(direction, force)


func _propagate_death_morale():
	if AISpawner == null or not is_instance_valid(AISpawner):
		return
	var alert_node = AISpawner.get_node_or_null("AlertPropagation")
	if alert_node != null and alert_node.has_method("propagate_ally_death"):
		alert_node.propagate_ally_death(self)



func _check_suppression():
	if gameData == null or not "cameraPosition" in gameData:
		return
	if not "playerVector" in gameData:
		return

	var ray_origin: Vector3 = gameData.cameraPosition
	var ray_dir: Vector3 = gameData.playerVector.normalized()
	var ray_end: Vector3 = ray_origin + ray_dir * 200.0
	var ab = ray_end - ray_origin
	var ap = global_position - ray_origin
	var t = clampf(ap.dot(ab) / ab.dot(ab), 0.0, 1.0)
	var closest = ray_origin + ab * t
	var dist = global_position.distance_to(closest)

	if dist < SUPPRESSION_RADIUS:
		var amount = 0.08 * (1.0 - dist / SUPPRESSION_RADIUS)
		_suppression = minf(1.0, _suppression + amount)

		if is_instance_valid(_awareness):
			_awareness.awareness = clampf(_awareness.awareness + amount * 2.0, 0.0, 1.0)
			_awareness._combat_memory = true



static var _vegetation_positions: Array = []
static var _vegetation_scanned: bool = false


func _scan_vegetation_once():
	if _vegetation_scanned:
		return
	_vegetation_scanned = true
	_vegetation_positions.clear()
	var world = get_node_or_null("/root/Map/World")
	if world == null:
		world = get_tree().current_scene
	if world == null:
		return
	var start_ms = Time.get_ticks_msec()
	var mmis = world.find_children("*", "MultiMeshInstance3D", true, false)
	for mmi in mmis:
		if is_instance_valid(mmi):
			_vegetation_positions.append(mmi.global_position)
	var elapsed = Time.get_ticks_msec() - start_ms
	if _settings.debugEnabled:
		print("[AIOverhaul] Vegetation scan: %d positions in %dms" % [_vegetation_positions.size(), elapsed])


func _player_near_vegetation() -> float:
	if _vegetation_positions.is_empty():
		return 0.0
	if gameData == null or not "playerPosition" in gameData:
		return 0.0

	var player_pos = gameData.playerPosition
	var best_concealment = 0.0
	for veg_pos in _vegetation_positions:
		var dx = player_pos.x - veg_pos.x
		var dz = player_pos.z - veg_pos.z
		var dist_sq = dx * dx + dz * dz
		if dist_sq < 100.0:
			var dist = sqrt(dist_sq)
			var bonus = 0.4 * (1.0 - dist / 10.0)
			if bonus > best_concealment:
				best_concealment = bonus
				if best_concealment >= 0.3:
					break
	return best_concealment


func _apply_foliage_concealment():
	if not playerVisible:
		return
	if gameData == null:
		return

	if is_instance_valid(_awareness) and _awareness._combat_memory:
		return

	if _above_player():
		return

	if not _vegetation_scanned:
		_scan_vegetation_once()

	var is_crouching = "isCrouching" in gameData and gameData.isCrouching
	var is_moving = "isMoving" in gameData and gameData.isMoving

	var conceal_base: float = 0.0
	if is_crouching:
		if not is_moving:
			conceal_base = remap(playerDistance3D, 30.0, 120.0, 0.0, 0.5)
		else:
			conceal_base = remap(playerDistance3D, 40.0, 120.0, 0.0, 0.3)
		conceal_base = clampf(conceal_base, 0.0, 0.5)

	var veg_bonus = _player_near_vegetation()
	if veg_bonus > 0.0:
		if is_crouching:
			conceal_base += veg_bonus
		else:
			conceal_base += veg_bonus * 0.3

	conceal_base = clampf(conceal_base, 0.0, 0.7)

	if conceal_base > 0.0 and randf() < conceal_base:
		playerVisible = false


func _alert_nearby(method: String, args: Array = []):
	if not _initialized or dead:
		return
	if AISpawner == null or not is_instance_valid(AISpawner):
		return
	var node = AISpawner.get_node_or_null("AlertPropagation")
	if node != null and node.has_method(method):
		node.callv(method, args)




func _get_world_node() -> Node:
	if _world_cached and is_instance_valid(_world_node):
		return _world_node
	_world_cached = true
	_world_node = get_node_or_null("/root/Map/World")
	return _world_node


func _get_visibility_distance() -> float:
	if gameData == null:
		return 200.0

	var world = _get_world_node()

	var ground_light: float = 5.0
	if world != null and "skyMaterial" in world and world.skyMaterial != null:
		var ground_color = world.skyMaterial.get_shader_parameter("groundColor")
		if ground_color is Color:
			ground_light = 10.0 * (ground_color.r + ground_color.g + ground_color.b) / 3.0

	var fog_val: float = 1.0
	if world != null and "fogValue" in world:
		fog_val = maxf(world.fogValue, 1.0)

	var overcast: float = 0.0
	if world != null and "overcastValue" in world:
		overcast = clampf(world.overcastValue, 0.0, 1.0)

	var visibility = (1.0 + ground_light / 1.5) * (4.0 / (fog_val + 3.0)) * (1.0 - 0.25 * overcast) * 50.0
	var weather_base = visibility

	if "indoor" in gameData and gameData.indoor:
		visibility -= 0.2 * weather_base

	var is_running = "isRunning" in gameData and gameData.isRunning
	var is_moving = "isMoving" in gameData and gameData.isMoving
	var is_crouching = "isCrouching" in gameData and gameData.isCrouching

	if is_running:
		visibility += 0.2 * weather_base
	elif is_moving and not is_crouching:
		visibility += 0.1 * weather_base
	elif is_moving and is_crouching:
		visibility -= 0.1 * weather_base
	elif not is_moving and is_crouching:
		visibility -= 0.2 * weather_base

	if "flashlight" in gameData and gameData.flashlight:
		if "TOD" in gameData and gameData.TOD == 4:
			visibility += 30.0
		elif visibility < 100.0:
			visibility += 20.0

	if boss:
		visibility = maxf(visibility, 60.0)

	return maxf(visibility, 0.0)



func _get_hearing_distance() -> float:
	if gameData == null:
		return 0.0

	var hearing: float = 0.0

	var is_running = "isRunning" in gameData and gameData.isRunning
	var is_landing = "land" in gameData and gameData.land
	var is_crouching = "isCrouching" in gameData and gameData.isCrouching
	var is_moving = "isMoving" in gameData and gameData.isMoving

	if is_running or is_landing:
		hearing = 20.0
	elif is_crouching and is_moving:
		hearing = 3.0
	elif is_moving:
		hearing = 6.0

	if "surface" in gameData:
		var surface = str(gameData.surface)
		if surface == "Metal":
			hearing *= 1.7
		elif surface == "Wood":
			hearing *= 1.35
	if "overweight" in gameData and gameData.overweight:
		hearing *= 1.35

	if hearing < 10.0:
		var noisy = false
		for prop in _hearing_interaction_props:
			if prop in gameData and gameData.get(prop) == true:
				noisy = true
				break
		if noisy:
			hearing = 10.0

	var world = _get_world_node()
	var is_indoor = "indoor" in gameData and gameData.indoor
	if not is_indoor and world != null and "wind" in world and world.wind:
		hearing *= 0.7

	return hearing



func _setup_debug_label():
	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.position = Vector3(0, 2.5, 0)
	_debug_label.font_size = 24
	_debug_label.pixel_size = 0.01
	_debug_label.modulate = Color.WHITE
	_debug_label.outline_size = 8
	add_child(_debug_label)
	if _settings.debugEnabled:
		print("[AIOverhaul] Label at (%d,%d,%d)" % [
		int(global_position.x), int(global_position.y), int(global_position.z)
	])


static var _state_names: Array = ["Idle", "Wander", "Guard", "Patrol", "Hide", "Ambush",
	"Cover", "Defend", "Shift", "Combat", "Hunt", "Attack", "Vantage", "Return"]


func _update_debug_label():
	if not is_instance_valid(_debug_label):
		return

	var text = ""

	if _settings.debugFaction and _faction_profile != null:
		var pers_tags = ["", " (Coward)", " (Berserker)", " (Lookout)", " (Enforcer)", " (Operator)", " (Sniper)"]
		var personality_tag = pers_tags[_personality] if _personality < pers_tags.size() else ""
		text += "[%s%s]\n" % [_faction_profile.faction_name, personality_tag]

	var state_name = _state_names[currentState] if currentState >= 0 and currentState < _state_names.size() else "?"
	text += "State: %s\n" % state_name

	if _settings.debugAwareness and is_instance_valid(_awareness):
		var phase_name = _awareness.get_phase_name()
		text += "Aware: %.0f%% [%s]\n" % [_awareness.awareness * 100.0, phase_name]
		if _awareness._combat_memory and _awareness.level < AwarenessSystem.AwarenessLevel.COMBAT:
			text += ">> %s (%.0fs)\n" % [phase_name, _awareness._time_since_stimulus]

	if _settings.debugReactionDelay and _is_reacting:
		text += "REACTING: %.1f/%.1f\n" % [_reaction_timer, _reaction_target]

	if boss and _boss_controller != null:
		text += "%s\n" % _boss_controller.get_phase_name()

	if _search_active:
		text += "SEARCH %d/%d\n" % [_search_points_checked + 1, _search_max_points]

	if _suppression > 0.1:
		text += "SUPP: %.0f%%\n" % (_suppression * 100.0)

	if _personality == Personality.SNIPER and _sniper_shots_from_pos > 0:
		text += "SHOTS: %d/%d%s\n" % [_sniper_shots_from_pos, _sniper_max_shots,
			" COMPROMISED" if _sniper_compromised else ""]

	if _predicted_pos_set:
		text += "PREDICTING\n"

	if not _first_shot_fired and is_instance_valid(_awareness) and _awareness.level >= AwarenessSystem.AwarenessLevel.COMBAT:
		text += "NEAR-MISS RDY\n"

	var speed_labels = ["", "CAUTIOUS", "SPRINT", "CREEP"]
	if _speed_mode > 0 and _speed_mode < speed_labels.size():
		text += "%s\n" % speed_labels[_speed_mode]

	if _settings.debugStagger and _is_staggered:
		text += "STAGGER: %.1f\n" % _stagger_timer

	text += "HP: %d" % health

	if text != _debug_cached_text:
		_debug_label.text = text
		_debug_cached_text = text

	var new_color: Color
	if is_instance_valid(_awareness):
		match _awareness.level:
			AwarenessSystem.AwarenessLevel.COMBAT: new_color = Color.RED
			AwarenessSystem.AwarenessLevel.ALERT: new_color = Color.ORANGE
			AwarenessSystem.AwarenessLevel.SUSPICIOUS: new_color = Color.YELLOW
			_: new_color = Color.GREEN if not _is_staggered else Color.MAGENTA
	else:
		if _is_staggered: new_color = Color.YELLOW
		elif _is_reacting: new_color = Color.ORANGE
		elif currentState in [State.Combat, State.Attack, State.Hunt, State.Shift]: new_color = Color.RED
		else: new_color = Color.WHITE

	if new_color != _debug_cached_color:
		_debug_label.modulate = new_color
		_debug_cached_color = new_color
