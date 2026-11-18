# The Pale Warden — Keeper of the Third Bell

**Map:** The Prison of Souls  
**Cadence:** Boss floors 3, 6, 9, …  
**Identity:** Pursuit, imprisonment, surveillance, and execution  
**Palette / silhouette:** Weathered iron, torn prison cloth, cold teal spectral fire, hanging chains, immense axe, and eyes in the helmet. A new articulated custom model is required; do not substitute an arbitrary boss template.
**Implementation status:** Registered for every third floor in the Prison of Souls and has a dedicated assembled model. Its current move selection reuses the Fallen Angel attack controller; the Sentence, Execution, and Prison Lockdown mechanics in this document are design targets, not implemented moves yet.

## Encounter rhythm

The Warden reads the arena, builds **Sentence**, and turns one fully marked player into the focus of a readable hunt. Other players can break Soul Anchors to interrupt the pursuit, peel chains off a teammate, or use gates and cover to buy time. At 50% HP, **The Unchained** phase detaches the chains and makes the Warden more aggressive without shortening reaction windows below readability.

### Sentence of Chains

- **Purpose:** Split attention and briefly restrict movement.
- **Preparation / warning:** Teal ground seams track each target for 0.9 s.
- **Execution / recovery:** Chains rise for 0.3 s; hit applies a 0.8 s movement slow, then the Warden recovers for 0.5 s.
- **Damage / area:** `0.45×` Warden baseline, one 5-stud zone per selected player.
- **Targeting / counterplay:** Cap at one marked point per living player; dodge the floor seam or break an ally free with one short interaction.
- **Multiplayer / effects:** Never target the same character with multiple chains in one cast. Use teal spectral links and a brief chain sound.

### The Execution

- **Purpose:** Convert three Sentence stacks into a high-pressure but survivable chase.
- **Preparation / warning:** 1.4 s axe raise and target-only execution mark; after the Warden vanishes, its reappearance gets a further 1.0 s strike warning.
- **Execution / recovery:** One delayed axe strike, then 1.1 s recovery.
- **Damage / area:** `1.6×` direct hit in a narrow lane, plus `0.55×` in a short ground shockwave. It must not down a full-health class from one isolated hit after normal defenses.
- **Targeting / counterplay:** Focus the highest Sentence target; stop the hunt by breaking an Anchor or use the warning to dodge the axe lane. A successful counter clears Sentence.
- **Multiplayer / effects:** Marked player is chosen once and broadcast to everyone; others can interrupt. No target switching during the warning.

### Prison Lockdown

- **Purpose:** Change routes and line of sight during the fight.
- **Preparation / warning:** Gate lanes glow for 1.2 s and slam shut after a distinct bell cue.
- **Execution / recovery:** Gates remain for 5 s; spirits cross two telegraphed lanes; 0.8 s recovery after opening.
- **Damage / area:** Spirit lane `0.5×`; gates deal no contact damage and never trap a player in a dead end.
- **Targeting / counterplay:** Two or more routes remain open; marked players can still reach any active Soul Anchor.
- **Multiplayer / effects:** All gate states are server-authored and replicated. Use existing prison gate pieces where possible.

### Eyes Everywhere

- **Purpose:** Make cover and the prison's searchlight identity matter in the boss room.
- **Preparation / warning:** Searchlight cones sweep for 1.0 s before their detection state begins.
- **Execution / recovery:** A player held in light gains one Sentence no faster than once per 1.2 s; lamps expire after 6 s. Breaking an Anchor disables the nearest lamp for 4 s.
- **Damage / area:** Detection has no direct damage. Sentence is capped at three.
- **Targeting / counterplay:** Break line of sight behind pillars/gates or destroy an Anchor. Light pools are visible and never silently apply stacks.
- **Multiplayer / effects:** Three lamps at most, distributed across the arena. Reuse the Prison searchlight logic where possible, but keep boss Sentence separate from the run-wide alarm counter.

### No Escape (ultimate)

- **Purpose:** Create a coordinated sequence of short hunts that rewards awareness.
- **Preparation / warning:** Arena dims for 1.0 s; spectral eyes select targets for 1.1 s each.
- **Execution / recovery:** Up to four execution attempts, spaced 1.0 s apart; the sequence ends with 1.5 s recovery.
- **Damage / area:** Each attempt uses the Execution's lane but `1.1×` damage; it stops after one attempt per player.
- **Targeting / counterplay:** Select distinct living players while possible. Every selected player receives their own tell and can dodge or use an Anchor; missed attacks still leave a safe route.
- **Multiplayer / effects:** Skip dead players and retarget only before that player's warning begins. Darkness remains translucent enough to read arena hazards.

## The Unchained phase (50% HP)

Armor splits along bright teal seams; detached chains orbit independently and create extra, slow-moving lane threats. Sentence gains are faster only while the Warden's searchlights are active. The boss uses shorter recovery, not shorter telegraphs. A custom break-apart/reform death pose and bell-and-chain sound set are required.

**Introduction / victory:** The third bell sounds through the fog; a searchlight finds an empty execution block before the Warden steps into it. On defeat, its axe drops, armor collapses inward, and the chains fall silent. Show the normal run reward panel after this map-specific fall.

## Architecture and required assets

Register a custom-built `pale_warden` in `BossAI` with a bespoke `build` function and client pose/VFX controller. Use the shared `BossAI.Kit`, `BossFX`, `BossIntro`, and `MobManager` damage path. Add the boss searchlight/Anchor state to its own server encounter state; do not alter Prison's existing three-sighting alarm semantics. Required authored assets: none for the first procedural prototype; later supply a unique bell, chain, and execution audio set if desired. Do not invent animation/audio IDs.

