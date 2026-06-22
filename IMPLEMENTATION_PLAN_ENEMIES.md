# Enemy & Boss Implementation Plan
## Roid - Deep Asteroid Belt Content

This document outlines the implementation plan for adding enemies and bosses to the roid game, designed to be encountered deep in the asteroid belt, away from the safety of the space station.

---

## Overview

### Design Philosophy
- **Optional Engagement**: All enemies are placed far from the station (1000+ units out)
- **Progressive Difficulty**: Enemies get harder the deeper the player ventures
- **Risk vs Reward**: More dangerous zones offer better loot (gems, skill points)
- **Avoidable**: Players can navigate around encounters or flee

### Zone Layout
```
┌─────────────────────────────────────────────────────────────┐
│  STATION (0,0)                                              │
│  ┌─────────────────┐                                        │
│  │  Safe Zone      │  No enemies, only asteroids            │
│  │  (0-500 units)  │  Tutorial/resource gathering area      │
│  └─────────────────┘                                        │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────┐                                        │
│  │  Outer Belt     │  Scout drones, light patrols           │
│  │  (500-1000)     │  1-2 enemies per encounter             │
│  └─────────────────┘                                        │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────┐                                        │
│  │  Deep Belt      │  Gunships, missile cruisers            │
│  │  (1000-1500)    │  Mini-bosses, 3-5 enemies              │
│  └─────────────────┘                                        │
│         │                                                   │
│         ▼                                                   │
│  ┌─────────────────┐                                        │
│  │  Fringe Zone    │  Bosses, heavy enemies                 │
│  │  (1500+)        │  Full combat encounters                │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Base Enemy System

### 1.1 Enemy Manager (`EnemyManager.gd`)
**Purpose**: Central manager for spawning and tracking all enemies

**Responsibilities**:
- Maintain list of active enemies
- Handle spawn zones based on distance from station
- Manage enemy waves and encounters
- Clean up dead enemies

**Key Signals**:
```gdscript
signal enemy_spawned(enemy: Node3D)
signal enemy_destroyed(enemy: Node3D, position: Vector3)
signal encounter_started(encounter_data: Dictionary)
signal encounter_completed(rewards: Dictionary)
```

**Spawn Logic**:
```gdscript
func get_spawn_zone(distance_from_station: float) -> SpawnZone:
    if distance_from_station < 500.0:
        return SpawnZone.SAFE
    elif distance_from_station < 1000.0:
        return SpawnZone.OUTER
    elif distance_from_station < 1500.0:
        return SpawnZone.DEEP
    else:
        return SpawnZone.FRINGE
```

### 1.2 Base Enemy Class (`BaseEnemy.gd`)
**Purpose**: Abstract base class for all enemies

**Common Properties**:
```gdscript
class_name BaseEnemy
extends CharacterBody3D

signal health_changed(new_health: float, max_health: float)
signal enemy_died()

@export var max_health: float = 100.0
@export var move_speed: float = 100.0
@export var rotation_speed: float = 2.0
@export var collision_damage: float = 10.0
@export var reward_gems: int = 5
@export var reward_skill_points: int = 0

var health: float
var target: Node3D  # Usually the player ship
var is_alive: bool = true
```

**Common Methods**:
```gdscript
func take_damage(amount: float) -> void
func die() -> void
func get_distance_to_player() -> float
func face_target(delta: float) -> void
```

---

## Phase 2: Regular Enemies

### 2.1 Scout Drone (`ScoutDrone.gd`)
**Zone**: Outer Belt (500-1000 units)

**Behavior**:
- Fast, agile movement
- Patrols in groups of 3-5
- Fires quick burst at player when in range
- Flees if health drops below 30%

**Properties**:
```gdscript
@export var patrol_radius: float = 50.0
@export var detection_range: float = 150.0
@export var fire_rate: float = 0.5
@export var projectile_speed: float = 300.0
```

**Movement States**:
```
PATROL → DETECT → ATTACK → FLEE
   ↑                          │
   └──────────────────────────┘
