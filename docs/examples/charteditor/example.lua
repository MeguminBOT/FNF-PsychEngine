-- Chart editor Lua example (REAL Lua / raw LuaProxy mode - the legacy PsychLua callback
-- API does not exist here; use the proxied objects directly).
-- Drop into: mods/<your mod>/scripts/charteditor/example.lua
--
-- Globals: `editor` (the ChartingState: editor.model, editor.selection, editor.audio,
-- editor.editSection, ...) and `api` (call with a colon: api:toast('hi')).
-- `import('pkg.Class')` from the LuaProxy bridge also works.
--
-- Same hooks as HScript: onEditorCreate, onChartLoaded(song), onNotePlaced(time, column,
-- strumLine), onNoteDeleted, onNoteMoved, onEventPlaced(time, name), onEventDeleted(time),
-- onSectionChanged(sec), onSelectionChanged(count), onPlaybackToggled(playing),
-- onSave(path), onEditorDestroy, and onEditorUpdate(elapsed) after api:enableUpdateHook().
--
-- NOTE: prefer HScript for api:addMenuItem/addQuickToggle (they take function arguments);
-- Lua-side function passing depends on the proxy bridge's closure support.

function onEditorCreate()
	api:toast('example.lua loaded')
end

function onNotePlaced(time, column, strumLine)
	-- react to edits; api:snapshot('label') before mutating editor.model yourself
end

function onSectionChanged(sec)
	-- api:toast('section ' .. sec)
end

function onSave(path)
	api:toast('lua saw the save')
end
