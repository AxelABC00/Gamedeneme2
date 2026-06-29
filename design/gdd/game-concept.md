# Game Concept: Bloombots (working title)

*Created: 2026-06-29*
*Status: Draft*

---

## Elevator Pitch

> It's a cozy mobile field-tending game where you tap to scatter little autonomous
> seed-bots that till, plant, water, and harvest on their own — and you keep a
> living field thriving by placing them well. Like a calm automation toy, AND ALSO
> a gentle placement puzzle where neglect has small, fair, recoverable costs.

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | Cozy idle / gentle placement-optimization sim |
| **Platform** | Mobile (iOS / Android), portrait, one-thumb |
| **Target Audience** | Casual cozy & idle players + light optimizers (see Player Profile) |
| **Player Count** | Single-player |
| **Session Length** | 2–10 min active bursts + idle accrual between sessions |
| **Monetization** | None yet (premium or non-aggressive cosmetics later; no energy walls, no forced ads) |
| **Estimated Scope** | Small–Medium (2–4 months, solo, first game) |
| **Comparable Titles** | Mini Motorways, Dorfromantik (cozy placement); idle farm games (Egg Inc.-style accrual) |

---

## Core Fantasy

You are the calm orchestrator of a tiny living field. You don't toil — you place
clever little robots and watch life unfold. The fantasy is **gentle mastery
without stress**: the quiet satisfaction of arranging a system that hums along on
its own, where your good decisions are visibly rewarded and the field keeps
breathing whether you're watching or not.

---

## Unique Hook

You never farm directly — **you orchestrate autonomous seed-bots**, each tending
its own surroundings, and the game is the gentle art of placing them so the whole
field stays alive. It's like a cozy automation toy, **AND ALSO** a low-stress
placement puzzle where ignoring a corner of your field has a small, fair,
recoverable cost — so your choices matter without ever punishing you with a
"game over."

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Submission** (relaxation, comfort) | 1 | Low-stress loop, idle accrual, no timers, ambient life |
| **Sensation** (sensory pleasure) | 2 | Soft "pop"/glow/sound on placement & harvest; everything gently breathes |
| **Challenge** (gentle mastery) | 3 | Optional optimization depth; small fair cost for neglect |
| **Expression** (self-expression) | 4 | How you arrange and shape your field over time |
| **Discovery** (exploration) | 5 | Unlocking new bot/crop types; field expansion |
| **Fantasy** | N/A | Light — "calm caretaker of a living field" |
| **Narrative** | N/A | None in MVP |
| **Fellowship** | N/A | None (single-player) |

### Key Dynamics (Emergent behaviors we want)
- Players experiment with bot placement to maximize coverage without crowding.
- Players develop a personal "rhythm" of checking in, collecting yield, expanding.
- Players take pride in a self-sustaining layout and screenshot/share it.

### Core Mechanics (Systems we build)
1. **Bot placement** — tap empty soil to drop an autonomous seed-bot (costs yield).
2. **Autonomous bot work cycle** — each bot tills → plants → waters → harvests tiles in its range on a loop.
3. **Yield economy** — harvests produce yield, spent to place/upgrade bots and expand the field.
4. **Gentle decay** — neglected tiles dry and crops wilt (small, recoverable loss); bots can run out of energy and pause.
5. **Progression/unlocks** — new bot types, crops, field expansions, light upgrades.

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** | You choose where each bot goes and how the field is shaped | Core |
| **Competence** | Your field visibly grows more efficient as you learn placement | Core |
| **Relatedness** | Light attachment to your bots and your evolving living field | Supporting |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** — gentle progression: unlock bots/crops, expand the field, grow yield.
- [x] **Explorers** — discover efficient layouts and how bot/crop systems interact.
- [ ] **Socializers** — not a focus (single-player).
- [ ] **Killers/Competitors** — explicitly NOT served (no PvP, no leaderboards pressure).

### Flow State Design
- **Onboarding curve**: First tap places a bot that immediately starts working — the loop teaches itself, zero text tutorial.
- **Difficulty scaling**: Field grows slowly; gentle decay introduces light, optional optimization pressure.
- **Feedback clarity**: Color signals health at a glance (vivid green = thriving, desaturated = wilting); yield counter rises visibly.
- **Recovery from failure**: Always fast and local — re-cover a dry tile, re-energize a bot; never a reset, never a block.

---

## Core Loop

