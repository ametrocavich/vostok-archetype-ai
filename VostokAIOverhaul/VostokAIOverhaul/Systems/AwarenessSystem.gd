extends Node

enum AwarenessLevel { UNAWARE, SUSPICIOUS, ALERT, COMBAT }

var awareness: float = 0.0
var level: AwarenessLevel = AwarenessLevel.UNAWARE
var last_known_position: Vector3 = Vector3.ZERO
var _prev_level: AwarenessLevel = AwarenessLevel.UNAWARE

var _combat_memory: bool = false
var _time_since_stimulus: float = 0.0
var _peak_awareness: float = 0.0

var settings: Resource = null


func update(delta: float, can_see: bool, distance: float, can_hear: bool, is_taking_fire: bool = false, gain_mult: float = 1.0):
	if settings == null:
		return

	var has_stimulus = can_see or can_hear or is_taking_fire

	# --- Gain ---

	if is_taking_fire:
		awareness = 1.0
		_combat_memory = true

	if can_see:
		if distance < 8.0:
			if awareness < 0.5 and settings.get("debugEnabled") == true:
				var ai_name = get_parent().name if get_parent() != null else "?"
				print("[AI:%s] CLOSE_LOCK: %.0fm, awareness forced to 100%%" % [ai_name, distance])
			awareness = 1.0
			_combat_memory = true
		elif distance < 15.0:
			awareness = maxf(awareness, 0.6)
			awareness += 3.0 * gain_mult * delta
		elif distance < 50.0:
			var gain_rate = remap(distance, 15.0, 50.0, 2.0, 0.9)
			awareness += gain_rate * gain_mult * delta
		elif distance < 100.0:
			var gain_rate = remap(distance, 50.0, 100.0, 0.9, 0.45)
			awareness += gain_rate * gain_mult * delta
		else:
			var gain_rate = remap(distance, 100.0, 200.0, 0.45, 0.14)
			gain_rate = maxf(gain_rate, 0.08)
			awareness += gain_rate * gain_mult * delta

	if can_hear:
		var sound_gain = settings.awarenessGainSound * 2.0
		awareness += sound_gain * gain_mult * delta

	# --- Stimulus tracking ---

	if has_stimulus:
		_time_since_stimulus = 0.0
		if awareness > _peak_awareness:
			_peak_awareness = awareness
	else:
		_time_since_stimulus += delta

	if level == AwarenessLevel.COMBAT:
	
	# --- Decay ---

	if not has_stimulus:
		var decay_rate: float

		if _combat_memory:
			if _time_since_stimulus < 10.0:
				decay_rate = 0.005
			elif _time_since_stimulus < 30.0:
				decay_rate = 0.012
			elif _time_since_stimulus < 60.0:
				decay_rate = 0.02
			else:
				decay_rate = 0.04
		else:
			if _time_since_stimulus < 3.0:
				decay_rate = 0.0
			elif _time_since_stimulus < 10.0:
				decay_rate = 0.02
			else:
				decay_rate = 0.04

		awareness -= decay_rate * delta

		if _combat_memory:
			var floor_val: float
			if _time_since_stimulus < 30.0:
				floor_val = settings.awarenessThresholdSuspicious
			elif _time_since_stimulus < 60.0:
				var t = (_time_since_stimulus - 30.0) / 30.0
				floor_val = lerpf(settings.awarenessThresholdSuspicious, 0.0, t)
			else:
				floor_val = 0.0
			awareness = maxf(awareness, floor_val)

	awareness = clampf(awareness, 0.0, 1.0)

	# --- Update level ---

	_prev_level = level

	if awareness >= settings.awarenessThresholdCombat:
		if level != AwarenessLevel.COMBAT:
		level = AwarenessLevel.COMBAT
		_combat_memory = true
	elif awareness >= settings.awarenessThresholdAlert:
		if level != AwarenessLevel.ALERT:
		level = AwarenessLevel.ALERT
	elif awareness >= settings.awarenessThresholdSuspicious:
		if level != AwarenessLevel.SUSPICIOUS:
		level = AwarenessLevel.SUSPICIOUS
	else:
		if level != AwarenessLevel.UNAWARE:
		level = AwarenessLevel.UNAWARE

	# Log level transitions
	if level != _prev_level and settings.get("debugEnabled") == true:
		var lvl_names = ["UNAWARE", "SUSPICIOUS", "ALERT", "COMBAT"]
		var ai_name = get_parent().name if get_parent() != null else "?"
		print("[AI:%s] AWARE: %.0f%% %s → %s" % [ai_name, awareness * 100,
			lvl_names[_prev_level] if _prev_level < 4 else "?",
			lvl_names[level] if level < 4 else "?"])

	if awareness <= 0.01 and _time_since_stimulus > 65.0:
		if _combat_memory and settings.get("debugEnabled") == true:
			var ai_name = get_parent().name if get_parent() != null else "?"
			print("[AI:%s] MEMORY_RESET: %.0fs no stimulus" % [ai_name, _time_since_stimulus])
		_combat_memory = false
		_peak_awareness = 0.0


func just_entered_level(check_level: AwarenessLevel) -> bool:
	return level == check_level and _prev_level != check_level


func get_phase_name() -> String:
	if _combat_memory and level < AwarenessLevel.COMBAT:
		if _time_since_stimulus < 8.0:
			return "CHASE"
		elif _time_since_stimulus < 20.0:
			return "WARY"
		elif _time_since_stimulus < 35.0:
			return "COOLING"
	match level:
		AwarenessLevel.COMBAT: return "COMBAT"
		AwarenessLevel.ALERT: return "ALERT"
		AwarenessLevel.SUSPICIOUS: return "NOTICE"
		_: return "NORMAL"


func reset():
	awareness = 0.0
	_peak_awareness = 0.0
	_time_since_stimulus = 0.0
	_combat_memory = false
	level = AwarenessLevel.UNAWARE
	_prev_level = AwarenessLevel.UNAWARE
