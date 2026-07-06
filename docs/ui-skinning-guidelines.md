# UI Skinning Guidelines

How to build a folder-based UI skin: the judgement popups (rating images), the "combo" word, combo
numbers, and the ready/set/go countdown, plus how they animate and where they sit on screen.

This is the UI-skin sibling of [note-skinning-guidelines.md](note-skinning-guidelines.md) (which
covers notes/strums/holds instead). The two are completely unrelated systems -- a UI skin has no
note art, and a note skin has no judgement popups -- but they share the same `.tcfg` config format
and folder-discovery rules.

---

## Quick start

1. Make a folder: `assets/shared/images/uiSkins/<YourSkin>/` (or, in a mod,
   `mods/<YourMod>/images/uiSkins/<YourSkin>/`).
2. Drop in your rating images and a skin config:
   ```
   sick.png
   good.png
   bad.png
   shit.png
   skin.tcfg
   ```
3. `skin.tcfg` (tabs or spaces for indentation, don't mix within one block):
   ```
   ratings:
       sick: sick
       good: good
       bad: bad
       shit: shit
   ```
4. Pick it in **Options > UI Skin**.

That's a valid skin covering just the rating popups. Everything else (combo word, numbers,
countdown, tween motion, placement, custom visual tiers) is optional and documented below. Any
element you don't provide falls back to the base engine's `stageUI` assets, so a partial skin is
completely fine.

---

## What a UI skin covers (and doesn't)