### Moment-to-Moment (30 seconds)
Tap empty soil → a seed-bot drops with a soft pop/glow → it begins tilling,
planting, watering, harvesting nearby tiles → small yield droplets float up as it
works. Intrinsically satisfying through tactile feedback and visible life.

### Short-Term (5-15 minutes)
Balance the field: spot a drying/uncovered patch, place or reposition a bot to
cover it, spend accumulated yield to upgrade a bot or unlock the next crop/bot type.

### Session-Level (30-120 minutes)
Across a session the player meaningfully grows the field — covers more ground,
unlocks a new bot type, expands into new soil — and leaves it in a self-sustaining
state. Natural stop: "the field hums on its own now." Reason to return: yield
accrues idly and a new unlock is almost affordable.

### Long-Term Progression
Over days: roster of bot types, variety of crops, field expansions, and light
automation/efficiency upgrades. Long-term goal: a sprawling, beautiful,
self-sustaining living field that reflects the player's style.

### Retention Hooks
- **Curiosity**: Next bot/crop type to unlock; what a bigger field looks like.
- **Investment**: A field you've shaped and don't want to neglect; idle yield waiting to be collected.
- **Mastery**: Tuning placement for ever-more-efficient, ever-greener fields.

---

## Game Pillars

### Pillar 1: Sakin ama Adil (Calm but Fair)
The game relaxes, but your choices matter — neglect carries a **small, fair, and
recoverable** cost (a wilted crop = a missed harvest), never stress.

*Design test*: Does a penalty teach or frustrate? → Choose the penalty that
teaches and can be recovered quickly; never one that permanently locks progress.

### Pillar 2: Tek Parmak, Sıfır Öğretici (One Thumb, Zero Tutorial)
Everything is understandable with a single tap and no written explanation.

*Design test*: Does an interaction require a second finger, a menu dive, or a
tutorial? → Cut it or simplify until it doesn't.

### Pillar 3: Sakin Optimizasyon (Gentle Mastery)
Players build a more efficient field by thinking, not by being stressed; mastery
is visible but optional.

*Design test*: Depth or simplicity? → Choose "optional depth" — the expert
notices it, the newcomer never trips over it.

### Pillar 4: Yaşayan Tarla (Living Field)
Bots and crops live on their own; the field breathes even when the player isn't
acting (idle-friendly).

*Design test*: Does a system give living visual feedback without player input? →
If not, animate it.

### Anti-Pillars (What This Game Is NOT)

- **NOT a game with a "game over" / run-ending loss**: penalties stay local and recoverable — it would compromise *Sakin ama Adil*.
- **NOT a game with permanent or unfair punishment that locks progress**: would break the trust *Sakin ama Adil* depends on.
- **NOT a game with time pressure, countdowns, or rush mechanics**: cost comes from neglect, not from a clock — it would compromise *Sakin Optimizasyon*.
- **NOT a game with complex menus or micromanagement**: would compromise *Tek Parmak, Sıfır Öğretici*.
- **NOT a game with aggressive monetization** (forced ads, energy wait-walls, pay-to-win): would compromise calm and player trust.

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| Mini Motorways | Cozy placement-optimization with gentle pressure | Autonomous agents do the work; farming theme; no failure state | Validates calm optimization on mobile |
| Dorfromantik | Relaxing, screenshot-worthy tile placement | Living, self-acting field rather than static tiles | Validates cozy placement broad appeal |
| Idle farm games (e.g. Egg Inc.) | Idle accrual + satisfying automation growth | Tactile single-mechanic depth, no aggressive monetization | Validates idle accrual retention |

**Non-game inspirations**: Watching ants/bees work, a windowsill garden swaying,
ASMR "satisfying machine" videos, the calm of tending something that mostly tends itself.

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 16–45, broad |
| **Gaming experience** | Casual to mid-core |
| **Time availability** | Short frequent sessions (commute, breaks) + idle check-ins |
| **Platform preference** | Mobile (phone, portrait, one hand) |
| **Current games they play** | Mini Motorways, Stardew Valley (mobile), cozy/idle titles, Two Dots |
| **What they're looking for** | A calming, low-pressure game that still rewards thought |
| **What would turn them away** | Stress, timers, tutorials, paywalls, fail screens |

---

## Visual Identity Anchor

The seed of the art bible — the look decided before it can be forgotten.

- **Direction**: **"Sıcak Defter" (Warm Storybook)** — flat, hand-drawn, rounded shapes; cozy and tactile.
- **One-line visual rule**: *"Her şey nazikçe nefes alır"* — everything gently breathes/moves (reinforces the *Living Field* pillar).

