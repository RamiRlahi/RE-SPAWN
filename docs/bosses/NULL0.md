# Null-0 — The Grandmaster

**Map:** The Neon Arcade  
**Cadence:** Boss floors 3, 6, 9, …  
**Identity:** Pattern recognition, portals, and arena manipulation  
**Palette / silhouette:** Fragmented floating geometry, holographic crown, magenta core, purple trails, and shifting armor shards. It must read as an arcade entity rather than a generic humanoid robot. Replace or evolve the existing custom ZAR-0 encounter; do not add a second unrelated arcade boss.
**Implementation status:** Registered for every third floor in the Neon Arcade. It has a dedicated floating core-and-shards model built on the existing Arcade Djinn animation controller; Block Drop, Laser Grid, Glitch Strike, and Game Over provide the current moves. Portal Volleys and the specified Error 404 patterns remain design targets, not implemented moves yet.

## Encounter rhythm

Null-0 alternates readable portal attacks with short windows where the party can attack the core. The existing magenta towers and portals remain mechanically relevant. At 50% HP, **Error 404** adds portal positions and combines patterns, but each pattern retains a visible safe route. Tower shields are server-authoritative and cannot be removed by client visuals alone.

### Glitch Portal

- **Purpose:** Threaten from multiple directions and make portal placement meaningful.
- **Preparation / warning:** Portals show destination arrows for 1.0 s.
- **Execution / recovery:** Three portal volleys over 1.2 s, then 0.7 s recovery.
- **Damage / area:** Each bolt `0.45×`; one hit per character per volley.
- **Targeting / counterplay:** Bolts travel along visible portal-to-floor lanes; players can move out of the lanes or break a nearby tower to remove one portal.
- **Multiplayer / effects:** Distribute lanes over current living players, maximum one direct lane per player; use existing Arcade portal/tower colors and a custom glitch trail.

### Pixel Rain

- **Purpose:** Ask players to read a pattern rather than chase a moving target.
- **Preparation / warning:** A 4×4 floor grid lights safe/danger cells for 1.15 s.
- **Execution / recovery:** Three descending waves, 0.45 s apart; 0.75 s recovery.
- **Damage / area:** `0.55×` per unsafe tile; repeat hits on the same character in one cast are suppressed.
- **Targeting / counterplay:** Show a clear pattern (row, checker, then cross); players move to dark cells. No fully covered grid.
- **Multiplayer / effects:** Same grid state for all players, synchronized from the server. Reuse portal/tower materials and layered pixel impacts.

### Game Over

- **Purpose:** Deliver the signature arena-wide attack with a learnable pattern.
- **Preparation / warning:** Three large regions telegraph for 1.2 s in a fixed order.
- **Execution / recovery:** Each region strikes 0.25 s apart; 1.0 s recovery.
- **Damage / area:** `0.9×` per region; a player hit once is immune to the remaining regions in that cast.
- **Targeting / counterplay:** Pattern starts from the edge opposite the safe lane and advances visibly; dodge toward the next dark region.
- **Multiplayer / effects:** Pattern is deterministic within a cast, so teammates can call the route. Keep the existing Game Over signature presentation, upgraded with a floor grid.

### Duplicate Error

- **Purpose:** Create a short identification window and coordinate target calls.
- **Preparation / warning:** Three silhouettes phase in for 0.8 s.
- **Execution / recovery:** Copies perform distinct windups for 2.2 s; the real Null-0 then attacks, followed by 0.8 s recovery.
- **Damage / area:** Wrong copies cannot damage or take health; the real strike is `0.65×`.
- **Targeting / counterplay:** Real copy has one stable visual tell (core pulse and shadow). Attacks to copies do not consume resources or punish players.
- **Multiplayer / effects:** One server-selected real model, replicated consistently. No client independently guesses the real target.

### Overclock / Insert Coin (ultimate)

- **Purpose:** Combine the learned grid and portal patterns in a final synchronization test.
- **Preparation / warning:** 1.3 s grid intro; portals telegraph their pattern before each cycle.
- **Execution / recovery:** Three synchronized cycles, 0.8 s apart, then 1.5 s recovery. Overclock raises projectile frequency in Error 404 but preserves the same minimum warning time.
- **Damage / area:** `0.65×` per unsafe cell/portal lane, with one damage event per character per cycle.
- **Targeting / counterplay:** Every cycle leaves at least 25% safe floor and one portal-free route. Destroying a tower removes one dangerous lane for the next cycle.
- **Multiplayer / effects:** Party shares the same grid, tower state, and timings. Floors, portals, projectiles, and damage all read a server-issued cycle index.

## Error 404 phase (50% HP)

The body fractures into floating components; the core stays clearly visible. Portals become more numerous, and previously learned patterns combine in pairs. Do not randomize the safe pattern after its tell: unpredictability comes from changing order, while fairness comes from fixed telegraph-to-impact timing.

**Introduction / victory:** Portals briefly show empty previews, then Null-0's crown and core assemble in the center. On defeat, the core freezes, fragments lose their glow, and the portal network shuts down in sequence. Follow with the normal run reward panel.

## Architecture and required assets

Register custom-built `null0` in `BossAI` (with its own build and pose/effect controller), reusing `BossAI.Kit`, `BossFX`, `BossIntro`, and the shared damage path. Integrate tower shield state with `ImmunityTower`, and read the Arcade's existing portal/grid geometry instead of making a parallel map system. Required authored assets: no animation IDs for a procedural first pass; a unique digital hit, portal, and phase-transition sound set can be supplied later. Do not invent sound or animation IDs.

