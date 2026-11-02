# RE///SPAWN — Class summoning economy

Every number here lives in `src/shared/GachaConfig.luau`. The in-game Rates & Pity panel is built from that file, so the odds players see are the odds the server rolls. Tune the config, not the code.

## 1. Core rules

- **Pull Tickets are the only summoning currency.** 1 ticket = 1 summon on any banner (the Altar of Souls for classes, plus the two existing cosmetic banners). Crystals are removed. Robux buys tickets directly, so there is no second paid currency to hide prices behind.
- **Starter classes:** a new profile owns Ranger, Fencer (`swordsman`), Cleric, Mage and Rogue. Every other class is locked until it is pulled, bought with Soul Essence, or bought directly with Robux. Unlocks are permanent, and players switch freely between owned classes.
- **The server decides everything.** It checks ownership on every class pick, campfire switch and dungeon entry (`ClassManager`), rolls every drop and summon with its own `Random`, and saves everything in the profile (`PlayerData`).

## 2. What a dungeon actually contains (from the code)

| Source | Value |
|---|---|
| Floor layout (`DungeonGenerator` plan) | Start → 2 rooms → 3 rooms → 2 rooms → Boss |
| Fighting rooms per floor | 1 + ⅔ + 1 + 1 + 1 = **≈4.67** (layer picks between Combat / Elite / utility rooms) |
| Elite rooms per floor | ⅓ + ½ + ½ = **≈1.33** (every mob in an Elite room is elite) |
| Mobs per room (`MobManager`) | `min(7 + 2 × Threat tier, 24)` |
| Threat tier (`DifficultyManager`) | +1 every 75 s of run time |
| Random elite chance | 3% + 0.7% per tier (max 10%) |
| Boss room | 1 boss + half the room's mobs (the dragon on floor 3, 6, 9… fights alone) |
| Extraction | every 3 floors |

**Run-length estimate:** about 4 min per floor, so a 3-floor run is about 12 min plus about 3 min of lobby/extraction, roughly **15 min, or 4 runs an hour**. Measure real runs (`RunStats`) and update this; every derived number scales with it.

| Floor | Avg tier | Mobs / room | Mobs on the floor |
|---|---|---|---|
| 1 | ~1.5 | ~10 | ~52 |
| 2 | ~4.5 | ~16 | ~83 |
| 3 | ~8 | ~23 | ~107 (dragon floor) |
| **Run** | | | **~242 mobs + 3 bosses** |

About 33% of kills are elite (28.5% from Elite rooms + about 4% random). Per run that is ~162 normal, ~80 elite and 3 bosses. Per hour: **~650 normal, ~320 elite, ~12 bosses.**

## 3. Pull Ticket drops

Each kill rolls **once per player who gets credit for it** (within 120 studs, the same rule as gold). The rolls are independent, and the ticket goes straight into the inventory with a small toast (`TicketToast`).

| Tier | How it's detected | Chance | Expected/hour |
|---|---|---|---|
| Normal | default | 0.25% (1 in 400) | 1.63 |
| Elite | `IsElite` | 0.6% (1 in ~167) | 1.92 |
| Mini-boss | Forgotten Isle `Behemoth` | 5% (1 in 20) | island only |
| Boss | `IsBoss` (floor bosses, dragon, isle bosses) | 15% (1 in ~7) | 1.80 |
| Summoned adds, tutorial | `Summoned`, boss minions, `Tutorial` run | 0 | — |

- **Per 3-floor dungeon run:** 0.41 + 0.48 + 0.45 ≈ **1.34 tickets**. 74% of runs drop at least one.
- **Per hour of pure dungeon time:** ≈ 5.35. With deaths, menus and lobby time (×0.8 uptime) that is **≈ 4.3 tickets/hour**, plus the **daily wish** (1 free summon a day).
- **Anti-farm cap:** 15 drops per player per rolling hour, about 3× the expected rate. Normal play never reaches it.

Hours of play (at 4.3/h, before the daily wish):

| Pulls | Hours |
|---|---|
| 10 | ~2.3 h |
| 50 | ~11.6 h |
| 100 | ~23 h |

*Critical note:* boss tickets make up about a third of income. If real runs are much shorter (deaths on floor 1–2), income drops faster than the kill count does. Check the `ticketDrops` stat per player after a week of live data.

## 4. The Altar of Souls (class banner)

### Rarity table (sums to 100%)