```

**Implementation Notes**:
- Use simple state machine
- Spawn at random patrol points within zone
- Leash back to patrol area if player runs away

### 2.2 Heavy Gunship (`HeavyGunship.gd`)
**Zone**: Deep Belt (1000-1500 units)

**Behavior**:
- Slow, tanky movement
- Multiple turret positions
- Fires sustained volleys
- Requires focused fire to destroy

**Properties**:
```gdscript
@export var turret_count: int = 3
@export var fire_rate: float = 0.3
@export var burst_count: int = 5
@export var burst_delay: float = 0.1
```

**Turret System**:
```gdscript
var turrets: Array[Node3D]  # References to turret nodes

func _update_turrets(delta: float) -> void:
    for turret in turrets:
        turret.look_at(target.global_position)
        if turret.can_fire():
            turret.fire()
```

### 2.3 Missile Cruiser (`MissileCruiser.gd`)
**Zone**: Deep Belt (1000-1500 units)

**Behavior**:
- Maintains distance from player
- Fires homing missiles
- Tries to stay at optimal range (200-300 units)

**Homing Missile Properties**:
```gdscript
@export var missile_speed: float = 150.0
@export var missile_turn_rate: float = 3.0
@export var missile_lifetime: float = 5.0
@export var missile_damage: float = 20.0
```

**Missile AI**:
```gdscript
func _physics_process(delta: float) -> void:
    var to_target = target.global_position - global_position
    var desired_rotation = to_target.normalized()
    velocity = velocity.normalized().lerp(desired_rotation, missile_turn_rate * delta) * missile_speed
```

### 2.4 Drone Carrier (`DroneCarrier.gd`)
**Zone**: Fringe Zone (1500+ units)

**Behavior**:
- Large, slow ship
- Spawns smaller drone minions
- Weak to direct fire
- Priority target in encounters

**Properties**:
```gdscript
@export var max_drones: int = 8
@export var spawn_interval: float = 3.0
@export var drone_health: float = 20.0
```

---

## Phase 3: Bosses

### 3.1 Serpent-class Drone Controller (`SerpentBoss.gd`)
**Zone**: Deep Belt (1200+ units)

**Concept**: A segmented enemy that weaves through asteroids like a snake

**Structure**:
```
[HEAD]─[SEG1]─[SEG2]─[SEG3]─[SEG4]─[SEG5]
  │      │      │      │      │      │
  ▼      ▼      ▼      ▼      ▼      ▼
 Fire   Fire   Fire   -     Fire   -
```

**Properties**:
```gdscript
@export var segment_count: int = 8
@export var segment_spacing: float = 15.0
@export var movement_speed: float = 120.0
@export var segment_health: float = 50.0
@export var head_health: float = 200.0
```

**Key Mechanics**:
1. **Segment Chain**: Each segment follows the one in front
2. **Head Destruction**: When head dies, next segment becomes head
3. **Independent Heads**: Destroyed segments create independent smaller snakes
4. **Projectile System**: Head and alternate segments fire projectiles

**Movement Algorithm**:
```gdscript
func _update_segments(delta: float) -> void:
    # Head moves toward target
    var target_pos = _get_movement_target()
    _head.velocity = _head.position.direction_to(target_pos) * movement_speed
    _head.position += _head.velocity * delta
    
    # Each segment follows the previous
    for i in range(1, segments.size()):
        var leader = segments[i - 1]
        var follower = segments[i]
        var dir = follower.position.direction_to(leader.position)
        var target_dist = segment_spacing
        var current_dist = follower.position.distance_to(leader.position)
        
        if current_dist > target_dist:
            follower.position += dir * (current_dist - target_dist) * 0.1
```

**Phases**:
1. **PATROL**: Weaves through asteroid field
2. **CHASE**: Pursues player aggressively
3. **COIL**: Spirals around player, firing from all segments
4. **RETREAT**: Pulls back when low health

### 3.2 Orbital Defense Platform (`LaserBoss.gd`)
**Zone**: Fringe Zone (1500+ units)

**Concept**: Stationary satellite that fires devastating laser beams

**Structure**:
```
     ┌─────────────┐
     │   SOLAR     │
     │   PANELS    │
     └──────┬──────┘
            │
    ┌───────┴───────┐
    │    CORE       │
    │   (weak)      │
    └───────┬───────┘
            │
     ┌──────┴──────┐
     │   LASER     │
     │   EMITTER   │
     └─────────────┘
