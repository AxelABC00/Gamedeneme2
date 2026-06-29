# Bloombots — Art Bible

> **Status:** Visual Identity Foundation (Sections 1–4) complete. Sections 5–9 (Character Design, Environment, UI/HUD, Asset Standards, Reference Direction) deferred — author with `/art-bible` (Resume) when production needs them.
> **Art Director Sign-Off (AD-ART-BIBLE):** Skipped — Lean review mode.
> **Visual Identity Anchor:** "Sıcak Defter" (Warm Storybook) — *"Her şey nazikçe nefes alır."*

---

## Section 1 — Visual Identity Statement

### Core Visual Rule

> **"Her şey nazikçe nefes alır" — Every element has a gentle pulse. When a choice must be made, choose the option that feels like it is softly exhaling.**

This is the single decision filter for every visual ambiguity in the project. If two approaches are equally valid technically, the one that reads as softer, rounder, warmer, or more alive is correct.

### Supporting Visual Principles

**Principle 1 — Warm Flatness (anchored to: Sakin ama Adil)**

The art style is flat-color illustration with warmth baked into every hue — no stark white, no cold grey, no pure black. Shadows are warm-shifted versions of their base color (never neutral grey). Highlights lean cream, never white. This keeps the emotional register calm even when conveying consequence.

*Design test:* When choosing between a cool-toned and a warm-toned version of any color (outline, shadow, UI tint), always choose the warm-toned version unless a deliberate cool signal is being sent (see Section 4 — wilt state).

**Principle 2 — Readable Silhouettes at Thumb Size (anchored to: Tek Parmak, Sıfır Öğretici)**

Every interactive element — bots, crops, buttons, field tiles — must be legible as a distinct shape at 64×64 logical pixels with no label. If the silhouette is ambiguous, the shape needs redesign before color or detail is added. Complexity lives in the detail layer (optional), never in the silhouette.

*Design test:* When an asset looks unclear at 64×64, do not add an icon or label to compensate — fix the silhouette instead.

**Principle 3 — Purposeful Accent (anchored to: Yaşayan Tarla)**

The single vivid life-green (see Section 4) appears only where life, growth, or player-caused abundance is present. It is never used decoratively. The rule is: if removing the green accent from a scene would make the scene feel equally alive, the green was misplaced. Its sparing use is what gives it semantic power — the field literally "lights up" green as it thrives.

*Design test:* When tempted to add green for visual variety or balance, ask "Is this green earned by growth here?" If not, use a warm neutral instead.

**Principle 4 — Storybook Geometry (anchored to: Sakin Optimizasyon)**

Shapes are clean, slightly rounded, and drawn with the confidence of a picture book illustration — not pixel-art jaggy, not vector-cold-precise. Outlines (where used) are warm-brown, slightly variable in implied weight, never mechanical. The geometry should look like it was drawn with care by a person, then simplified for a screen.

*Design test:* When an element looks too mechanical or too wobbly, reference a children's picture book silhouette for the right level of confident-but-handmade simplicity.

---

## Section 2 — Mood & Atmosphere

### 2a — Tending / Active Placing
*The player is actively scattering bots, making layout decisions.*

| Attribute | Value |
|---|---|
| Primary emotion | Quiet excitement, purposeful agency |
| Energy level | Medium-low — engaged but never urgent |
| Lighting character | Golden-hour afternoon light; warm, low-angle, long soft shadows implied through sprite shading; high warmth, medium contrast |
| Time-of-day direction | Late afternoon — the most nurturing, un-harsh light |
| Atmospheric adjectives | Focused, warm, expectant, settled, purposeful |

The mood here is a gardener deciding where to place the next seed tray — deliberate, gentle, pleasantly absorbed. The palette is at its warmest. Bot placement animations should feel like setting something down softly, not launching or shooting.

### 2b — Idle / Thriving Field
*No immediate player action needed; bots are humming along, crops are growing.*

| Attribute | Value |
|---|---|
| Primary emotion | Contentment, quiet pride, gentle wonder |
| Energy level | Low — restful, with subtle micro-movement |
| Lighting character | Soft midday warmth, slightly diffuse; lower contrast than Tending state; the scene glows rather than casts shadows |
| Time-of-day direction | Midsummer midday, but softened — think overcast-bright, not harsh noon |
| Atmospheric adjectives | Humming, abundant, still, golden, alive |