| Rarity | Odds | Contents | Per item |
|---|---|---|---|
| Common | 60.0% | Soul Essence Wisp (10 Essence) | 60.0% |
| Rare | 27.0% | Ice Mage, Gunslinger | 13.5% each |
| Epic | 9.4% | Fire Knight, Berserker, Martial Artist | featured 4.7%, others 2.35% each |
| Legendary | 3.0% | Summoner | 3.0% |
| Mythic | 0.6% | Death Knight | 0.6% |

The starter classes are never in the pool, so a summon can never give back a starter.

### Pity (per banner, saved)

- At least one Epic or better within every **10** summons.
- Legendary soft pity from summon **60** (+6% per summon); hard pity at **75** (Legendary or better).
- Mythic hard pity at **150**.
- **×10** guarantees at least one Rare; **×25** guarantees at least one Epic.
- **Featured rotation:** one Epic class is featured each week (Monday 00:00 UTC, rotating Fire Knight → Berserker → Martial Artist). When you roll an Epic, it is the featured class 50% of the time. If it isn't, the next Epic is guaranteed to be.
- **Starlight:** +1 per altar summon. **100 Starlight buys any class you don't own** (Rare or better, the Death Knight included). This is the hard guarantee: no player ever needs more than 100 altar summons for a class they want.
- **Milestones** (lifetime altar summons → Soul Essence): 25 → 100, 50 → 200, 100 → 400, 200 → 800.
- Single, ×10 and ×25 summons all cost 1 ticket each, with no bulk discount on pulls. The discount is on ticket packs, so the odds are the same however you pull.

### Simulated pulls (20,000 runs of the exact rules; script: `docs/gacha-sim.py`)

| Goal | No Starlight/Essence | With all systems |
|---|---|---|
| Ice Mage / Gunslinger (first copy) | mean 7.6 | 6.9 |
| Fire Knight (featured) | 11.0 | 10.9 |
| Berserker / Martial Artist (off-banner) | 37 (p90 84) | 23–24 (p90 ~40) |
| Summoner | 29.7 (p90 63) | 29.1 |
| Death Knight | 98.8 (p90 150) | 75 (≤ 100) |
| **All 7 classes** | mean 114, p90 150, p99 199 | **mean 81, never above 100** |

## 5. Duplicates → Soul Essence

| Duplicate | Essence |
|---|---|
| Rare class | 40 |
| Epic class | 100 |
| Legendary class | 250 |
| Mythic class | 600 |
| Altar Common | 10 |

Once a player owns everything, the altar averages **~37 Essence per summon**. Essence can never be turned back into tickets, so summoning can't be looped. It buys:

