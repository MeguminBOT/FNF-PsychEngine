# Note Skinning Guidelines

How to build a folder-based note skin: canvas sizes, file naming, and the full `skin.tcfg` format.

This is the note-skin sibling of [ui-skinning-guidelines.md](ui-skinning-guidelines.md) (which
covers judgement popups / combo / countdown instead). The two are unrelated systems that happen to
share the same config format and discovery rules.

---

## Quick start

1. Make a folder: `assets/shared/images/noteSkins/<YourSkin>/` (or, in a mod,
   `mods/<YourMod>/images/noteSkins/<YourSkin>/`).
2. Drop in at least a note, a strum, and a skin config:
   ```
   noteArrow.png
   strumArrow.png
   skin.tcfg
   ```
3. `skin.tcfg` (tabs or spaces for indentation, don't mix within one block):
   ```
   images:
       notes:
           arrow: noteArrow
       strums:
           arrow: strumArrow

   general:
       scale: 0.7
   ```
4. Pick it in **Options > Note Skin**, or set `"arrowSkin": "YourSkin"` in a chart's metadata.

That's a complete, valid skin. Everything below is what you can add on top of it: pressed/confirm
frames, hold sustains, splashes, per-lane art, per-keycount overrides, animation, and recoloring.

---

## Canvas & sprite size guidelines

All sizes below are in the **1x reference frame: one lane cell = 160x160 pixels**. Design your art
as if the engine rendered a lane at 160px wide with no scaling -- that's the frame every bundled
skin (and the classic pre-folder assets) is authored in. The engine then shrinks everything down
per key count at render time; you never account for that in your art, you just keep `scale: 0.7`
in your `skin.tcfg` (the default) and it lines up. The [runtime scaling](#how-the-engine-scales-your-art-at-runtime)
section below explains where the 0.7 comes from.

"Canvas" is the full image size (what you'd see in your art program); "sprite" is the drawn art
inside it -- leave a few pixels of breathing room rather than running art edge-to-edge.

| Asset | Canvas (max) | Sprite (recommended) | Notes |
|---|---|---|---|
| Strum / Receptor | 160x160 | ~156px wide | The static receptor at the top of the lane. |
| Note | 160x160 | matches the strum | The falling note head. |
| Pressed | 160x160 | ~152px wide, slightly smaller than the strum | Animated 1-3 frames; plays while the key is held with no note under it, for a "keydown" feel. |
| Confirm | 256x256 | varies (depends on glow/burst effects) | Animated 1-3 frames, starting slightly *bigger* than the strum and shrinking down to strum size on the last frame. |
| Hold body | 160px wide | 50px-146px wide, any height | The engine stretches/squashes this vertically as needed, so height doesn't need to match anything. |
| Hold end (tail) | same as hold body | same as hold body | Optional; skip it if your hold body already tapers off cleanly. |
| Note splash | independent of note size | your call | See [Splashes](#splashes) below; splashes have their own `splashScale`. |

For a concrete reference, the bundled Default skin's actual files (trimmed to content, which is why
they're a touch under the canvas numbers): `noteArrow.png`/`strumArrow.png` 157x154,
`pressArrow1.png` 152x148, `confirmArrow1.png` 256x256, `holdBody.png` 50x20, `holdEnd.png` 50x22.

All of the above support animation and the in-engine RGB recolor shader (see
[Recoloring](#recoloring--colorable)) regardless of size.

### How the engine scales your art at runtime

Two numbers multiply together, and they're calibrated so the 160px reference frame "just works":

- **Lane spacing** is `160 x` a per-keycount factor (`Mania.noteSizes`): 1K `0.9`, 2K `0.85`,
  3K `0.8`, **4K `0.7`**, 5K `0.66`, 6K `0.6`, 7K `0.5`, 8K `0.42`, 9K `0.36`. So a 4K lane is
  actually 112px wide on screen, a 9K lane ~58px.
- **Your art's scale** is `skin.tcfg`'s `scale` multiplied by that same keycount factor relative to
  4K. With the default `scale: 0.7`, art authored at 160px renders at exactly 112px in 4K --
  filling the lane -- and shrinks in step with the lanes on higher key counts automatically.

In other words: with `scale: 0.7`, **on-screen size = your authored size x the keycount factor**.
You draw once at 1x (the 160 frame) and every key count comes out right.

If you'd rather author at a different canvas size (say, 320px art), just compensate in `scale` so
`canvas x scale = 112` at 4K (320 x 0.35). Either way, stay consistent across the whole skin:
`scale` (and `pixelScale` for the pixel-art variant) is one number per element at most, never
per-frame -- you can't mix "some frames pre-scaled, some not" within one element.

### Pivot points and centering (if you animate in Adobe Animate / Flash-style tools)

If you draw your skin as a symbol animation (Adobe Animate, or anything that exports a
Sparrow/Starling atlas) rather than hand-placed frame PNGs, keep every frame of one element on the
**same pivot**, or the sprite will visibly drift as it plays.

`art/flashFiles/Fixed Note Assets/` in this repo holds the `.fla` project sources and atlas exports
behind the bundled note art. A real export from there
(`multikey-repack-adobeanimate.xml` -- it feeds the classic multikey atlas rather than a folder
skin, but it's authored in the same 160px reference frame as everything above) shows the pattern:

| Frame | Trimmed size | Pivot | Reading |
|---|---|---|---|
| `noteArrow0000` | 157x157 | (78.5, 78.5) | Dead centre of the frame -- notes/strums are single, unanimated frames. |
| `strumArrow0000` | 157x157 | (78.5, 78.5) | Same canvas and pivot as the note, so scale/rotation math lines up between them. |
| `pressArrow0000..0003` | 157x157 | (78.5, 78.5) on frame 0 | Same size and pivot as the strum across all 4 frames -- nothing shifts as it plays. |
| `confirmArrow0000..0003` | 222x222 (in a 228x228 padded canvas) | (112.55, 112.55) | Bigger canvas than the note (the "grows in, settles down" burst), but still centred consistently frame to frame. |
| `holdBody0000` | 50x20 | (0, 0) | Sustains pivot top-left, not centred -- the engine stretches/tiles this along the lane, it never rotates in place like a note does. |
| `holdEnd0000` | 50x22 | (0, 0) | Same top-left pivot as the body. |

The takeaway: pick one canvas size per element, centre every animated frame of that element
identically (top-left for hold body/tail, dead-centre for everything that rotates), and only change
canvas size *between* elements (e.g. confirm bigger than note), never *within* one element's frame
sequence.

### HD (`@2x`) assets

Ship any image at double resolution and suffix the filename with `@2x` (e.g. `noteArrow@2x.png`
alongside, or instead of, `noteArrow.png`). The engine detects `@2x` files automatically and
downscales them by half at load time, the same convention osu! skins use. You don't need to declare
this anywhere in `skin.tcfg` -- it's picked up per-file.

For animation sequences, `@2x` goes **after the frame number**, at the very end of the filename:
`confirmArrow1@2x.png`, `splash0001@2x.png` -- never `confirmArrow@2x1.png`. It also stacks last
when combined with the `-pixel` suffix: `confirmArrow1-pixel@2x.png`.

### Pixel-art variants

A skin can ship a second, pixel-art version of its assets for use on pixel-art stages. Two ways to
provide it, checked in this order:

1. A `pixel/` subfolder mirroring the same file names (`pixel/noteArrow.png`).
2. A `-pixel` suffix on the file itself (`noteArrow-pixel.png`).

Set `pixelVariant: true` under `general` so the game **automatically** switches to your skin (and
its pixel art) whenever a pixel-art stage is active, even if the player's selected skin is something
else. Use `pixel: true` instead if the skin should *always* render as pixel art regardless of stage.
Pixel art usually needs a bigger on-screen zoom than HD art -- that's what `pixelScale` (see
[`general`](#general)) is for.

---

## File naming: single image vs. animation sequence

Every image reference in `skin.tcfg` (e.g. `noteArrow`) is a **key**, not a literal filename with
extension. The engine resolves a key to actual files in this order:

1. **A single image**: `<key>.png` (or `<key>@2x.png`). Used as-is, one frame.
2. **A numbered sequence**: `<key><sep><N>.png`, where `<sep>` is empty, `-`, or `_`, and `<N>` is
   zero-padded to 1, 2, 3, or 4 digits, starting at index `0` or `1`. The engine tries every
   combination and uses whichever run of files actually exists on disk, e.g. `confirmArrow1.png`,
   `confirmArrow2.png`, `confirmArrow3.png` or `splash0001.png`, `splash0002.png`, ...

You don't declare which case applies -- just name your files consistently and point `skin.tcfg` at
the shared prefix. Whether an element actually plays as an animation (vs. holding frame 1) is
controlled separately by the `animated` group (see below); a sequence with `animated: false` just
displays its first frame.

---

## The `skin.tcfg` format

`.tcfg` ("tabbed config") is the primary format; a plain `.json` file with the same field names also
works as a fallback (`skin.json`, matching the internal shape 1:1) if you'd rather write JSON.
`skin.tcfg` is checked first.

Rules:
- Indentation defines nesting. Use tabs *or* spaces, but don't mix them within one block.
- `key: value` on one line is a leaf (a setting). `key:` with indented lines beneath it is a group.
- Lines starting with `#` (or `###`) are comments; blank lines are ignored.
- Values: `true`/`false` become booleans, `[a, b]` becomes an array, plain numbers become
  Int/Float, anything else is a string. Quoting a string value (`'...'` or `"..."`) is optional.
- Keys themselves are never quoted.

Two real examples ship with the engine and are the best starting point:
[`assets/shared/images/noteSkins/Default/skin.tcfg`](../assets/shared/images/noteSkins/Default/skin.tcfg)
(a real, working skin) and
[`assets/shared/images/noteSkins/Default/skin.example.tcfg`](../assets/shared/images/noteSkins/Default/skin.example.tcfg)
(every field, fully commented, with a key-count override section). Everything below documents that
same reference in prose.

### Targeting: which lane does a setting apply to?

Most settings can be a single value (applies to every lane) or a per-lane breakdown. When
per-lane, indent special target keys underneath:

| Target key | Meaning |
|---|---|
| `arrow` | Every cardinal lane (left/down/up/right) -- the common case. |
| `center` | The middle lane on an odd key count (1K, 3K, 5K, 7K, 9K). |
| `col<N>` | One specific column, **1-indexed**. `col1` is the first lane. Mutually exclusive with `center` for the same field -- use whichever is more convenient. |

A column's *direction name* (used to resolve `arrow`/`center` and the rotation table) comes from
the chart's key count. For reference, the built-in direction tables by key count are:

| Keys | Lane directions (col1 -> colN) |
|---|---|
| 1K | square |
| 2K | left, right |
| 3K | left, square, right |
| 4K | left, down, up, right |
| 5K | left, down, square, up, right |
| 6K | left, up, right, left, down, right |
| 7K | left, up, right, square, left, down, right |
| 8K | left, down, up, right, left, down, up, right |
| 9K | left, down, up, right, square, left, down, up, right |

("square" is the engine's internal name for a center lane -- it's what `center` targets.)

A bare, non-indented value (`arrow: noteArrow`) applies to every lane that isn't otherwise
overridden. `col<N>` keys win over `arrow`/`center` when both are present for the same lane.

### `images`

Declares the image key for every element. Sub-groups: `notes`, `strums`, `pressed`, `confirm` (each
takes `arrow`/`center`/`col<N>` targets), plus three flat keys: `holdBody`, `holdEnd`, `splash`.

```
images:
	notes:
		arrow: noteArrow
		center: noteCenter
	strums:
		arrow: strumArrow
		center: strumCenter
	pressed:
		arrow: pressArrow
	confirm:
		arrow: confirmArrow
	holdBody: holdBody
	holdEnd: holdEnd
	splash: splash
```

Omitting `pressed`, `confirm`, `holdEnd`, or `splash` entirely is fine -- they're all optional.
A missing `holdEnd` just means sustains have no tail cap; a missing `splash` falls back to the
engine's built-in splash art (or the legacy `noteSplashes/` sparrow atlas, if that's what you
point `splash` at instead of a folder-native key).

### `general`

Flat settings, one level, no per-element sub-groups (per-lane targeting still applies to
individual fields via `arrow`/`center`/`col<N>` where noted):

| Field | Type | Default | Meaning |
|---|---|---|---|
| `rotate` | Bool | `true` | Whether cardinal-lane art gets auto-rotated per `directionAngles`. Set `false` if your art is already pre-drawn facing each direction. |
| `directionAngles` | `[left, down, up, right]` | `[-90, 180, 0, 90]` | Rotation in degrees applied to the base art for each cardinal direction (unused lanes ignored). |
| `columnAngles` | array, indexed by column | unset | Per-column rotation override -- use this when two lanes share a direction name (e.g. both "left" lanes in 6K) but need different angles. |
| `fps` | Int, or per-lane | `24` | Animation playback rate. |
| `scale` | Float, or per-lane | `0.7` | Base note/strum/hold size multiplier. |
| `pixelScale` | Float, or per-lane | falls back to `scale` | Size multiplier used instead of `scale` while rendering as pixel art (low-res pixel art usually wants a bigger zoom). |
| `antialiasing` | Bool, or per-lane | `true` | Smoothing for non-pixel art. |
| `holdAntialiasing` | Bool | `false` | Smoothing specifically for the hold body/tail. |
| `holdAlpha` | Float, or per-lane | `0.5` | Opacity of the hold body while its note is missed/released. |
| `pixel` | Bool | `false` | Force this skin to always render as pixel art. |
| `pixelVariant` | Bool | `false` | Auto-select this skin (and its pixel art) on pixel-art stages. See [Pixel-art variants](#pixel-art-variants). |
| `splashScale` | Float | `1` | Note-splash size multiplier. |
| `splashFps` | Int, or `[min, max]` | `[22, 26]` | Splash animation rate; a `[min, max]` range picks a random rate per splash, matching vanilla's slight variation. |
| `hi-res` | Bool | auto-detected | Informational hint that this skin ships `@2x` assets. `@2x` files are detected regardless of this flag -- it's just documentation for humans reading the file. |

### `animated`

Per-element booleans: `notes`, `strums`, `pressed`, `confirm`, `holdBody`, `holdEnd`. When `false`
(or omitted for an element that's implicitly false), a multi-frame sequence still resolves but only
its first frame is shown -- useful for a skin that ships numbered frames but wants the "note"
element itself static (only `pressed`/`confirm` animating is the common vanilla-like setup).

### `colorable`

Per-element booleans: `notes`, `strums`, `pressed`, `confirm`, `holdBody`, `holdEnd`, `splash`.
Controls whether the engine's RGB recolor shader (the note-color palette players set in Options) is
allowed to tint that element at all. `strums` defaults to `false` (receptors are usually
pre-colored art); everything else defaults to `true`. See [Recoloring](#recoloring--colorable).

### `offsets`

Per-element `[x, y]` pixel nudges: `notes`, `strums`, `holdBody`, `holdEnd`, `splash`. Each accepts
either one `[x, y]` pair for every lane, or a per-lane breakdown (`arrow`/`center`/`col<N>`, each
itself an `[x, y]` pair).

### Key-count sections (per-keycount overrides)

A top-level block named `<N>K` (e.g. `4K:`, `6K:`) is merged **on top of** everything above it, but
only applies when the chart is actually using that many keys. Use it for skins that need genuinely
different art or settings per key count (not just per-lane within one key count):

```
4K:
	images:
		notes:
			col1: noteLEFT
			col2: noteDOWN
			col3: noteUP
			col4: noteRIGHT
	general:
		fps:
			col1: 12
			col2: 24
			col3: 24
			col4: 12
```

A key-count section can contain any of the groups above (`images`, `general`, `animated`,
`colorable`, `offsets`) and only needs to redeclare the fields it's overriding -- everything else
still falls back to the base (non-key-count) config.

> **Warning:** key-count sections are a full override merge per field, not a deep patch of nested
> per-lane objects. If you override `images.notes` inside a `4K:` block, provide all four lanes you
> care about there -- don't expect a `col2` set at the top level to keep applying once `4K.images`
> exists.

---

## Splashes

Point `images.splash` at a key the same way you would a note. The engine looks for it as
folder-native frames first (a single image, `@2x`, `pixel/`, or a numbered sequence, exactly like
every other element); if that resolves, the splash plays as part of your skin, recolored per-lane
via the same palette as notes (unless `colorable.splash: false`). If it *doesn't* resolve as
folder-native frames, `splash` is instead treated as a legacy sparrow-atlas name (packed
`.png`/`.xml`), for skins ported from the pre-folder splash system. Omit `splash` entirely to use
the engine's own default splash art.

`splashScale` and `splashFps` (under `general`) and `splashOffsets` (under `offsets`) tune the
splash independently of note sizing.

---

## Recoloring (`colorable`)

Note art is normally shipped as plain white/greyscale line art, and the engine tints it per-lane at
runtime using the player's note-color palette (an RGB shader, not a swapped texture). This is what
`colorable` controls per element. If your art is already fully colored (e.g. hand-painted, distinct
per-lane images), set that element's `colorable` to `false` so the shader leaves it alone.

Two independent things gate whether an element actually gets tinted in a real game:
1. The skin must allow it (`colorable.<element>: true`).
2. The player must have that element's "Link ... to note color" option enabled (per-element toggles
   in Options: splash / sustain / pressed / confirm / strum). Both must be true; either one being
   false means the element keeps its own fixed color.

When an element is *not* linked (or the skin marked it non-colorable), each note element can still
be given its own **independent per-asset color** through the in-game Note Colors menu -- this is
separate from `skin.tcfg` entirely and is a player-side preference, not something the skin author
sets.

---

## Testing your skin

- Select it in **Options > Note Skin** and play any song, or set `editorOverride` behavior by
  previewing it from the chart editor (the Options tab has a live note-skin/character preview).
- Toggle **Downscroll** and a pixel-art stage while testing, since both exercise different code
  paths (rotation math, and the pixel-art asset resolution respectively).
- If an element silently doesn't show up, check the filename resolution rules above first
  (case-sensitivity, the separator/padding/start-index combinations) before assuming `skin.tcfg` is
  wrong -- a missing file resolves to "no frames," not an error.
