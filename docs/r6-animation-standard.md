# R6 animation standard

The quality bar for every R6 animation in RE-SPAWN, learned from reference work
the team picked (studied frame by frame, November 2026). Body mechanics rules
(planted feet etc.) are in the "Mechanics" section; everything else is what
makes the references read as polished.

## References

| Who | What to study | Link |
|-----|---------------|------|
| Yahy | **Combat (best match for us).** M1 combo, abilities, combat idle, sprint | https://yahy-portfolio.carrd.co/ (Vimeo: M1 combo V2, Descending Cataclysm, X-Swipe, Jet Blitz, Idle animation) |
| Floppa | Locomotion: walk, run, idle | https://devforum.roblox.com/t/open-r6-animator-locomotion-portfolio/4936429 |
| god90 (DevForum) | Free walk + run cycle | https://devforum.roblox.com/t/r6-run-walk-animations/2484804 |
| Derk2104 | Battlegrounds-style punch combo (attacker + victim) | https://www.derk2104portfolio.com/ (Animation card) |
| Ninjabread | Older boxing combo, idles, jab | https://devforum.roblox.com/t/open-animator-portfolio-r6/641177 |
| AySplash | Cinematic studies, trailers (bendy-limb rig) | https://www.aysplash.dev/ |
| Nopeman | — site down (n1xdragon.com does not resolve) | https://www.n1xdragon.com/ |
| FIFT33N | — clips unavailable (Gyazo delivery suspended) | https://devforum.roblox.com/t/fift33n-animator-portfolio/532165 |

## What the good ones do

### 1. The torso does the work
- Attacks lean **20–45°**: jab/cross about 20–25°, a lunge about 35°, a finisher smash about 45°.
  Ours were 5–15°, which reads stiff.
- Every strike **twists** the torso into it (45° or more) and often **rolls** it sideways
  (up to about 30° on hooks and overheads).
- The head stays aimed at the target while the body turns under it.

### 2. Opposition, always
- The free arm **pulls back hard** as the striking arm extends (counter-arm). It is never idle.
- In walks and runs the arms swing against the legs; the torso twists against the hips.

### 3. Anticipation you can see
- Light hits: a short wind-up (2–4 frames at 60 fps) in the opposite direction.
- Finishers and big skills: a **coil**. The body crouches, the arms cross or tuck, the head drops,
  and it **holds for about 0.25–0.5 s** before the release. The hold is what makes the release hit.
- Jumps and aerial slams start with a deep crouch.

### 4. Snap in, hold, ease out
- Strike frames are fast: 2–4 frames (0.03–0.07 s) into contact.
- **Hold the extended pose** for a few frames, then ease back out.
  "Strong easing" means fast in, slow settle; never linear.
- Combo rhythm: a hit about every **0.25 s** (Yahy) to **0.4 s** (Ninjabread). Each hit returns
  toward the guard, but not all the way, so the chain flows.

### 5. Whole-body rotation sells big moves
- Uppercuts and launchers throw the body diagonally (about 40°) with the legs trailing.
- Aerial slams **flip** the body: leap with the body arched and arms overhead → rotate past
  horizontal → dive head first, arms reaching down → impact with the body nearly inverted, then recover.

### 6. Silhouette and stance
- Combat idle: arms up in a guard in front of the chest, staggered narrow stance, slight breathing
  (a 2–3 s cycle). Arms are never glued to the sides.
- Locomotion idle: feet slightly wide, arms angled about 10–15° out from the body, small head turns.
- Every key pose should read as a clear silhouette from the gameplay camera.

### 7. Locomotion numbers (Floppa, god90)
- **Walk:** about a 1.0 s cycle; legs swing about ±30°; arms swing small and stay slightly out;
  torso upright with a small bob, a little roll toward the supporting leg and a little twist with the stride.
- **Run:** about a 0.7 s cycle; torso pitched forward about 15° and twisting with the stride;
  arms pump high (nearly horizontal forward, well back behind); the front leg drives up 60–80°;
  the back leg extends fully; there's a short airborne phase.

### 8. Layering for gameplay (Yahy)
- M1 chains are **upper-body only**, so the game's movement drives the legs and the player
  can keep moving. Only the **finisher** takes the full body.
- In our system, M1 stages touch only `W`, `N`, `RS`, `LS` (plus small `Root` rotation);
  finishers and abilities may drive `Root` offsets and the legs (`RH`, `LH`) with foot planting.

## Mechanics (the rules from before)
- **An R6 leg is the SHIN (below the knee), not the thigh.** The thigh and knee are hidden in
  the torso. So a supporting leg stays close to upright with its foot flat, leaning only a
  little forward (knee over toes, up to about 25°); when the body crouches, the leg **slides up into the
  torso** (hip offset) instead of splaying out like a thigh. Kneeling: the back shin lies along
  the floor, knee down under the hip, foot behind.
- R6 legs are rigid; **the bottom face of the leg is the foot**. Supporting feet stay planted:
  no slide, float or sink. Feet leave the ground only to step, jump or kick, and steps lift and
  set down. Body height follows the legs; the centre of mass stays over the support.
- Each move has anticipation → action → follow-through → recovery.
- Validate every frame (side and front), and report the foot numbers.

## R6 limits worth knowing
- In-game R6 limbs can't bend. AySplash's trailers use a **bendy-limb rig** (two blocks per limb)
  for cinematics only; the Blender R6 rig we use has the same upper/lower bones, but the game
  character is rigid, so gameplay animations get their shape from the torso, shoulders and hips.
- A leaning rigid leg stands on an edge of the foot; keep support legs within about 40° of vertical.
