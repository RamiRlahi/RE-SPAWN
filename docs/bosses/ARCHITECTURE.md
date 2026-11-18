# Boss architecture and floor schedule

## Existing systems

- `MobManager.planRoom` creates a boss record when it plans a Boss room. It reads the run's `RunLevel` and `MapId` from `RunScope`, then activates the record only when the room is entered.
- `MapData` supplies a regular boss pool and now supplies `majorBoss`, the signature boss selected at floors 3, 6, 9, and every third floor after that. The Infernal Keep is wired to Ignarath now. The Prison and Arcade point to `pale_warden` and `null0`; until those kinds register with custom builds, their third-floor encounters safely use the map's current custom boss as a fallback.
- Standard bosses use `BossAI` for the state loop, signature timing, enrage, damage hooks, and shared telegraph helpers. Their custom builders and client animation/VFX modules give them their own silhouettes and presentation.
- Ignarath uses the specialized `DragonBoss` state machine because it has server-owned flight, a custom `DragonBuilder` rig, a shield minigame, and client-side animation/effects in `DragonBossFX`.
- Boss damage goes through `MobManager.hurtPlayer`, preserving dodge i-frames, parries, curses, incoming-damage hooks, and knockback. Boss attacks choose living players from the boss's own run/arena.
- The Keep's arena is built by `Hazards.BuildBossArena`: lava, vents, and pillars are already available. Ignarath's new temporary fissures and fire patches add changing danger without destroying map geometry.
- Existing network channels are `BossIntro`, `BossFX`, and `DragonFX`; no new remote is needed for the current Ignarath work. No animation IDs or sound IDs are invented.

## Boss ownership and cadence

| Map | Signature boss | Floors |
|---|---|---|
| The Prison of Souls | The Pale Warden (`pale_warden`) | 3, 6, 9, … |
| The Infernal Keep | Ignarath (`dragon`) | 3, 6, 9, … |
| The Neon Arcade | Null-0 (`null0`) | 3, 6, 9, … |
| The Frozen Halls (sealed) | Malakor, until a dedicated concept is supplied | 3, 6, 9, … |

On other boss floors, each map uses its regular boss pool. The tutorial retains its own weakened boss flow. The Forgotten Isle is an endless island with a separate ritual boss system, not a dungeon-floor schedule.

The major-boss IDs are data-driven. Once the Warden and Null-0 have their custom builds and register with `BossAI`, the existing schedule selects them automatically. Until then, their map's already-built boss is used, so an unfinished kind can never produce a broken boss room.

## Damage reference

Character classes currently start between 95 and 300 max HP before run upgrades. Ignarath's attack baseline is `25 × 1.3 × DifficultyManager damage scale`; each attack uses a multiplier on that baseline, and final damage still flows through the shared player damage path. New damage values below are expressed as multipliers, not raw HP.