This is the game's "screensaver" state and must be the most visually rewarding. The life-green is at its fullest saturation here. Gentle idle animations (bots doing small repetitive motions, crops doing a slow sway loop) carry all the life. No UI urgency should intrude.

### 2c — Freshly-Placed Bot Working
*A bot has just been deployed and begins its first work cycle.*

| Attribute | Value |
|---|---|
| Primary emotion | Delight, anticipation, slight whimsy |
| Energy level | Medium — more active than idle, but still light |
| Lighting character | A small warm local highlight on the bot itself; the bot is the focal light source for a moment |
| Time-of-day direction | Inherits the current scene light; the bot itself adds a brief warm twinkle |
| Atmospheric adjectives | Cheerful, industrious, curious, small, earnest |

The newly-placed bot should emit a brief "getting to work" animation — small, looping, characterful. This is the game's main moment of delight delivery. The bot's local warmth should feel like it is waking up and breathing in for the first time.

### 2d — Wilt / Neglect State
*A patch has been untended too long; crops are wilting.*

| Attribute | Value |
|---|---|
| Primary emotion | Gentle melancholy — inviting, not alarming |
| Energy level | Very low — slower, slightly heavier motion |
| Lighting character | Slightly cooler and more desaturated than the healthy state; the warmth is dimmed, not gone; light feels like early overcast morning rather than golden hour |
| Time-of-day direction | Pre-dawn grey-warmth — not night, not cold, just the light before the sun arrives |
| Atmospheric adjectives | Drooping, quiet, waiting, hushed, wistful |

**Critical design mandate:** The wilt state must make the player feel *tenderness*, not anxiety. It should read as a plant waiting for water, not a plant dying. Visual cues are slow droop animations, slightly desaturated (muted) crop colors, and a cooler-shifted version of the earth palette — never red, never pulsing alert colors, never high contrast. The wilt patch should look like it is asking to be tended, not screaming at the player.

No red. No flashing. No harsh outline. See Section 4 for the specific wilt palette and Section 3 for the droop shape cue that backs up the color signal for colorblind safety.

---

## Section 3 — Shape Language

### Bot Silhouette Philosophy

Bots are the game's primary character and must be readable, lovable, and distinct at 64×64 logical pixels — approximately thumb-tip size on a mobile screen. The silhouette rule is: **one dominant readable body shape + one personality-defining feature**.

**Body shape:** Small, rounded-bottom, slightly top-heavy. Think of a rounded seed pod or a smooth river pebble with a head. Flat on the bottom (implies stability and groundedness — these are working bots, not floaty creatures), softly domed on top. The overall silhouette reads as a small friendly creature at a glance, not a machine or a vehicle.

**Personality feature:** One element per bot type that differentiates its role — a small shovel nub for a tilling bot, a watering-can spout for a water bot, a small basket shape for a harvest bot. This feature must be visible at thumbnail size and must not clutter the core silhouette. If covering the personality feature still leaves the bot readable as "a bot," the feature is the right scale.

**Emotional read:** Roundness = safe, friendly, non-threatening. Slightly top-heavy = earnest, trying hard. Flat bottom = grounded, purposeful. The bots should feel like helpful small creatures, not robots. They are machines, but they are *warm* machines. (Anchors to: Yaşayan Tarla — living things, not cold tools.)

**Thumb-size test:** Print the bot silhouette at 64×64 px. Cover color. If the role is identifiable, the shape is correct. If not, the personality feature needs to be larger or bolder.

### Field & Tile Geometry

Field tiles are softly irregular squares — not perfect pixel grid, but not organic blobs either. Imagine a grid drawn by hand on graph paper: straight-ish, with just enough variation to feel natural. Tile edges have a slight warm-brown implied border (not a hard stroke, but a slightly darker edge on the tile color) that reinforces the grid as a readable system without making it feel mechanical.

The grid is the player's canvas for Sakin Optimizasyon — it must read as an inviting space to fill, not a constraint. Slightly rounded tile corners (4–8 px radius equivalent) soften the grid feel.

Tile sizes must be large enough for a bot to be clearly visible inside one tile at 1:1 mobile scale, with enough padding that the bot does not feel cramped.

### Crop Shapes

Crops follow a strict shape vocabulary of three stages, each with a distinct silhouette:

1. **Seed / just planted:** A small rounded nub or sprout shape — barely breaking ground. Very small. Reads as potential.
2. **Growing:** A compact plant shape with 2–3 visible leaf forms. Readable as "a plant" at a glance. Leaves are simple rounded lobes, not detailed.
3. **Ready / harvestable:** Fuller, rounder, slightly taller. The most satisfying shape in the game — the "done" shape should feel visually complete and slightly plump. This is where the life-green accent is most saturated.

