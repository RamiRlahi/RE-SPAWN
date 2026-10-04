# RE-SPAWN notes

## Effects performance rule

Builds stack: Projectile Count × Ricochet bounces × attack speed × party size can turn one click into hundreds of hits. Every effect that can fire once per hit, per projectile or per bounce must be budgeted.

- **Client:** go through `src/client/FxBudget.luau`.
  - `FxBudget.Allow(key, perSecond)` before spawning per-hit parts, particles, tracers, sounds or damage numbers.
  - `FxBudget.Light()` before making a short-lived effect light.
  - Budgets shrink automatically when the frame rate drops.
- **Server:** gate per-hit effect remotes (`HitImpact`, `RicochetFX`, and similar) with `fxAllowed(player, key, perSecond)` in `SkillManager`. Damage, knockback and stagger are never limited, only their effects.
- **Global safety net:** `VfxDetail` already counts every effect light from any class against the FxBudget light cap and switches off the extras. Don't rely on it alone for parts and particles.
- **Never budget:** things the player must see, such as boss attacks, warnings, and an enemy projectile's always-on-top dot and trail. Only a projectile's extras (its Highlight and light) are budgeted.

## General performance rules

- **Finding targets:** never walk `Workspace:GetDescendants()`. The generated dungeon is tens of thousands of instances. Use `HumanoidIndex.Each()` / `HumanoidIndex.List()` (`src/shared/HumanoidIndex.luau`) for models with a Humanoid, or a specific folder (`Workspace.Mobs`).
- **Highlights:** each one is a full extra render pass. Use at most one per character (`CharacterOutline`; a Legendary aura's outline replaces it), and only a few on projectiles (`EnemyProjectiles.MAX_OUTLINES`).
- **Lights:**
  - No permanent `PointLight`s on mobs or on scenery. Neon parts glow on their own.
  - Short-lived effect lights go through `FxBudget.Light()`.
  - Lights that brighten as an attack wind-up (a telegraph) are fine.
- **Dungeon props:**
  - `CanTouch = false` (nothing listens for touches).
  - Floors and small props cast no shadow (`spawnInstance(..., noShadow)`).
  - Avoid long chains of tiny parts.
- **Per-frame work:** throttle raycasts and spherecasts (the camera's occlusion check runs at 15 Hz), cull by distance, and only write UI properties when the value changes.
- **Safety net:** `PerfMode` switches shadows and scenery effects off when the frame rate stays under ~35 fps. The Low Detail VFX setting does the same on request.
