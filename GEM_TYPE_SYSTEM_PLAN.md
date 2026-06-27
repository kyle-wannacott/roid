# Gem Type System — Implementation Plan

## Overview

Introduce **typed gems** (Green, Blue, Yellow, Purple, Red — like Crash Bandicoot/Spyro) that link asteroid distance → gem rarity → skill tree costs. This creates a clear exploration incentive: players must travel farther from the station to earn rarer gems needed for deeper skill tree unlocks.

A **gem inventory panel** is added to the top of the skill tree UI showing how many of each gem type the player owns.

---

## 1. Gem Type Definitions

| Gem | Color | Hex | Rarity | Typical Source |
|---|---|---|---|---|
| **Green** | 💚 Green | `#44DD66` | Common | Inner asteroids (0–400m) |
| **Blue** | 💙 Blue | `#4488FF` | Uncommon | Mid asteroids (300–700m) |
| **Yellow** | 💛 Yellow | `#FFCC22` | Rare | Outer asteroids (600–1000m) |
| **Purple** | 💜 Purple | `#AA44FF` | Very Rare | Deep-space asteroids (900–1400m) |
| **Red** | ❤️ Red | `#FF3344` | Legendary | Extreme range / Bosses only |

### New resource: `scripts/GemTypeData.gd`

A simple autoload/static class defining all gem types as constants. This avoids string duplication across the codebase:

```gdscript
class_name GemTypeData

const TYPES := ["green", "blue", "yellow", "purple", "red"]

const DISPLAY_NAMES := {
    "green": "Green",
    "blue": "Blue",
    "yellow": "Yellow",
    "purple": "Purple",
    "red": "Red",
}

const COLORS := {
    "green": Color("#44DD66"),
    "blue": Color("#4488FF"),
    "yellow": Color("#FFCC22"),
    "purple": Color("#AA44FF"),
    "red": Color("#FF3344"),
}

const RARITY_INDEX := {
    "green": 0,
    "blue": 1,
    "yellow": 2,
    "purple": 3,
    "red": 4,
}
```

---

## 2. Player Inventory — Track Gems Per Type

### File: `scripts/PlayerSkills.gd`

**Changes:**
- Replace single `gems: int` with `gem_inventory: Dictionary` → `{"green": 0, "blue": 0, "yellow": 0, "purple": 0, "red": 0}`
- Add helper methods:
  - `get_gem_count(type: String) -> int`
  - `add_gems(type: String, count: int)`
  - `spend_gems(cost: Dictionary) -> bool`  — `{"green": 2, "blue": 1}`
  - `has_enough_gems(cost: Dictionary) -> bool`
  - `get_all_gem_counts() -> Dictionary`
  - `get_total_gems() -> int`
- Persist `gem_inventory` in the save JSON alongside `unlocked_skills`
- Update `gems_changed` signal to emit the full inventory dictionary
- **Migration**: if old `gems` int field exists in save data, convert to `{"green": gems}`
- Refund system: `refund_skill()` returns the correct gem types

**Impact on Ship.gd:**
- Ship's `gems: int` → `gem_inventory: Dictionary`
- `gems_changed(count: int)` → `gems_changed(inventory: Dictionary)`
- `add_gems(amount)` → `add_gems_by_type(type: String, count: int)`
- `set_gems(amount)` → `set_gem_inventory(inventory: Dictionary)`
- Collection logic checks per-type capacity

---

## 3. Gem Visual — Type-Based Colors

### File: `scripts/GemManager.gd`

**Changes:**
- Replace weighted `PALETTE` array with gem type colors from `GemTypeData`
- `spawn_gem(at: Vector3, gem_type: String = "green") -> int` — takes a type parameter
- Remove `_pick_palette_color()` — color is determined by type
- Add `get_gem_type(idx: int) -> String` to look up which type an instance is

### File: `scripts/Gem.gd`

**Changes:**
- Add `var gem_type: String = "green"` property (set before adding to scene)
- Pass `gem_type` to `gem_manager.spawn_gem(pos, gem_type)` on spawn
- Store the type so Ship can read `gem.gem_type` on collection

---

## 4. Asteroid Drops — Distance-Based Gem Type

### File: `scripts/AsteroidManager.gd`

**Changes:**
- New method `_roll_gem_type(distance: float) -> String` with probability curves

**Distance → Gem Type Probability Table:**