Wilted stage: the same three shapes, but drooping — leaves curve downward, the whole form leans slightly. The droop is the primary non-color cue for neglect (see Section 4 colorblind safety). The silhouette change must be unambiguous even in greyscale.

All crop shapes are simple closed forms with no internal line detail at small sizes. Detail (veins, texture) is only added at large showcase sizes, never at gameplay tile scale.

### UI Shape Grammar

UI elements live in the same storybook world as the field — they do NOT use cold modern UI conventions (sharp corners, flat grey panels, thin hairline borders). Instead:

**UI panels:** Warm cream rectangles with slightly rounded corners and a soft warm-brown outline that matches the tile edge treatment. They look like index cards or notebook paper torn from the same storybook.

**Buttons:** Rounded rectangles — more rounded than the panels, emphasizing approachability. The active/tappable state is conveyed by a slight size increase (scale up ~3%) and a warm outline brightening, not by color inversion. This keeps the tapping experience feeling gentle, not mechanical.

**Icons:** Same shape vocabulary as bots and crops — rounded, confident, picture-book line weight. Icons should feel like they belong in the same illustrated world, not imported from a different design system.

**UI sits in the world, not over it.** Where possible, UI elements are diegetic (a bot's status floats above it as a small icon, not in a separate HUD panel). Overlay UI is minimized and when present, uses low opacity warm cream panels so the field remains visible beneath.

(Anchors to: Tek Parmak, Sıfır Öğretici — the world teaches its own rules through consistent shape language; UI and world speak the same visual dialect.)

### Hero Shapes vs Supporting Shapes

| Category | Shape Character | Role |
|---|---|---|
| Bots | Rounded, top-heavy, personality feature | Hero — player's agents, always visually distinct |
| Harvestable crops | Plump, full, saturated | Hero at moment of harvest — peak visual reward |
| Field tiles (empty) | Quiet, slightly textured flat fill | Supporting — canvas, not distraction |
| Field tiles (planted) | Same + small crop shape centered | Supporting, elevated by crop |
| UI panels | Warm, notebook-paper feel | Supporting — frame without competing |
| Decorative elements (fences, path stones) | Small, rounded, low saturation | Background — set dressing only, never competing with bots/crops |

Hero shapes get: crisp silhouettes, the life-green accent when thriving, mild idle animations.
Supporting shapes get: flat or minimal-gradient fills, no animation unless communicating state change, muted palette.

---

## Section 4 — Color System

### Primary Palette

| Swatch Name | Hex | Role & Meaning |
|---|---|---|
| **Toprak** (Soil Brown) | `#7B5B3A` | Primary earth tone. The ground, unpainted tiles, outlines, bot bodies. The game's anchor — everything else reads against this. |
| **Saman** (Warm Straw) | `#F5E6C8` | The "paper" of the storybook. Background sky, UI panel fills, empty field. Warm cream, never white. |
| **Kil** (Clay) | `#C48B5A` | Mid-earth tone. Planted tile state, secondary bot details, warm UI borders. Bridges Toprak and Saman. |
| **Gün Işığı** (Sunlight) | `#F2C46D` | The warmth accent. Harvest reward moments, active bot highlight glow, ripe crop shimmer. Used at key reward beats only. |
| **Yaşam Yeşili** (Life Green) | `#5DBB63` | THE single vivid life accent. Growing crops, thriving field state, harvest-ready indicator. Must remain isolated from other saturated colors so it always reads as "life." |
| **Solgun Çimen** (Faded Grass) | `#A3B899` | Desaturated green for growing-but-not-yet-ripe crops. Transitions toward Yaşam Yeşili as crops mature. Never competes with the hero green. |
| **Alacakaranlık** (Dusk Mauve) | `#9B8EA0` | The single cool-shift accent. Used ONLY in the wilt/neglect state to cool the warmth. A muted lavender-grey — melancholic, not alarming. |

**Palette budget:** 7 colors total. All art is built from these 7 plus their shade/tint variants (multiply or lighten the base colors in the renderer, do not introduce new hues). This keeps the draw-call and texture cost minimal — a small atlas of flat-color shapes is all that is needed.

### Semantic Color Vocabulary

| Signal | Primary Color | Non-Hue Backup |
|---|---|---|
| Growth / life / thriving | Yaşam Yeşili `#5DBB63` | Upright posture, full plump shape, active bot animations |
| Gentle neglect / wilt | Alacakaranlık `#9B8EA0` shift + desaturation of Solgun Çimen | **Droop shape** (leaves curve down), slowed animation speed |
| Bot presence / player's agent | Kil `#C48B5A` body + Toprak `#7B5B3A` outline | Distinctive rounded-top silhouette shape (see Section 3) |
| Player action / tap feedback | Gün Işığı `#F2C46D` brief flash | Scale pulse (element scales up ~5% then returns to normal over 0.2s) |
| Harvest ready | Yaşam Yeşili at maximum saturation + Gün Işığı shimmer | Plump stage-3 crop silhouette (fullest shape in the vocabulary) |
| Empty / untouched tile | Saman `#F5E6C8` tinted with Toprak `#7B5B3A` at low opacity | No animation, no crops visible |
| UI interactive element | Kil outline on Saman fill | Rounded-rectangle shape distinct from world geometry |

### Per-State Color Temperature Rules

| Game State | Color Temperature | Palette Shift |
|---|---|---|
| Tending / Active Placing | Warm (amber-shifted) | All palette colors pushed ~5% warmer; Gün Işığı accent active |
| Idle / Thriving Field | Warm neutral | Palette as defined; Yaşam Yeşili at full saturation across field |
| Freshly-placed bot | Local warm spotlight | Brief Gün Işığı `#F2C46D` radial gradient centered on bot (simple radial, mobile-safe) |
| Wilt / Neglect | Cool (slightly desaturated) | Alacakaranlık bleeds into affected tiles; Yaşam Yeşili replaced by Solgun Çimen on wilted crops; overall tile desaturated ~20% |
| Night mode (if added) | Warm dark | All colors darkened by multiplying with a deep warm-brown overlay; Gün Işığı becomes the key accent on active bots as a soft glow |

Temperature shifts are achieved via a single screen-space color modulate overlay (Godot's `CanvasModulate` node) — one draw call, zero per-pixel shader cost. This is the mobile-safe implementation path.

### UI Palette

The UI uses the same palette as the world with one constraint: **UI elements never use Yaşam Yeşili**. That color is reserved for world-space growth signals only. If UI borrows green (e.g., a "confirm" button), use Solgun Çimen `#A3B899` instead, which reads as "positive" without stealing the vivid life-green's semantic meaning.

| UI Element | Color |
|---|---|
| Panel background | Saman `#F5E6C8` |
| Panel border / outline | Toprak `#7B5B3A` at 60% opacity |
| Primary button fill | Kil `#C48B5A` |
| Primary button text / icon | Saman `#F5E6C8` |
| Secondary / inactive button | Saman fill + Kil outline |
| Tap feedback flash | Gün Işığı `#F2C46D` |
| Positive confirm action | Solgun Çimen `#A3B899` (not Yaşam Yeşili) |
| Destructive / warning action | Alacakaranlık `#9B8EA0` (never red) |

The UI palette is a warm, muted subset of the world palette. It never competes with the field. When a UI panel overlays the field, it uses Saman at 85% opacity so the field remains visible beneath — the player should never feel disconnected from their field, even in menus.

### Colorblind Safety

The game's primary semantic distinction is **healthy vs. wilting**. This must not rely on hue (green vs. not-green) alone.

| Distinction | Hue cue | Backup cues (non-hue, always present) |
|---|---|---|
| Healthy crop vs. wilting crop | Yaşam Yeşili vs. desaturated + Alacakaranlık shift | **Shape:** drooping vs. upright silhouette; **Motion:** wilting crops animate at 50% speed with downward drift; **Brightness:** healthy crops are ~15% brighter than wilted crops in luminance |
| Active bot vs. idle bot | Gün Işığı highlight vs. no highlight | **Motion:** active bots have a working animation loop; idle bots stand still |
| Harvest ready vs. not ready | Yaşam Yeşili peak saturation | **Shape:** stage-3 full/plump silhouette vs. stage-2 smaller silhouette; **Scale:** harvest-ready crops are ~10% larger than growing crops |
| Player tap feedback | Gün Işığı flash | **Motion:** scale pulse; entirely shape/motion-based, hue is secondary |

**Rule:** Every semantic distinction has at least one non-hue backup. The wilt state specifically uses droop + slow motion + brightness drop as three independent non-color signals, any one of which is sufficient to read the state correctly. The game must be fully playable in greyscale for deuteranopia safety.
