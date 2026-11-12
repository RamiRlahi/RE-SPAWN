# Katana class: move reference

Source: the 56 s DMC5 combo video (youtube.com/watch?v=d-ggzGbsEWE), stepped through
frame by frame (every 0.7–1.5 s). Only moves made with the katana are listed; the
kicks and punches at 0:20–0:21 (gauntlets) are left out.

Names here are working names, our own. When the class is built it gets its own
name, sword and look; only the mechanics carry over.

| # | Seen at | What happens | Our working name | Suggested slot |
|---|---------|--------------|------------------|----------------|
| 1 | 0:00–0:02 | Fast close-range katana slashes on one enemy, staying in place. | Edge Combo | M1 |
| 2 | 0:06–0:08.5 | Low, very fast dash along the ground. The blade leaves long glowing arcs along the whole path; ends in a low lunge pose past the target. Hits everything on the line. | Flash Step | Skill 1 (E) |
| 3 | 0:04–0:05, 0:11–0:13 | At range, with no travel time: a sphere of glowing slash lines appears around the target and bursts. Used several times in a row. | Rift Cut | Skill 2 (F) |
| 4 | 0:14.5 | Rising slash that launches the enemy into the air. | Rising Cut | part of M1, or Empowered Flash Step |
| 5 | 0:02.5–0:03.3 | Airborne slash: jumps to the launched enemy and cuts with a glowing trail. | Air Cut | part of M1 (in the air) |
| 6 | 0:09–0:10, 0:16–0:19 | A dark, glowing double appears beside him and swings its own sword, copying his attacks. | Shadow Double | Skill 3 (Q) |
| 7 | 0:25–0:37 | The finisher. He sheathes the sword and stands still (enemies frozen); a crouched quick-draw with a glowing aura; the screen fills with hundreds of slash lines; then he kneels and slowly sheathes while the lines shatter and every enemy takes the hits at once; white flash. | Thousand Cuts | Ultimate (R) |

## Notes for building it

- **Thousand Cuts** fits our ultimates (Blade Storm, High Noon): stop time, fill the
  room with cuts, then all the damage lands when the blade clicks home. The slash lines
  are many short-lived parts, so they go through `FxBudget` (CLAUDE.md).
- **Rift Cut** hits at the aim point with no projectile, which no class has yet. It
  needs a max range and should be cheap on cooldown or use charges (it's spammed in the
  video).
- **Flash Step** overlaps with the Rogue's Dash and the Sword Master's Sword Rush. To
  set it apart: a much longer line, and the slash marks on the line explode a beat later.
- **Shadow Double** is the least sure: in the video it's blurry and only partly a katana
  move. Could be cut, or turned into a passive (every Nth attack the double repeats it).
- The frames are low resolution and 1 s apart, so timings and hit counts are
  estimates. Anything that matters (combo length, dash distance) should be set by feel.