| Distance | Green | Blue | Yellow | Purple | Red |
|---|---|---|---|---|---|
| 0–200m | 100% | 0% | 0% | 0% | 0% |
| 200–350m | 75% | 25% | 0% | 0% | 0% |
| 350–500m | 40% | 50% | 10% | 0% | 0% |
| 500–650m | 15% | 45% | 35% | 5% | 0% |
| 650–800m | 5% | 30% | 45% | 18% | 2% |
| 800–1000m | 2% | 15% | 40% | 35% | 8% |
| 1000m+ | 0% | 5% | 30% | 45% | 20% |

- `_break_asteroid(idx)` — after determining gem count, roll each gem's type using the distance-based table
- Pass `gem_type` when instantiating the Gem scene
- Larger asteroids get a +1 tier bonus to their effective distance (LARGE asteroids at 300m roll from 400m table)

---

## 5. Enemy Drops — Tougher Enemies Drop Rarer Gems

### File: `scripts/BaseEnemy.gd`

**Changes:**
- Replace `reward_gems: int` with `reward_gem_table: Dictionary` e.g. `{"green": 2, "blue": 1}`
- Add `get_reward_gem_table() -> Dictionary` method (replaces `get_reward_gems()`)
- Default: `{"green": 1}` for basic enemies

### File: scripts for each enemy type
- **ScoutDrone**: `{"green": 1}`
- **HeavyGunship**: `{"green": 2, "blue": 1}`
- **MissileCruiser**: `{"blue": 2, "yellow": 1}`
- **SerpentBoss**: `{"yellow": 2, "purple": 1}`
- (Future bosses): `{"purple": 2, "red": 1}`

### File: `scripts/EnemyManager.gd`

**Changes:**
- In `_spawn_enemy_at_position`, boost the enemy's reward table based on distance from station (e.g., a ScoutDrone at 800m adds a Yellow to its drop table)
- In `_on_enemy_died`, read `enemy.get_reward_gem_table()` and spawn typed Gem pickups

### File: `scripts/Main.gd`

**Changes:**
- `_on_enemy_destroyed()` — spawn typed gems using the enemy's reward table, same system as asteroid gem drops

---

## 6. Skill Tree — Skills Cost Specific Gem Types

### File: `resources/skill_tree_data.json`

**Changes:**
- Add a new field `gem_cost` to each skill node — a dict mapping gem type → count
- Old `cost` field becomes a shortcut for `{"green": cost}` or removed entirely
- Skill cost formula: distance from root in the tree determines gem rarity

**Mapping: tree distance → gem cost:**

| Tree Distance from Root | Example Skills | Gem Cost |
|---|---|---|
| Tier 1 (adjacent to root, <150px) | fuel_capacity, gem_magnet, laser_range, armor_plating | `{"green": 2}` |
| Tier 2 (150–300px) | fuel_capacity_2, gem_magnet_2, laser_range_2 | `{"green": 3}` or `{"blue": 1}` |
| Tier 3 (300–500px) | fuel_capacity_3, gem_magnet_3 | `{"blue": 2}` or `{"green": 1, "blue": 1}` |
| Tier 4 (500–700px) | armor_plating_3, missile_unlock | `{"yellow": 1, "blue": 1}` |
| Tier 5 (700–900px, edges) | shield_recharge_2, nanobot_gem_heal, mining_laser_combat | `{"purple": 1, "yellow": 1}` |
| Capstone (>900px, extreme edge) | missile_capacity_3, magnet_speed_3 | `{"red": 1, "purple": 1}` |

### File: `scripts/PlayerSkills.gd`

**Changes:**
- `can_unlock()` — check each gem type in `gem_cost` dict against `gem_inventory`
- `unlock_skill()` — deduct the required gem types from inventory
- `refund_skill()` — refund the correct gem types

### File: `scripts/skill_tree.gd`

**Changes:**
- **Info panel**: show gem cost breakdown instead of single number
  - "Cost: 2💚 Green + 1💙 Blue"
  - Each gem type colored with its own color
  - Missing types shown in red, owned in green
- `_build_unlock_status_text()` — show which gem types the player is short on
- Unlock button text: "Unlock (2 Green + 1 Blue)"
- Replace single `cost` checks with `gem_cost` dict checks

---

## 7. Skill Tree Gem Inventory Panel

### File: `scenes/skill_tree.tscn` + `scripts/skill_tree.gd`

**Design:**
A horizontal bar across the top of the skill tree (below the header, above TreeViewport) or integrated into the Header HBoxContainer, showing each gem type with its colored icon + count.

