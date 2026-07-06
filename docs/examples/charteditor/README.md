# Chart editor script examples

Two versions of the same tiny script, one per scripting flavor, showing how to hook into the new
chart editor (`editors.ChartingState`) from a mod.

| File | Flavor | Notes |
|---|---|---|
| `example.hx` | HScript | Can pass real function references to `api.addMenuItem` / `api.addQuickToggle` / `api.addOptionButton`. |
| `example.lua` | Real Lua (raw LuaProxy) | The legacy PsychLua callback API does not exist here -- everything goes through the proxied `editor`/`api` objects. Prefer HScript when you need to hand a function to `api:addMenuItem`-style calls; Lua-side function passing depends on the proxy bridge's closure support. |

## Using one

Drop the file into `mods/<YourMod>/scripts/charteditor/` (either extension is picked up
automatically; both can coexist). It loads once when the chart editor opens and stays loaded for
that editor session.

## Globals

Both flavors receive the same two globals:

- **`editor`** -- the `ChartingState` instance: `editor.model` (the chart data), `editor.selection`,
  `editor.audio`, `editor.noteField`, `editor.uiRoot`, `editor.undoStack`, `editor.editSection`.
- **`api`** -- a small stable facade (`EditorScriptAPI`) so scripts can extend the editor's UI
  without touching its internals: `addMenuItem`, `addQuickToggle`, `addOptionButton`, `toast`,
  `snapshot` (push an undo checkpoint before you mutate `editor.model` yourself),
  `enableUpdateHook` (opts into the per-frame hook below).

## Hooks

Fired at mutation points, never per-frame unless you opt in:

- `onEditorCreate()` -- editor booted, scripts loaded
- `onChartLoaded(songName)` -- a chart was adopted (boot, New, Open, or an autosave restore)
- `onNotePlaced(time, column, strumLine)` / `onNoteDeleted(time, column, strumLine)`
- `onNoteMoved(time, column, strumLine)`
- `onEventPlaced(time, name)` / `onEventDeleted(time)`
- `onSectionChanged(section)`
- `onSelectionChanged(count)`
- `onPlaybackToggled(playing)`
- `onSave(path)`
- `onEditorUpdate(elapsed)` -- **only** after the script calls `api.enableUpdateHook()` /
  `api:enableUpdateHook()`; keeps the editor's frame budget untouched for scripts that don't need it
- `onEditorDestroy()`

## Notes for HScript

Always put braces on function bodies, even one-liners -- `hscript-insanity` (the interpreter behind
editor scripting) doesn't parse a brace-less single statement the way Haxe itself does. Sub-type
imports aren't supported either; import the top-level class.