| Covered | Not covered |
|---|---|
| Rating popup images (sick/good/bad/shit, or custom names) | Note, strum, hold, splash art (that's a note skin) |
| The "combo" word image | Health bar / icons |
| Combo number digit images (0-9) | Score/misses text |
| Ready / Set / Go countdown images | Pause menu, freeplay, or any other UI screen |
| Popup animation (velocity, gravity, ease, duration) | |
| Popup screen placement (per-element position, number spacing) | |
| Optional custom visual rating tiers by hit-time window | |

---

## Canvas & sprite size guidelines

These are the actual dimensions of the bundled Default skin's assets, given as a guideline -- the
engine does not enforce any canvas size, and every element scales independently via `tween.*.scale`
at runtime regardless of its source resolution.

| Asset | Reference size (Default skin) | Notes |
|---|---|---|
| Rating popups (`sick`/`good`/`bad`/`shit`) | roughly 260-400px wide, 125-165px tall | Wider ratings ("sick", "shit") need more horizontal canvas than short ones ("good", "bad"); keep each rating's own art internally consistent in visual weight/scale. |
| Combo word | ~340x140 | One image; there's no per-frame combo animation, just the tween. |
| Combo number digits (`num0`-`num9`) | ~95x120 each | Ship all ten as separate files sharing one prefix (see [images](#images) below); keep every digit the same canvas size so `numSpacing` lines them up evenly. |
| Ready / Set / Go | ~560-760px wide, 320-430px tall | These are usually the biggest assets in the skin since they're shown large and briefly at song start. |

All images support the same `@2x` HD convention as note skins (ship `combo@2x.png` alongside or
instead of `combo.png` and the engine downscales it automatically) and the same `pixel/` subfolder /
`-pixel` suffix convention for pixel-art stages.

---

## The `skin.tcfg` format

Same lexer/rules as note skins: indentation defines nesting (tabs or spaces, don't mix within a
block), `key: value` is a leaf, `key:` with indented children is a group, `#`/`###` start comments,
values parse as Bool/Array/number/String automatically, and a plain `.json` file with matching field
names works as a fallback (`skin.json`, checked after `.tcfg`).

Two references ship with the engine:
[`assets/shared/images/uiSkins/Default/skin.tcfg`](../assets/shared/images/uiSkins/Default/skin.tcfg)
(the real Default skin, reproducing vanilla behavior exactly) and
[`assets/shared/images/uiSkins/Default/skin.example.tcfg`](../assets/shared/images/uiSkins/Default/skin.example.tcfg)
(every field, fully commented). This document walks through that same reference in prose.

### `images`

Flat keys, no per-lane targeting (there are no "lanes" in a UI skin):

| Field | Default | Resolves to |
|---|---|---|
| `combo` | `combo` | `<key>.png` -- the "combo" word |
| `num` | `num` | a **prefix**: `<key>0.png` .. `<key>9.png`, one file per digit |
| `ready` | `ready` | `<key>.png` |
| `set` | `set` | `<key>.png` |
| `go` | `go` | `<key>.png` |

```
images:
	combo: combo
	num: num
	ready: ready
	set: set
	go: go
```

You only need to declare a field if you're renaming the underlying file from its default; omitting
`images` entirely and just shipping files named `combo.png`/`num0.png`/.../`ready.png`/`set.png`/
`go.png` works with no config at all.

### `general`

| Field | Type | Default | Meaning |
|---|---|---|---|
| `antialiasing` | Bool | `true` | Smoothing for non-pixel art. |
| `pixel` | Bool | `false` | Force this skin to always render as pixel art (no smoothing, pixel-stage sizing rules). |
| `pixelVariant` | Bool | `false` | Auto-select this skin (and its `pixel/` art) whenever a pixel-art stage is active, mirroring the note-skin behavior. |
| `pixelScale` | Float | falls back to plain scale | Size multiplier used only while rendering as pixel art. |

There is no general "scale" field -- popup *size* is controlled per-element under `tween` (see
below), not here.

### `ratings`

Maps each **real** rating name (from the game's hit-timing windows: `sick`, `good`, `bad`, `shit`)
to an image key. Almost always identity (`sick: sick`), but lets you rename the backing files or
point two rating names at the same image:

```
ratings:
	sick: sick
	good: good
	bad: bad
	shit: shit
```

### `tween`

Controls how every popup (rating / combo / numbers) animates: an initial upward velocity, gravity
pulling it back down, a fade duration and easing curve, and its display scale. Global values under
`tween` apply to all three elements; the `rating`, `combo`, and `numbers` sub-blocks override
per-element.

| Field | Where | Type | Meaning |
|---|---|---|---|
| `duration` | global or per-element | Float (seconds) | Alpha fade-out time. |
| `ease` | global or per-element | String | Easing curve name for the fade (see the list below). |
| `velocityY` | per-element | Float or `[min, max]` | Initial upward speed; a range picks a random value per popup, like vanilla's slight variation. |
| `velocityX` | per-element | Float or `[min, max]` | Initial horizontal drift. |
| `accelY` | per-element | Float or `[min, max]` | Downward gravity pulling the popup back down over its lifetime. |
| `scale` | per-element | Float | Display size multiplier for that element. |
| `startDelay` | per-element | Float (seconds) | Delay before the fade begins. Leave unset to stay beat-relative (synced to the song's BPM) instead of a fixed time. |

Recognized `ease` values: `linear`, `quadIn`/`quadOut`/`quadInOut`, `cubeIn`/`cubeOut`/`cubeInOut`,
`sineIn`/`sineOut`/`sineInOut`, `expoIn`/`expoOut`/`expoInOut`, `backIn`/`backOut`/`backInOut`,
`elasticIn`/`elasticOut`/`elasticInOut`, `bounceIn`/`bounceOut`/`bounceInOut` (case-insensitive).

```
tween:
	duration: 0.2
	ease: linear
	rating:
		velocityY: [140, 175]
		velocityX: [0, 10]
		accelY: 550
		scale: 0.7
	combo:
		velocityY: [140, 160]
		velocityX: [1, 10]
		accelY: [200, 300]
		scale: 0.7
	numbers:
		velocityY: [140, 160]
		velocityX: [-5, 5]
		accelY: [200, 300]
		scale: 0.5
```

### `placement`

Every popup's on-screen position, all in one place -- the engine contributes no positioning
constants of its own beyond these defaults:

| Field | Meaning |
|---|---|
| `anchorX` | The popups' centre column, as a fraction of screen width (`0.35` = 35% from the left, the vanilla position). |
| `numSpacing` | Pixel gap between combo-number digits. |
| `rating` | `[x, y]` offset of the rating image from the anchor / screen centre. |
| `combo` | `[x, y]` offset of the combo word. |
| `numbers` | `[x, y]` offset of the combo-number block. |

```
placement:
	anchorX: 0.35
	numSpacing: 43
	rating: [-40, -60]
	combo: [50, 60]
	numbers: [-90, 80]
```

Omitting `placement` entirely uses these exact vanilla values, so you only need to declare the
fields you're actually moving. The in-engine UI Skin editor exposes draggable hitboxes for every
element that write these numbers out for you -- easier than hand-tuning offsets blind.

### `judgements` (optional custom visual tiers)

Lets you show a different image for an *especially* tight hit, purely as a visual flourish -- it
never changes scoring or combo, which always come from the real hit-timing windows. Each tier is
named freely and needs its own image in the skin folder:

```
judgements:
	perfect:
		image: perfect
		window: 22.5
```

| Field | Required | Meaning |
|---|---|---|
| `image` | no (defaults to the tier's name) | image key to show |
| `window` | yes | this tier is used when `abs(hit timing ms) <= window` |
| `sound` | no | optional hitsound override for this tier |
| `splash` | no | optional note-splash override |
| `antialias` | no | per-tier antialiasing override |
| `scale` | no | per-tier scale override |

Multiple tiers are checked tightest-window-first, so a `perfect` tier at `22.5` ms only shows for
hits at least that precise, and anything looser falls through to the real rating's normal image.
This is entirely additive -- a skin with no `judgements` block behaves exactly like vanilla's four
ratings.

---

## Testing your skin

- Select it in **Options > UI Skin** and play a song; hit some notes at different accuracy to see
  every rating tier.
- If you're tuning `placement`, use the in-engine UI Skin editor's draggable hitboxes rather than
  guessing offsets -- it writes the same fields this document describes.
- Toggle a pixel-art stage while testing if you ship `pixel`/`pixelVariant` art, since that's a
  separate code path from the normal HD art.
- An omitted field always falls back cleanly (to the vanilla default, or to the base engine's
  `stageUI` assets for a missing image) -- there's no need to declare fields you're not changing.
