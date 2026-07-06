// Chart editor HScript example.
// Drop into: mods/<your mod>/scripts/charteditor/example.hx
//
// Globals: `editor` (the ChartingState: .model, .selection, .audio, .noteField, .uiRoot,
// .undoStack, .editSection) and `api` (the stable facade).
//
// Hooks: onEditorCreate, onChartLoaded(song), onNotePlaced/onNoteDeleted/onNoteMoved(time,
// column, strumLine), onEventPlaced(time, name), onEventDeleted(time), onSectionChanged(sec),
// onSelectionChanged(count), onPlaybackToggled(playing), onSave(path), onEditorDestroy,
// and onEditorUpdate(elapsed) after api.enableUpdateHook().
//
// hscript notes: always use braces on function bodies; no sub-type imports.

function onEditorCreate() {
	api.toast('example.hx loaded');

	api.addMenuItem('Tools', 'Count Notes', function() {
		api.toast(editor.model.chart.noteList.length + ' notes in the chart');
	});

	api.addQuickToggle('Example', false, function(on) {
		api.toast('example toggle: ' + on);
	});

	api.addOptionButton('Example Script Button', function() {
		api.toast('clicked at section ' + editor.editSection);
	});
}

function onNotePlaced(time, column, strumLine) {
	// react to chart edits; call api.snapshot('label') BEFORE mutating editor.model yourself
}

function onSave(path) {
	api.toast('script saw the save: ' + path);
}
