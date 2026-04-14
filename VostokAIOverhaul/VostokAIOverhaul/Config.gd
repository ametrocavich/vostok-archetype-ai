extends Node

var settings = preload("res://VostokAIOverhaul/Settings.tres")
var config = ConfigFile.new()

const FILE_PATH = "user://MCM/AIOverhaul"
const MOD_ID = "AIOverhaul"

func _ready() -> void:

	config.set_value("Bool", "reactionDelayEnabled", {
		"name" = "Reaction Delay",
		"tooltip" = "Brief pause before AI fires after spotting you (range-based)",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "awarenessEnabled", {
		"name" = "Graduated Awareness",
		"tooltip" = "Awareness builds gradually (0-1 float) instead of instant detection",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "factionEnabled", {
		"name" = "Faction Behavior",
		"tooltip" = "Per-faction combat weights and personality traits",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "staggerEnabled", {
		"name" = "Hit Stagger",
		"tooltip" = "AI briefly stops firing when hit",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "suppressionEnabled", {
		"name" = "Suppression",
		"tooltip" = "Near-miss fire degrades AI accuracy and forces cover",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "foliageConcealment", {
		"name" = "Crouch Concealment",
		"tooltip" = "Crouching at distance reduces detection chance",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "nightPenaltyEnabled", {
		"name" = "Night Penalty",
		"tooltip" = "Reduced AI detection at night without flashlight",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "bossPhaseEnabled", {
		"name" = "Boss Phases",
		"tooltip" = "Punisher 3-phase system: Professional, Commander, Desperate",
		"default" = true,
		"value" = true
	})
	config.set_value("Bool", "pacingEnabled", {
		"name" = "Spawn Pacing",
		"tooltip" = "Modulates spawn rate based on combat intensity",
		"default" = true,
		"value" = true
	})

	config.set_value("Int", "aiCountMultiplier", {
		"name" = "AI Count Multiplier",
		"tooltip" = "1 = vanilla, 2 = double. Requires map transition.",
		"default" = 1,
		"value" = 1,
		"minRange" = 1,
		"maxRange" = 5
	})
	config.set_value("Float", "reactionDelayClose", {
		"name" = "Reaction Delay - Close (<20m)",
		"tooltip" = "Seconds before AI fires at close range",
		"default" = 0.2,
		"value" = 0.2,
		"minRange" = 0.0,
		"maxRange" = 2.0
	})
	config.set_value("Float", "reactionDelayMid", {
		"name" = "Reaction Delay - Mid (20-50m)",
		"tooltip" = "Seconds before AI fires at mid range",
		"default" = 0.5,
		"value" = 0.5,
		"minRange" = 0.0,
		"maxRange" = 3.0
	})
	config.set_value("Float", "reactionDelayFar", {
		"name" = "Reaction Delay - Far (>50m)",
		"tooltip" = "Seconds before AI fires at far range",
		"default" = 1.0,
		"value" = 1.0,
		"minRange" = 0.0,
		"maxRange" = 3.0
	})
	config.set_value("Float", "staggerDuration", {
		"name" = "Stagger - Body Duration",
		"tooltip" = "Seconds AI pauses after body hit",
		"default" = 0.4,
		"value" = 0.4,
		"minRange" = 0.1,
		"maxRange" = 1.5
	})
	config.set_value("Float", "headStaggerDuration", {
		"name" = "Stagger - Head Duration",
		"tooltip" = "Seconds AI pauses after headshot",
		"default" = 0.8,
		"value" = 0.8,
		"minRange" = 0.2,
		"maxRange" = 2.0
	})
	config.set_value("Bool", "debugEnabled", {
		"name" = "Debug Overlay",
		"tooltip" = "Awareness/state/faction labels above AI + debug hotkeys",
		"default" = false,
		"value" = false
	})
	config.set_value("Keycode", "keySpawnAI", {
		"name" = "Debug Key - Spawn AI",
		"tooltip" = "Spawn AI 15m ahead (debug only)",
		"default" = KEY_F9,
		"value" = KEY_F9
	})
	config.set_value("Keycode", "keyGodMode", {
		"name" = "Debug Key - God Mode",
		"tooltip" = "Toggle invulnerability",
		"default" = KEY_F10,
		"value" = KEY_F10
	})
	config.set_value("Keycode", "keyHeal", {
		"name" = "Debug Key - Heal",
		"tooltip" = "Restore health to 100",
		"default" = KEY_F11,
		"value" = KEY_F11
	})
	config.set_value("Keycode", "keySpawnBoss", {
		"name" = "Debug Key - Spawn Boss",
		"tooltip" = "Spawn Punisher 30m ahead (debug only)",
		"default" = KEY_F8,
		"value" = KEY_F8
	})

	var McmHelpers = _try_load_mcm()
	if McmHelpers != null:
		if !FileAccess.file_exists(FILE_PATH + "/config.ini"):
			DirAccess.open("user://").make_dir_recursive(FILE_PATH)
			config.save(FILE_PATH + "/config.ini")
		else:
			McmHelpers.CheckConfigurationHasUpdated(MOD_ID, config, FILE_PATH + "/config.ini")
			config.load(FILE_PATH + "/config.ini")

		_on_config_updated(config)

		McmHelpers.RegisterConfiguration(
			MOD_ID,
			"AI Overhaul",
			FILE_PATH,
			"AI Overhaul — Smarter, fairer, more intense",
			{
				"config.ini" = _on_config_updated
			}
		)
	else:
		if OS.is_debug_build():
			print("[AIOverhaul] MCM not found, using defaults")


func _try_load_mcm():
	if ResourceLoader.exists("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres"):
		return load("res://ModConfigurationMenu/Scripts/Doink Oink/MCM_Helpers.tres")
	return null


func _on_config_updated(_config: ConfigFile):
	settings.reactionDelayEnabled = _config.get_value("Bool", "reactionDelayEnabled")["value"]
	settings.awarenessEnabled = _config.get_value("Bool", "awarenessEnabled")["value"]
	settings.factionEnabled = _config.get_value("Bool", "factionEnabled")["value"]
	settings.staggerEnabled = _config.get_value("Bool", "staggerEnabled")["value"]
	settings.suppressionEnabled = _config.get_value("Bool", "suppressionEnabled")["value"]
	settings.foliageConcealment = _config.get_value("Bool", "foliageConcealment")["value"]
	settings.nightPenaltyEnabled = _config.get_value("Bool", "nightPenaltyEnabled")["value"]
	settings.bossPhaseEnabled = _config.get_value("Bool", "bossPhaseEnabled")["value"]
	settings.pacingEnabled = _config.get_value("Bool", "pacingEnabled")["value"]

	settings.aiCountMultiplier = float(_config.get_value("Int", "aiCountMultiplier")["value"])
	settings.reactionDelayClose = _config.get_value("Float", "reactionDelayClose")["value"]
	settings.reactionDelayMid = _config.get_value("Float", "reactionDelayMid")["value"]
	settings.reactionDelayFar = _config.get_value("Float", "reactionDelayFar")["value"]
	settings.staggerDuration = _config.get_value("Float", "staggerDuration")["value"]
	settings.headStaggerDuration = _config.get_value("Float", "headStaggerDuration")["value"]

	settings.debugEnabled = _config.get_value("Bool", "debugEnabled")["value"]
	settings.keySpawnAI = _config.get_value("Keycode", "keySpawnAI")["value"]
	settings.keyGodMode = _config.get_value("Keycode", "keyGodMode")["value"]
	settings.keyHeal = _config.get_value("Keycode", "keyHeal")["value"]
	settings.keySpawnBoss = _config.get_value("Keycode", "keySpawnBoss")["value"]
