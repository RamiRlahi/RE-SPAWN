# RE-SPAWN notes

## Effects performance rule

Builds stack: Projectile Count × Ricochet bounces × attack speed × party size can turn one click into hundreds of hits. Every effect that can fire once per hit, per projectile or per bounce must be budgeted.

- **Client:** go through `src/client/FxBudget.luau`.
  - `FxBudget.Allow(key, perSecond)` before spawning per-hit parts, particles, tracers, sounds or damage numbers.
  - `FxBudget.Light()` before making a short-lived effect light.
  - Budgets shrink automatically when the frame rate drops.
- **Server:** gate per-hit effect remotes (`HitImpact`, `RicochetFX`, and similar) with `fxAllowed(player, key, perSecond)` in `SkillManager`. Damage, knockback and stagger are never limited, only their effects.
- **Global safety net:** `VfxDetail` already counts every effect light from any class against the FxBudget light cap and switches off the extras. Don't rely on it alone for parts and particles.
- **Never budget:** things the player must see, such as boss attacks, enemy projectiles and warnings.
