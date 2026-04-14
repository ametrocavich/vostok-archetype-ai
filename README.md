# Archetype AI

AI overhaul for Road to Vostok. Built for the community modloader.

## The Problem

Vanilla AI has a state machine with some conditions, but the conditions are shallow and the selection within each bracket is random with roughly equal weights.

```mermaid
graph LR
    A[Timer expires\n4-10s] --> DIST{Distance > 20m?}

    DIST -->|far| FAR{Roll 1-9}
    FAR --> F1[Combat]
    FAR -->|if !noHiding| F2[Hide]
    FAR --> F3[Cover]
    FAR --> F4[Vantage]
    FAR --> F5[Defend]
    FAR -->|if visible, <100m\n& not trading| F6[Hunt / Shift]
    FAR -->|if visible, <100m\n& not trading\n& not manual wpn| F7[Attack]
    FAR -->|else| F8[Combat fallback]

    DIST -->|close| CLOSE{Roll 1-4}
    CLOSE --> C1[Combat]
    CLOSE --> C2[Defend]
    CLOSE -->|if visible\n& not trading| C3[Hunt]
    CLOSE -->|if visible\n& not trading\n& not manual wpn| C4[Attack]
    CLOSE -->|else| C5[Combat fallback]

    style FAR fill:#c44,color:#fff
    style CLOSE fill:#c44,color:#fff
```

There's a distance bracket and a visibility gate on the aggressive options, so it's not pure random. But within each bracket the roll is flat, every valid option has equal chance. Nothing considers cover, health, suppression, elevation, or what the AI was already doing. It can roll Hide in the middle of a firefight or stand in the open when cover is right there.

## What This Mod Does

Replaces the dice rolls with a condition tree. Instead of picking a random state the AI checks what's actually happening and picks the one right answer.

### Decision Tree

```mermaid
graph TD
    START([Decision]) --> FLEE{HP < 30%?}
    FLEE -->|yes| HIDE[Hide / Flee]
    FLEE -->|no| HIT{Taking damage\nwhile exposed?}
    HIT -->|yes, cover nearby| COVER1[Cover - scramble]
    HIT -->|yes, no cover| DEFEND0[Defend - shoot back]
    HIT -->|no| SUPP{Suppressed?}
    SUPP -->|heavy| COVER2[Cover or Hide]
    SUPP -->|no| ELEV{High ground?}
    ELEV -->|yes, visible| DEFEND1[Defend - hold angle]
    ELEV -->|yes, blind| VANTAGE1[Vantage - find edge]
    ELEV -->|no| VIS{Player visible?}
    VIS -->|yes, have cover| DEFEND2[Defend - shoot from cover]
    VIS -->|yes, exposed, >40m| VANTAGE2[Vantage - find position]
    VIS -->|yes, exposed, <40m| COVER3[Cover or Defend]
    VIS -->|no| LOS{LOS lost how long?}
    LOS -->|< 3s| HOLD[Hold - grace period]
    LOS -->|< 15m away| ATTACK[Attack - push]
    LOS -->|> 30m away| GUARD[Guard - hold angle]
    LOS -->|15-30m| HUNT[Hunt - cautious approach]

    style START fill:#47a,color:#fff
    style HIDE fill:#a44,color:#fff
    style COVER1 fill:#a84,color:#fff
    style COVER2 fill:#a84,color:#fff
    style COVER3 fill:#a84,color:#fff
    style DEFEND0 fill:#4a4,color:#fff
    style DEFEND1 fill:#4a4,color:#fff
    style DEFEND2 fill:#4a4,color:#fff
    style ATTACK fill:#c44,color:#fff
    style HUNT fill:#aa4,color:#000
    style GUARD fill:#48a,color:#fff
    style HOLD fill:#48a,color:#fff
    style VANTAGE1 fill:#84a,color:#fff
    style VANTAGE2 fill:#84a,color:#fff
```

Every branch has one answer for one reason. Personality shifts the thresholds (berserkers skip the flee check, cowards flee earlier, snipers always prefer vantage) but the structure is the same.

If there's no cover nearby the AI won't waste time looking for some. It stays where it is and fights. No more running in circles in an open field.

### Awareness

Vanilla detection is binary, you're either spotted or you aren't. This mod replaces it with a 0-1 float that ramps up over time. Took a lot from how MGSV handles its alert system.

