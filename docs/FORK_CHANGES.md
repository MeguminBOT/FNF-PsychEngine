# Fork Changes vs. Archived Psych Engine

Baseline: archived-repo commit
[`5c67ced`](https://github.com/ShadowMario/FNF-PsychEngine/commit/5c67ced49e5a98535298a6daa3f8f4ec79ac8399)
("Update gitVersion.txt", 2025-03-24).

This document covers two distinct eras of work, and is split accordingly:

- **[Part 1: Base Engine Fixes](#part-1-base-engine-fixes)** -- `5c67ced..153fe63a`, **179 commits,
  188 files changed, ~20,300 insertions / ~17,800 deletions**. Modernization of the archived engine:
  updated libraries, a rewritten build/setup process, ModSecurity, and a large backlog of crash and
  bug fixes. The goal of this era was compatibility and maintenance, not new features.
- **[Part 2: Fork-Specific Features](#part-2-fork-specific-features)** --
  `153fe63a..HEAD`, **173 commits, 594 files changed, ~56,900 insertions / ~17,100 deletions**. New,
  fork-original systems built on top of the modernized base: the chart editor rewrite, the note/UI
  skin rework, multikey and time-signature support, the osu! beatmap converter, Android support, and
  more.

([source/states/MainMenuState.hx](../source/states/MainMenuState.hx#L16))

---

## Part 1: Base Engine Fixes

## Library swaps and version changes

### Pinned versions

| Library              | Archived (5c67ced) | This fork       | Notes                                                                                          |
| -------------------- | ------------------ | --------------- | ---------------------------------------------------------------------------------------------- |
| `lime`               | 8.1.2              | **8.3.2**       | Minor upgrade                                                                                  |
| `openfl`             | 9.3.3              | **9.5.2**       | Minor upgrade; required source patch in `PsychUIInputText` (see fixes)                         |
| `flixel`             | 5.6.1              | **6.1.2**       | **Major** upgrade                                                                              |
| `flixel-addons`      | 3.2.2              | **4.0.1**       | **Major** upgrade                                                                              |
| `flixel-tools`       | 1.5.1              | 1.5.1           | unchanged                                                                                      |
| `hscript-iris`       | 1.1.3              | **removed**     | Replaced by `hscript-insanity` to gain class-based scripted states                              |
| `hscript-insanity`   | —                  | **git (pinned)**| New: [`inky03/hscript-insanity`](https://github.com/inky03/hscript-insanity); the script interpreter, supports scripting whole classes/states |
| `hscript`            | (transitive)       | 2.7.0           | Still a transitive dep; no longer the script interpreter                                        |
| `tjson`              | 1.4.0              | 1.4.0           | unchanged                                                                                      |
| `hxdiscord_rpc`      | 1.2.4              | **1.3.0**       | Minor upgrade                                                                                  |
| `hxvlc`              | 2.0.1              | **2.2.6**       | Patch upgrades                                                                                 |
| `hxcpp`              | 4.3.2  | **git (HEAD)**  | Switched to git source as release `hxcpp 4.3.2` is very old; built from source in setup        |
| `tink_core`          | (transitive)       | **1.26.0**      | New explicit pin (strict requirement of `grig.audio`)                                          |
| `thx.core`           | (transitive)       | **0.44.0**      | New explicit pin                                                                     |
| `grig.audio`         | git @ [`cbf91e2`](https://gitlab.com/haxe-grig/grig.audio/-/commit/cbf91e2)    | git (HEAD)      | Unpinned                                                                                       |
| `funkin.vis`         | git @ [`22b1ce0`](https://github.com/FunkinCrew/funkVis/commit/22b1ce0)    | git (HEAD)      | Unpinned, then source-patched (see fixes)                                                      |

### Removed / replaced

| Removed                                | Replaced by                                                                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `linc_luajit` (git, pinned `1906c4a`)  | **`hxluajit` + `hxluajit-wrapper`** (git, `MAJigsaw77/hxluajit` and `MAJigsaw77/hxluajit-wrapper`) — commit [`9dffe42`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/9dffe42)                |
| `flxanimate` (git, `Dot-Stuff/flxanimate`) | **`flixel-animate`** (git, [`MaybeMaru/flixel-animate`](https://github.com/MaybeMaru/flixel-animate)) — see [migration notes](MIGRATION_1.0.4_to_1.1.md#flxanimate--flixel-animate-texture-atlas) |

The `<haxedef name="LINC_LUA_RELATIVE_DYNAMIC_LIB"/>` line in
[Project.xml](../Project.xml) was deleted with the Lua swap (hxluajit links
LuaJIT statically).

---

## Build / setup overhaul

- [setup/windows.bat](../setup/windows.bat) and [setup/unix.sh](../setup/unix.sh)
  call `haxelib` directly with pinned versions and `--skip-dependencies`,
  removing any reliance on an external dependency manager.
- **Project-local `.haxelib/` repo on Windows** (`haxelib newrepo`), so the
  engine's dependency set never collides with other Haxe projects on the same
  machine. [art/buildScripts/build_x64.bat](../art/buildScripts/build_x64.bat)
  sets `HAXELIB_PATH=%cd%\.haxelib\` before invoking `lime`. Unix script keeps
  the standard `~/haxelib/`.
- **`hxcpp` is installed from git first**, before any other library, and every
  subsequent `haxelib install` / `haxelib git` call uses `--skip-dependencies`
  so nothing can implicitly pull the old release versions, e.g `hxcpp 4.3.2`.
- A cleanup loop removes any non-`git` `hxcpp` version directory that snuck
  onto disk, then `haxelib set hxcpp git --always` re-pins the active version.
- Setup now runs `haxe compile.hxml` inside `.haxelib/hxcpp/git/tools/hxcpp/`
  to build `hxcpp.n` from source (required after a fresh `haxelib git hxcpp`).
- Setup also applies a `sed` / PowerShell patch to
  `funkin.vis`'s `SpectralAnalyzer.hx` (`makeLogGraph` call) so it matches the
  current `grig.audio` API.
- All `<haxelib>` entries in [Project.xml](../Project.xml) have their
  `version=""` attributes removed — the build uses whatever is currently
  installed/pinned in the active `.haxelib/` repo.
- The original setup also pinned each git dep to a specific commit; the fork
  uses default-branch HEAD instead so any future fixes published to those
  repos flow in.

---

## Project.xml structural changes

- `<haxedef name="LINC_LUA_RELATIVE_DYNAMIC_LIB"/>` removed (Lua swap).
- `TITLE_SCREEN_EASTER_EGG`, `BASE_GAME_FILES`, `VIDEOS_ALLOWED` are no longer
  wrapped in `<section if="officialBuild">` — they are unconditionally defined.
- New `<haxeflag name="--macro" value="macros.PatchIris.patch()" if="MODS_ALLOWED" />`
  reroutes every `Type.resolveClass()` call inside `hscript-iris` through
  `ModSecurity.safeResolveClass` so mod scripts can't import / instantiate
  blocklisted classes (see ModSecurity below).
- `<haxelib>` `version=""` attributes stripped.
- `linc_luajit` haxelib entry replaced with `hxluajit` + `hxluajit-wrapper`.

---
## New feature: Modpack types
Extended pack.json metadata a bit for convenience.
- Two types of packs, defined in pack.json. "Mod pack" or "Script Pack"
  - Script packs run globally and are always accessable through pause menus "Mod Settings".
  - Mod packs run locally with the option to opt in using "runsGlobally" as usual. If a mod pack has settings, it will also show up in pause menus "Mod Settings".

## New feature: ModSecurity
A new mod-script semi-sandboxing system was added across several commits
([`eb8811c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/eb8811c), [`6e8fa50`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6e8fa50), [`95f384e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/95f384e), [`7691e27`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/7691e27), [`a42a83d`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/a42a83d), [`472cb16`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/472cb16), [`8d09b9c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8d09b9c),
[`4ea53b6`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4ea53b6), [`13f80a4`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/13f80a4), [`abc2a27`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/abc2a27)):

- **[source/backend/ModSecurity.hx](../source/backend/ModSecurity.hx)** scans
  every Lua / HScript file in a mod when the mod is enabled.
- Pattern matching covers `os.exit` / `os.getenv` / `os.tmpname` /
  `os.setlocale`, reflection tampering, `runHaxeCode`, `runHaxeFunction`,
  `addHaxeLibrary`, etc., with severity categories.
- Prompts the user once per mod (centered panel UI) to **Trust** or
  **Block** the mod's scripts; the decision persists.
- Per-session MD5 hash cache so unchanged scripts skip rescanning; stamp-based
  fast-skip plus a `decided` flag for trust persistence.
- New per-mod **SEC button** in the Mods menu to review / change trust.
- Compile-time macro `macros.PatchIris.patch()` injects
  `ModSecurity.safeResolveClass` into hscript-iris's class-resolution path. This is to prevent scripts from being able to tamper with `ModSecurity`.
- Configure what should get flagged through Misc options menu.
---

## Bug fixes

Over **80 distinct fixes** in the range — single-purpose commits. Grouped:

### Build / dependency
- [`06c8597`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/06c8597) -- local haxelib repo via `HAXELIB_PATH`; corrected `funkin.vis`
  URL (`FunkinCrew/funkin.vis` 404s → `funkVis`); `tink_core` pinned to 1.26.0.
- [`fff1352`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/fff1352) -- `funkin.vis` `SpectralAnalyzer.hx` patched for current
  `grig.audio` API; `hxcpp` git-tool built in setup.
- [`4992ac7`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4992ac7) -- setup rewritten to use direct `haxelib` calls with pinned
  versions; broken `hxcpp 4.3.2` release prevented from landing.

### Crashes / null safety
- [`dcb466f`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/dcb466f) -- `PsychUIInputText.updateCaret`: clamp `caretIndex` to avoid
  `openfl 9.5.2` `RangeError` from `getLineOffset(-1)` (chart editor crash on
  clicking a different note).
- [`c2d5974`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c2d5974) -- `LoadingState.preloadCharacter`: silently skip when JSON missing.
- [`9b8feec`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/9b8feec) -- `ErrorHandledShader`: stringify Dynamic error before saving crash log.
- [`86522b5`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/86522b5) -- Infinite freeze when a notes-group member is null.
- [`489ed9e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/489ed9e) -- `Note.get_hitsoundVolume` infinite recursion.
- [`c3d2ab6`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c3d2ab6) -- `DialogueBoxPsych` infinite loop on null dialogue entry.
- Null-guards added to `PlayState` (char swap, alt idle), `ModsMenuState`,
  `CreditsState`, `BaseStage`, `RGBPalette`,
  `DialogueBox` / `DialogueCharacter`, `CutsceneHandler`, `NoteOffsetState`,
  `OptionsState`, `Conductor.judgeNote`, `MenuCharacter`, `Character`,
  `MusicPlayer.updatePlaybackTxt`, `OverlayShader`, `StageData`, and several
  Lua reflection callsites.

### Off-by-one / bounds
- [`ef81461`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ef81461) -- `Note.defaultRGB`.
- [`aafd17c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/aafd17c) -- `StrumNote.arrowRGB`.
- [`e55bf76`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e55bf76) -- `Note.initializeGlobalRGBShader` RGB triple bounds.
- [`5f4b7a5`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5f4b7a5) -- `arrowRGB` regression that broke right arrow.

### Mid-iteration mutation bugs
- [`b92b6e9`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/b92b6e9) -- `popUpScore` skipping sprites.
- [`3fa2d2b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/3fa2d2b), [`3fbcfda`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/3fbcfda), [`5b04712`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5b04712) -- `Paths.freeGraphicsFromMemory` /
  `clearStoredMemory` / `clearUnusedMemory` no longer mutate `StringMap`
  mid-iteration.
- [`573ec37`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/573ec37) -- `Achievements.reloadList` same fix.
- [`0c56ab9`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/0c56ab9) -- `PlayState` ghost-note skip from concurrent `unspawnNotes` mutation.

### Lua / HScript runtime
- [`13cf9d1`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/13cf9d1) -- `setSoundPitch` targets music when tag empty; drops double-apply.
- [`066f555`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/066f555) -- `setSoundVolume` routes empty tag to `FlxG.sound.music`.
- [`01aba4f`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/01aba4f) -- `startTween` stored / removed under canonical key.
- [`86fdd9a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/86fdd9a) -- Lua error message read from top of stack, not status code.
- [`6c93f40`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6c93f40) -- `getBool` now accepts real `Bool` values from Lua.
- [`83e70f8`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/83e70f8), [`0267019`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/0267019), [`229f181`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/229f181) -- HScript: re-check `funk.hscript` after
  init; skip `Reflect.callMethod` on non-functions; catch generic exceptions.
- [`ff68f6d`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ff68f6d) -- `CallbackHandler` dispatcher not updating `lastCalledScript`.
- [`4aa6ff1`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4aa6ff1), [`5be673b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5be673b), [`fa04660`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/fa04660) -- `LuaUtils` numeric-index parsing fixes.
- [`c2bbbe9`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c2bbbe9), [`67d156a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/67d156a), [`eecee0e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/eecee0e) -- `addAnimByIndices` /
  `luaSpriteAddAnimationByIndices` / `addAnimationBySymbolIndices` drop null
  `parseInt` results.

### Editors
- [`1b72086`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/1b72086), [`ed9107c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ed9107c) -- Stage / Character editor: validate animation indices.
- [`22a9084`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/22a9084) -- `WeekEditorState`: drop non-numeric components when pasting bg color.
- [`c737f22`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c737f22) -- `PsychUIInputText` Ctrl+C / Ctrl+X when selection starts at 0.
- [`af9f95d`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/af9f95d) -- `PsychUIInputText` fixed uppercase handling and backspace (I think..?)
- [`6b2aa63`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6b2aa63) -- `PsychUINumericStepper._updateValue` actually strips stray minuses.

### Misc gameplay / UI
- [`4576d57`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4576d57) -- `popUpScore` pool reset velocity/acceleration on acquire.
- [`c5786a6`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c5786a6) -- `Character` inverted `animPaused` for atlas characters.
- [`01a03f2`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/01a03f2) -- `MenuCharacter` missing-character fallback.
- [`4539adb`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4539adb) -- `TypedAlphabet.update` subtract delay instead of clamping.
- [`199665a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/199665a) -- `OverlayShader` invalid GLSL syntax in `blendLighten`.
- [`5d3c143`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5d3c143) -- `StageData.validateVisibility` dangling-else / unreachable branch.
- [`5556251`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5556251) -- `Conductor.getStepRounded` operator precedence.
- [`1ae7843`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/1ae7843) -- `NotesColorSubState` swapped pixel / non-pixel branches.
- [`95c7bad`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/95c7bad) -- `ModSettingsSubState` `Map<->Array` fallback + `super()` before
  `close()`.
- [`1d547be`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/1d547be) -- `MainMenuState` detect mouse motion on either axis.
- [`63e3bc4`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/63e3bc4) -- `FreeplayState` per-song saved difficulty never being restored.
- [`74c320b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/74c320b) -- `HealthIcon` guard against zero `iSize` on tall/square graphics.
- [`8fae1b4`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8fae1b4) -- `NoteTypesConfig.loadFromTxt` fall-through on null/invalid file.
- [`99413c6`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/99413c6), [`9c77b49`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/9c77b49) -- `NoteTypesConfig._propCheckArray` fixes.
- [`9841654`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/9841654) -- `Note.set_clipRect` bypass setter recursion + bounds-check frameIndex.
- [`b3af659`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/b3af659) -- `MusicPlayer.updatePlaybackTxt` NPE on whole-number rates.
- [`0cd087f`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/0cd087f) -- `Achievements.getScore` no longer crashes on non-score achievements.
- [`c2898cd`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c2898cd) -- `Difficulty.loadFromWeek` walks index 0, uses splice instead of
  remove-by-value.

---

## Performance work

Roughly **30 perf-focused commits**. Highlights:
- [`2ed24c2`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2ed24c2) -- `FPSCounter` ring buffer + skip redundant `TextField` writes.
- [`cb90687`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/cb90687) -- `MusicBeatState` only writes `save.fullscreen` on change; inline
  `stepHit` loop.
- [`78f27b2`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/78f27b2) -- `Controls` input checks cache binds, avoid iterator allocations.
- [`4c1d271`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4c1d271) -- Cache `FlxKey → strum-index` map for keyboard input.
- [`254c1bd`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/254c1bd) -- Reuse `keysCheck` buffers, avoid `Array.contains` scans.
- [`40add49`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/40add49) -- Short-circuit BPM-map walks once past the target time/step.
- [`e295f20`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e295f20) -- Only push `curDecStep` / `curDecBeat` when they actually change.
- [`df01aa0`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/df01aa0) -- Skip redundant `indexOf` scans in note-spawn loop.
- [`61f7c39`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/61f7c39) -- Pool the args buffer for Lua → Haxe callback dispatch.
- [`83e3e78`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/83e3e78) -- Avoid per-call allocations in script-callback dispatchers.
- [`5cda815`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5cda815) -- Pool `FlxSprite` instances in `popUpScore`.
- [`3069939`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/3069939) -- Dedupe per-song hitsound precaches in `Note.set_noteType`.
- [`8eb55a8`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8eb55a8) -- Cache `Mods.parseList` result per-state.
- [`10a9cfa`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/10a9cfa) -- Stop flushing the save on `Highscore.get*` lookups.
- [`4850432`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4850432) -- `Language.formatKey` hoists regex to static.
- [`e250e39`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e250e39) -- `CoolUtil` hoist regex, single-lookup color map.
- [`cbc4760`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/cbc4760) -- Cache pixelUI `Paths.image` lookup in `StrumNote.reloadNote`.
- [`366ac2b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/366ac2b), [`6288721`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6288721) -- Inline `stagesFunc` at hot-path callsites.
- [`95f384e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/95f384e) -- ModSecurity per-session hash cache.

---

## Other notable changes
- [`f0d23af`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/f0d23af) -- Source code formatting normalized across all classes (the bulk
  of the diff line count).
- [`525c571`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/525c571) -- Updated `hxformat.json` to match.
- [`51844b4`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/51844b4) -- `FlxText` respects antialiasing pref via
  `FlxSprite.defaultAntialiasing`.
- [`14d8b6b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/14d8b6b) -- `getSparrowAtlas` / `getPackerAtlas` / `getAsepriteAtlas`
  short-circuit on null image; pixel `Note` / `StrumNote.loadGraphic` guarded
  against missing skin (was producing `'null'` asset id spam); leftover debug
  `trace` dropped.

---

## Maintainer notes

- If the `funkin.vis` repo updates `SpectralAnalyzer.hx`, the `sed` /
  PowerShell patch in [setup/windows.bat](../setup/windows.bat) /
  [setup/unix.sh](../setup/unix.sh) may need to be re-checked or removed.
- If `grig.audio` ever bumps its `tink_core` pin, update both setup scripts
  (`haxelib install tink_core 1.26.0 …`) and re-test.
- The `hxcpp` git-tool compile step is required after every fresh
  `haxelib git hxcpp` — don't remove it from setup.
- The fork unpinned all four git deps (`flixel-animate`, `funkin.vis`,
  `grig.audio`, `hxcpp`). If a dependency's API drift breaks the build again,
  the fastest mitigation is to re-pin to the original commits listed in the
  table above.

---

## Part 2: Fork-Specific Features

Boundary commit: [`153fe63a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/153fe63a4d4aec55f67026093249a65a70d402be)
("Fixed runHaxeCode issues due to script.setDefaults"). Everything from here on is fork-original
work: new systems, not compatibility fixes for the archived engine. Engine version moved from 1.1
through **1.2.1** (current) across this range.

This part is a tour of the major systems, grouped by area, not a commit-by-commit log -- there are
173 commits here. Representative commit links are given per system for anyone who wants to dig into
the history.

### Real Lua scripting & ScriptedStates hardening

- [`97bcea8`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/97bcea8) -- Initial direct-access
  Lua implementation: the object-bridge groundwork that `LuaProxy` (raw-mode Lua) and the chart
  editor's `EditorLuaScript` both build on.
- [`151e199`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/151e199),
  [`8dc572e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8dc572e),
  [`992c74c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/992c74c) -- ScriptedStates
  fixes: object access and method-lookup caching, backwards-compatibility fixes across both Lua and
  HScript.
- [`12d1c9b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/12d1c9b) -- Switched
  `hscript-insanity` to a personal fork to unblock class-based scripted-state fixes upstream hadn't
  merged yet.
- [`df31fc2`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/df31fc2) -- Scripted states keep
  scope to the launched modpack (a scripted state from one mod can no longer reach into another's
  files).
- [`2887b6d`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2887b6d) -- Null-checks corrupt
  `chart_editor_data` in a song's metadata instead of crashing on load.
- [`557dbff`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/557dbff) -- `FlxG` and `Paths` are
  usable from Lua without an explicit `import()` call.
- [`207bcbe`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/207bcbe) -- HScript errors
  originating from a Lua call now show line numbers.
- [`7219640`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/7219640) -- Script load order is
  controllable per mod via `_order.txt` / `_loadorder.txt`.
- [`40f9d3c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/40f9d3c) -- Scripted states
  support bare-root global overrides (a mod's top-level `states/X.hx` can override an engine state
  wholesale) with a clean camera/song-return path.

See [LuaProxy-API.md](LuaProxy-API.md), [SCRIPTED_STATES.md](SCRIPTED_STATES.md) and
[REAL_LUA.md](REAL_LUA.md) / [REAL_LUA_TECH_DEBT.md](REAL_LUA_TECH_DEBT.md) for the user-facing and
technical-debt documentation of this system.

### Note runtime v2 (full note-logic rewrite)

- [`e321460`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e321460) -- Full rewrite of the
  note logic: notes and strumlines are no longer built around the legacy `FlxTypedGroup<Note>` +
  index-based lookups. The new stack splits pure data (`NoteData`) from drawables
  (`NoteSprite`/`SustainSprite`/`Receptor`), pools everything, and drives the strumlines from the
  native `SongChart` model directly (`PlayState.SONG` *is* the chart, not a converted copy).
- [`374541a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/374541a) -- Neutral `NoteDefaults`
  + per-note custom textures, decoupling v2 fully from the legacy runtime.
- [`918c060`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/918c060) -- Custom-note skinning
  API: per-part textures (head / hold body / tail), independent RGB toggling, and Lua callbacks for
  scripted note types.
- [`fcc882c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/fcc882c),
  [`57d0e8e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/57d0e8e),
  [`e3f1527`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e3f1527),
  [`6bc7acb`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6bc7acb) -- The strumline-native
  `psych_v2` chart format: `SongChart` becomes the primary in-memory chart (up to N strumlines,
  `cameraTarget` per section, data-driven character singing), `Conductor` reads native chart
  sections for timing, and the old psych_v1 `SwagSong` format converts up to it on load.
- [`6634dcf`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6634dcf),
  [`e331460`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e331460),
  [`413e4b2`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/413e4b2) -- `compatibilityMode`:
  a modpack flag that runs the pre-v2 note/strumline code as a legacy shim (mirroring
  `goodNoteHit`/`noteMiss`/strum geometry/hold head-tail behavior) for mods whose scripts poke the
  old internals directly, plus a script converter that rewrites outdated calls automatically.
- [`c72e26c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c72e26c),
  [`2039e8d`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2039e8d) -- Sustain scaling and
  angle/rotation fixes for the new pooled sustain drawables.
- [`490b526`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/490b526),
  [`b4a1f61`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/b4a1f61),
  [`a2824cd`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/a2824cd),
  [`226d443`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/226d443) -- Hot-path performance
  work on the new note/strum stack: cached scroll-axis vectors, allocation-free column-hit
  resolution on key press, pooled RGB shader + splash data reuse on recycle, trimmed per-frame
  script-callback overhead.
- [`d052677`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/d052677),
  [`8be6988`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8be6988) -- Score, combo and a
  proper judgement on sustain hits; the sustain trail now ends cleanly on the endTime step line.

See [note-system-v2.md](note-system-v2.md) and [docs/examples/custom-notes](examples/custom-notes)
/ [docs/examples/glitch-notes](examples/glitch-notes) for the scripting-facing side of this.

### Folder note skins v2 & per-asset colors

- [`2cdb225`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2cdb225),
  [`ddd5904`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ddd5904),
  [`1c6e15e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/1c6e15e) -- Initial note-skinning
  rework: folder-based skins with per-object animated/colored toggles, treating a single static frame
  as its own valid case.
- [`d33a362`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/d33a362),
  [`8a2a0cb`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8a2a0cb) -- Decoupled note skins
  from the note system entirely and added the custom `.tcfg` config format (JSON still works as a
  fallback), plus pixel-art variants for the Default and Chip skins.
- [`cde68b7`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/cde68b7),
  [`a63ae99`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/a63ae99) -- Migrated the built-in
  Default, Chip and Future skins to the new folder-skin system.
- [`5b24f2b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5b24f2b) -- Fixed folder- and
  pixel-skin resolution edge cases.
- [`aae0df0`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/aae0df0),
  [`2184ef7`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2184ef7),
  [`76e599d`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/76e599d),
  [`a4010de`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/a4010de),
  [`2c082bf`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2c082bf),
  [`7881cdd`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/7881cdd),
  [`053eb7a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/053eb7a) -- Per-asset note
  colors: each skin element can be linked to the note color palette or given its own independent
  color, editable per keycount through a redesigned Note Colors menu (click-to-edit).
- [`990910a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/990910a),
  [`162f53b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/162f53b),
  [`f0fbe0b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/f0fbe0b) -- Note splashes
  decoupled from note visuals entirely, centered on the receptor, with their own independent color.
- [`6a7d2dd`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6a7d2dd) -- Strumlines are
  symmetrically placed and middle-scroll is properly centered for any key count.

New full-reference guide: [note-skinning-guidelines.md](note-skinning-guidelines.md).

### UI skin system

- [`aa7418a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/aa7418a) -- Judgement / combo /
  countdown folder-skin system: a UI skin themes the rating popups, the "combo" word, combo numbers
  and the ready/set/go countdown, plus their tween motion and popup placement, entirely separately
  from note skins.

New full-reference guide: [ui-skinning-guidelines.md](ui-skinning-guidelines.md).

### Chart editor rewrite (`ChartingState`) & the `ui` framework

- [`a6a3025`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/a6a3025) -- A full custom UI
  framework (`source/ui/`) written from scratch: a retained-mode, invalidation-driven widget kit on
  top of plain OpenFL display objects (no Flixel dependency), used for every menu, dropdown, modal
  and tooltip in the new editor.
- [`8587032`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8587032) -- A completely new chart
  editor built on that framework: decoupled data (`ChartEditorModel`, `UndoStack`, `SelectionModel`,
  `ClipboardModel`), a pooled Flixel notefield reusing the note-v2 drawables/skins, rebindable
  keybinds, autosave/backups, and rail-tab panels for every song/section/event/data/audio/meta/
  display/options concern the legacy editor had.
- [`595f4e7`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/595f4e7) -- The old chart editor
  moved to `legacy.editors.*` and stays fully functional (`compatibilityMode` and the debug menu both
  still offer it as "Legacy Chart Editor").
- [`68014d2`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/68014d2) -- Data/asset handling
  optimizations in the new editor (pooled note drawables, window-realized rendering).
- [`a46281e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/a46281e),
  [`4128623`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/4128623) -- Every editor (chart,
  character, stage, animation, dialogue, credits, week, ...) moved into a single top-level
  `source/editors/` package instead of being scattered across `source/states/`.
- Scripting: `EditorScriptHost` loads `scripts/charteditor/*.lua|*.hx` in raw-LuaProxy /
  HScript mode and dispatches editor-lifecycle hooks (`onNotePlaced`, `onSectionChanged`,
  `onSave`, ...) -- see [docs/examples/charteditor](examples/charteditor).

### Time signatures & multikey (N-key) support

- [`0b5c1dc`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/0b5c1dc) -- Chart data layer gains
  time signatures, a `keyCount` for multikey songs, and per-section overrides for both.
- [`f4b4883`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/f4b4883) -- Meter-aware beat
  tracking so BPM/step/beat math respects a section's own time signature.
- [`ce4a37f`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ce4a37f) -- Multikey gameplay:
  N-key strums, notes, splashes, input handling, and mid-song lane-count changes.
- [`ca9dfde`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ca9dfde) -- Chart editor multikey
  grid with per-section key-count / scroll-speed / time-signature toggles.
- [`1313f13`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/1313f13) -- Chart editor Options
  tab: metronome presets, an in-editor character preview, and quantized note colors.
- [`123ffbc`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/123ffbc) -- BPM re-snap/rescale
  and downscroll support in the chart editor.

### osu! beatmap converter

- [`d548d91`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/d548d91),
  [`6da5e53`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6da5e53) -- A converters backend
  and the initial osu!mania `.osz`/`.osu` -> Psych song conversion (a bundled ffmpeg handles audio /
  video re-encoding).
  - [`5233ed7`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/5233ed7) -- Quantization,
    scroll-velocity conversion, batch importing.
  - [`463987c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/463987c) -- Alignment fixed by
    shifting the audio instead of re-timing every note; video conversion sped up.
- [`6532e1b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/6532e1b),
  [`2bdd8eb`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/2bdd8eb) -- osu!**std** -> mania
  conversion (a custom lane-assignment heuristic with anti-jack logic), multi-keycount passes in one
  batch, and a generated `settings.json` for the converted modpack.
- [`ab6afb8`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ab6afb8),
  [`ab29504`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/ab29504),
  [`c5bafa9`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c5bafa9) -- osu! storyboard (`.osb`)
  support: a spec-derived parser and native player, storyboard sample sounds, on-hit note hitsounds
  via chart events, and storyboards prioritized over plain video/background when present.
- [`449d9bd`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/449d9bd) -- An osu!mania-style star
  difficulty-rating engine with an MD5-keyed chart cache, surfaced in Freeplay's song-info flyout.
- [`8060110`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/8060110) -- Converter UI redesign:
  keycount picker and a scrollable conversion log.

### Android support

- [`c2aed95`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c2aed95) -- Initial Android
  support (arm64 only; DiscordRPC disabled on mobile).
- [`072f314`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/072f314),
  [`958b869`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/958b869),
  [`f77a6df`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/f77a6df) -- Touch-pad / hitbox
  controls layered above the Flixel game, with per-modpack opt-out (`nativeMobile` in `pack.json`)
  falling back to the default pads.
- [`47e3d71`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/47e3d71),
  [`00a25a9`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/00a25a9),
  [`dea7630`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/dea7630) -- Android file-access
  macro for hardwired asset paths, HScript routed through the correct paths, crash logs saved to
  `crash/`.
- [`849e8b9`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/849e8b9) -- Adaptive/themed app
  icon support.
- [`72ca596`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/72ca596) -- Gameplay-changers
  button for mobile.

### Freeplay, options, and other user-facing rework

- [`b6eee6c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/b6eee6c) -- Freeplay: per-song
  saved difficulties, search, sort and grouping.
- [`9264e76`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/9264e76) -- Freeplay no longer
  needs a week file to list a song.
- [`3c05a9c`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/3c05a9c) -- Song info & difficulty
  star-rating flyout.
- [`feac8cc`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/feac8cc) -- Animated favorite-star
  icon.
- [`e696c1e`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/e696c1e) -- Options menu: full
  rework with a new two-depth category/setting navigation
  ([`c9aa73b`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c9aa73b)).
- [`286b04f`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/286b04f) -- Credits screen initial
  rework.
- [`512d449`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/512d449) -- Self-updating
  functionality.
- [`056bdb4`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/056bdb4),
  [`c443216`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/c443216) -- Flip/scale-aware
  character animation offsets, fixing JSON offsets on characters that default to `flipX`.
- [`cc0f143`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/cc0f143) -- A performance-counter
  overlay with CPU/GPU/memory metrics.

### LoadingState multithreading fix

The threaded asset loader (`LoadingState`) could freeze the game indefinitely on song load.
Reworked across three commits:

- [`d2cab02`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/d2cab02) -- Atomic load counters.
  The `loaded++` mutex was commented out, so concurrent worker increments were lost and `loaded`
  never reached `loadMax` -- the loader waited forever. Counters now use a dedicated always-alive
  mutex; `startThreads()` fires exactly once; the thread pool is created once per load (was up to
  3x, leaking workers); `requestedBitmaps` is snapshot-swapped under its mutex in `checkLoaded`.
- [`824a09a`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/824a09a) -- Replaced the lime
  `Future` chain + per-character thread fan-out + completion latch with one sequential prep task on
  the pool (no more concurrent pushes into the prepare lists, one threading system). Prep always
  reaches `startThreads()` even on exception, so a failed prep can no longer leave the loader hung.
- [`08b781f`](https://github.com/MeguminBOT/FNF-PsychEngine/commit/08b781f) -- Load watchdog: if
  loading makes zero progress for 30s it force-completes (logging diagnostics, lazy-loading the
  rest) instead of freezing, on both the loading-screen and the headless busy-wait paths. Pool size
  capped at 6 (loading is I/O-bound; more threads would just add contention), and the progress bar
  is guarded against a divide-by-zero.

---

## Part 2 maintainer notes

- `compatibilityMode` and the legacy editor package (`legacy.editors.*`, `legacy.*` note runtime) are
  the escape hatch for mods that poke pre-v2 internals directly. Keep them in sync with any future
  v2-side renames, or document the break in [MIGRATION_1.0.4_to_1.1.md](MIGRATION_1.0.4_to_1.1.md).
- The `ui` package (`source/ui/`) is written to be extractable as a standalone haxelib later: it has
  zero references to Flixel, Psych Engine states, or asset paths. Keep it that way if you touch it.
- The osu! converter bundles its own ffmpeg binary; if that binary is ever swapped or upgraded, retest
  both the audio path and the video/storyboard path.
- Folder note skins and UI skins share the same `.tcfg` config format and discovery rules
  (`images/noteSkins/<Name>/skin.tcfg`, `images/uiSkins/<Name>/skin.tcfg`) -- see
  [note-skinning-guidelines.md](note-skinning-guidelines.md) and
  [ui-skinning-guidelines.md](ui-skinning-guidelines.md).