```
┌─────────────────────────────────────────────────────────────┐
│  💚 × 12    💙 × 8    💛 × 3    💜 × 1    ❤️ × 0          │
└─────────────────────────────────────────────────────────────┘
```

**Implementation:**
- Add a new `GemInventoryPanel` (HBoxContainer) as a child of the skill_tree root
- Position it at the top of TreeViewport, below the Header
- Contains 5 `Label` nodes, one per gem type with colored text
- Connect to `PlayerSkills.gems_changed` to refresh counts
- `_update_gem_inventory_display()` method called on `build_tree()` and on signal
- Each label: `[color=#44DD66]●[/color] 12` using BBCode for colored bullet icons

**Alternate approach (simpler):**
- Add 5 small colored squares + count labels directly into the Header HBoxContainer
- They sit between the skill title and the zoom buttons

---

## 8. HUD / Dashboard Updates

### File: `scripts/HUD.gd`

**Changes:**
- Gem display shows per-type counts as small colored icons in a row
- Or maintain a total count but add a tooltip showing breakdown

### File: `scripts/ShipDashboard.gd`

**Changes:**
- Same per-type display in the bottom-right dashboard panel

### File: `scripts/Ship.gd`

**Changes:**
- `gems: int` → `gem_inventory: Dictionary`
- Collection logic: reads `gem.gem_type` and increments the matching inventory key
- Signals: `gems_changed` emits the full inventory dict
- Sync with `PlayerSkills` on dock/undock

---

## 9. Implementation Order

### Phase 1: Foundation (Gem Types)
1. Create `scripts/GemTypeData.gd` with type constants
2. Update `GemManager.gd` — type-based palette, `spawn_gem(type)` parameter
3. Update `Gem.gd` — store and expose gem type property
4. Update `PlayerSkills.gd` — `gem_inventory` dict, typed accessors, save/load with migration

### Phase 2: Asteroid Integration
5. Update `AsteroidManager.gd` — `_roll_gem_type(distance)` method
6. Use it in `_break_asteroid()` when spawning gems

### Phase 3: Enemy Integration
7. Update `BaseEnemy.gd` — `reward_gem_table` dict
8. Update each enemy subclass with typed reward tables
9. Update `EnemyManager.gd` and `Main.gd` — spawn typed gems from enemies

### Phase 4: Skill Tree Costs
10. Update `resources/skill_tree_data.json` — add `gem_cost` field to each node
11. Update `PlayerSkills.gd` — typed cost checking in `can_unlock()` / `unlock_skill()` / `refund_skill()`
12. Update `skill_tree.gd` — info panel shows gem cost types, unlock button uses new cost system

### Phase 5: Gem Inventory Panel in Skill Tree
13. Add gem inventory display bar to the skill tree UI (tscn + gd)
14. Wire to `PlayerSkills.gems_changed`

### Phase 6: HUD & Ship Integration
15. Update `Ship.gd` — typed gem collection and inventory
16. Update `HUD.gd` and `ShipDashboard.gd` — per-type gem display

### Phase 7: Balance & Polish
17. Tune all drop probabilities, gem cost values, and distances
18. Test full loop: mine asteroid → get typed gems → unlock typed skill

---

## 10. Key Design Decisions

1. **Gems are physical pickups** — even typed gems are instantiated as `Gem.tscn` with color set by their type. The player flies over them to collect.
2. **Inventory is per-type** — each gem type is tracked separately. Skill tree panel shows the breakdown.
3. **Skills cost specific types** — a skill in the outer tree costs `{"yellow": 2, "blue": 1}`. The player must have those specific gems.
4. **No conversion** — gems don't convert between types. This keeps the exploration incentive pure.
5. **Distance is from station (origin)** — all drop tables use `position.length()` as the distance measure.
6. **Skill tree position from root** — gem cost tiers are based on Euclidean distance from the root skill's `(x, y)` position.

---

## 11. Risks & Mitigations

- **Risk**: Player gets stuck (needs Purples, can't survive far enough) → Inner belt always provides enough Green/Blue for escape and early upgrades. Mid-belt skills bridge the gap.
- **Risk**: Inventory management feels tedious with 5 types → Compact one-row UI display. The system replaces a single number with 5, so it's still glanceable.
- **Risk**: Skills become confusing with mixed costs → Clear colored cost breakdown in tooltip. Each gem type icon is colored uniquely.
- **Risk**: Existing save files break → Migration in `PlayerSkills.load_data()`: if old `gems` field exists, convert to `{"green": gems}`.
