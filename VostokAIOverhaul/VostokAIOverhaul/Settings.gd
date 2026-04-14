extends Resource
class_name AIOverhaulSettings

var reactionDelayEnabled: bool = true
var reactionDelayClose: float = 0.2
var reactionDelayMid: float = 0.5
var reactionDelayFar: float = 1.0
var reactionDelayBoss: float = 0.15
var reactionResetTime: float = 5.0

var weaponAccuracyEnabled: bool = true
var pistolEffectiveRange: float = 25.0
var rifleEffectiveRange: float = 80.0
var shotgunEffectiveRange: float = 15.0
var beyondRangeSpreadMult: float = 3.0
var bossIgnoresWeaponPenalty: bool = true

var staggerEnabled: bool = true
var staggerDuration: float = 0.4
var headStaggerDuration: float = 0.8
var staggerCooldown: float = 1.5

var suppressionEnabled: bool = true

var foliageConcealment: bool = true

var factionEnabled: bool = true

var nightPenaltyEnabled: bool = true

var awarenessEnabled: bool = true
var awarenessGainSound: float = 0.15
var awarenessThresholdSuspicious: float = 0.2
var awarenessThresholdAlert: float = 0.5
var awarenessThresholdCombat: float = 0.7

var bossPhaseEnabled: bool = true
var bossPhase2Threshold: float = 0.66
var bossPhase3Threshold: float = 0.33

var aiCountMultiplier: float = 1.0

var pacingEnabled: bool = true

var debugEnabled: bool = false
var godModeActive: bool = false
var debugReactionDelay: bool = true
var debugAwareness: bool = true
var debugFaction: bool = true
var debugStagger: bool = true

var keySpawnAI: int = KEY_F9
var keyGodMode: int = KEY_F10
var keyHeal: int = KEY_F11
var keySpawnBoss: int = KEY_F8