```mermaid
stateDiagram-v2
    [*] --> NORMAL
    NORMAL --> NOTICE : sound / glimpse
    NOTICE --> ALERT : confirmed contact
    ALERT --> COMBAT : sustained LOS
    COMBAT --> CHASE : LOS break, 0-8s
    CHASE --> WARY : still searching, 8-20s
    WARY --> COOLING : giving up, 20-35s
    COOLING --> NORMAL : fully reset ~65s
    NOTICE --> NORMAL : no stimulus (decay)
    ALERT --> NOTICE : no stimulus (decay)
    COMBAT --> ALERT : awareness drops

    NORMAL --> COMBAT : point blank / taking fire
```

Visibility reads the actual sky shader, fog density, and overcast from the game engine. Night and fog tank detection range. Sound depends on surface type (metal is 1.7x louder than dirt), weather, and what the player is doing. Crouching on grass at 50m? They won't hear you. Sprinting on metal in a quiet building? They know exactly where you are.

### Personalities

Every AI gets a personality when it spawns. These aren't just accuracy tweaks, they change how the AI actually plays.

```mermaid
graph LR
    subgraph Bandits
        B1[Normal - 40%]
        B2[Coward - 35%]
        B3[Berserker - 25%]
    end
    subgraph Guards
        G1[Normal - 45%]
        G2[Lookout - 30%]
        G3[Enforcer - 25%]
    end
    subgraph Military
        M1[Normal - 50%]
        M2[Sniper - 25%]
        M3[Operator - 25%]
    end
```

| Archetype | Sees player | Loses LOS | Key trait |
|-----------|------------|-----------|-----------|
| **Coward** | Same as Normal | Guard (won't push) | Flees at 40% HP |
| **Berserker** | Shift >30m, Defend <30m | Attack (sprints to you) | Never flees, charges when hit |
| **Sniper** | Cover <15m, Defend >15m | Vantage (new position) | Relocates after 3-5 shots |
| **Operator** | Shift >40m, Defend <40m | Shift >30m, Hunt <30m | Pushes through low suppression |
| **Enforcer** | Defend (always) | Guard (always) | Never advances, never retreats |
| **Lookout** | Cover <20m, Defend >20m | Guard (won't push) | 1.5x awareness gain speed |
| **Normal** | Defend if covered, else Cover/Vantage | Attack <15m, Guard >30m, Hunt mid | Balanced, cover-aware |

### Combat Memory

Vanilla forgets you in seconds. This mod keeps combat memory for over a minute. When you break LOS the AI extrapolates your movement direction and tries to cut you off (took this from FEAR's approach to position evaluation). 30% of the time they guess wrong so it doesn't feel like wallhacks.

Personality matters here too. Berserkers sprint to your last position. Cowards hold where they are. Normal AI cautiously hunts. Search uses existing map waypoints biased in your movement direction.

### Other Stuff

**Suppression** - bullets passing near AI build suppression pressure (point-to-line math, no physics queries). Pinned AI lose accuracy and seek cover, heavy suppression causes panic.

**Alert propagation** - one AI entering combat boosts nearby AI to alert, not combat. They investigate on their own instead of everyone dogpiling you. 40-50m range, military gets a stronger awareness boost than bandits.

**First-shot near-miss** - first round after detection misses close on purpose. Gives you that half-second of "where was that" before the shooting starts. Took this from how Halo handles first contact.

**Boss phases** - Punisher bosses go from tactical to calling reinforcements to full desperation rush as they take damage.

**Spawn pacing** - tension tracker pauses spawning during fights, gives you a breather after. Based on L4D's Director concept.

**Weapon limits** - shotguns drop off past 15m, pistols past 25m, rifles past 80m. Moving AI shoots worse. No more shotgun snipers.

**Weather visibility** - detection range scales with sky shader lighting, fog, overcast, TOD, posture, flashlight.

**Surface hearing** - metal 1.7x, wood 1.35x, wind reduces hearing 0.7x, crouch-walking is nearly silent.

**Performance LOD** - distant AI skip expensive raycasts. Still wander and animate, just not burning CPU at 200m+.

## Install

Drop `VostokAIOverhaul/` (the folder with mod.txt in it) into your mods directory, launch the game.

**ImmersiveXP**: Not compatible, both mods override AI.gd. Disable IXP.
**Faction Warfare**: Compatible.
**MCM**: Key settings configurable in-game.

## Debug

Turn on Debug Mode in MCM. F8-F11 for spawn/godmode/heal. Awareness labels show up above AI heads with state, awareness %, and personality.

## Credits

Took a lot of ideas from FEAR, MGSV, L4D, the LAMBS Danger mod for ARMA, and Tarkov/Hunt for the boss and faction stuff. SPT Questing Bots for spawn pacing ideas.

## License

MIT
