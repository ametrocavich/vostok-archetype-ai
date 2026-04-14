extends Node

func _ready():
	if ResourceLoader.exists("res://ImmersiveXP/AI.gd"):
		push_warning("[AIOverhaul] ImmersiveXP detected — AI override conflict. Both mods override AI.gd.")

	overrideScript("res://VostokAIOverhaul/Core/AI.gd")
	overrideScript("res://VostokAIOverhaul/Core/AISpawner.gd")
	overrideScript("res://VostokAIOverhaul/Core/Character.gd")

	var debug_helper = load("res://VostokAIOverhaul/Debug/DebugHelper.gd").new()
	debug_helper.name = "AIOverhaulDebug"
	get_tree().root.call_deferred("add_child", debug_helper)

	print("[AIOverhaul] Script overrides registered")
	queue_free()


func overrideScript(overrideScriptPath: String):
	var script: Script = load(overrideScriptPath)
	if script == null:
		push_warning("[AIOverhaul] Failed to load %s" % overrideScriptPath)
		return null
	script.reload()
	var parentScript = script.get_base_script()
	if parentScript == null:
		push_warning("[AIOverhaul] No base script for %s" % overrideScriptPath)
		return null
	script.take_over_path(parentScript.resource_path)
	return script