**Supporting principles & design tests**
1. **Yuvarlak ve yumuşak (round & soft)**: no sharp/threatening edges. *Test*: Is a shape sharp or aggressive? → Round it.
2. **Sıcak toprak + tek canlı yeşil (warm earth + one living green)**: low-saturation warm palette; vivid green = health, desaturation = wilt. *Test*: Can the player read field health at a glance from color alone?
3. **Sürekli hafif hareket (constant gentle motion)**: bots, crops, and light always subtly move — idle still looks alive. *Test*: Is anything on screen perfectly still for 5 seconds? → Animate it.

**Color philosophy**: warm, muted earth tones as the base; a single vivid life-green
as the signal of health and growth; wilting reads as that green draining away.

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | **Godot 4.3** (developer preference; excellent for 2D, free, clean Android/iOS export, lightweight for a first game) |
| **Key Technical Challenges** | Many autonomous bots ticking efficiently; offline/idle accrual math; touch placement feel; save/load |
| **Art Style** | 2D, flat hand-drawn / storybook, rounded |
| **Art Pipeline Complexity** | Low–Medium (custom 2D, simple shapes + gentle animation) |
| **Audio Needs** | Moderate — soft ambient music + tactile SFX (place, harvest, water) |
| **Networking** | None |
| **Content Volume** | MVP: 1 field, 1 bot, 1 crop. Target: 3–4 bot types, 3–4 crops, field expansion, light upgrades |
| **Procedural Systems** | Minimal — possibly procedural field layout/expansion later |

---

## Risks and Open Questions

### Design Risks
- The core loop may feel aimless without enough gentle pressure — balance the decay/cost carefully (the "small punishment" must teach, not nag).
- "Calm" vs "optimization" tension: too much depth breaks calm; too little makes it boring.

### Technical Risks
- Performance with many bots ticking simultaneously on mobile (mitigate: simple per-bot state machine, batched ticks).
- Idle/offline accrual correctness (mitigate: timestamp-based simulation on resume).

### Market Risks
- Cozy/idle is popular but crowded — the autonomous-bot orchestration hook must read clearly in store screenshots.

### Scope Risks
- First game: feature creep into "more bot types / systems." Anti-pillars + tight MVP guard against this.

### Open Questions
- Is the bot-orchestration loop fun in isolation? → Resolve with `/prototype`.
- What's the right decay rate so neglect stings but never frustrates? → Tune in prototype/playtest.
- Grid-based field vs free placement? → Decide in prototype (leaning grid for clarity + one-thumb).

---

## MVP Definition

**Core hypothesis**: "Placing autonomous seed-bots to keep a living field thriving —
with a small, fair cost for neglect — is satisfying and relaxing on its own."

**Required for MVP**:
1. A single field (one screen, grid of soil tiles).
2. One bot type that performs the full cycle (till → plant → water → harvest) in its range.
3. One crop + yield resource; yield spent to place more bots.
4. Gentle decay: tiles dry / crops wilt if untended (small recoverable loss).
5. Soft placement & harvest feedback (pop / glow / sound).
6. Basic idle accrual (bots keep working; collect on return).

**Explicitly NOT in MVP** (defer):
- Multiple bot/crop types, field expansion, upgrades, unlocks tree.
- Cosmetics, seasons, narrative, cloud save, monetization.

### Scope Tiers (if budget/time shrinks)

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | 1 field, 1 bot, 1 crop | Core loop + gentle decay + idle accrual | ~2–3 weeks |
| **Vertical Slice** | 1 polished field | Core + 2–3 bot types + 1 unlock + audio + save | ~3–4 weeks |
| **Alpha** | Full field + expansion | All bot/crop types, upgrades, progression (rough) | ~4–6 weeks |
| **Full Vision** | Complete, polished | All features, polish, store-ready Android/iOS build | ~2–4 months total |

---

## Next Steps

- [ ] Fill in CLAUDE.md technology stack — `/setup-engine` (pin Godot 4.3)
- [ ] Establish visual identity — `/art-bible` (build on the Visual Identity Anchor above)
- [ ] **Prototype the core loop** — `/prototype bot-orchestration` (validate fun before GDDs)
- [ ] If prototype PROCEEDS: decompose into systems — `/map-systems`
- [ ] Author per-system GDDs — `/design-system [system]`
- [ ] Validate core loop with playtest — `/playtest-report`
- [ ] Plan first milestone — `/sprint-plan new`
