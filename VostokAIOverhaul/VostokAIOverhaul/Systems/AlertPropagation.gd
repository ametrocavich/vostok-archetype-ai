extends Node

var _settings: Resource = preload("res://VostokAIOverhaul/Settings.tres")
var _spawner: Node = null
var _propagation_cooldown: float = 0.0

const PROPAGATION_COOLDOWN: float = 3.0
const ALERT_RANGE: float = 40.0
const GUNFIRE_RANGE: float = 50.0
const AWARENESS_CAP: float = 0.55


func setup(spawner: Node):
	_spawner = spawner


func _physics_process(delta):
	if _propagation_cooldown > 0.0:
		_propagation_cooldown -= delta


func propagate_combat_alert(source_ai: Node, player_position: Vector3):
	if _propagation_cooldown > 0.0:
		return
	_propagation_cooldown = PROPAGATION_COOLDOWN

	if not is_instance_valid(_spawner) or not is_instance_valid(_spawner.agents):
		return

	var source_pos = source_ai.global_position
	var faction_mult = _get_faction_mult(source_ai)

	var children = _spawner.agents.get_children()
	for child in children:
		if child == source_ai or not is_instance_valid(child):
			continue
		if child.get("dead") == true:
			continue

		var dist = source_pos.distance_to(child.global_position)
		if dist > ALERT_RANGE:
			continue

		var awareness_node = child.get_node_or_null("AwarenessSystem")
		if awareness_node == null or not "awareness" in awareness_node:
			continue

		if awareness_node.awareness >= AWARENESS_CAP:
			continue

		var boost = remap(dist, 0.0, ALERT_RANGE, 0.25, 0.05) * faction_mult
		awareness_node.awareness = minf(awareness_node.awareness + boost, AWARENESS_CAP)
		var noise = Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		awareness_node.last_known_position = player_position + noise

	if _settings.debugEnabled:
		print("[AIOverhaul] Alert propagated from (%.0f,%.0f) — faction_mult=%.1f" % [
			source_pos.x, source_pos.z, faction_mult
		])


func propagate_gunfire(source_ai: Node):
	if not is_instance_valid(_spawner) or not is_instance_valid(_spawner.agents):
		return

	var source_pos = source_ai.global_position
	var faction_mult = _get_faction_mult(source_ai)

	var children = _spawner.agents.get_children()
	for child in children:
		if child == source_ai or not is_instance_valid(child):
			continue
		if child.get("dead") == true:
			continue

		var awareness_node = child.get_node_or_null("AwarenessSystem")
		if awareness_node == null or not "awareness" in awareness_node:
			continue

		if awareness_node.awareness >= AWARENESS_CAP:
			continue

		var dist = source_pos.distance_to(child.global_position)
		if dist > GUNFIRE_RANGE:
			continue

		var boost = remap(dist, 0.0, GUNFIRE_RANGE, 0.15, 0.02) * faction_mult
		awareness_node.awareness = minf(awareness_node.awareness + boost, AWARENESS_CAP)
		var noise = Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
		awareness_node.last_known_position = source_pos + noise


func propagate_ally_death(dead_ai: Node):
	if not is_instance_valid(_spawner) or not is_instance_valid(_spawner.agents):
		return

	var death_pos = dead_ai.global_position
	var faction_mult = _get_faction_mult(dead_ai)

	var children = _spawner.agents.get_children()
	for child in children:
		if child == dead_ai or not is_instance_valid(child):
			continue
		if child.get("dead") == true:
			continue

		var dist = death_pos.distance_to(child.global_position)
		if dist > ALERT_RANGE:
			continue

		var awareness_node = child.get_node_or_null("AwarenessSystem")
		if awareness_node == null or not "awareness" in awareness_node:
			continue

		var personality = child.get("_personality")

		if personality == 1:
			# Coward: panic flee
			awareness_node.awareness = minf(awareness_node.awareness + 0.3, AWARENESS_CAP)
			awareness_node.last_known_position = death_pos
			child.ChangeState("Hide")
		elif personality == 2:
			# Berserker: rage rush toward death
			awareness_node.awareness = minf(awareness_node.awareness + 0.4, AWARENESS_CAP)
			awareness_node.last_known_position = death_pos
			child.ChangeState("Hunt")
		else:
			var boost = remap(dist, 0.0, ALERT_RANGE, 0.3, 0.1) * faction_mult
			awareness_node.awareness = minf(awareness_node.awareness + boost, AWARENESS_CAP)
			awareness_node.last_known_position = death_pos

	if _settings.debugEnabled:
		print("[AIOverhaul] Morale cascade from death at (%.0f,%.0f)" % [death_pos.x, death_pos.z])


func propagate_player_gunfire(player_pos: Vector3):
	if not is_instance_valid(_spawner) or not is_instance_valid(_spawner.agents):
		return

	var children = _spawner.agents.get_children()
	for child in children:
		if not is_instance_valid(child) or child.get("dead") == true:
			continue

		var awareness_node = child.get_node_or_null("AwarenessSystem")
		if awareness_node == null or not "awareness" in awareness_node:
			continue
		if awareness_node.awareness >= AWARENESS_CAP:
			continue

		var dist = player_pos.distance_to(child.global_position)
		if dist > GUNFIRE_RANGE:
			continue

		var boost = remap(dist, 0.0, GUNFIRE_RANGE, 0.15, 0.02)
		awareness_node.awareness = minf(awareness_node.awareness + boost, AWARENESS_CAP)
		var noise = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		awareness_node.last_known_position = player_pos + noise


func _get_faction_mult(ai_node: Node) -> float:
	var profile = ai_node.get("_faction_profile")
	if profile != null and "faction_name" in profile:
		match profile.faction_name:
			"Bandit":
				return 0.5
			"Guard":
				return 1.0
			"Military":
				return 1.5
			"Punisher":
				return 0.3
	return 0.7