- **Direct class unlocks (not random):** Rare 350, Epic 900, Legendary 2,000, Mythic 4,000. These are a bad-luck backstop, priced well above the expected pulls (a Mythic costs 4,000 Essence, roughly 100+ duplicates' worth, while Starlight gets there first).
- **Essence Shop:** every class armor (600 each), the Dark VFX variant (1,500).
- **Planned sinks** (not built yet): weapon skins, emotes, VFX recolours, titles, Class Codex frames. Without them, Essence goes dead for whales after the shop is cleared. This is the biggest long-term gap.

## 6. Robux

- **One ticket = 25 R$.**

| Pack | R$ | R$/ticket | Discount |
|---|---|---|---|
| 1 | 25 | 25.0 | — |
| 5 | 119 | 23.8 | 5% |
| 10 | 225 | 22.5 | 10% |
| 25 | 525 | 21.0 | 16% |
| 50 | 999 | 20.0 | 20% |
| 100 | 1,799 | 18.0 | 28% |

- **Direct class purchases exist, except Mythic:** Rare 199, Epic 499, Legendary 999. These sit near the expected ticket cost (Rare ≈ 7 pulls ≈ 175 R$; off-banner Epic ≈ 24 pulls ≈ 540 R$; Summoner ≈ 29 pulls ≈ 650 R$ but with a long tail to 75). Players who hate randomness pay a small premium for certainty. The Death Knight is pull-, Starlight- or Essence-only, so the Mythic stays something you earn.
- **Spending ceiling:** because of Starlight, unlocking every class costs **at most 100 tickets (~1,800–2,500 R$)**. This is intentionally low and fair. Long-term revenue has to come from the cosmetic banners and future cosmetics, not from classes. Raise the Starlight cost only if revenue truly needs it; it is the system's main fairness promise.
- **Setup still needed:** create the Developer Products in Creator Hub at these prices and paste their ids into `TicketProducts` / `ClassProducts`. A `productId = 0` hides that product.

## 7. Player simulations (classes only)

Daily income: casual = 1 h/day × 4.3 + 1 daily wish ≈ **5.3 pulls/day**; dedicated = 3 h/day ≈ **13.9 pulls/day**.

| Player | First new class | Summoner | All 7 classes |
|---|---|---|---|
| Casual F2P (1 h/day) | day 1–2 | ~day 6 | ~day 15 avg, **day 19 at worst** |
| Dedicated F2P (3 h/day) | day 1 | ~day 2–3 | ~day 6, day 8 at worst |
| Casual + one 25-pack (525 R$) | day 1 | ~day 2 | ~day 11 avg |
| Casual + 100-pack (1,799 R$) | day 1 | day 1 | day 1 (≤100 pulls guaranteed with the 3 starting + daily) |

That is about three weeks for a casual free player to own everything, a reasonable target for a 12-class roguelite whose classes are its content. If retention data shows players finishing too early, raise the Starlight cost from 100 to 120 before touching drop rates. Changing drop rates also affects the cosmetic banners.

## 8. Exploit prevention (implemented)

- **Server-authoritative:** the client only asks ("summon ×10 on this banner"). Ticket costs, rolls, pity, grants and saving all happen on the server. Drops come from `Humanoid.Died` on the server and never from a client event.
- **Ownership is checked on the server** in `ClassManager` (screen pick, campfire `SetClass`, and `Enter`, which covers the tutorial, respawn and dev paths). The client's lock display is cosmetic only.
- **No farming of free adds:** summoned minions, boss adds, horde spawns and tutorial runs drop nothing. There is a per-player hourly cap of 15 drops, and kill credit needs the player within 120 studs.
- **Double-pull protection:** a per-player `busy` lock; requests with an unknown count fall back to a single.
- **Receipts:** `ProcessReceipt` is idempotent by `PurchaseId`, which is saved before `PurchaseGranted` is returned. If the save fails it returns `NotProcessedYet` so Roblox retries. A class bought after it was already pulled gives its duplicate Essence instead.
- **PolicyService:** players with `ArePaidRandomItemsRestricted` can't buy ticket packs (the button is replaced with a notice). Earned tickets, and direct non-random class purchases, still work.
- **Odds disclosure:** the Rates & Pity panel shows per-item odds, all pity rules, the featured rotation, duplicate values and milestones. The Shop shows the drop rates. It is all generated from the config.
- **Recommended next:** switch `PlayerData.Save` from `SetAsync` to `UpdateAsync` with a session lock. Today, two servers loading the same profile within seconds of each other can overwrite each other. That is rare, but it is the remaining duplication risk.

## 9. Existing saves (grandfathering)

On first load after this change (`stats.classInit`):

1. Every profile gets the five starters.
2. A profile that existed before (it had `gachaInit`) also keeps **every class it had invested in**: an Awakened character for it, or any talent spent in it. Those players clearly played those classes.
3. Old profiles get a **10-ticket gift**.
4. Any **Crystals are converted to Pull Tickets** at 300 : 1, rounded up. Set bonuses that paid crystals now pay tickets.
5. `FREE_SUMMONS` is now **false**, so summons on all banners cost tickets.

## 10. Long-term systems (status)

| System | Status |
|---|---|
| Collection sets ("Every Soul Answers": all classes → 500 Essence) | built |
| Altar milestones | built |
| Summon history (last 50, with banner and time) | built (summon page → History tab) |
| Visible pity counters (Epic / Legendary / Mythic / Starlight) | built |
| Rarity-dependent reveal, Mythic reveal, skip | existing `ConstellationWish` cinematic (has SKIP); the class reward shows its hero (`RewardPreview`) |
| Class Codex, class mastery, daily/weekly challenges, achievements | not built. Recommended next: daily challenges paying 1–2 tickets (≈+30% F2P income) are the cleanest retention lever |
| Dark-fantasy altar in the lobby, rune circle, silhouette reveal, class intro | not built: the summon page is still the existing Sanctum UI |

## 11. Final recommendation

Ship this as is, with Starlight at 100 as the public promise ("every class within 100 summons, guaranteed"). It is generous, easy to explain, and keeps the class economy clearly fair, which matters on Roblox where most players are young and PolicyService rules apply. Make money from cosmetics, and build Essence sinks before launch so duplicates stay meaningful. After a week of live data, compare `ticketDrops` per hour with the 4.3 estimate and adjust `TicketDrops` first.