```

**Properties**:
```gdscript
@export var laser_damage_per_sec: float = 50.0
@export var laser_width: float = 30.0
@export var laser_range: float = 800.0
@export var charge_time: float = 3.0
@export var fire_duration: float = 2.0
@export var cooldown_time: float = 4.0
```

**Laser States**:
```gdscript
enum LaserState {
    IDLE,
    TELEGRAPHING,  # Warning beam appears
    FIRING,        # Full damage beam
    COOLDOWN       # Recharging
}
```

**Key Mechanics**:
1. **Telegraph Phase**: Dashed warning line appears before firing
2. **Sweeping Beam**: Laser rotates slowly during fire phase
3. **Solar Panel Weakness**: Destroying panels reduces charge time
4. **Core Exposure**: Core is vulnerable only during cooldown

**Attack Pattern**:
```
IDLE (2s) → TELEGRAPH (3s) → FIRING (2s) → COOLDOWN (4s) → repeat
```

### 3.3 Asteroid Hive (`BulletHellBoss.gd`)
**Zone**: Fringe Zone (1800+ units)

**Concept**: Spherical core with rotating turrets, fires bullet patterns

**Structure**:
```
        [Turret]
           │
[Turret]──CORE──[Turret]
           │
        [Turret]
```

**Properties**:
```gdscript
@export var turret_count: int = 6
@export var rotation_speed: float = 1.0
@export var fire_rate: float = 0.2
@export var bullet_speed: float = 200.0
@export var pattern_count: int = 4
```

**Bullet Patterns**:
```gdscript
enum BulletPattern {
    SPIRAL,        # Single rotating stream
    DOUBLE_SPIRAL, # Two opposing streams
    RING,          # Expanding circle of bullets
    BURST,         # Quick burst of multiple bullets
    HOMING,        # Slow-tracking bullets
}
```

**Pattern Implementation**:
```gdscript
func _fire_spiral() -> void:
    for i in range(turret_count):
        var angle = current_spiral_angle + (TAU / turret_count) * i
        var direction = Vector2(cos(angle), sin(angle))
        _spawn_bullet(global_position, direction * bullet_speed)

func _fire_ring() -> void:
    var bullet_count = 16
    for i in range(bullet_count):
        var angle = TAU / bullet_count * i
        var direction = Vector2(cos(angle), sin(angle))
        _spawn_bullet(global_position, direction * bullet_speed)
```

**Safe Zones**:
- Bullets have gaps that skilled players can navigate
- Pattern telegraphs which gaps will be safe
- Asteroids in the arena provide temporary cover

**Phases** (based on health):
1. **Phase 1 (100-70%)**: Single spiral
2. **Phase 2 (70-40%)**: Double spiral
3. **Phase 3 (40-0%)**: Ring + spiral combo

---

## Phase 4: Projectile System

### 4.1 Base Projectile (`BaseProjectile.gd`)
```gdscript
class_name BaseProjectile
extends Area3D

@export var speed: float = 300.0
@export var damage: float = 10.0
@export var lifetime: float = 3.0
@export var is_homing: bool = false
@export var homing_strength: float = 2.0

var velocity: Vector3
var target: Node3D

func _physics_process(delta: float) -> void:
    if is_homing and target:
        var to_target = target.global_position - global_position
        velocity = velocity.normalized().lerp(to_target.normalized(), homing_strength * delta) * speed
    
    global_position += velocity * delta
    lifetime -= delta
    if lifetime <= 0:
        queue_free()
```

### 4.2 Enemy Bullet (`EnemyBullet.gd`)
```gdscript
extends BaseProjectile

func _on_body_entered(body: Node3D) -> void:
    if body.has_method("take_damage"):
        body.take_damage(damage)
        queue_free()
```

### 4.3 Homing Missile (`HomingMissile.gd`)
```gdscript
extends BaseProjectile

func _ready() -> void:
    is_homing = true
    speed = 150.0
    damage = 25.0
    lifetime = 5.0
```

---

## Phase 5: Integration

### 5.1 Main.gd Changes
```gdscript
# Add to Main.gd
@onready var enemy_manager: Node3D = $EnemyManager

func _ready() -> void:
    # ... existing code ...
    enemy_manager.enemy_destroyed.connect(_on_enemy_destroyed)

func _on_enemy_destroyed(enemy: Node3D, position: Vector3) -> void:
    # Spawn explosion effect
    # Award gems/skill points to player
    # Update HUD
    pass
