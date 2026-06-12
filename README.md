![PsychionalEngineLogo](docs/img/PsychEngineLogoTweak.png)

Continuation of where 1.0.4 left off with bugfixes, performance improvements and updated to work with newer libraries.  If you're looking for really niche cool custom features, then this fork is not for you, this is aiming to just be "Psych Engine" as if the Psych Team kept maintaining it.

**Currently, near all existing mods should work as intended, or just require minor changes, if something is broken please let me know. **

No elaborate image or video previews really necessary yet as it currently is just your regular Psych Engine really.
Monthly releases at minimum for the foreseeable future. Patches may come in between if needed.

*Note:
AI coding agents have been used but carefully human reviewed by me and two other coders. Coding agents are fine if you know what you are doing.*

## Highlights
- **Engine version: 1.1** (up from 1.0.4)
- **Newer libs** -- upgraded to current HaxeFlixel 6, OpenFL 9.5,
  and Lime 8.3.
- **Building from source "just works" again** -- the install scripts have been updated and builds cleanly on Windows, Linux, and macOS without hunting down compatible library versions.
- **80+ bug fixes**, from edge cases, rare cases and common bugs 
- **30+ performance improvements**, especially around input handling, the
  scripting layer, and gameplay hot paths.
- **New faster Lua backend**
- **New: ModSecurity** -- Psych will now scan mod scripts for risky behaviour and ask you whether to trust each mod before running it.
Full release notes on the github page.


### (Docs) Migrating mods from 1.0.x to 1.1.x:
<https://github.com/MeguminBOT/FNF-PsychEngine/blob/master/docs/MIGRATION_1.0.4_to_1.1.md>
### (Docs) Full fork differences:
<https://github.com/MeguminBOT/FNF-PsychEngine/blob/master/docs/FORK_CHANGES.md>

### Known issues:
- [Mods Menu] Enable all button is still bugged.
- [Loading Screen] May freeze in rare cases
- [Base game: MILF] GF pos is wrong
- ~~[Selection Box broken in chart editor] ~~
### To be added:
- SWF toggle for flixel-animate
~~- Input text fields: Improve writing uppercase letters.~~
- Some minor common events (e.g. Camera Flash)
- Better flashing lights condition checks.
- Non pitched audio when the playback rate is modified.
- HScript backend swap, possibly support classes.
~~- Less frequent Mod Trust dialogs. (Happens on all runHaxeCode calls currently)~~
- Support Opus and WebM files.
- Better volume control
- Improve note skins (keep backwards compatible)
~~- Mod settings in the Pause/Freeplay Menus~~
- Freeplay Menu improvements (Search, sort by, group by)
- Add common options/modifiers from other VSRGs.
- Dynamic difficulty detection (less accidental missing json errors
- Proper Android support

Latest experimental dev build for testers: https://discord.com/channels/922849922175340586/1505362306010185728/1511509185890750535

## Pull requests are always welcome

#### Psych Engine by ShadowMario, Friday Night Funkin' by ninjamuffin99
