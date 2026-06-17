# Fork Changes vs. Archived Psych Engine

Baseline: archived-repo commit
[`5c67ced`](https://github.com/ShadowMario/FNF-PsychEngine/commit/5c67ced49e5a98535298a6daa3f8f4ec79ac8399)
("Update gitVersion.txt", 2025-03-24).

Summary of the diff `5c67ced..HEAD`: **147 commits, 172 files changed,
~17,400 insertions / ~16,900 deletions**. That's only for the updated libraries, formatting, bugfixes, more to come later!

Project version bumped: **1.0.4 → 1.1.1**
([source/states/MainMenuState.hx](../source/states/MainMenuState.hx#L16))

---

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
| `hxvlc`              | 2.0.1              | **2.3.0**       | Patch upgrades                                                                                 |
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