```

### 5.2 Ship.gd Changes
```gdscript
# Add to Ship.gd
func take_damage(amount: float) -> void:
    if _damage_cooldown > 0.0:
        return
    health -= amount
    _damage_cooldown = 0.5
    health_changed.emit(health, _eff_max_health)
    if health <= 0:
        die()

func _on_enemy_projectile_hit(area: Area3D) -> void:
    if area.has_method("get_damage"):
        take_damage(area.get_damage())
```

### 5.3 Collision Layers
```
Layer 1: Player Ship
Layer 2: Asteroids
Layer 3: Enemy Ships
Layer 4: Enemy Projectiles
Layer 5: Player Projectiles
Layer 6: Pickups (Gems, etc.)
```

---

## Implementation Order

### Week 1: Foundation
- [ ] Create `EnemyManager.gd` with zone system
- [ ] Create `BaseEnemy.gd` abstract class
- [ ] Set up collision layers for enemies
- [ ] Add enemy spawning logic to Main.gd

### Week 2: Regular Enemies
- [ ] Implement `ScoutDrone.gd`
- [ ] Implement `HeavyGunship.gd`
- [ ] Create enemy projectile system
- [ ] Add basic AI behaviors

### Week 3: Advanced Enemies
- [ ] Implement `MissileCruiser.gd` with homing missiles
- [ ] Implement `DroneCarrier.gd` with spawning
- [ ] Add enemy death effects and rewards
- [ ] Balance enemy health/damage

### Week 4: Boss - Serpent
- [ ] Create segmented enemy system
- [ ] Implement snake-like movement
- [ ] Add segment destruction mechanics
- [ ] Create boss health bar UI

### Week 5: Boss - Laser Satellite
- [ ] Create stationary boss with phases
- [ ] Implement laser beam with telegraph
- [ ] Add solar panel weak points
- [ ] Create sweeping beam rotation

### Week 6: Boss - Bullet Hell
- [ ] Create rotating turret system
- [ ] Implement bullet pattern system
- [ ] Add safe zone mechanics
- [ ] Create phase transitions

### Week 7: Polish
- [ ] Add sound effects for enemies
- [ ] Create enemy spawn animations
- [ ] Balance all encounters
- [ ] Add difficulty scaling

### Week 8: Testing
- [ ] Playtest all encounters
- [ ] Adjust spawn rates and difficulty
- [ ] Fix bugs and edge cases
- [ ] Optimize performance

---

## Asset Requirements

### Sprites/Models
- Scout Drone (small, fast)
- Heavy Gunship (large, armored)
- Missile Cruiser (medium, with missile pods)
- Drone Carrier (large, with drone bay)
- Serpent segments (head + body)
- Laser Satellite (with solar panels)
- Bullet Hell Core (spherical with turrets)

### Effects
- Enemy explosions (small, medium, large)
- Laser beam effect
- Bullet impact effects
- Shield hit effect
- Engine trails

### UI
- Enemy health bars
- Boss health bars (larger, more prominent)
- Encounter warning text
- Boss name display

### Sounds
- Enemy engine sounds
- Weapon fire sounds
- Explosion sounds
- Boss intro music
- Alert sounds

---

## Technical Considerations

### Performance
- Use object pooling for projectiles
- Limit maximum active enemies (20-30)
- Use LOD for distant enemies
- Optimize collision detection

### Save System
- Track defeated bosses
- Save encounter states
- Persist enemy kills for achievements

### Difficulty Scaling
- Scale enemy health with player level
- Increase spawn rates in deeper zones
- Add elite enemy variants

---

## Future Extensions

### Additional Bosses
- **Asteroid Golem**: Made of asteroids, throws chunks
- **Carrier Boss**: Spawns waves of fighters
- **Energy Being**: Teleports, fires energy waves

### Enemy Variants
- **Elite Enemies**: Stronger versions with special abilities
- **Armored Enemies**: Require specific damage types
- **Stealth Enemies**: Cloak when not attacking

### Encounter Types
- **Ambush**: Enemies spawn from all sides
- **Escort**: Protect a friendly ship
- **Survival**: Hold out for X seconds
- **Boss Rush**: Multiple bosses in sequence

---

*Document Version: 1.0*
*Created: 2026-06-23*
