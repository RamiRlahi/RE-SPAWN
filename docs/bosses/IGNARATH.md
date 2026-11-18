# Ignarath — The Ashen Sovereign

**Map:** The Infernal Keep  
**Cadence:** Boss floors 3, 6, 9, …  
**Identity:** Environmental destruction and aerial pressure  
**Palette:** Basalt black, molten orange, ember red, smoke  
**Build status:** Existing custom DragonBuilder rig; this pass adds map ownership, a volcanic palette, Magma Eruption, Devouring Flames, and Cataclysm. Meteor Shower already exists and is being retained as the aerial signature.

## Encounter rhythm

Ignarath opens with ground attacks that teach players to watch the floor. Meteor Shower changes the fight into an aerial positioning test. At 50% HP, **World Eater** increases attack pressure and makes temporary burning ground more common. At 20% HP, Ignarath forces one Cataclysm sequence, then returns to the normal move loop.

### Infernal Breath

- **Purpose:** Sweep a broad lane and force the party to reposition together.
- **Preparation / warning:** 0.5 s head wind-up, then a 0.9 s floor cone.
- **Execution / recovery:** 1.6 s sweep; 2.0 s while enraged; 0.3 s settle.
- **Damage / area:** Current breath tick is `0.28×` the scaled dragon baseline, at most once per character every 0.3 s, in a 44-stud cone.
- **Targeting / counterplay:** Faces the selected player before the cone locks; dodge across the lane or use the Keep pillars. Leave short-lived fire marks where the stream passes.
- **Multiplayer / effects:** Sweeps across the group in phase two; throat and mouth glow while charging. Use the existing DragonFX breath stream and roar/charge sounds.

### Magma Eruption

- **Purpose:** Make several floor zones unsafe and seed temporary arena hazards.
- **Preparation / warning:** 1.05 s circles at separated positions.
- **Execution / recovery:** Erupt each marked point in a short stagger; 0.45 s recovery (0.25 s in phase two).
- **Damage / area:** `0.8×` inside each 5.5–6.5-stud impact. Residual patches deal `0.16×` every 0.5 s for up to 3.5 s, sharing a character cooldown across patches.
- **Targeting / counterplay:** Distributes warnings over living players with offsets; spots are kept apart where the arena allows. Move out before impact, then avoid the cracked glowing ground.
- **Multiplayer / effects:** 4–9 marks based on player count and phase. Layer the existing explosion with a brief molten column, sparks, smoke, and ground scorch. All damage is server-side.

### Wings of Ruin (existing Wing Buffet / gust)

- **Purpose:** Punish players who stay close to Ignarath.
- **Preparation / warning:** 0.9 s circular warning, with a wing raise and wing sound.
- **Execution / recovery:** One blast and a 0.6 s recovery.
- **Damage / area:** Existing `0.45×` baseline inside 30 studs, with knockback.
- **Targeting / counterplay:** Radial; dodge out or use distance. Phase two can seed a few short fire trails at the edge of the blast.
- **Multiplayer / effects:** Hits each nearby player once. Keep the expanding shockwave and add a flame edge in World Eater.

### Meteor Shower (existing aerial signature)

- **Purpose:** Turn the whole arena into a readable movement puzzle while Ignarath becomes the visual focus.
- **Preparation / warning:** Takeoff 1.35 s, charge 0.8 s, then each impact receives a 1.25 s floor warning (1.5 s for the final meteor).
- **Execution / recovery:** 9–16 projectiles; launches every 0.36 s, tightening to 0.24 s at the end. Controlled landing has a 1.25 s warning and 1.2 s recovery.
- **Damage / area:** Normal impact `0.72×`; final impact `1.25×`. Fire patches share a 0.65 s player cooldown with direct impacts.
- **Targeting / counterplay:** Most shots lead a living player with jitter; every third shot denies nearby space. Last three shots tighten around the party. Run clear of the marked circles.
- **Multiplayer / effects:** Shot count scales with living players, clamped to 9–16. Projectiles originate at the mouth, client-rendered; warning, impact, and damage positions are server-chosen.

### Devouring Flames

- **Purpose:** Test timing and pattern recognition instead of aim tracking.
- **Preparation / warning:** 0.95 s for the first segmented ring, then 0.72 s per later ring. Each ring has an obvious 76-degree safe lane.
- **Execution / recovery:** Three outward rings; four in World Eater; 0.55 s recovery.
- **Damage / area:** `0.7×` when a player is within 2.5 studs of the ring's radius and outside the safe lane.
- **Targeting / counterplay:** Rings expand from the arena center. The safe lane shifts between rings; players move through the gap rather than trying to outrun the full wave.
- **Multiplayer / effects:** Same marked safe lane is visible to the whole party. Segmented floor telegraph, ember ring, and a low impact shake.

### Cataclysm (ultimate, once at 20% HP)

- **Purpose:** Deliver a climactic, avoidable arena-wide test of movement and timing.
- **Preparation / warning:** Rise 1.35 s, charge 1.2 s, 2.0 s central impact warning.
- **Execution / recovery:** A giant mouth-fired fireball impacts, followed by two outward magma shockwaves (0.8 s warning each), then a warned landing and 1.8 s recovery.
- **Damage / area:** Center impact `1.15×` within 23 studs; outward wave `0.6×` in a 6-stud band; landing `0.7×` within 18 studs.
- **Targeting / counterplay:** Center impact is fixed, not homing. Leave the central circle; then read and dodge each wave band. The final landing has its own circle.
- **Multiplayer / effects:** All cues and damage resolve from the server. Reuse DragonFX for a scaled projectile, layered explosion, shockwaves, and temporary burning center. No unavoidable stacked hits: waves are separated by warnings and share a player cooldown.

## World Eater phase (50% HP)

The model's existing enrage becomes the named World Eater phase: basalt fissures brighten, ember emission increases, attack gaps shorten, Magma Eruption gains marks, Devouring Flames adds a ring, and Meteor Shower accelerates its final section. The phase changes attack tempo and hazard density without removing safe responses.

## Animation, death, and assets

Takeoff, hover, firing, landing, and enraged wing poses are driven by `DragonState` in `DragonBossFX`. The DragonBuilder keeps its articulated silhouette, now in basalt/charcoal with neon magma fissures. Existing roar, wing, and charge sounds are reused. The existing fall-and-roll death and shared boss victory/reward presentation remain. No new sound or animation asset IDs are assumed; bespoke replacement recordings can be supplied later.

