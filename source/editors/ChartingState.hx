package editors;

import backend.SongChart;
import backend.SongChart.SongNote;
import editors.charting.EditorShell;
import editors.charting.audio.FlxChartAudio;
import editors.charting.audio.IChartAudio;
import editors.charting.data.ChartEditorModel;
import editors.charting.data.ClipboardModel;
import editors.charting.data.EditorKeybinds;
import editors.charting.data.ChartPattern;
import editors.charting.data.EditorPrefs;
import editors.charting.data.SelectionModel;
import editors.charting.data.SnapGrid;
import editors.charting.data.UndoStack;
import editors.charting.render.EditorNoteField;
import editors.charting.script.EditorScriptHost;
import editors.content.FileDialogHandler;
import editors.content.PsychJsonPrinter;
import flixel.FlxG;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UIRoot;
import ui.UITheme;
import ui.input.UIFocus;
import ui.input.UIPointer;
import ui.widgets.UIAccordion;
import ui.widgets.UIButton;
import ui.widgets.UICheckbox;
import ui.widgets.UIChip;
import ui.widgets.UIContextMenu;
import ui.widgets.UIDropdown;
import ui.widgets.UILabel;
import ui.widgets.UIMenuItem;
import ui.widgets.UIModal;
import ui.widgets.UIPanel;
import ui.widgets.UIRailTab;
import ui.widgets.UIScrollPane;
import ui.widgets.UISeparator;
import ui.widgets.UISlider;
import ui.widgets.UIStepper;
import ui.widgets.UITextInput;
import ui.widgets.UIToast;
import ui.widgets.UITooltip;

/**
	The chart editor. Owns and wires every decoupled part: the retained OpenFL UI layer
	(`UIRoot` + `EditorShell` chrome), the data core (`editors.charting.data.*`), the Flixel
	notefield (`EditorNoteField`), playback (`IChartAudio`) and the Lua/HScript host
	(`EditorScriptHost`) - the parts never reference each other directly.

	Section values (BPM / time sig / scroll velocity / keys) carry NO explicit "change" flags:
	each section inherits the previous section's effective values and an override simply IS a
	differing value - see `ChartEditorModel`.
**/
class ChartingState extends MusicBeatState {
	/** The retained UI layer (public for scripts). **/
	public var uiRoot(default, null):UIRoot;

	/** The chrome: bands, docks, transport, status (public for scripts). **/
	public var shell(default, null):EditorShell;

	/** The chart data model (public for scripts). **/
	public var model(default, null):ChartEditorModel;

	/** The selection set (public for scripts). **/
	public var selection(default, null):SelectionModel;

	/** Snapshot-based undo/redo over the whole chart (public for scripts). **/
	public var undoStack(default, null):UndoStack;

	/** The note/event clipboard (public for scripts). **/
	public var clipboard(default, null):ClipboardModel;

	/** The active grid-snap selection (public for scripts). **/
	public var snap(default, null):SnapGrid;

	/** The Flixel grid/notes view (public for scripts). **/
	public var noteField(default, null):EditorNoteField;

	/** The playback service (public for scripts). **/
	public var audio(default, null):IChartAudio;

	/** The Lua/HScript host (raw LuaProxy + hscript; see `EditorScriptHost` for hooks). **/
	public var scripts(default, null):EditorScriptHost;

	final customMenuItems:Map<String, Array<UIMenuItem>> = new Map();
	final customToggles:Array<CustomToggle> = [];
	final customOptionButtons:Array<CustomButton> = [];

	/** The section the panels operate on. **/
	public var editSection(default, null):Int = 0;

	/** How many sections back "Copy From" pulls notes from (1 = the previous section). **/
	var copyFromBack:Int = 4;

	// 1x = square cells with the full section in view; higher zooms stretch rows for fine editing.
	static final ZOOM_LABELS:Array<String> = ["0.25x", "0.5x", "1x", "2x", "3x", "4x", "6x", "8x", "12x", "16x", "24x"];
	static final ZOOM_VALUES:Array<Float> = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24];
	static final RATE_LABELS:Array<String> = [
		"0.25x", "0.50x", "0.75x", "1.00x", "1.25x", "1.50x", "1.75x", "2.00x", "2.50x", "3.00x"
	];
	static final RATE_VALUES:Array<Float> = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3];
	static final TAB_NAMES:Array<String> = [
		"Song",
		"Section",
		"Events",
		"Data",
		"Audio",
		"Meta",
		"Display",
		"Options",
		"Character",
		"Strumlines",
		"Patterns"
	];

	/** Metronome sound presets (name shown in Options, sound asset, accent pitch). **/
	static final METRONOME_PRESETS:Array<{name:String, sound:String, accentPitch:Float}> = [
		{name: 'Tick', sound: 'Metronome_Tick', accentPitch: 1.5},
		{name: 'Beep', sound: 'metronome/beep', accentPitch: 1.5},
		{name: 'Click', sound: 'metronome/click', accentPitch: 1.5},
		{name: 'Wood', sound: 'metronome/wood', accentPitch: 1.4}
	];

	/** How many strumlines may render lanes at once. **/
	static inline var MAX_VISIBLE_LINES:Int = 6;

	/** Time-signature denominators the engine actually supports (only powers of 2 keep 16/d an
		integer step-per-beat; anything else is unsupported, so the pickers are limited to these). **/
	static final VALID_DENOMINATORS:Array<Int> = [1, 2, 4, 8, 16];

	static final DENOMINATOR_LABELS:Array<String> = ['1', '2', '4', '8', '16'];

	/** Index into `VALID_DENOMINATORS` for a denominator (falls back to 4). **/
	static function denomIndex(d:Int):Int {
		var idx:Int = VALID_DENOMINATORS.indexOf(d);
		return (idx >= 0) ? idx : 2;
	}

	var zoomIndex:Int = 2;
	var rateIndex:Int = 3;

	var waveformChip:UIChip;
	var metronomeChip:UIChip;
	var hitsoundsChip:UIChip;
	var vortexChip:UIChip;
	var quantChip:UIChip;
	var downscrollChip:UIChip;

	// event inspector state + widgets
	var eventsList:Array<Array<String>> = [];
	var selectedEventGroup:Array<Dynamic> = null;
	var selectedEventSub:Int = 0;
	var eventHead:UIAccordion;
	var eventDrop:UIDropdown;
	var eventVal1:UITextInput;
	var eventVal2:UITextInput;

	// section panel widgets (null while another rail tab is active)
	var sectionHead:UIAccordion;
	var camTargetDrop:UIDropdown;
	var altCheck:UICheckbox;
	var bpmStep:UIStepper;
	var beatsStep:UIStepper;
	var denomDrop:UIDropdown;
	var speedStep:UIStepper;
	var velStep:UIStepper;
	var keysStep:UIStepper;
	var selectedHead:UIAccordion;
	var hitTimeStep:UIStepper;
	var sustainStep:UIStepper;
	var noteTypeDrop:UIDropdown;
	var noteTypesList:Array<String> = [];

	var fpsTimer:Float = 0;
	var lastViewTime:Float = -1;
	var placingNote:SongNote = null;
	var scrollHold:Float = 0;
	var boxing:Bool = false;
	var boxX:Float = 0;
	var boxY:Float = 0;
	var metaWorking:backend.SongMeta.SongMetaInfo = null;
	var playStartMs:Float = 0;
	var nextHitIndex:Int = 0;
	var lastMetroKey:Int = -1;

	/** Patterns rail: selected pattern, its length in snap steps, and the target strumline (-1 = auto). **/
	var patternId:Int = 0;
	var patternLength:Int = 8;
	var patternLine:Int = -1;

	/** When on, clicking the grid drops the selected pattern instead of placing a single note. **/
	var patternArmed:Bool = false;

	final fileDialog:FileDialogHandler = new FileDialogHandler();

	/** Seconds between autosave checks (only writes when the chart changed). **/
	static inline var AUTOSAVE_SECS:Float = 120;

	/** Newest backups kept in the backup folder. **/
	static inline var BACKUP_LIMIT:Int = 10;

	var autosaveTimer:Float = 0;
	var dirtySinceAutosave:Bool = false;
	var autosaveAgeSecs:Float = -1;
	var backupCount:Int = 0;

	override function create():Void {
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;
		FlxG.camera.bgColor = UITheme.bg;

		if (Difficulty.list.length < 1)
			Difficulty.resetList();

		EditorPrefs.load();
		EditorKeybinds.init();
		applyThemeFromPrefs();

		snap = new SnapGrid();
		snap.select(EditorPrefs.snapIndex);
		zoomIndex = clampIndex(EditorPrefs.zoomIndex, ZOOM_LABELS.length);
		rateIndex = 3; // rate always opens at 1.00x

		model = new ChartEditorModel();
		undoStack = new UndoStack();
		selection = new SelectionModel();
		clipboard = new ClipboardModel();

		var chart:SongChart = PlayState.SONG;
		if (chart == null || chart.sections.length == 0) {
			chart = makeBlankChart();
			PlayState.SONG = chart;
		}
		ensureGfLine(chart);
		model.load(chart);

		audio = new FlxChartAudio();
		audio.load(backend.Song.loadedSongName, chart.needsVoices);
		audio.setVolumes(EditorPrefs.instVol, EditorPrefs.mainVol, EditorPrefs.oppVol);
		audio.setRate(RATE_VALUES[rateIndex]);
		if (audio.loaded) {
			var guard:Int = 0;
			while (model.endTime < audio.length && guard++ < 4000)
				model.ensureSectionCount(model.sectionCount() + 1);
		}

		model.onChanged = onModelChanged;
		selection.onChanged = onSelectionChanged;

		UILocale.translate = translatePhrase;
		UIFonts.register('assets/fonts/vcr.ttf');

		buildEventsList();
		buildNoteTypesList();
		#if sys
		pruneBackups();
		#end

		uiRoot = new UIRoot();
		UITooltip.install();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		shell = new EditorShell(uiRoot, FlxG.width, FlxG.height);
		wireChrome();
		buildRightDock();
		shell.rail.setTabs(railTabs());
		shell.rail.onSelect = function(_:Int):Void buildLeftPanel(currentPanel());
		shell.rail.select(1);

		noteField = new EditorNoteField(model, selection, shell.fieldX, shell.fieldY, shell.fieldW, shell.fieldH);
		noteField.setZoom(ZOOM_VALUES[zoomIndex]);
		noteField.setDownscroll(EditorPrefs.downscroll);
		noteField.maxTime = audio.loaded ? audio.length : -1;
		noteField.typeIndexOf = function(t:String):Int return noteTypesList.indexOf(t);
		noteField.waveEnabled = EditorPrefs.waveform;
		applyWaveConfig();
		noteField.vortexEnabled = EditorPrefs.vortex;
		add(noteField.group);
		add(noteField.overlay);

		if (EditorPrefs.combinedDock)
			setCombinedDock(true);

		refreshSongLabel();
		updateBpmChip();
		updateStatus();
		updateTimeLabel();

		scripts = new EditorScriptHost(this);
		scripts.loadAll();
		if (scripts.hasScripts) {
			rebuildStrumlineUI(); // pick up script-registered toggles/menu items
			scripts.call('onEditorCreate', []);
			scripts.call('onChartLoaded', [model.chart.song]);
		}

		super.create();
	}

	static inline function clampIndex(v:Int, len:Int):Int {
		return (v < 0) ? 0 : (v >= len ? len - 1 : v);
	}

	/** The `UILocale.translate` bridge into the engine's language files. **/
	static function translatePhrase(key:String, fallback:String):String {
		return Language.getPhrase(key, fallback);
	}

	/** Every chart carries a hidden gf strumline - the native "GF Section" replacement. **/
	static function ensureGfLine(chart:SongChart):Void {
		for (line in chart.strumLines)
			if (line.id == 'gf')
				return;
		chart.strumLines.push({
			index: chart.strumLines.length,
			id: 'gf',
			type: 2,
			isPlayer: false,
			visible: false,
			characters: [(chart.gfVersion != null) ? chart.gfVersion : 'gf'],
			keyCount: chart.keyCount
		});
	}

	/**
		A minimal empty chart: opponent/player/gf strumlines and four default 4/4 sections.
		@return the chart, ready for `model.load`
	**/
	static function makeBlankChart():SongChart {
		var chart:SongChart = new SongChart();
		chart.song = 'Test';
		chart.bpm = 150;
		chart.speed = 1;
		chart.keyCount = 4;
		chart.strumLines.push({
			index: 0,
			id: 'opponent',
			type: 0,
			isPlayer: false,
			visible: true,
			characters: ['dad'],
			keyCount: 4
		});
		chart.strumLines.push({
			index: 1,
			id: 'player',
			type: 1,
			isPlayer: true,
			visible: true,
			characters: ['bf'],
			keyCount: 4
		});
		chart.strumLines.push({
			index: 2,
			id: 'gf',
			type: 2,
			isPlayer: false,
			visible: false,
			characters: ['gf'],
			keyCount: 4
		});
		var i:Int = 0;
		while (i < 4) {
			chart.sections.push({
				cameraTarget: 1,
				bpm: 150,
				changeBPM: false,
				beats: 4,
				denominator: 4
			});
			i++;
		}
		return chart;
	}

	/** Layers the UI root above the game view but below the FPS counter. **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	function onGameResized(_:Int, _:Int):Void {
		syncViewport();
	}

	/** Mirrors the game's scale-mode output so UI coordinates match game coordinates. **/
	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	/** Central post-mutation refresh: clamps the cursor, re-realizes the grid, updates panels. **/
	function onModelChanged():Void {
		dirtySinceAutosave = true;
		if (editSection >= model.sectionCount())
			editSection = model.sectionCount() - 1;
		if (editSection < 0)
			editSection = 0;
		if (noteField != null)
			noteField.onModelChanged();
		refreshSectionPanel();
		updateBpmChip();
		updateStatus();
		updateTimeLabel();
	}

	/**
		Compact number formatting for chrome labels.
		@param v the value
		@return whole numbers without decimals, else rounded to 2 places
	**/
	static function fmt(v:Float):String {
		var i:Int = Std.int(v);
		return (v == i) ? Std.string(i) : Std.string(Math.round(v * 100) / 100);
	}

	function refreshSongLabel():Void {
		var chart:SongChart = model.chart;
		shell.songLabel.text = '${chart.song} - ${Difficulty.getString(false)} - ${model.keyCountAt(0)}K';
		shell.layoutMenuExtras();
	}

	function updateBpmChip():Void {
		shell.bpmChip.label = 'BPM ${fmt(model.bpmAt(editSection))}';
	}

	function updateStatus():Void {
		var step:Int = (noteField != null) ? Std.int(noteField.stepsOf(noteField.viewTime)) : 0;
		shell.statusLeft.text = 'Section ${editSection + 1}/${model.sectionCount()} - Step $step - Selected: ${selection.count}';
	}

	/**
		Formats a song position for the transport readout.
		@param ms the time in milliseconds (negative clamps to 0)
		@return `mm:ss.mmm`
	**/
	static function fmtTime(ms:Float):String {
		if (ms < 0)
			ms = 0;
		var total:Int = Std.int(ms);
		var m:Int = Std.int(total / 60000);
		var s:Int = Std.int(total / 1000) % 60;
		var mil:Int = total % 1000;
		return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s + '.' + (mil < 100 ? (mil < 10 ? '00' : '0') : '') + mil;
	}

	function updateTimeLabel():Void {
		if (noteField == null)
			return;
		shell.timeLabel.text = fmtTime(noteField.viewTime) + ' / ' + fmtTime(model.endTime);
		shell.layoutTime();
	}

	/** One snap unit expressed in 16th-note steps (snap 1/16 = 1 step, 1/4 = 4 steps). **/
	inline function snapSteps():Float {
		return 16 / snap.value;
	}

	function refreshSectionPanel():Void {
		if (sectionHead == null)
			return;
		var sec:Int = editSection;
		sectionHead.title = 'Section - #$sec';
		sectionHead.hint = 'of ${model.sectionCount()}';
		camTargetDrop.select(model.cameraTargetAt(sec));
		altCheck.checked = model.sectionAltState(sec);
		bpmStep.value = model.bpmAt(sec);
		beatsStep.value = model.beatsAt(sec);
		denomDrop.select(denomIndex(model.denominatorAt(sec)));
		speedStep.value = model.chart.speed;
		velStep.value = model.velocityAt(sec);
		keysStep.value = model.keyCountAt(sec);
	}

	/** Moves the section cursor (extends the chart when stepping past the end). **/
	public function gotoSection(sec:Int):Void {
		if (sec < 0)
			sec = 0;
		model.ensureSectionCount(sec + 1);
		var changed:Bool = (sec != editSection);
		editSection = sec;
		if (noteField != null)
			noteField.setViewTime(model.sectionStart(sec));
		refreshSectionPanel();
		updateBpmChip();
		updateStatus();
		updateTimeLabel();
		if (changed && scripts != null && scripts.hasScripts)
			scripts.call('onSectionChanged', [editSection]);
	}

	/**
		A stub click handler for not-yet-wired actions.
		@param what the toast text explaining which pass delivers the feature
		@return a callback that shows the toast
	**/
	inline function todo(what:String):Void->Void {
		return function():Void UIToast.show(what);
	}

	/** Assigns behavior to every shell control (menus, chips, transport, menu-bar extras). **/
	function wireChrome():Void {
		shell.menuBar.setMenus([
			{title: "File", items: fileMenu},
			{title: "Edit", items: editMenu},
			{title: "View", items: viewMenu},
			{title: "Playback", items: playbackMenu},
			{title: "Tools", items: toolsMenu},
			{title: "Help", items: helpMenu}
		]);

		shell.snapChip.label = 'Snap ${snap.label()}';
		shell.zoomChip.label = 'Zoom ${ZOOM_LABELS[zoomIndex]}';
		shell.rateChip.label = 'Rate ${RATE_LABELS[rateIndex]}';
		shell.snapChip.onClick = wrapSnap;
		shell.zoomChip.onClick = wrapZoom;
		shell.rateChip.onClick = wrapRate;
		shell.snapChip.onRightClick = openSnapMenu;
		shell.zoomChip.onRightClick = openZoomMenu;
		shell.rateChip.onRightClick = openRateMenu;

		shell.prevBtn.onClick = function():Void gotoSection(editSection - 1);
		shell.nextBtn.onClick = function():Void gotoSection(editSection + 1);
		shell.playBtn.onClick = togglePlayback;
		shell.stopBtn.onClick = stopPlayback;
		shell.loopBtn.onClick = function():Void shell.loopBtn.active = !shell.loopBtn.active;
		shell.timeline.onScrub = onTimelineScrub;

		shell.searchBtn.onClick = todo("Search isn't implemented yet");
		shell.optionsBtn.onClick = function():Void selectPanel(7);
	}

	/** The timeline's full span: audio length when loaded, else the chart end. **/
	inline function totalMs():Float {
		return audio.loaded ? audio.length : model.endTime;
	}

	/** Seeks audio + view + hit/metronome cursors together. **/
	function seekTo(ms:Float):Void {
		if (audio.loaded)
			audio.seek(ms);
		noteField.setViewTime(ms);
		nextHitIndex = model.firstNoteIndex(ms + 0.01);
		lastMetroKey = -1;
	}

	function togglePlayback():Void {
		if (!audio.loaded) {
			UIToast.show('No audio found for this chart');
			return;
		}
		if (audio.playing)
			audio.pause();
		else {
			playStartMs = noteField.viewTime;
			nextHitIndex = model.firstNoteIndex(playStartMs + 0.01);
			lastMetroKey = -1;
			audio.play(playStartMs);
		}
		if (scripts.hasScripts)
			scripts.call('onPlaybackToggled', [audio.playing]);
	}

	function stopPlayback():Void {
		if (!audio.loaded)
			return;
		audio.pause();
		seekTo(playStartMs);
	}

	function onTimelineScrub(p:Float):Void {
		seekTo(p * totalMs());
	}

	/** Hands the edited chart (already `PlayState.SONG`) to gameplay in charting mode. **/
	function goToPlayState():Void {
		if (audio.loaded)
			audio.pause();
		persistentUpdate = false;
		FlxG.mouse.visible = false;
		PlayState.chartingMode = true;
		backend.StageData.loadDirectory(PlayState.SONG);
		LoadingState.loadAndSwitchState(new PlayState());
	}

	/**
		Playback-time audio feedback: metronome ticks on beat boundaries (accented on each
		section's first beat) and hitsounds as the playhead crosses notes.
		@param t the current playback position in ms
	**/
	function tickMetronomeAndHits(t:Float):Void {
		// metronome: beat boundaries at the current section's time signature
		var sec:Int = model.sectionAt(t);
		var spb:Int = backend.Conductor.stepsPerBeat(model.denominatorAt(sec));
		var beatIn:Int = Std.int((noteField.stepsOf(t) - noteField.stepsOf(model.sectionStart(sec))) / spb);
		var key:Int = sec * 10000 + beatIn;
		if (key != lastMetroKey) {
			var wasFresh:Bool = (lastMetroKey == -1);
			lastMetroKey = key;
			if (EditorPrefs.metronome && !wasFresh) {
				var preset = METRONOME_PRESETS[clampIndex(EditorPrefs.metroPreset, METRONOME_PRESETS.length)];
				var snd = FlxG.sound.play(Paths.sound(preset.sound), 0.6);
				#if FLX_PITCH
				if (snd != null && beatIn == 0 && EditorPrefs.metroAccent)
					snd.pitch = preset.accentPitch;
				#end
			}
		}

		// hitsounds: notes the playhead just passed (one per side per frame, like legacy)
		var list:Array<SongNote> = model.chart.noteList;
		var lines = model.chart.strumLines;
		var playedP:Bool = false;
		var playedO:Bool = false;
		while (nextHitIndex < list.length && list[nextHitIndex].time <= t) {
			var note:SongNote = list[nextHitIndex];
			nextHitIndex++;
			// vortex receptors light up as their notes cross the playhead
			noteField.confirmForNote(note.strumLine, note.column);
			if (!EditorPrefs.hitsounds)
				continue;
			var isPlayer:Bool = (note.strumLine >= 0 && note.strumLine < lines.length) && lines[note.strumLine].isPlayer;
			if (isPlayer) {
				if (!playedP && EditorPrefs.hitsoundP > 0) {
					FlxG.sound.play(Paths.sound('hitsound'), EditorPrefs.hitsoundP);
					playedP = true;
				}
			} else if (!playedO && EditorPrefs.hitsoundO > 0) {
				FlxG.sound.play(Paths.sound('hitsound'), EditorPrefs.hitsoundO);
				playedO = true;
			}
		}
	}

	/** Rail-position -> panel index (`TAB_NAMES`); rebuilt by `railTabs`. Rail positions and panel
		indices differ because Events/Audio/Display tabs are dropped when the right dock is shown. **/
	final railPanelMap:Array<Int> = [];

	/**
		The rail tab set. Events/Audio/Display already live in the right dock, so they only appear as
		rail tabs in combined-dock mode (where the right dock is folded away); CHAR/STRM likewise.
	**/
	function railTabs():Array<UIRailTab> {
		railPanelMap.resize(0);
		var tabs:Array<UIRailTab> = [];
		function add(panel:Int, caption:String, tip:String):Void {
			tabs.push({caption: caption, tooltipFallback: tip});
			railPanelMap.push(panel);
		}
		add(0, "SONG", "Song");
		add(1, "SECT", "Section");
		if (EditorPrefs.combinedDock)
			add(2, "EVNT", "Events");
		add(3, "DATA", "Data");
		if (EditorPrefs.combinedDock)
			add(4, "AUDI", "Audio");
		add(5, "META", "Meta");
		if (EditorPrefs.combinedDock)
			add(6, "DISP", "Display");
		add(10, "PTRN", "Patterns");
		add(7, "OPTS", "Options");
		if (EditorPrefs.combinedDock) {
			add(8, "CHAR", "Character");
			add(9, "STRM", "Strumlines");
		}
		return tabs;
	}

	/** The panel index behind the currently-selected rail position. **/
	inline function currentPanel():Int {
		var pos:Int = shell.rail.selectedIndex;
		return (pos >= 0 && pos < railPanelMap.length) ? railPanelMap[pos] : 0;
	}

	/** Selects the rail tab that shows a given panel (no-op if it isn't currently on the rail). **/
	function selectPanel(panel:Int):Void {
		var pos:Int = railPanelMap.indexOf(panel);
		if (pos >= 0)
			shell.rail.select(pos);
	}

	function cycleSnap(dir:Int):Void {
		snap.cycle(dir);
		EditorPrefs.snapIndex = snap.index;
		shell.snapChip.label = 'Snap ${snap.label()}';
	}

	function wrapSnap():Void {
		snap.select((snap.index + 1) % SnapGrid.SNAPS.length);
		EditorPrefs.snapIndex = snap.index;
		shell.snapChip.label = 'Snap ${snap.label()}';
	}

	function cycleZoom(dir:Int):Void {
		setZoomIndex(clampIndex(zoomIndex + dir, ZOOM_LABELS.length));
	}

	function wrapZoom():Void {
		setZoomIndex((zoomIndex + 1) % ZOOM_LABELS.length);
	}

	function setZoomIndex(idx:Int):Void {
		zoomIndex = idx;
		EditorPrefs.zoomIndex = zoomIndex;
		shell.zoomChip.label = 'Zoom ${ZOOM_LABELS[zoomIndex]}';
		if (noteField != null)
			noteField.setZoom(ZOOM_VALUES[zoomIndex]);
	}

	function cycleRate(dir:Int):Void {
		setRateIndex(clampIndex(rateIndex + dir, RATE_LABELS.length));
	}

	function wrapRate():Void {
		setRateIndex((rateIndex + 1) % RATE_LABELS.length);
	}

	function setRateIndex(idx:Int):Void {
		rateIndex = idx;
		shell.rateChip.label = 'Rate ${RATE_LABELS[rateIndex]}';
		audio.setRate(RATE_VALUES[rateIndex]);
	}

	/** Right-click a value chip: a checkable list of every option, picked directly. **/
	function openSnapMenu():Void {
		var items:Array<UIMenuItem> = [];
		for (i in 0...SnapGrid.SNAPS.length) {
			var idx:Int = i;
			items.push({label: '1/${SnapGrid.SNAPS[i]}', checked: (i == snap.index), onSelect: function():Void {
				snap.select(idx);
				EditorPrefs.snapIndex = snap.index;
				shell.snapChip.label = 'Snap ${snap.label()}';
			}});
		}
		UIContextMenu.open(FlxG.mouse.x, FlxG.mouse.y, items);
	}

	function openZoomMenu():Void {
		var items:Array<UIMenuItem> = [];
		for (i in 0...ZOOM_LABELS.length) {
			var idx:Int = i;
			items.push({label: ZOOM_LABELS[i], checked: (i == zoomIndex), onSelect: function():Void setZoomIndex(idx)});
		}
		UIContextMenu.open(FlxG.mouse.x, FlxG.mouse.y, items);
	}

	function openRateMenu():Void {
		var items:Array<UIMenuItem> = [];
		for (i in 0...RATE_LABELS.length) {
			var idx:Int = i;
			items.push({label: RATE_LABELS[i], checked: (i == rateIndex), onSelect: function():Void setRateIndex(idx)});
		}
		UIContextMenu.open(FlxG.mouse.x, FlxG.mouse.y, items);
	}

	/** Restores the previous snapshot and refreshes everything that may hold stale references. **/
	function performUndo():Void {
		var label:String = undoStack.undo(model);
		if (label != null) {
			selection.prune(model.chart.noteList);
			selectedEventGroup = null;
			rebuildStrumlineUI();
			UIToast.show('Undid: $label');
		} else
			UIToast.show('Nothing to undo');
	}

	function performRedo():Void {
		var label:String = undoStack.redo(model);
		if (label != null) {
			selection.prune(model.chart.noteList);
			selectedEventGroup = null;
			rebuildStrumlineUI();
			UIToast.show('Redid: $label');
		} else
			UIToast.show('Nothing to redo');
	}

	function fileMenu():Array<UIMenuItem> {
		return appendCustom("File", [
			{label: "New Chart", shortcut: EditorKeybinds.bindLabel('new_chart'), onSelect: newChart},
			{label: "Open...", shortcut: EditorKeybinds.bindLabel('open'), onSelect: openChartDialog},
			{label: "Reload From Disk", onSelect: reloadChart},
			{label: "Open Autosave", onSelect: openNewestAutosave},
			{separator: true},
			{label: "Save", shortcut: EditorKeybinds.bindLabel('save'), onSelect: function():Void saveChart(false)},
			{label: "Save As...", shortcut: EditorKeybinds.bindLabel('save_as'), onSelect: function():Void saveChart(true)},
			{label: "Export Legacy (v1)...", onSelect: exportLegacyChart},
			{separator: true},
			{label: "Import V-Slice...", onSelect: importVSlice},
			{label: "Export V-Slice...", onSelect: exportVSlice},
			{separator: true},
			{label: "Exit Editor", shortcut: "Esc", onSelect: leaveEditor}
		]);
	}

	function editMenu():Array<UIMenuItem> {
		return appendCustom("Edit", [
			{
				label: "Undo",
				shortcut: EditorKeybinds.bindLabel('undo'),
				disabled: !undoStack.canUndo,
				onSelect: performUndo
			},
			{
				label: "Redo",
				shortcut: EditorKeybinds.bindLabel('redo'),
				disabled: !undoStack.canRedo,
				onSelect: performRedo
			},
			{separator: true},
			{
				label: "Cut",
				shortcut: EditorKeybinds.bindLabel('cut'),
				disabled: selection.count == 0,
				onSelect: cutSelection
			},
			{label: "Copy", shortcut: EditorKeybinds.bindLabel('copy'), onSelect: copySelection},
			{label: "Paste", shortcut: EditorKeybinds.bindLabel('paste'), onSelect: pasteAtSection},
			{
				label: "Delete",
				shortcut: EditorKeybinds.bindLabel('delete'),
				disabled: selection.count == 0,
				onSelect: deleteSelection
			},
			{separator: true},
			{label: "Select All", shortcut: EditorKeybinds.bindLabel('select_all'), onSelect: selectAll},
			{label: "Select Section", onSelect: selectSection}
		]);
	}

	function viewMenu():Array<UIMenuItem> {
		return appendCustom("View", [
			{label: "Waveform", checked: EditorPrefs.waveform, onSelect: function():Void setToggle(0, !EditorPrefs.waveform)},
			{label: "Metronome", checked: EditorPrefs.metronome, onSelect: function():Void setToggle(1, !EditorPrefs.metronome)},
			{label: "Hitsounds", checked: EditorPrefs.hitsounds, onSelect: function():Void setToggle(2, !EditorPrefs.hitsounds)},
			{separator: true},
			{label: "Vortex Mode", checked: EditorPrefs.vortex, onSelect: function():Void setToggle(3, !EditorPrefs.vortex)},
			{label: "Quant Colors", checked: EditorPrefs.quantColors, onSelect: function():Void setToggle(4, !EditorPrefs.quantColors)},
			{label: "Downscroll", checked: EditorPrefs.downscroll, onSelect: function():Void setToggle(5, !EditorPrefs.downscroll)},
			{separator: true},
			{label: "Combined Dock", checked: EditorPrefs.combinedDock, onSelect: function():Void setCombinedDock(!EditorPrefs.combinedDock)}
		]);
	}

	function playbackMenu():Array<UIMenuItem> {
		return appendCustom("Playback", [
			{label: "Playtest", shortcut: EditorKeybinds.bindLabel('playtest'), onSelect: goToPlayState},
			{label: "Preview", shortcut: EditorKeybinds.bindLabel('preview'), onSelect: todo("In-editor preview isn't implemented yet")},
			{separator: true},
			{label: "Play / Pause", shortcut: EditorKeybinds.bindLabel('play_pause'), onSelect: togglePlayback},
			{label: "Stop", onSelect: stopPlayback},
			{separator: true},
			{label: "Go to Start", shortcut: EditorKeybinds.bindLabel('goto_start'), onSelect: function():Void gotoSection(0)},
			{label: "Go to End", shortcut: EditorKeybinds.bindLabel('goto_end'), onSelect: function():Void gotoSection(model.sectionCount() - 1)},
			{label: "Go to...", shortcut: EditorKeybinds.bindLabel('go_to'), onSelect: openGoToModal}
		]);
	}

	function toolsMenu():Array<UIMenuItem> {
		return appendCustom("Tools", [
			{label: "Keybinds...", onSelect: openKeybindsModal},
			{label: "Adapt Notes to Snap", onSelect: adaptNotesToSnap},
			{separator: true},
			{label: "Legacy Chart Editor", onSelect: openLegacyEditor}
		]);
	}

	function helpMenu():Array<UIMenuItem> {
		return appendCustom("Help", [
			{label: "Help", shortcut: EditorKeybinds.bindLabel('help'), onSelect: openHelpModal},
			{label: "About", onSelect: openAboutModal}
		]);
	}

	function newChart():Void {
		backend.Song.chartPath = null;
		backend.Song.loadedSongName = null;
		adoptChart(makeBlankChart());
		UIToast.show('New chart');
	}

	/** Swaps the whole editor onto a different chart (new/open). **/
	function adoptChart(chart:SongChart):Void {
		if (audio.playing)
			audio.pause();
		undoStack.reset();
		selection.clear();
		placingNote = null;
		selectedEventGroup = null;
		metaWorking = null;
		editSection = 0;
		PlayState.SONG = chart;
		ensureGfLine(chart);
		model.load(chart);
		audio.load(backend.Song.loadedSongName, chart.needsVoices);
		audio.setVolumes(EditorPrefs.instVol, EditorPrefs.mainVol, EditorPrefs.oppVol);
		audio.setRate(RATE_VALUES[rateIndex]);
		if (audio.loaded) {
			var guard:Int = 0;
			while (model.endTime < audio.length && guard++ < 4000)
				model.ensureSectionCount(model.sectionCount() + 1);
		}
		noteField.maxTime = audio.loaded ? audio.length : -1;
		noteField.waveSource = audio.waveformSound(EditorPrefs.waveTarget);
		noteField.onModelChanged();
		noteField.setViewTime(0);
		buildLeftPanel(currentPanel());
		if (!EditorPrefs.combinedDock)
			buildRightDock();
		refreshSongLabel();
		updateBpmChip();
		updateStatus();
		updateTimeLabel();
		if (scripts != null && scripts.hasScripts)
			scripts.call('onChartLoaded', [chart.song]);
	}

	/** Serializes the chart as deterministic psych_v2 JSON. **/
	function buildV2Json():String {
		return PsychJsonPrinter.print(backend.Song.buildPsychV2(cast model.chart, model.chart), backend.Song.PSYCH_V2_INLINE, backend.Song.PSYCH_V2_KEY_ORDER);
	}

	/** Save-dialog default: the loaded chart's own path, else the mods folder root. **/
	function dialogFileName():String {
		var path:String = backend.Song.chartPath;
		if (path != null && path.length > 0)
			return path;
		#if MODS_ALLOWED
		return Paths.mods() + Paths.formatToSongPath(model.chart.song) + '.json';
		#else
		return Paths.formatToSongPath(model.chart.song) + '.json';
		#end
	}

	/** Ctrl+S: overwrites the known chart path; falls back to a dialog. **/
	function saveChart(forceDialog:Bool):Void {
		var data:String = buildV2Json();
		var path:String = backend.Song.chartPath;
		if (!forceDialog && path != null && path.length > 0) {
			try {
				sys.io.File.saveContent(path, data);
				UIToast.show('Saved: $path');
				if (scripts.hasScripts)
					scripts.call('onSave', [path]);
			} catch (e:Dynamic)
				UIToast.show('Save failed: $e');
			return;
		}
		fileDialog.save(dialogFileName(), data, function():Void {
			backend.Song.chartPath = fileDialog.path.replace('\\', '/');
			UIToast.show('Saved: ${fileDialog.path}');
			if (scripts.hasScripts)
				scripts.call('onSave', [backend.Song.chartPath]);
		}, null, function():Void UIToast.show('Error saving chart'));
	}

	/** Serializes the clean legacy v1 view (native fields never leak into a v1 save). **/
	function exportLegacyChart():Void {
		@:privateAccess model.chart.notes = model.chart.buildLegacySections();
		var data:String = PsychJsonPrinter.print(model.chart.toLegacySwag(), ['sectionNotes', 'events']);
		fileDialog.save(Paths.formatToSongPath(model.chart.song) + '.json', data, function():Void UIToast.show('Legacy chart saved: ${fileDialog.path}'),
			null, function():Void UIToast.show('Error saving chart'));
	}

	/** Autosave folder, relative to the working directory. **/
	static inline var BACKUP_DIR:String = 'backups';

	/** Writes a timestamped psych_v2 backup into `backups/` and prunes to the newest ten. **/
	function doAutosave():Void {
		#if sys
		try {
			if (!sys.FileSystem.exists(BACKUP_DIR))
				sys.FileSystem.createDirectory(BACKUP_DIR);
			var stamp:String = DateTools.format(Date.now(), '%Y-%m-%d_%H-%M-%S');
			var name:String = Paths.formatToSongPath(model.chart.song);
			sys.io.File.saveContent('$BACKUP_DIR/${name}_$stamp.json', buildV2Json());
			pruneBackups();
			autosaveAgeSecs = 0;
		} catch (e:Dynamic) {}
		#end
	}

	#if sys
	function backupFiles():Array<String> {
		if (!sys.FileSystem.exists(BACKUP_DIR))
			return [];
		var out:Array<String> = [];
		for (file in sys.FileSystem.readDirectory(BACKUP_DIR))
			if (file.endsWith('.json'))
				out.push(file);
		out.sort(function(a:String, b:String):Int return (a < b) ? -1 : (a > b ? 1 : 0));
		return out;
	}

	function pruneBackups():Void {
		var files:Array<String> = backupFiles();
		while (files.length > BACKUP_LIMIT) {
			try {
				sys.FileSystem.deleteFile('$BACKUP_DIR/${files[0]}');
			} catch (e:Dynamic) {}
			files.shift();
		}
		backupCount = files.length;
	}
	#end

	/** Loads the newest backup; the chart path is cleared so Save can't clobber the real file. **/
	function openNewestAutosave():Void {
		#if sys
		var files:Array<String> = backupFiles();
		if (files.length == 0) {
			UIToast.show('No autosaves yet');
			return;
		}
		try {
			var raw:String = sys.io.File.getContent('$BACKUP_DIR/${files[files.length - 1]}');
			var loaded:SongChart = backend.Song.parseJSON(raw, files[files.length - 1]);
			if (loaded == null || loaded.sections.length == 0) {
				UIToast.show('Autosave was not a valid chart');
				return;
			}
			backend.Song.chartPath = null; // force Save As so the real chart isn't clobbered silently
			backend.Song.loadedSongName = loaded.song;
			adoptChart(loaded);
			UIToast.show('Loaded autosave: ${files[files.length - 1]}');
		} catch (e:Dynamic)
			UIToast.show('Error loading autosave: $e');
		#end
	}

	/** Exports the chart as V-Slice `-chart.json` + `-metadata.json` into a chosen folder. **/
	function exportVSlice():Void {
		@:privateAccess model.chart.notes = model.chart.buildLegacySections();
		var pack = legacy.editors.charting.VSlice.export(model.chart.toLegacySwag());
		if (pack == null || pack.chart == null || pack.metadata == null) {
			UIToast.show('V-Slice export failed');
			return;
		}
		var chartName:String = Paths.formatToSongPath(model.chart.song);
		fileDialog.openDirectory('Choose the export folder', function():Void {
			try {
				var path:String = fileDialog.path.replace('\\', '/');
				sys.io.File.saveContent('$path/$chartName-chart.json', PsychJsonPrinter.print(pack.chart, ['events', 'notes', 'scrollSpeed']));
				sys.io.File.saveContent('$path/$chartName-metadata.json', PsychJsonPrinter.print(pack.metadata, ['characters', 'difficulties', 'timeChanges']));
				UIToast.show('V-Slice exported to: $path');
			} catch (e:Dynamic)
				UIToast.show('Export failed: $e');
		});
	}

	/** Imports a V-Slice chart (expects `-metadata.json` beside the picked `-chart.json`). **/
	function importVSlice():Void {
		fileDialog.open(null, 'Open a V-Slice -chart.json', null, function():Void {
			try {
				var path:String = fileDialog.path.replace('\\', '/');
				var metaPath:String = path.replace('-chart.json', '-metadata.json');
				if (metaPath == path || !sys.FileSystem.exists(metaPath)) {
					UIToast.show('No matching -metadata.json next to the chart');
					return;
				}
				var pack = legacy.editors.charting.VSlice.convertToPsych(cast haxe.Json.parse(fileDialog.data),
					cast haxe.Json.parse(sys.io.File.getContent(metaPath)));
				if (pack == null || pack.difficulties == null) {
					UIToast.show('Not a valid V-Slice chart');
					return;
				}
				var chosen:backend.Song.SwagSong = null;
				for (k in ['normal', 'hard', 'easy'])
					if (pack.difficulties.exists(k)) {
						chosen = pack.difficulties.get(k);
						break;
					}
				if (chosen == null)
					for (k in pack.difficulties.keys()) {
						chosen = pack.difficulties.get(k);
						break;
					}
				if (chosen == null) {
					UIToast.show('No difficulties found in the V-Slice chart');
					return;
				}
				if (pack.events != null && pack.events.events != null && pack.events.events.length > 0)
					chosen.events = (chosen.events != null) ? chosen.events.concat(pack.events.events) : pack.events.events;
				var native:SongChart = SongChart.fromLegacy(chosen);
				backend.Song.chartPath = null;
				backend.Song.loadedSongName = native.song;
				adoptChart(native);
				UIToast.show('Imported: ${native.song}');
			} catch (e:Dynamic)
				UIToast.show('Import failed: $e');
		});
	}

	/** File picker → parses any supported chart format → swaps the editor onto it. **/
	function openChartDialog():Void {
		fileDialog.open('chart.json', 'Open a chart', null, function():Void {
			try {
				var loaded:SongChart = backend.Song.parseJSON(fileDialog.data, fileDialog.path);
				if (loaded == null || loaded.sections.length == 0) {
					UIToast.show('Not a valid chart file');
					return;
				}
				backend.Song.chartPath = fileDialog.path.replace('\\', '/');
				backend.Song.loadedSongName = loaded.song;
				adoptChart(loaded);
				UIToast.show('Loaded: ${loaded.song}');
			} catch (e:Dynamic)
				UIToast.show('Error loading chart: $e');
		});
	}

	/** Re-reads the current chart from its file on disk, discarding unsaved edits. **/
	function reloadChart():Void {
		var path:String = backend.Song.chartPath;
		if (path == null || path.length == 0) {
			UIToast.show('Nothing to reload (chart was never saved to a file)');
			return;
		}
		#if sys
		try {
			if (!sys.FileSystem.exists(path)) {
				UIToast.show('File not found: $path');
				return;
			}
			var raw:String = sys.io.File.getContent(path);
			var loaded:SongChart = backend.Song.parseJSON(raw, path);
			if (loaded == null || loaded.sections.length == 0) {
				UIToast.show('Not a valid chart file');
				return;
			}
			backend.Song.loadedSongName = loaded.song;
			adoptChart(loaded);
			UIToast.show('Reloaded: ${loaded.song}');
		} catch (e:Dynamic)
			UIToast.show('Error reloading: $e');
		#else
		UIToast.show('Reload is unavailable on this platform');
		#end
	}

	function pasteAtSection():Void {
		if (!clipboard.hasContent) {
			UIToast.show('Clipboard is empty');
			return;
		}
		undoStack.snapshot(model, 'Paste');
		var placed:Int = clipboard.paste(model, model.sectionStart(editSection));
		UIToast.show('Pasted $placed items');
	}

	/** Flips a view toggle from either the View menu or the quick-toggle chips. **/
	function setToggle(which:Int, value:Bool):Void {
		switch (which) {
			case 0:
				EditorPrefs.waveform = value;
				if (waveformChip != null)
					waveformChip.on = value;
				if (noteField != null)
					noteField.waveEnabled = value;
			case 1:
				EditorPrefs.metronome = value;
				if (metronomeChip != null)
					metronomeChip.on = value;
			case 2:
				EditorPrefs.hitsounds = value;
				if (hitsoundsChip != null)
					hitsoundsChip.on = value;
			case 3:
				EditorPrefs.vortex = value;
				if (vortexChip != null)
					vortexChip.on = value;
				if (noteField != null)
					noteField.vortexEnabled = value;
			case 4:
				EditorPrefs.quantColors = value;
				if (quantChip != null)
					quantChip.on = value;
				if (noteField != null)
					noteField.refreshNotes();
			case 5:
				EditorPrefs.downscroll = value;
				if (downscrollChip != null)
					downscrollChip.on = value;
				if (noteField != null)
					noteField.setDownscroll(value);
		}
	}

	/** Folds the right dock into the left dock (extra rail tabs) or restores the two-dock layout. **/
	function setCombinedDock(on:Bool):Void {
		EditorPrefs.combinedDock = on;
		shell.setCombined(on);
		waveformChip = null;
		metronomeChip = null;
		hitsoundsChip = null;
		vortexChip = null;
		quantChip = null;
		downscrollChip = null;
		eventHead = null;
		eventDrop = null;
		eventVal1 = null;
		eventVal2 = null;
		clearPane(shell.rightPane);
		if (!on)
			buildRightDock();
		shell.rail.setTabs(railTabs());
		buildLeftPanel(currentPanel());
		if (noteField != null)
			noteField.resize(shell.fieldX, shell.fieldY, shell.fieldW, shell.fieldH);
	}

	function leaveEditor():Void {
		FlxG.sound.playMusic(Paths.music('freakyMenu'));
		MusicBeatState.switchState(new editors.MasterEditorMenu());
	}

	function openLegacyEditor():Void {
		MusicBeatState.switchState(new legacy.editors.ChartingState());
	}

	function openKeybindsModal():Void {
		var mw:Float = 540;
		var mh:Float = 520;
		var modal:UIModal = new UIModal("Keybinds", mw, mh);

		var pane:UIScrollPane = new UIScrollPane(mw - 32, mh - 40 - 60);
		pane.x = 16;
		pane.y = 4;
		var y:Float = 6;
		var lastGroup:String = null;
		for (action in editors.charting.data.EditorKeybinds.actions) {
			if (action.group != lastGroup) {
				lastGroup = action.group;
				var head:UILabel = new UILabel(action.group.toUpperCase(), 10, 2);
				head.x = 4;
				head.y = y + 6;
				pane.content.addChild(head);
				y += UITheme.px(26);
			}
			var row:KeybindRow = new KeybindRow(action, mw - 32 - UITheme.px(14));
			row.x = 4;
			row.y = y;
			pane.content.addChild(row);
			y += row.h + UITheme.px(4);
		}
		pane.refreshContent(y + 8);
		modal.body.addChild(pane);

		var hint:UILabel = new UILabel("Click a row, then press the new key (Esc cancels).", 10, 2);
		hint.x = 16;
		hint.y = mh - 40 - 44;
		modal.body.addChild(hint);
		var reset:UIButton = new UIButton("Reset All", 110, 28, function():Void {
			editors.charting.data.EditorKeybinds.resetAll();
			modal.close();
			UIToast.show('Keybinds reset to defaults');
		});
		reset.x = 16;
		reset.y = mh - 40 - 76;
		modal.body.addChild(reset);
		var ok:UIButton = new UIButton("Close", 110, 28, modal.close, true);
		ok.x = mw - 126;
		ok.y = mh - 40 - 76;
		modal.body.addChild(ok);
		modal.open();
	}

	function openGoToModal():Void {
		var modal:UIModal = new UIModal("Go to Section", 360, 160);
		var stepper:UIStepper = new UIStepper("Section", 360 - 32, editSection, 1);
		stepper.min = 0;
		stepper.max = model.sectionCount() - 1;
		stepper.boxWidth = UITheme.px(110);
		stepper.x = 16;
		stepper.y = 16;
		modal.body.addChild(stepper);
		var ok:UIButton = new UIButton("Go", 110, 28, function():Void {
			modal.close();
			gotoSection(Std.int(stepper.value));
		}, true);
		ok.x = 360 - 126;
		ok.y = 160 - 40 - 44;
		modal.body.addChild(ok);
		modal.open();
	}

	function openHelpModal():Void {
		var mw:Float = 560;
		var mh:Float = 540;
		var modal:UIModal = new UIModal("Help", mw, mh);

		var pane:UIScrollPane = new UIScrollPane(mw - 32, mh - 40 - 60);
		pane.x = 16;
		pane.y = 4;
		var y:Float = 6;

		inline function header(text:String):Void {
			var head:UILabel = new UILabel(text.toUpperCase(), 10, 2);
			head.x = 4;
			head.y = y + 6;
			pane.content.addChild(head);
			y += UITheme.px(26);
		}
		inline function row(left:String, right:String):Void {
			var l:UILabel = new UILabel(left, 11, 0);
			l.x = 8;
			l.y = y;
			pane.content.addChild(l);
			var r:UILabel = new UILabel(right, 11, 1);
			r.x = UITheme.px(190);
			r.y = y;
			pane.content.addChild(r);
			y += UITheme.px(20);
		}

		header("Mouse");
		row("LMB (grid)", "Place / remove note - drag down for sustain");
		row("Shift + LMB", "Place without snapping");
		row("Ctrl + LMB drag", "Box select (Shift adds to selection)");
		row("RMB", "Select note / event - context menu");
		row("Mouse wheel", "Scroll by one snap unit");
		row("LMB (event lane)", "Place / remove event");

		var lastGroup:String = null;
		for (action in editors.charting.data.EditorKeybinds.actions) {
			if (action.group != lastGroup) {
				lastGroup = action.group;
				header(action.group);
			}
			var bind:String = editors.charting.data.EditorKeybinds.bindLabel(action.id);
			row((bind != "") ? bind : "unbound", action.label);
		}

		pane.refreshContent(y + 8);
		modal.body.addChild(pane);

		var hint:UILabel = new UILabel("Rebind everything under Tools > Keybinds.", 10, 2);
		hint.x = 16;
		hint.y = mh - 40 - 44;
		modal.body.addChild(hint);
		var ok:UIButton = new UIButton("Close", 110, 28, modal.close, true);
		ok.x = mw - 126;
		ok.y = mh - 40 - 76;
		modal.body.addChild(ok);
		modal.open();
	}

	function openAboutModal():Void {
		var modal:UIModal = new UIModal("About", 500, 200);
		var l1:UILabel = new UILabel("Psych Engine v2.0 chart editor", 16, 0);
		l1.x = 16;
		l1.y = 14;
		modal.body.addChild(l1);
		var l2:UILabel = new UILabel("A full rewrite of the Chart Editor with a UI framework written from scratch.", 11, 1);
		l2.x = 16;
		l2.y = 48;
		modal.body.addChild(l2);
		var ok:UIButton = new UIButton("Close", 110, 28, modal.close, true);
		ok.x = 500 - 126;
		ok.y = 200 - 40 - 44;
		modal.body.addChild(ok);
		modal.open();
	}

	/** Disposes and removes everything in a dock pane (before a rebuild). **/
	static function clearPane(pane:UIScrollPane):Void {
		var i:Int = pane.content.numChildren;
		while (--i >= 0) {
			var child = pane.content.getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).dispose();
		}
		pane.content.removeChildren();
		pane.setScroll(0);
	}

	/**
		(Re)builds the left dock for a rail tab. In combined-dock mode the merged tabs gain
		their right-dock sections and CHAR/STRM become real tabs.
		@param tabIndex the rail tab (indexes `TAB_NAMES`)
		@param keepScroll restores the pane's scroll position (same-tab rebuilds)
	**/
	function buildLeftPanel(tabIndex:Int, keepScroll:Bool = false):Void {
		var scroll:Float = keepScroll ? shell.leftPane.scrollY : 0;
		clearPane(shell.leftPane);
		if (EditorPrefs.combinedDock) {
			eventHead = null;
			eventDrop = null;
			eventVal1 = null;
			eventVal2 = null;
		}
		sectionHead = null;
		camTargetDrop = null;
		altCheck = null;
		bpmStep = null;
		beatsStep = null;
		denomDrop = null;
		speedStep = null;
		velStep = null;
		keysStep = null;
		selectedHead = null;
		hitTimeStep = null;
		sustainStep = null;
		noteTypeDrop = null;

		var colW:Float = shell.leftW - UITheme.px(26);
		var flow:DockFlow = new DockFlow(shell.leftPane, UITheme.px(12), UITheme.px(8));

		switch (tabIndex) {
			case 0:
				buildSongPanel(flow, colW);
			case 1:
				buildSectionPanel(flow, colW);
			case 2 if (EditorPrefs.combinedDock):
				flow.header(new UIAccordion("Events", colW));
				addHintRow(flow, colW, "LMB in the lane places; RMB a mark to edit.");
				buildEventSection(flow, colW);
			case 3:
				buildDataPanel(flow, colW);
			case 4 if (EditorPrefs.combinedDock):
				flow.header(new UIAccordion("Audio", colW));
				buildSongAudioSection(flow, colW);
			case 5:
				buildMetaPanel(flow, colW);
			case 6 if (EditorPrefs.combinedDock):
				flow.header(new UIAccordion("Display", colW));
				buildQuickTogglesSection(flow, colW);
			case 6:
				flow.header(new UIAccordion("Display", colW));
				addHintRow(flow, colW, "Quick toggles live in the right dock.");
			case 7:
				buildOptionsPanel(flow, colW);
			case 8:
				buildCharacterSection(flow, colW);
			case 9:
				buildStrumlinesSection(flow, colW);
			case 10:
				buildPatternsPanel(flow, colW);
			default:
				flow.header(new UIAccordion(TAB_NAMES[tabIndex], colW));
				addHintRow(flow, colW, 'Nothing here yet.');
		}
		flow.reflow();
		if (keepScroll)
			shell.leftPane.setScroll(scroll);
	}

	function addHintRow(flow:DockFlow, colW:Float, text:String):Void {
		var hint:UILabel = new UILabel(text, 11, 2);
		hint.resize(colW, UITheme.px(18));
		flow.add(hint);
	}

	/** SONG tab: song-level metadata, characters/stage pickers and audio reload. **/
	function buildSongPanel(flow:DockFlow, colW:Float):Void {
		var chart:SongChart = model.chart;
		flow.header(new UIAccordion("Song", colW));

		var name:UITextInput = new UITextInput("Song Name", colW, chart.song, function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Song Name');
			chart.song = v;
			refreshSongLabel();
		});
		name.boxWidth = UITheme.px(130);
		flow.add(name);

		var bpm:UIStepper = new UIStepper("Base BPM", colW, chart.bpm, 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'BPM');
			model.setBpm(0, v, EditorPrefs.bpmAdapt);
		});
		bpm.min = 1;
		bpm.max = 999;
		bpm.decimals = 2;
		flow.add(bpm);

		var speed:UIStepper = new UIStepper("Scroll Speed", colW, chart.speed, 0.1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Scroll Speed');
			chart.speed = v;
			model.markDirty();
		});
		speed.min = 0.1;
		speed.max = 10;
		speed.decimals = 1;
		flow.add(speed);

		var offset:UIStepper = new UIStepper("Offset (ms)", colW, chart.offset, 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Offset');
			chart.offset = v;
			model.markDirty();
		});
		offset.min = -5000;
		offset.max = 5000;
		flow.add(offset);

		flow.add(new UICheckbox("Needs Voices", colW, chart.needsVoices, function(v:Bool):Void {
			undoStack.snapshot(model, 'Needs Voices');
			chart.needsVoices = v;
		}));

		var kc:UIStepper = new UIStepper("Base Key Count", colW, model.keyCountAt(0), 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Key Count');
			model.setKeyCount(0, Std.int(v));
		});
		kc.min = 1;
		kc.max = 9;
		flow.add(kc);

		var vel:UIStepper = new UIStepper("Scroll Velocity", colW, model.velocityAt(0), 0.1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Scroll Velocity');
			model.setVelocity(0, v);
		});
		vel.min = -10;
		vel.max = 10;
		vel.decimals = 1;
		flow.add(vel);

		var beats:UIStepper = new UIStepper("Beats", colW, model.beatsAt(0), 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Time Signature');
			model.setBeats(0, v, EditorPrefs.timeSigAdapt);
		});
		beats.tooltip = "Base time signature numerator";
		beats.min = 1;
		beats.max = 16;
		flow.add(beats);

		var denom:UIDropdown = new UIDropdown("Denominator", colW, function(index:Int, _:String):Void {
			undoStack.snapshot(model, 'Time Signature');
			model.setDenominator(0, VALID_DENOMINATORS[index], EditorPrefs.timeSigAdapt);
		});
		denom.tooltip = "Base time signature denominator";
		denom.boxWidth = UITheme.px(90);
		denom.setItems(DENOMINATOR_LABELS);
		denom.select(denomIndex(model.denominatorAt(0)));
		flow.add(denom);

		flow.header(new UIAccordion("Characters", colW));
		addPickerRow(flow, colW, "Player", characterList(), chart.player1, function(v:String):Void {
			undoStack.snapshot(model, 'Characters');
			chart.player1 = v;
		});
		addPickerRow(flow, colW, "Opponent", characterList(), chart.player2, function(v:String):Void {
			undoStack.snapshot(model, 'Characters');
			chart.player2 = v;
		});
		addPickerRow(flow, colW, "Girlfriend", characterList(), chart.gfVersion, function(v:String):Void {
			undoStack.snapshot(model, 'Characters');
			chart.gfVersion = v;
		});
		addPickerRow(flow, colW, "Stage", stageList(), chart.stage, function(v:String):Void {
			undoStack.snapshot(model, 'Stage');
			chart.stage = v;
		});

		flow.header(new UIAccordion("Audio Files", colW));
		flow.add(new UIButton("Reload Audio", colW, UITheme.px(28), function():Void {
			backend.Song.loadedSongName = model.chart.song;
			audio.load(backend.Song.loadedSongName, model.chart.needsVoices);
			applyAudioVolumes();
			audio.setRate(RATE_VALUES[rateIndex]);
			noteField.maxTime = audio.loaded ? audio.length : -1;
			applyWaveConfig();
			UIToast.show(audio.loaded ? 'Audio loaded' : 'No audio found for "${model.chart.song}"');
			updateTimeLabel();
		}));
	}

	function characterList():Array<String> {
		#if MODS_ALLOWED
		var list:Array<String> = listEditorFiles('characters/', ['.json']);
		list.sort(function(a:String, b:String):Int return (a < b) ? -1 : (a > b ? 1 : 0));
		return list;
		#else
		return [];
		#end
	}

	function stageList():Array<String> {
		#if MODS_ALLOWED
		var list:Array<String> = listEditorFiles('stages/', ['.json']);
		list.sort(function(a:String, b:String):Int return (a < b) ? -1 : (a > b ? 1 : 0));
		return list;
		#else
		return [];
		#end
	}

	/** A dropdown row when options exist, else a plain text input (same commit callback). **/
	function addPickerRow(flow:DockFlow, colW:Float, label:String, options:Array<String>, current:String, commit:String->Void):Void {
		if (options.length > 0) {
			if (current != null && current.length > 0 && options.indexOf(current) < 0)
				options.unshift(current);
			var drop:UIDropdown = new UIDropdown(label, colW, function(_:Int, value:String):Void commit(value));
			drop.boxWidth = UITheme.px(140);
			drop.setItems(options);
			var idx:Int = options.indexOf(current);
			if (idx >= 0)
				drop.select(idx);
			flow.add(drop);
		} else {
			var input:UITextInput = new UITextInput(label, colW, (current != null) ? current : '', function(v:String):Void commit(v));
			input.boxWidth = UITheme.px(140);
			flow.add(input);
		}
	}

	/** META tab: edits `data/<song>/metadata.json` (Freeplay info flyout). **/
	function buildMetaPanel(flow:DockFlow, colW:Float):Void {
		if (metaWorking == null) {
			var loaded:backend.SongMeta.SongMetaInfo = backend.SongMeta.load(Paths.formatToSongPath(model.chart.song));
			metaWorking = (loaded != null) ? loaded : (cast {});
		}
		var head:UIAccordion = new UIAccordion("Metadata", colW);
		head.hint = "metadata.json";
		flow.header(head);

		var title:UITextInput = new UITextInput("Title", colW, (metaWorking.songName != null) ? metaWorking.songName : '',
			function(v:String):Void metaWorking.songName = v);
		title.boxWidth = UITheme.px(130);
		flow.add(title);
		var artist:UITextInput = new UITextInput("Artist", colW, (metaWorking.artist != null) ? metaWorking.artist : '',
			function(v:String):Void metaWorking.artist = v);
		artist.boxWidth = UITheme.px(130);
		flow.add(artist);
		var charter:UITextInput = new UITextInput("Charter", colW, (metaWorking.charter != null) ? metaWorking.charter : '',
			function(v:String):Void metaWorking.charter = v);
		charter.boxWidth = UITheme.px(130);
		flow.add(charter);
		var source:UITextInput = new UITextInput("Source", colW, (metaWorking.source != null) ? metaWorking.source : '',
			function(v:String):Void metaWorking.source = v);
		source.boxWidth = UITheme.px(130);
		flow.add(source);
		var tags:UITextInput = new UITextInput("Tags", colW, (metaWorking.tags != null) ? metaWorking.tags.join(', ') : '', function(v:String):Void {
			var list:Array<String> = [];
			for (tag in v.split(','))
				if (tag.trim().length > 0)
					list.push(tag.trim());
			metaWorking.tags = list;
		});
		tags.tooltip = "Comma-separated";
		tags.boxWidth = UITheme.px(130);
		flow.add(tags);

		flow.header(new UIAccordion("Display Overrides", colW));
		var dispBpm:UIStepper = new UIStepper("Display BPM", colW, (metaWorking.displayBpm != null) ? metaWorking.displayBpm : 0, 1, function(v:Float):Void {
			if (v > 0)
				metaWorking.displayBpm = v;
			else
				Reflect.deleteField(metaWorking, 'displayBpm');
		});
		dispBpm.tooltip = "0 = show the real BPM";
		dispBpm.min = 0;
		dispBpm.max = 999;
		dispBpm.decimals = 2;
		flow.add(dispBpm);

		var sig:Array<Int> = (metaWorking.displayTimeSignature != null) ? metaWorking.displayTimeSignature : [0, 0];
		var sigNum:UIStepper = new UIStepper("Sig Numerator", colW, sig[0], 1, function(v:Float):Void setMetaSig(0, Std.int(v)));
		sigNum.min = 0;
		sigNum.max = 32;
		flow.add(sigNum);
		var sigDen:UIStepper = new UIStepper("Sig Denominator", colW, (sig.length > 1) ? sig[1] : 0, 1, function(v:Float):Void setMetaSig(1, Std.int(v)));
		sigDen.min = 0;
		sigDen.max = 32;
		flow.add(sigDen);

		flow.add(new UIButton("Save Metadata", colW, UITheme.px(28), saveMetaFile));
		addHintRow(flow, colW, "Custom label/value rows aren't implemented yet.");
	}

	function setMetaSig(slot:Int, v:Int):Void {
		var sig:Array<Int> = (metaWorking.displayTimeSignature != null) ? metaWorking.displayTimeSignature : [0, 0];
		while (sig.length < 2)
			sig.push(0);
		sig[slot] = v;
		if (sig[0] > 0 && sig[1] > 0)
			metaWorking.displayTimeSignature = sig;
		else
			Reflect.deleteField(metaWorking, 'displayTimeSignature');
	}

	/** Writes `metadata.json` beside the chart file (requires a saved chart path). **/
	function saveMetaFile():Void {
		#if sys
		if (backend.Song.chartPath == null) {
			UIToast.show('Save the chart first so the editor knows where metadata.json lives');
			return;
		}
		for (field in ['songName', 'artist', 'charter', 'source']) {
			var v:Dynamic = Reflect.field(metaWorking, field);
			if (v == null || Std.string(v).length < 1)
				Reflect.deleteField(metaWorking, field);
		}
		if (metaWorking.tags != null && metaWorking.tags.length < 1)
			Reflect.deleteField(metaWorking, 'tags');

		var p:String = backend.Song.chartPath.replace('\\', '/');
		var metaPath:String = p.substr(0, p.lastIndexOf('/')) + '/metadata.json';
		try {
			sys.io.File.saveContent(metaPath, haxe.Json.stringify(metaWorking, null, '\t'));
			UIToast.show('Metadata saved: $metaPath');
		} catch (e:Dynamic)
			UIToast.show('Error saving metadata: $e');
		#else
		UIToast.show('Metadata saving is desktop-only');
		#end
	}

	/** DATA tab: texture overrides and the game-over set. **/
	function buildDataPanel(flow:DockFlow, colW:Float):Void {
		var chart:SongChart = model.chart;
		flow.header(new UIAccordion("Textures", colW));
		var arrow:UITextInput = new UITextInput("Note Skin", colW, (chart.arrowSkin != null) ? chart.arrowSkin : '', function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Note Skin');
			chart.arrowSkin = (v.length > 0) ? v : null;
		});
		arrow.boxWidth = UITheme.px(130);
		flow.add(arrow);
		var splash:UITextInput = new UITextInput("Splash Skin", colW, (chart.splashSkin != null) ? chart.splashSkin : '', function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Splash Skin');
			chart.splashSkin = (v.length > 0) ? v : null;
		});
		splash.boxWidth = UITheme.px(130);
		flow.add(splash);
		flow.add(new UICheckbox("Disable Note RGB", colW, chart.disableNoteRGB, function(v:Bool):Void {
			undoStack.snapshot(model, 'Note RGB');
			chart.disableNoteRGB = v;
		}));

		flow.header(new UIAccordion("Game Over", colW));
		var goChar:UITextInput = new UITextInput("Character", colW, (chart.gameOverChar != null) ? chart.gameOverChar : '', function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Game Over');
			chart.gameOverChar = (v.length > 0) ? v : null;
		});
		goChar.boxWidth = UITheme.px(130);
		flow.add(goChar);
		var goSound:UITextInput = new UITextInput("Death Sound", colW, (chart.gameOverSound != null) ? chart.gameOverSound : '', function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Game Over');
			chart.gameOverSound = (v.length > 0) ? v : null;
		});
		goSound.boxWidth = UITheme.px(130);
		flow.add(goSound);
		var goLoop:UITextInput = new UITextInput("Loop Music", colW, (chart.gameOverLoop != null) ? chart.gameOverLoop : '', function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Game Over');
			chart.gameOverLoop = (v.length > 0) ? v : null;
		});
		goLoop.boxWidth = UITheme.px(130);
		flow.add(goLoop);
		var goEnd:UITextInput = new UITextInput("Retry Sound", colW, (chart.gameOverEnd != null) ? chart.gameOverEnd : '', function(v:String):Void {
			undoStack.snapshotCoalesced(model, 'Game Over');
			chart.gameOverEnd = (v.length > 0) ? v : null;
		});
		goEnd.boxWidth = UITheme.px(130);
		flow.add(goEnd);
	}

	/** OPTS tab: editor preferences, metronome presets, performance and script buttons. **/
	function buildOptionsPanel(flow:DockFlow, colW:Float):Void {
		flow.header(new UIAccordion("Editor Options", colW));
		flow.add(new UIButton("Keybinds...", colW, UITheme.px(28), openKeybindsModal));
		flow.add(new UIButton("Open Autosave", colW, UITheme.px(28), openNewestAutosave));
		flow.add(new UICheckbox("Combined Dock", colW, EditorPrefs.combinedDock, function(v:Bool):Void setCombinedDock(v)));
		var snapGhost:UICheckbox = new UICheckbox("Snap Region Marker", colW, EditorPrefs.snapRegionGhost,
			function(v:Bool):Void EditorPrefs.snapRegionGhost = v);
		snapGhost.tooltip = "Highlight every grid cell the current snap covers under the cursor";
		flow.add(snapGhost);

		flow.header(new UIAccordion("Note Adaptation", colW));
		var adaptLabels:Array<String> = ["Keep (ms)", "Rescale", "Snap"];
		var bpmAdapt:UIDropdown = new UIDropdown("BPM Change", colW, function(i:Int, _:String):Void EditorPrefs.bpmAdapt = i);
		bpmAdapt.boxWidth = UITheme.px(120);
		bpmAdapt.setItems(adaptLabels);
		bpmAdapt.select(clampIndex(EditorPrefs.bpmAdapt, adaptLabels.length));
		bpmAdapt.tooltip = "How existing notes react when you change BPM";
		flow.add(bpmAdapt);
		var tsAdapt:UIDropdown = new UIDropdown("Time Sig Change", colW, function(i:Int, _:String):Void EditorPrefs.timeSigAdapt = i);
		tsAdapt.boxWidth = UITheme.px(120);
		tsAdapt.setItems(adaptLabels);
		tsAdapt.select(clampIndex(EditorPrefs.timeSigAdapt, adaptLabels.length));
		tsAdapt.tooltip = "How existing notes react when you change beats or denominator";
		flow.add(tsAdapt);

		flow.header(new UIAccordion("Theme", colW));
		var themeDrop:UIDropdown = new UIDropdown("Preset", colW, function(index:Int, _:String):Void {
			EditorPrefs.themePreset = index;
			applyThemeFromPrefs();
			EditorPrefs.save();
		});
		themeDrop.boxWidth = UITheme.px(120);
		themeDrop.setItems([for (p in ui.UITheme.PRESETS) p.name]);
		themeDrop.select(clampIndex(EditorPrefs.themePreset, ui.UITheme.PRESETS.length));
		themeDrop.tooltip = "Base colour scheme (Light mode included)";
		flow.add(themeDrop);
		var accentHex:UITextInput = new UITextInput("Accent (hex)", colW,
			(EditorPrefs.accentOverride >= 0) ? StringTools.hex(EditorPrefs.accentOverride, 6) : '', function(v:String):Void {
				var col:Int = parseHexColor(v);
				if (StringTools.trim(v).length == 0) {
					EditorPrefs.accentOverride = -1;
					applyThemeFromPrefs();
					EditorPrefs.save();
				} else if (col >= 0) {
					EditorPrefs.accentOverride = col;
					ui.UITheme.applyAccent(col);
					EditorPrefs.save();
				}
			});
		accentHex.boxWidth = UITheme.px(100);
		accentHex.tooltip = "Custom accent colour, e.g. 8A5EE0 (blank = use the preset's accent)";
		flow.add(accentHex);

		flow.header(new UIAccordion("Metronome", colW));
		var metroDrop:UIDropdown = new UIDropdown("Sound", colW, function(index:Int, _:String):Void EditorPrefs.metroPreset = index);
		metroDrop.boxWidth = UITheme.px(120);
		metroDrop.setItems([for (p in METRONOME_PRESETS) p.name]);
		metroDrop.select(clampIndex(EditorPrefs.metroPreset, METRONOME_PRESETS.length));
		flow.add(metroDrop);
		flow.add(new UICheckbox("Accent First Beat", colW, EditorPrefs.metroAccent, function(v:Bool):Void EditorPrefs.metroAccent = v));

		flow.header(new UIAccordion("Performance", colW));
		var poolCap:UIStepper = new UIStepper("Note Pool Cap", colW, EditorPrefs.notePoolCap, 32, function(v:Float):Void {
			EditorPrefs.notePoolCap = Std.int(v);
		});
		poolCap.tooltip = "Max pooled note sprites kept in memory (0 = dynamic/unlimited)";
		poolCap.min = 0;
		poolCap.max = 1024;
		flow.add(poolCap);

		if (customOptionButtons.length > 0) {
			flow.header(new UIAccordion("Scripts", colW));
			for (b in customOptionButtons)
				flow.add(new UIButton(b.label, colW, UITheme.px(28), b.cb));
		}

		flow.header(new UIAccordion("About", colW));
		addHintRow(flow, colW, "Psych Engine v2.0 chart editor.");
	}

	/** SECT tab: per-section inherited values, section tools and the selection inspector. **/
	function buildSectionPanel(flow:DockFlow, colW:Float):Void {
		sectionHead = new UIAccordion("Section - #0", colW);
		flow.header(sectionHead);

		camTargetDrop = new UIDropdown("Camera Target", colW, function(index:Int, _:String):Void {
			undoStack.snapshot(model, 'Camera Target');
			model.setCameraTarget(editSection, index);
		});
		camTargetDrop.boxWidth = UITheme.px(110);
		var lineIds:Array<String> = [];
		for (line in model.chart.strumLines)
			lineIds.push(line.id);
		camTargetDrop.setItems(lineIds);
		flow.add(camTargetDrop);

		altCheck = new UICheckbox("Alt Animation", colW, false, function(v:Bool):Void {
			undoStack.snapshot(model, 'Alt Animation');
			model.setSectionAlt(editSection, v);
		});
		altCheck.tooltip = "Alt-anim every opponent note in this section";
		flow.add(altCheck);

		bpmStep = new UIStepper("BPM", colW, 150, 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'BPM');
			model.setBpm(editSection, v, EditorPrefs.bpmAdapt);
		});
		bpmStep.tooltip = "Inherited from the previous section until changed";
		bpmStep.min = 1;
		bpmStep.max = 999;
		bpmStep.decimals = 2;
		flow.add(bpmStep);

		beatsStep = new UIStepper("Beats", colW, 4, 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Time Signature');
			model.setBeats(editSection, v, EditorPrefs.timeSigAdapt);
		});
		beatsStep.tooltip = "Time signature numerator (inherited until changed)";
		beatsStep.min = 1;
		beatsStep.max = 16;
		flow.add(beatsStep);

		denomDrop = new UIDropdown("Denominator", colW, function(index:Int, _:String):Void {
			undoStack.snapshot(model, 'Time Signature');
			model.setDenominator(editSection, VALID_DENOMINATORS[index], EditorPrefs.timeSigAdapt);
		});
		denomDrop.tooltip = "Time signature denominator (inherited until changed)";
		denomDrop.boxWidth = UITheme.px(90);
		denomDrop.setItems(DENOMINATOR_LABELS);
		denomDrop.select(denomIndex(model.denominatorAt(editSection)));
		flow.add(denomDrop);

		speedStep = new UIStepper("Scroll Speed", colW, 1.0, 0.1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Scroll Speed');
			model.chart.speed = v;
			model.markDirty();
		});
		speedStep.tooltip = "Song-level scroll speed";
		speedStep.min = 0.1;
		speedStep.max = 10;
		speedStep.decimals = 1;
		flow.add(speedStep);

		velStep = new UIStepper("Scroll Velocity", colW, 1.0, 0.1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Scroll Velocity');
			model.setVelocity(editSection, v);
		});
		velStep.tooltip = "Inherited from the previous section until changed";
		velStep.min = -10;
		velStep.max = 10;
		velStep.decimals = 1;
		flow.add(velStep);

		keysStep = new UIStepper("Key Count", colW, 4, 1, function(v:Float):Void {
			undoStack.snapshotCoalesced(model, 'Key Count');
			model.setKeyCount(editSection, Std.int(v));
		});
		keysStep.tooltip = "Inherited from the previous section until changed";
		keysStep.min = 1;
		keysStep.max = 9;
		flow.add(keysStep);

		var tools:UIAccordion = new UIAccordion("Section Tools", colW);
		tools.hint = "notes + events";
		flow.header(tools);
		flow.add(buttonPair(colW, "Copy", copySection, "Swap Sides", swapSection));
		flow.add(buttonPair(colW, "Paste", pasteAtSection, "Duet", duetSection));
		flow.add(buttonPair(colW, "Copy Prev", copyLastSection, "Mirror", mirrorSection));
		var copyFromStep:UIStepper = new UIStepper("Copy From", colW, copyFromBack, 1, function(v:Float):Void {
			copyFromBack = (v < 1) ? 1 : Std.int(v);
		});
		copyFromStep.decimals = 0;
		copyFromStep.min = 1;
		copyFromStep.max = 999;
		copyFromStep.boxWidth = UITheme.px(80);
		flow.add(copyFromStep);
		flow.add(new UIButton("Copy From", colW, UITheme.px(26), copyFromNSectionsBack));
		var clear:UIButton = new UIButton("Clear Section", colW, UITheme.px(28), clearSection);
		clear.danger = true;
		flow.add(clear);

		selectedHead = new UIAccordion("Selected - 0 Notes", colW);
		flow.header(selectedHead);
		hitTimeStep = new UIStepper("Hit Time (ms)", colW, 0, 0.5, function(v:Float):Void {
			if (selection.count != 1)
				return;
			undoStack.snapshotCoalesced(model, 'Hit Time');
			var note:SongNote = selection.notes[0];
			model.moveNote(note, (v < 0) ? 0 : v, note.strumLine, note.column);
			if (scripts.hasScripts)
				scripts.call('onNoteMoved', [note.time, note.column, note.strumLine]);
		});
		hitTimeStep.decimals = 1;
		hitTimeStep.min = 0;
		hitTimeStep.max = 1e10;
		hitTimeStep.boxWidth = UITheme.px(100);
		flow.add(hitTimeStep);
		sustainStep = new UIStepper("Sustain", colW, 0, 0.5, function(v:Float):Void {
			if (selection.count == 0)
				return;
			undoStack.snapshotCoalesced(model, 'Sustain');
			var i:Int = selection.notes.length;
			while (--i >= 0)
				selection.notes[i].length = (v > 0) ? v : 0;
			model.markDirty();
		});
		sustainStep.decimals = 1;
		sustainStep.min = 0;
		sustainStep.max = 1e10;
		sustainStep.boxWidth = UITheme.px(100);
		flow.add(sustainStep);
		noteTypeDrop = new UIDropdown("Note Type", colW, function(index:Int, _:String):Void {
			if (selection.count == 0)
				return;
			undoStack.snapshot(model, 'Note Type');
			var typeName:String = noteTypesList[index];
			var i:Int = selection.notes.length;
			while (--i >= 0)
				selection.notes[i].type = typeName;
			model.markDirty();
		});
		noteTypeDrop.boxWidth = UITheme.px(130);
		noteTypeDrop.setItems(noteTypesList, [for (i => n in noteTypesList) (n == '') ?'$i. Normal':'$i. $n']);
		flow.add(noteTypeDrop);

		refreshSectionPanel();
		refreshSelectedPanel();
	}

	function buildNoteTypesList():Void {
		noteTypesList = [];
		#if MODS_ALLOWED
		var exts:Array<String> = ['.txt'];
		#if LUA_ALLOWED
		exts.push('.lua');
		#end
		#if HSCRIPT_ALLOWED
		exts.push('.hx');
		#end
		noteTypesList = listEditorFiles('custom_notetypes/', exts);
		#end
		for (id => noteType in objects.notes.NoteDefaults.defaultNoteTypes)
			if (!noteTypesList.contains(noteType))
				noteTypesList.insert(id, noteType);
	}

	function onSelectionChanged():Void {
		updateStatus();
		refreshSelectedPanel();
		if (scripts != null && scripts.hasScripts)
			scripts.call('onSelectionChanged', [selection.count]);
	}

	function refreshSelectedPanel():Void {
		if (selectedHead == null)
			return;
		selectedHead.title = 'Selected - ${selection.count} Notes';
		if (selection.count == 0)
			return;
		var first:SongNote = selection.notes[0];
		hitTimeStep.value = first.time;
		sustainStep.value = first.length;
		// step the sustain by one snap unit at the note's section, not a raw 0.5ms nudge (which
		// was too fine to ever build a visible hold).
		var susStep:Float = model.snapMs(model.sectionAt(first.time), snap.value);
		sustainStep.step = (susStep > 1) ? susStep : 1;
		var idx:Int = noteTypesList.indexOf((first.type != null) ? first.type : '');
		if (idx >= 0)
			noteTypeDrop.select(idx);
	}

	function copySection():Void {
		clipboard.copySection(model, editSection);
		UIToast.show('Copied section (${clipboard.noteCount} notes)');
	}

	function swapSection():Void {
		undoStack.snapshot(model, 'Swap Sides');
		model.swapSection(editSection);
		UIToast.show('Swapped sides');
	}

	function duetSection():Void {
		undoStack.snapshot(model, 'Duet');
		var added:Int = model.duetSection(editSection);
		UIToast.show('Duet: $added notes added');
	}

	function mirrorSection():Void {
		undoStack.snapshot(model, 'Mirror');
		model.mirrorSection(editSection);
		UIToast.show('Mirrored section');
	}

	function copyLastSection():Void {
		undoStack.snapshot(model, 'Copy Last');
		var added:Int = model.copyFromSection(editSection, -1);
		UIToast.show('Copied $added notes from the previous section');
	}

	function copyFromNSectionsBack():Void {
		var back:Int = (copyFromBack < 1) ? 1 : copyFromBack;
		if (editSection - back < 0) {
			UIToast.show('No section $back back to copy from');
			return;
		}
		undoStack.snapshot(model, 'Copy From -$back');
		var added:Int = model.copyFromSection(editSection, -back);
		UIToast.show('Copied $added notes from $back section(s) back');
	}

	/** Applies the saved theme preset + optional custom accent to the live UI. **/
	function applyThemeFromPrefs():Void {
		var idx:Int = clampIndex(EditorPrefs.themePreset, ui.UITheme.PRESETS.length);
		ui.UITheme.apply(ui.UITheme.PRESETS[idx].palette);
		if (EditorPrefs.accentOverride >= 0)
			ui.UITheme.applyAccent(EditorPrefs.accentOverride);
	}

	/** Parses a `RRGGBB` / `#RRGGBB` hex string, or -1 when it isn't a valid colour. **/
	static function parseHexColor(s:String):Int {
		if (s == null)
			return -1;
		s = StringTools.trim(s);
		if (StringTools.startsWith(s, '#'))
			s = s.substr(1);
		if (StringTools.startsWith(s, '0x') || StringTools.startsWith(s, '0X'))
			s = s.substr(2);
		if (s.length != 6)
			return -1;
		var v:Null<Int> = Std.parseInt('0x' + s);
		return (v != null) ? (v & 0xFFFFFF) : -1;
	}

	/** Re-snaps every note in the chart to the current grid snap. **/
	function adaptNotesToSnap():Void {
		undoStack.snapshot(model, 'Adapt Notes');
		var moved:Int = model.snapAllNotes(snap.value);
		model.markDirty();
		selection.prune(model.chart.noteList);
		UIToast.show('Adapted $moved notes to ${snap.label()}');
	}

	function clearSection():Void {
		undoStack.snapshot(model, 'Clear Section');
		var removed:Int = model.clearSection(editSection, true, true);
		UIToast.show('Cleared $removed items');
	}

	function buttonPair(colW:Float, leftLabel:String, leftCb:Void->Void, rightLabel:String, rightCb:Void->Void):UIComponent {
		var group:UIComponent = new UIComponent(false, false);
		var half:Float = (colW - UITheme.px(8)) / 2;
		var bh:Float = UITheme.px(26);
		var a:UIButton = new UIButton(leftLabel, half, bh, leftCb);
		a.fontSize = 11;
		group.addChild(a);
		var b:UIButton = new UIButton(rightLabel, half, bh, rightCb);
		b.fontSize = 11;
		b.x = half + UITheme.px(8);
		group.addChild(b);
		group.resize(colW, bh);
		return group;
	}

	function buildRightDock():Void {
		var keepScroll:Float = shell.rightPane.scrollY;
		clearPane(shell.rightPane);
		waveformChip = null;
		metronomeChip = null;
		hitsoundsChip = null;
		vortexChip = null;
		quantChip = null;
		downscrollChip = null;
		eventHead = null;
		eventDrop = null;
		eventVal1 = null;
		eventVal2 = null;

		var colW:Float = shell.rightW - UITheme.px(26);
		var flow:DockFlow = new DockFlow(shell.rightPane, UITheme.px(12), UITheme.px(8));

		flow.header(new UIAccordion("Quick Toggles", colW));
		buildQuickTogglesSection(flow, colW);

		flow.header(new UIAccordion("Character", colW));
		buildCharacterCard(flow, colW);

		var strumHead:UIAccordion = new UIAccordion("Strumlines", colW);
		strumHead.hint = 'visible <= $MAX_VISIBLE_LINES';
		flow.header(strumHead);
		buildStrumlineRows(flow, colW);

		flow.header(new UIAccordion("Song Audio", colW));
		buildSongAudioSection(flow, colW);

		buildEventSection(flow, colW);

		flow.reflow();
		shell.rightPane.setScroll(keepScroll);
	}

	function buildQuickTogglesSection(flow:DockFlow, colW:Float):Void {
		waveformChip = new UIChip("Waveform", true, EditorPrefs.waveform, function(v:Bool):Void setToggle(0, v));
		metronomeChip = new UIChip("Metronome", true, EditorPrefs.metronome, function(v:Bool):Void setToggle(1, v));
		hitsoundsChip = new UIChip("Hitsounds", true, EditorPrefs.hitsounds, function(v:Bool):Void setToggle(2, v));
		vortexChip = new UIChip("Vortex", true, EditorPrefs.vortex, function(v:Bool):Void setToggle(3, v));
		quantChip = new UIChip("Quant", true, EditorPrefs.quantColors, function(v:Bool):Void setToggle(4, v));
		downscrollChip = new UIChip("Downscroll", true, EditorPrefs.downscroll, function(v:Bool):Void setToggle(5, v));
		flow.add(chipRow(colW, [
			waveformChip,
			metronomeChip,
			hitsoundsChip,
			vortexChip,
			quantChip,
			downscrollChip
		]));

		if (customToggles.length > 0) {
			var chips:Array<UIChip> = [];
			for (t in customToggles) {
				var entry:CustomToggle = t;
				chips.push(new UIChip(entry.label, true, entry.on, function(v:Bool):Void {
					entry.on = v;
					entry.cb(v);
				}));
			}
			flow.add(chipRow(colW, chips));
		}
	}

	function buildCharacterSection(flow:DockFlow, colW:Float):Void {
		flow.header(new UIAccordion("Character", colW));
		buildCharacterCard(flow, colW);
	}

	function buildCharacterCard(flow:DockFlow, colW:Float):Void {
		var card:UIPanel = new UIPanel(colW, UITheme.px(104), UITheme.card);
		card.corner = UITheme.px(10);
		card.outline = true;
		var charChip:UIChip = new UIChip("PLAYER - " + model.chart.player1);
		charChip.x = UITheme.px(10);
		charChip.y = UITheme.px(10);
		charChip.onClick = todo("Character preview isn't implemented yet");
		card.addChild(charChip);
		flow.add(card);
	}

	function buildStrumlinesSection(flow:DockFlow, colW:Float):Void {
		var head:UIAccordion = new UIAccordion("Strumlines", colW);
		head.hint = 'visible <= $MAX_VISIBLE_LINES';
		flow.header(head);
		buildStrumlineRows(flow, colW);
	}

	/** First player strumline (fallback 0) - the default pattern target. **/
	function defaultPatternLine():Int {
		var lines = model.chart.strumLines;
		var i:Int = 0;
		while (i < lines.length) {
			if (lines[i].isPlayer)
				return i;
			i++;
		}
		return 0;
	}

	/** PTRN tab: pick a preset VSRG pattern and drop it onto a line at the playhead. **/
	function buildPatternsPanel(flow:DockFlow, colW:Float):Void {
		flow.header(new UIAccordion("Patterns", colW));
		addHintRow(flow, colW, "Drops an osu!mania-style preset at the playhead.");

		var patDrop:UIDropdown = new UIDropdown("Pattern", colW, function(i:Int, _:String):Void patternId = i);
		patDrop.boxWidth = UITheme.px(130);
		patDrop.setItems(ChartPattern.NAMES);
		patDrop.select(clampIndex(patternId, ChartPattern.NAMES.length));
		flow.add(patDrop);

		var lenStep:UIStepper = new UIStepper("Length (steps)", colW, patternLength, 1, function(v:Float):Void {
			patternLength = Std.int(v < 1 ? 1 : v);
		});
		lenStep.min = 1;
		lenStep.max = 256;
		lenStep.tooltip = "How many snap steps the pattern spans (spacing = current snap)";
		flow.add(lenStep);

		var lines = model.chart.strumLines;
		var lineIds:Array<String> = [];
		var lineIdx:Array<Int> = [];
		var li:Int = 0;
		while (li < lines.length) {
			lineIds.push(lines[li].id + (lines[li].isPlayer ? " (P)" : ""));
			lineIdx.push(li);
			li++;
		}
		if (patternLine < 0 || patternLine >= lines.length)
			patternLine = defaultPatternLine();
		var lineDrop:UIDropdown = new UIDropdown("Target Line", colW, function(i:Int, _:String):Void patternLine = lineIdx[i]);
		lineDrop.boxWidth = UITheme.px(130);
		lineDrop.setItems(lineIds);
		var sel:Int = lineIdx.indexOf(patternLine);
		lineDrop.select(sel >= 0 ? sel : 0);
		flow.add(lineDrop);

		flow.add(new UIButton("Place at Playhead", colW, UITheme.px(28), placePattern));
		var mouseToggle:UICheckbox = new UICheckbox("Place with Mouse", colW, patternArmed, function(v:Bool):Void patternArmed = v);
		mouseToggle.tooltip = "While on, click the grid to drop the pattern at that lane and time";
		flow.add(mouseToggle);
	}

	/** Places the selected pattern at the playhead on the chosen target line (button entry point). **/
	function placePattern():Void {
		var line:Int = patternLine;
		if (line < 0 || line >= model.chart.strumLines.length)
			line = defaultPatternLine();
		placePatternAt(line, model.floorTime(noteField.viewTime, snap.value));
	}

	/**
		Generates the selected pattern and inserts its notes on a strumline starting at a time.
		@param line the target strumline index
		@param startTime the (snapped) start time in ms
	**/
	function placePatternAt(line:Int, startTime:Float):Void {
		var lines = model.chart.strumLines;
		if (line < 0 || line >= lines.length) {
			UIToast.show('No target strumline');
			return;
		}
		var kc:Int = lines[line].keyCount;
		var offsets:Array<PatternNote> = ChartPattern.build(patternId, kc, patternLength);
		if (offsets.length == 0)
			return;

		undoStack.snapshot(model, 'Place Pattern');
		var startSteps:Float = noteField.stepsOf(startTime);
		var per:Float = snapSteps();
		var placed:Array<SongNote> = [];

		// suppress per-note refreshes; one markDirty covers the whole batch
		var saved:Void->Void = model.onChanged;
		model.onChanged = null;
		for (pn in offsets) {
			if (pn.col < 0 || pn.col >= kc)
				continue;
			var t:Float = noteField.timeOfSteps(startSteps + pn.step * per);
			if (model.noteAt(t, line, pn.col) != null)
				continue;
			placed.push(model.addNote(t, line, pn.col));
		}
		// grow sections if the pattern runs past the current chart end (still refresh-suppressed)
		if (placed.length > 0) {
			var lastT:Float = noteField.timeOfSteps(startSteps + patternLength * per);
			var guard:Int = 0;
			while (model.endTime <= lastT && guard++ < 4000)
				model.ensureSectionCount(model.sectionCount() + 1);
		}
		model.onChanged = saved;
		model.markDirty();

		if (placed.length > 0) {
			selection.setAll(placed);
			if (scripts != null && scripts.hasScripts)
				for (note in placed)
					scripts.call('onNotePlaced', [note.time, note.column, note.strumLine]);
			UIToast.show('Placed ${placed.length} notes (${ChartPattern.NAMES[patternId]})');
		} else
			UIToast.show('Nothing placed (spots occupied or off-lane)');
	}

	function buildStrumlineRows(flow:DockFlow, colW:Float):Void {
		var lines = model.chart.strumLines;
		var i:Int = 0;
		while (i < lines.length) {
			flow.add(strumlineRow(colW, i));
			i++;
		}
		flow.add(new UIButton("+ Add Strumline", colW, UITheme.px(28), addStrumlineClicked));
	}

	function addStrumlineClicked():Void {
		undoStack.snapshot(model, 'Add Strumline');
		var idx:Int = model.addStrumLine('extra${model.chart.strumLines.length}', 'bf', model.chart.keyCount);
		rebuildStrumlineUI();
		UIToast.show('Added strumline #$idx - note: gameplay only renders opponent/player/gf lines for now (gf notes make GF sing)');
	}

	/** Re-renders whichever dock hosts the strumline rows (and the camera-target items). **/
	function rebuildStrumlineUI():Void {
		if (!EditorPrefs.combinedDock)
			buildRightDock();
		buildLeftPanel(currentPanel(), true);
	}

	/** Public dock re-render for scripts. **/
	public function rebuildDocks():Void {
		rebuildStrumlineUI();
	}

	/**
		Registers a script-provided menu entry (rendered after a separator on next open).
		@param menu the top-level menu title ("File", "Edit", "View", "Playback", "Tools", "Help")
		@param label the entry text
		@param onSelect fired when picked
	**/
	public function addCustomMenuItem(menu:String, label:String, onSelect:Void->Void):Void {
		var list:Array<UIMenuItem> = customMenuItems.get(menu);
		if (list == null) {
			list = [];
			customMenuItems.set(menu, list);
		}
		list.push({label: label, onSelect: onSelect});
	}

	/**
		Registers a script-provided chip in the Quick Toggles section (shows on next dock build).
		@param label the chip text
		@param initial the starting state
		@param onToggle fired when the chip flips
	**/
	public function addCustomToggle(label:String, initial:Bool, onToggle:Bool->Void):Void {
		customToggles.push({label: label, on: initial, cb: onToggle});
	}

	/**
		Registers a script-provided button in the Options tab's Scripts section.
		@param label the button text
		@param onClick fired when clicked
	**/
	public function addCustomOptionButton(label:String, onClick:Void->Void):Void {
		customOptionButtons.push({label: label, cb: onClick});
	}

	/** Appends a menu's registered custom entries behind a separator. **/
	function appendCustom(menu:String, items:Array<UIMenuItem>):Array<UIMenuItem> {
		var extra:Array<UIMenuItem> = customMenuItems.get(menu);
		if (extra != null && extra.length > 0) {
			items.push({separator: true});
			for (it in extra)
				items.push(it);
		}
		return items;
	}

	function openStrumlineMenu(idx:Int, mx:Float, my:Float):Void {
		var line = model.chart.strumLines[idx];
		UIContextMenu.open(mx, my, [
			{label: 'Set Character...', onSelect: function():Void openCharacterModal(idx)},
			{label: 'Set Key Count', onSelect: function():Void openKeyCountMenu(idx, mx, my)},
			{label: line.visible ? 'Hide Lane' : 'Show Lane', onSelect: function():Void toggleLineVisible(idx, !line.visible)},
			{separator: true},
			{label: 'Move Up', disabled: idx <= 0, onSelect: function():Void moveStrumline(idx, -1)},
			{label: 'Move Down', disabled: idx >= model.chart.strumLines.length - 1, onSelect: function():Void moveStrumline(idx, 1)},
			{separator: true},
			{
				label: 'Remove Strumline',
				disabled: model.chart.strumLines.length <= 1,
				onSelect: function():Void {
					undoStack.snapshot(model, 'Remove Strumline');
					model.removeStrumLine(idx);
					rebuildStrumlineUI();
				}
			}
		]);
	}

	/** Reorders a lane in the grid (note/camera associations follow - gameplay unchanged). **/
	function moveStrumline(idx:Int, dir:Int):Void {
		undoStack.snapshot(model, 'Reorder Strumlines');
		model.swapStrumLines(idx, idx + dir);
		rebuildStrumlineUI();
	}

	function openKeyCountMenu(idx:Int, mx:Float, my:Float):Void {
		var items:Array<UIMenuItem> = [];
		var line = model.chart.strumLines[idx];
		var k:Int = 1;
		while (k <= 9) {
			var kc:Int = k;
			items.push({
				label: '${kc}K',
				checked: line.keyCount == kc,
				onSelect: function():Void {
					undoStack.snapshot(model, 'Key Count');
					var removed:Int = model.setLineKeyCount(idx, kc);
					rebuildStrumlineUI();
					if (removed > 0)
						UIToast.show('$removed out-of-range notes removed');
				}
			});
			k++;
		}
		UIContextMenu.open(mx, my, items);
	}

	/** Shows/hides a lane in the grid (enforces the visible-lines cap). **/
	function toggleLineVisible(idx:Int, visible:Bool):Void {
		if (visible && model.visibleLineCount() >= MAX_VISIBLE_LINES) {
			UIToast.show('At most $MAX_VISIBLE_LINES strumlines can be visible');
			rebuildStrumlineUI();
			return;
		}
		undoStack.snapshot(model, 'Lane Visibility');
		model.setLineVisible(idx, visible);
		rebuildStrumlineUI();
	}

	function openCharacterModal(idx:Int):Void {
		var line = model.chart.strumLines[idx];
		var modal:UIModal = new UIModal("Set Character", 380, 150);
		var input:UITextInput = new UITextInput("Character", 380 - 32, (line.characters.length > 0) ? line.characters[0] : '');
		input.x = 16;
		input.y = 12;
		input.boxWidth = UITheme.px(180);
		modal.body.addChild(input);
		var ok:UIButton = new UIButton("Apply", 110, 28, function():Void {
			undoStack.snapshot(model, 'Line Character');
			model.setLineCharacter(idx, input.text);
			modal.close();
			rebuildStrumlineUI();
		}, true);
		ok.x = 380 - 126;
		ok.y = 150 - 40 - 44;
		modal.body.addChild(ok);
		modal.open();
	}

	function applyAudioVolumes():Void {
		audio.setVolumes(EditorPrefs.instVol, EditorPrefs.mainVol, EditorPrefs.oppVol);
	}

	function buildSongAudioSection(flow:DockFlow, colW:Float):Void {
		var inst:UIStepper = new UIStepper("Inst Volume", colW, EditorPrefs.instVol, 0.1, function(v:Float):Void {
			EditorPrefs.instVol = v;
			applyAudioVolumes();
		});
		inst.min = 0;
		inst.max = 1;
		inst.decimals = 1;
		flow.add(inst);
		var mainVox:UIStepper = new UIStepper("Main Vocals", colW, EditorPrefs.mainVol, 0.1, function(v:Float):Void {
			EditorPrefs.mainVol = v;
			applyAudioVolumes();
		});
		mainVox.min = 0;
		mainVox.max = 1;
		mainVox.decimals = 1;
		flow.add(mainVox);
		var oppVox:UIStepper = new UIStepper("Opponent Vocals", colW, EditorPrefs.oppVol, 0.1, function(v:Float):Void {
			EditorPrefs.oppVol = v;
			applyAudioVolumes();
		});
		oppVox.min = 0;
		oppVox.max = 1;
		oppVox.decimals = 1;
		flow.add(oppVox);
		flow.add(new UISlider("Hitsound P", colW, 0, 1, EditorPrefs.hitsoundP, function(v:Float):Void EditorPrefs.hitsoundP = v));
		flow.add(new UISlider("Hitsound O", colW, 0, 1, EditorPrefs.hitsoundO, function(v:Float):Void EditorPrefs.hitsoundO = v));

		var waveDrop:UIDropdown = new UIDropdown("Waveform Source", colW, function(index:Int, _:String):Void {
			EditorPrefs.waveTarget = index;
			applyWaveConfig();
		});
		waveDrop.boxWidth = UITheme.px(130);
		waveDrop.setItems(["Instrumental", "Player Vocals", "Opponent Vocals"]);
		waveDrop.select(clampIndex(EditorPrefs.waveTarget, 3));
		flow.add(waveDrop);
		flow.add(new UICheckbox("Per-Strumline Waveform", colW, EditorPrefs.wavePerStrum, function(v:Bool):Void {
			EditorPrefs.wavePerStrum = v;
			applyWaveConfig();
		}));
	}

	/** Pushes the current waveform prefs onto the note field: either a single centered source, or the
		opponent + player vocals drawn over their own strumlines when `wavePerStrum` is on. **/
	function applyWaveConfig():Void {
		if (noteField == null)
			return;
		noteField.wavePerStrum = EditorPrefs.wavePerStrum;
		if (EditorPrefs.wavePerStrum) {
			noteField.waveSourceA = audio.waveformSound(2); // opponent vocals over line 0
			noteField.waveSourceB = audio.waveformSound(1); // player vocals over line 1
		} else
			noteField.waveSource = audio.waveformSound(EditorPrefs.waveTarget);
	}

	/** Enumerates default + `custom_events/*.txt` event definitions (`[name, description]`). **/
	function buildEventsList():Void {
		eventsList = [];
		#if MODS_ALLOWED
		for (file in listEditorFiles('custom_events/', ['.txt']))
			eventsList.push([file, Paths.getTextFromFile('custom_events/$file.txt')]);
		#end
		for (id => event in legacy.editors.ChartingState.defaultEvents) {
			var dup:Bool = false;
			for (e in eventsList)
				if (e[0] == event[0]) {
					dup = true;
					break;
				}
			if (!dup && event[0].length > 0)
				eventsList.push(event);
		}
	}

	#if MODS_ALLOWED
	/**
		Enumerates unique file names (without extension) across every mod directory + shared assets.
		@param folder the asset subfolder (e.g. `custom_events/`)
		@param exts accepted extensions (with dots)
		@return the deduplicated names
	**/
	static function listEditorFiles(folder:String, exts:Array<String>):Array<String> {
		var out:Array<String> = [];
		for (directory in Mods.directoriesWithFile(Paths.getSharedPath(), folder)) {
			if (!sys.FileSystem.exists(directory))
				continue;
			for (file in sys.FileSystem.readDirectory(directory)) {
				var path:String = haxe.io.Path.join([directory, file.trim()]);
				if (sys.FileSystem.isDirectory(path) || file.startsWith('readme.'))
					continue;
				for (ext in exts) {
					var name:String = file.substr(0, file.length - ext.length);
					if (name.length > 0 && path.endsWith(ext) && !out.contains(name)) {
						out.push(name);
						break;
					}
				}
			}
		}
		return out;
	}
	#end

	function buildEventSection(flow:DockFlow, colW:Float):Void {
		eventHead = new UIAccordion("Event - none", colW);
		flow.header(eventHead);

		eventDrop = new UIDropdown("Event", colW, function(index:Int, _:String):Void {
			eventDrop.tooltip = eventsList[index][1];
			if (selectedEventGroup != null) {
				undoStack.snapshot(model, 'Edit Event');
				var subs:Array<Dynamic> = selectedEventGroup[1];
				(subs[selectedEventSub] : Array<Dynamic>)[0] = eventsList[index][0];
				model.markDirty();
			}
		});
		eventDrop.boxWidth = UITheme.px(150);
		eventDrop.setItems([for (e in eventsList) e[0]]);
		if (eventsList.length > 0)
			eventDrop.tooltip = eventsList[0][1];
		flow.add(eventDrop);

		eventVal1 = new UITextInput("Value 1", colW, "", function(v:String):Void applyEventValue(1, v));
		eventVal1.boxWidth = UITheme.px(150);
		flow.add(eventVal1);
		eventVal2 = new UITextInput("Value 2", colW, "", function(v:String):Void applyEventValue(2, v));
		eventVal2.boxWidth = UITheme.px(150);
		flow.add(eventVal2);
		flow.add(eventButtonRow(colW));
		flow.add(new UISeparator(colW));
		refreshEventInspector();
	}

	/**
		Writes a value field of the selected stacked event.
		@param slot 1 = Value 1, 2 = Value 2
		@param v the new value text
	**/
	function applyEventValue(slot:Int, v:String):Void {
		if (selectedEventGroup == null)
			return;
		undoStack.snapshotCoalesced(model, 'Event Value');
		var subs:Array<Dynamic> = selectedEventGroup[1];
		var sub:Array<Dynamic> = subs[selectedEventSub];
		while (sub.length <= slot)
			sub.push('');
		sub[slot] = v;
		model.markDirty();
	}

	/** Syncs the inspector widgets to the selected event group (auto-expands the section). **/
	function refreshEventInspector():Void {
		if (noteField != null)
			noteField.selectedEventTime = (selectedEventGroup != null) ? (selectedEventGroup[0] : Float) : -1;
		if (eventHead == null)
			return;
		if (selectedEventGroup == null) {
			eventHead.title = 'Event - none';
			eventHead.hint = 'RMB a mark to edit';
			return;
		}
		// surface the selection: expand the inspector section if it was collapsed
		if (!eventHead.expanded) {
			eventHead.expanded = true;
			if (eventHead.onToggle != null)
				eventHead.onToggle(true);
		}
		var subs:Array<Dynamic> = selectedEventGroup[1];
		if (selectedEventSub >= subs.length)
			selectedEventSub = subs.length - 1;
		if (selectedEventSub < 0)
			selectedEventSub = 0;
		eventHead.title = 'Event - ${selectedEventSub + 1} of ${subs.length}';
		eventHead.hint = fmtTime(selectedEventGroup[0]);
		var sub:Array<Dynamic> = subs[selectedEventSub];
		var name:String = sub[0];
		var found:Int = -1;
		var i:Int = 0;
		while (i < eventsList.length) {
			if (eventsList[i][0] == name) {
				found = i;
				break;
			}
			i++;
		}
		// events from chart/events files that aren't installed still show by name
		if (found < 0 && name != null && name.length > 0) {
			eventsList.push([name, 'Unknown event (from the chart file)']);
			eventDrop.setItems([for (e in eventsList) e[0]]);
			found = eventsList.length - 1;
		}
		if (found >= 0) {
			eventDrop.select(found);
			eventDrop.tooltip = eventsList[found][1];
		}
		eventVal1.text = (sub.length > 1 && sub[1] != null) ? Std.string(sub[1]) : '';
		eventVal2.text = (sub.length > 2 && sub[2] != null) ? Std.string(sub[2]) : '';
	}

	/** The event group occupying the snap cell that starts at `t`, or `null`. **/
	function eventGroupNear(t:Float):Array<Dynamic> {
		var unit:Float = model.snapMs(model.sectionAt(t), snap.value);
		var scratch:Array<Dynamic> = [];
		model.eventsBetween(t - 1, t + unit - 1, scratch);
		return (scratch.length > 0) ? scratch[0] : null;
	}

	/** Lays chips into a wrapping flow row group (overflowing chips break to the next line). **/
	function chipRow(colW:Float, chips:Array<UIChip>):UIComponent {
		var group:UIComponent = new UIComponent(false, false);
		var x:Float = 0;
		var y:Float = 0;
		var rowH:Float = 0;
		var i:Int = 0;
		var n:Int = chips.length;
		while (i < n) {
			var chip:UIChip = chips[i];
			if (x > 0 && x + chip.w > colW) {
				x = 0;
				y += rowH + UITheme.px(6);
			}
			chip.x = x;
			chip.y = y;
			group.addChild(chip);
			x += chip.w + UITheme.px(8);
			if (chip.h > rowH)
				rowH = chip.h;
			i++;
		}
		group.resize(colW, y + rowH);
		return group;
	}

	function strumlineRow(colW:Float, idx:Int):UIComponent {
		var line = model.chart.strumLines[idx];
		var charName:String = (line.characters.length > 0) ? line.characters[0] : '?';
		var tag:String = line.isPlayer ? "PLR" : (line.id == 'gf' ? "GF" : (line.type == 0 ? "OPP" : "ADD"));

		var card:UIPanel = new UIPanel(colW, UITheme.px(46), UITheme.card);
		card.corner = UITheme.px(9);
		card.outline = true;
		var nameLabel:UILabel = new UILabel(line.id, 12, 0);
		nameLabel.x = UITheme.px(10);
		nameLabel.y = UITheme.px(7);
		card.addChild(nameLabel);
		var subLabel:UILabel = new UILabel('$charName - ${line.keyCount}K', 10, 2);
		subLabel.x = UITheme.px(10);
		subLabel.y = UITheme.px(25);
		card.addChild(subLabel);
		var eye:UICheckbox = new UICheckbox("", UITheme.px(20), line.visible, function(v:Bool):Void toggleLineVisible(idx, v));
		eye.tooltip = "Show this lane in the grid";
		eye.x = colW - UITheme.px(30);
		eye.y = (UITheme.px(46) - eye.h) / 2;
		card.addChild(eye);
		var tagChip:UIChip = new UIChip(tag);
		tagChip.fontSize = 10;
		tagChip.tooltip = "Line options";
		tagChip.render();
		tagChip.x = colW - UITheme.px(38) - tagChip.w;
		tagChip.y = (UITheme.px(46) - tagChip.h) / 2;
		tagChip.onClick = function():Void {
			var p = tagChip.localToGlobal(new openfl.geom.Point(0, tagChip.h + 2));
			var local = uiRoot.popupLayer.globalToLocal(p);
			openStrumlineMenu(idx, local.x, local.y);
		};
		card.addChild(tagChip);
		return card;
	}

	function eventButtonRow(colW:Float):UIComponent {
		var group:UIComponent = new UIComponent(false, false);
		var bw:Float = (colW - UITheme.px(18)) / 4;
		var bh:Float = UITheme.px(24);
		var labels:Array<String> = ["+", "-", "<", ">"];
		var actions:Array<Void->Void> = [
			addStackedEvent,
			removeStackedEvent,
			function():Void stepStackedEvent(-1),
			function():Void stepStackedEvent(1)
		];
		var tips:Array<String> = [
			"Stack another event at this time",
			"Remove this stacked event",
			"Previous stacked event",
			"Next stacked event"
		];
		var i:Int = 0;
		while (i < 4) {
			var b:UIButton = new UIButton(labels[i], bw, bh, actions[i]);
			b.tooltip = tips[i];
			b.x = i * (bw + UITheme.px(6));
			group.addChild(b);
			i++;
		}
		group.resize(colW, bh);
		return group;
	}

	function addStackedEvent():Void {
		if (selectedEventGroup == null) {
			UIToast.show('Select an event first (RMB a mark in the lane)');
			return;
		}
		undoStack.snapshot(model, 'Stack Event');
		var subs:Array<Dynamic> = selectedEventGroup[1];
		var name:String = (eventDrop != null && eventsList.length > 0) ? eventsList[eventDrop.selectedIndex][0] : '';
		subs.push([name, '', '']);
		selectedEventSub = subs.length - 1;
		model.markDirty();
		refreshEventInspector();
	}

	function removeStackedEvent():Void {
		if (selectedEventGroup == null)
			return;
		undoStack.snapshot(model, 'Remove Event');
		var subs:Array<Dynamic> = selectedEventGroup[1];
		var t:Float = selectedEventGroup[0];
		model.removeEvent(selectedEventGroup, selectedEventSub);
		if (subs.length == 0)
			selectedEventGroup = null;
		refreshEventInspector();
		if (scripts.hasScripts)
			scripts.call('onEventDeleted', [t]);
	}

	function stepStackedEvent(dir:Int):Void {
		if (selectedEventGroup == null)
			return;
		var subs:Array<Dynamic> = selectedEventGroup[1];
		selectedEventSub = clampIndex(selectedEventSub + dir, subs.length);
		refreshEventInspector();
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (!fileDialog.completed)
			return;

		autosaveTimer += elapsed;
		if (autosaveAgeSecs >= 0)
			autosaveAgeSecs += elapsed;
		if (autosaveTimer >= AUTOSAVE_SECS) {
			autosaveTimer = 0;
			if (dirtySinceAutosave) {
				dirtySinceAutosave = false;
				doAutosave();
			}
		}

		fpsTimer += elapsed;
		if (fpsTimer >= 1.0) {
			fpsTimer = 0;
			var fps:Int = (Main.fpsVar != null) ? Main.fpsVar.currentFPS : 0;
			var age:String = (autosaveAgeSecs < 0) ? 'off' : (autosaveAgeSecs < 60 ? '${Std.int(autosaveAgeSecs)}s ago' : '${Std.int(autosaveAgeSecs / 60)}m ago');
			shell.statusRight.text = 'autosave: $age - backups: $backupCount - $fps FPS';
			shell.layoutStatus();
		}

		if (!UIFocus.typing && !UIRoot.overlayOpen) {
			handleKeybinds(elapsed);
			handleFieldMouse();
		}

		scripts.callUpdate(elapsed);

		audio.update(elapsed);
		if (audio.playing) {
			var t:Float = audio.time;
			if (shell.loopBtn.active && t >= model.sectionEnd(editSection)) {
				seekTo(model.sectionStart(editSection));
				t = audio.time;
			}
			noteField.setViewTime(t);
			tickMetronomeAndHits(t);
		}
		if (shell.playBtn.active != audio.playing)
			shell.playBtn.active = audio.playing;

		noteField.updateHot(elapsed);

		if (noteField.viewTime != lastViewTime) {
			lastViewTime = noteField.viewTime;
			if (!audio.playing && audio.loaded) {
				audio.seek(noteField.viewTime);
				nextHitIndex = model.firstNoteIndex(noteField.viewTime + 0.01);
			}
			var sec:Int = model.sectionAt(noteField.viewTime);
			if (sec != editSection) {
				editSection = sec;
				refreshSectionPanel();
				updateBpmChip();
				if (scripts.hasScripts)
					scripts.call('onSectionChanged', [editSection]);
			}
			updateStatus();
			updateTimeLabel();
			var total:Float = totalMs();
			shell.timeline.progress = (total > 0) ? noteField.viewTime / total : 0;
		}
	}

	/** Vortex: toggles a note in the Nth note lane (1-based; lane 0 is events) at the playhead. **/
	function vortexToggle(lane:Int):Void {
		var line:Int = noteField.laneStrumLine(lane);
		if (line < 0)
			return;
		var col:Int = noteField.laneColumn(lane);
		noteField.confirmReceptor(lane);
		var t:Float = model.floorTime(noteField.viewTime, snap.value);
		var existing:SongNote = model.noteAt(t, line, col);
		if (existing != null) {
			undoStack.snapshot(model, 'Vortex Remove');
			selection.remove(existing);
			model.removeNote(existing);
			if (scripts.hasScripts)
				scripts.call('onNoteDeleted', [existing.time, existing.column, existing.strumLine]);
		} else {
			undoStack.snapshot(model, 'Vortex Place');
			var note:SongNote = model.addNote(t, line, col);
			if (scripts.hasScripts)
				scripts.call('onNotePlaced', [note.time, note.column, note.strumLine]);
		}
	}

	/** Placement time under the pointer: floored to the snap cell, or raw while Shift is held. **/
	function placeTimeAt(my:Float):Float {
		var raw:Float = noteField.timeAtY(my);
		var t:Float = FlxG.keys.pressed.SHIFT ? raw : model.floorTime(raw, snap.value);
		return (t < 0) ? 0 : t;
	}

	/**
		All notefield pointer editing: the placement ghost, wheel scroll, LMB place/remove +
		sustain drag, Ctrl+LMB box select, and RMB selection/context menus. Skipped entirely
		while the pointer belongs to the UI layer.
	**/
	function handleFieldMouse():Void {
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		var inside:Bool = noteField.contains(mx, my) && !UIPointer.overUI;

		// placement ghost under the cursor (legacy dummy-arrow feel)
		if (inside && !UIRoot.overlayOpen) {
			var ghostLane:Int = noteField.laneAt(mx);
			if (ghostLane >= 0)
				noteField.showGhost(ghostLane, placeTimeAt(my), FlxG.keys.pressed.SHIFT ? 0.2 : snapSteps(), EditorPrefs.snapRegionGhost);
			else
				noteField.hideGhost();
		} else
			noteField.hideGhost();

		var wheel:Int = FlxG.mouse.wheel;
		if (wheel != 0 && inside)
			noteField.scrollBySnap(-wheel, snap.value);

		// Ctrl+LMB drag = box select
		if (boxing) {
			if (FlxG.mouse.pressed) {
				noteField.showBoxRect(boxX, boxY, mx, my);
				return;
			}
			boxing = false;
			noteField.hideBoxRect();
			selectNotesInRect(boxX, boxY, mx, my, FlxG.keys.pressed.SHIFT);
			return;
		}
		if (FlxG.mouse.justPressed && inside && !UIPointer.downOnUI && FlxG.keys.pressed.CONTROL) {
			boxing = true;
			boxX = mx;
			boxY = my;
			return;
		}

		// armed pattern: a grid click drops the whole pattern at that lane/time
		if (patternArmed && FlxG.mouse.justPressed && inside && !UIPointer.downOnUI && !FlxG.keys.pressed.CONTROL) {
			var line:Int = noteField.laneStrumLine(noteField.laneAt(mx));
			if (line >= 0) {
				placePatternAt(line, placeTimeAt(my));
				return;
			}
		}

		if (FlxG.mouse.justPressed && inside && !UIPointer.downOnUI) {
			var hit:SongNote = noteField.noteUnder(mx, my);
			if (hit != null) {
				undoStack.snapshot(model, 'Remove Note');
				selection.remove(hit);
				model.removeNote(hit);
				if (scripts.hasScripts)
					scripts.call('onNoteDeleted', [hit.time, hit.column, hit.strumLine]);
			} else {
				var lane:Int = noteField.laneAt(mx);
				var line:Int = noteField.laneStrumLine(lane);
				if (line >= 0) {
					var t:Float = placeTimeAt(my);
					undoStack.snapshot(model, 'Place Note');
					placingNote = model.addNote(t, line, noteField.laneColumn(lane));
					selection.setAll([placingNote]);
					if (scripts.hasScripts)
						scripts.call('onNotePlaced', [placingNote.time, placingNote.column, placingNote.strumLine]);
				} else if (lane == 0) {
					var t:Float = placeTimeAt(my);
					var group:Array<Dynamic> = eventGroupNear(t);
					if (group != null) {
						undoStack.snapshot(model, 'Remove Event');
						if (group == selectedEventGroup)
							selectedEventGroup = null;
						model.chart.events.remove(group);
						model.markDirty();
						if (scripts.hasScripts)
							scripts.call('onEventDeleted', [(group[0] : Float)]);
					} else if (eventsList.length > 0) {
						undoStack.snapshot(model, 'Place Event');
						var idx:Int = (eventDrop != null) ? eventDrop.selectedIndex : 0;
						model.addEvent(t, eventsList[idx][0], (eventVal1 != null) ? eventVal1.text : '', (eventVal2 != null) ? eventVal2.text : '');
						selectedEventGroup = eventGroupNear(t);
						selectedEventSub = 0;
						if (scripts.hasScripts)
							scripts.call('onEventPlaced', [t, eventsList[idx][0]]);
					}
					refreshEventInspector();
				}
			}
		}

		if (placingNote != null) {
			if (FlxG.mouse.pressed) {
				var t:Float = placeTimeAt(my);
				var len:Float = t - placingNote.time;
				if (len < 0)
					len = 0;
				if (len != placingNote.length) {
					model.setNoteLength(placingNote, len);
					// keep the Selected panel's Sustain field in sync while dragging the tail
					if (sustainStep != null && selection.count == 1 && selection.notes[0] == placingNote)
						sustainStep.value = placingNote.length;
				}
			} else
				placingNote = null;
		}

		if (FlxG.mouse.justPressedRight && inside && !UIPointer.downOnUI) {
			var hit:SongNote = noteField.noteUnder(mx, my);
			if (hit != null) {
				if (!selection.has(hit))
					selection.setAll([hit]);
				openNoteContext(mx, my);
			} else if (noteField.laneAt(mx) == 0) {
				var group:Array<Dynamic> = eventGroupNear(model.floorTime(noteField.timeAtY(my), snap.value));
				if (group != null) {
					selectedEventGroup = group;
					selectedEventSub = 0;
					refreshEventInspector();
				}
			}
		}
	}

	/** Selects notes whose lane and time fall inside the dragged rectangle. **/
	function selectNotesInRect(x0:Float, y0:Float, x1:Float, y1:Float, additive:Bool):Void {
		var xLo:Float = (x0 < x1) ? x0 : x1;
		var xHi:Float = (x0 < x1) ? x1 : x0;
		var tA:Float = noteField.timeAtY(y0);
		var tB:Float = noteField.timeAtY(y1);
		var tLo:Float = (tA < tB) ? tA : tB;
		var tHi:Float = (tA < tB) ? tB : tA;

		var scratch:Array<SongNote> = [];
		model.notesBetween(tLo - 1, tHi + 1, scratch);
		var picked:Array<SongNote> = additive ? selection.notes.copy() : [];
		var i:Int = 0;
		var n:Int = scratch.length;
		while (i < n) {
			var note:SongNote = scratch[i];
			var lx:Float = noteField.laneScreenX(note.strumLine, note.column);
			if (lx >= 0 && lx + noteField.cellSize >= xLo && lx <= xHi && picked.indexOf(note) < 0)
				picked.push(note);
			i++;
		}
		selection.setAll(picked);
	}

	function openNoteContext(mx:Float, my:Float):Void {
		UIContextMenu.open(mx, my, [
			{label: 'Delete', shortcut: EditorKeybinds.bindLabel('delete'), onSelect: deleteSelection},
			{label: 'Copy', shortcut: EditorKeybinds.bindLabel('copy'), onSelect: copySelection},
			{separator: true},
			{label: 'Deselect', onSelect: selection.clear}
		]);
	}

	function deleteSelection():Void {
		if (selection.count == 0)
			return;
		undoStack.snapshot(model, 'Delete');
		var fireHooks:Bool = scripts != null && scripts.hasScripts;
		var i:Int = selection.notes.length;
		while (--i >= 0) {
			var note:SongNote = selection.notes[i];
			model.chart.noteList.remove(note);
			if (fireHooks)
				scripts.call('onNoteDeleted', [note.time, note.column, note.strumLine]);
		}
		selection.clear();
		model.markDirty();
	}

	/** Copies the selection (anchored at its earliest note); no selection = the whole section. **/
	function copySelection():Void {
		if (selection.count == 0) {
			copySection();
			return;
		}
		var anchor:Float = selection.notes[0].time;
		var i:Int = selection.notes.length;
		while (--i >= 0)
			if (selection.notes[i].time < anchor)
				anchor = selection.notes[i].time;
		clipboard.copyNotes(selection.notes, anchor);
		UIToast.show('Copied ${selection.count} notes');
	}

	function cutSelection():Void {
		if (selection.count == 0)
			return;
		copySelection();
		deleteSelection();
	}

	function selectAll():Void {
		selection.setAll(model.chart.noteList);
	}

	function selectSection():Void {
		var scratch:Array<SongNote> = [];
		model.notesBetween(model.sectionStart(editSection), model.sectionEnd(editSection), scratch);
		selection.setAll(scratch);
	}

	/** Q/E: adjusts the selection's sustains, or the hovered note's when nothing is selected. **/
	function adjustSelectedSustains(dir:Int):Void {
		var targets:Array<SongNote> = selection.notes;
		var hovered:SongNote = null;
		if (targets.length == 0) {
			hovered = noteField.noteUnder(FlxG.mouse.x, FlxG.mouse.y);
			if (hovered == null)
				return;
		}
		undoStack.snapshotCoalesced(model, 'Sustain');
		if (hovered != null) {
			bumpSustain(hovered, dir);
		} else {
			var i:Int = targets.length;
			while (--i >= 0)
				bumpSustain(targets[i], dir);
		}
		model.markDirty();
	}

	function bumpSustain(note:SongNote, dir:Int):Void {
		var step:Float = model.stepMs(model.sectionAt(note.time));
		var len:Float = note.length + dir * step;
		note.length = (len > 0) ? len : 0;
	}

	/**
		Polls every editor keybind (all rebindable via `EditorKeybinds`). Only runs while no
		text input has focus and no overlay is open.
		@param elapsed frame time in seconds (drives the scroll hold-repeat)
	**/
	function handleKeybinds(elapsed:Float):Void {
		// W/S scroll with hold-repeat
		var upHeld:Bool = EditorKeybinds.pressed('step_up');
		var downHeld:Bool = EditorKeybinds.pressed('step_down');
		if (EditorKeybinds.justPressed('step_up') || EditorKeybinds.justPressed('step_down')) {
			noteField.scrollBySnap(EditorKeybinds.justPressed('step_up') ? -1 : 1, snap.value);
			scrollHold = -0.35;
		} else if (upHeld || downHeld) {
			scrollHold += elapsed;
			while (scrollHold >= 0.05) {
				scrollHold -= 0.05;
				noteField.scrollBySnap(upHeld ? -1 : 1, snap.value);
			}
		}

		// vortex mode: number keys toggle notes on the playhead row, lane order left→right
		if (EditorPrefs.vortex) {
			var k:Int = 0;
			while (k < 8) {
				if (EditorKeybinds.justPressed('vortex_${k + 1}'))
					vortexToggle(k + 1);
				k++;
			}
		}

		if (EditorKeybinds.justPressed('delete'))
			deleteSelection();
		if (EditorKeybinds.justPressed('copy'))
			copySelection();
		if (EditorKeybinds.justPressed('cut'))
			cutSelection();
		if (EditorKeybinds.justPressed('select_all'))
			selectAll();
		if (EditorKeybinds.justPressed('sustain_shrink'))
			adjustSelectedSustains(-1);
		if (EditorKeybinds.justPressed('sustain_grow'))
			adjustSelectedSustains(1);

		if (EditorKeybinds.justPressed('section_prev'))
			gotoSection(editSection - 1);
		else if (EditorKeybinds.justPressed('section_next'))
			gotoSection(editSection + 1);

		if (EditorKeybinds.justPressed('goto_start'))
			gotoSection(0);
		else if (EditorKeybinds.justPressed('goto_end'))
			gotoSection(model.sectionCount() - 1);

		if (EditorKeybinds.justPressed('undo'))
			performUndo();
		else if (EditorKeybinds.justPressed('redo'))
			performRedo();

		if (EditorKeybinds.justPressed('snap_prev'))
			cycleSnap(-1);
		else if (EditorKeybinds.justPressed('snap_next'))
			cycleSnap(1);

		if (EditorKeybinds.justPressed('zoom_out'))
			cycleZoom(-1);
		else if (EditorKeybinds.justPressed('zoom_in'))
			cycleZoom(1);

		if (EditorKeybinds.justPressed('rate_down'))
			cycleRate(-1);
		else if (EditorKeybinds.justPressed('rate_up'))
			cycleRate(1);

		if (EditorKeybinds.justPressed('play_pause'))
			togglePlayback();
		if (EditorKeybinds.justPressed('go_to'))
			openGoToModal();
		if (EditorKeybinds.justPressed('help'))
			openHelpModal();
		if (EditorKeybinds.justPressed('reset_section'))
			seekTo(model.sectionStart(editSection));
		if (EditorKeybinds.justPressed('playtest'))
			goToPlayState();

		if (EditorKeybinds.justPressed('paste'))
			pasteAtSection();

		if (EditorKeybinds.justPressed('save'))
			saveChart(false);
		if (EditorKeybinds.justPressed('save_as'))
			saveChart(true);
		if (EditorKeybinds.justPressed('open'))
			openChartDialog();
		if (EditorKeybinds.justPressed('new_chart'))
			newChart();

		if (controls.BACK)
			leaveEditor();
	}

	override function destroy():Void {
		EditorPrefs.save();
		if (scripts != null)
			scripts.destroy();
		if (audio != null)
			audio.destroy();
		if (noteField != null)
			noteField.dispose();
		FlxG.mouse.useSystemCursor = false;
		FlxG.signals.gameResized.remove(onGameResized);
		UIToast.reset();
		UITooltip.reset();
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}

/** A script-registered quick toggle. **/
private typedef CustomToggle = {
	var label:String;
	var on:Bool;
	var cb:Bool->Void;
}

/** A script-registered Options-panel button. **/
private typedef CustomButton = {
	var label:String;
	var cb:Void->Void;
}

/**
	One row of the keybinds modal: action label left, current bind right. Click to capture the
	next keypress (with live modifiers) as the primary bind; Escape cancels the capture.
**/
private final class KeybindRow extends ui.UIComponent implements ui.input.IUIFocusable {
	final action:editors.charting.data.EditorKeybinds.EditorAction;
	final labelTf:openfl.text.TextField;
	final bindTf:openfl.text.TextField;
	var capturing:Bool = false;

	/**
		@param action the rebindable action this row edits
		@param width the row width
	**/
	public function new(action:editors.charting.data.EditorKeybinds.EditorAction, width:Float) {
		super(true, true);
		this.action = action;
		labelTf = ui.UIFonts.make(UITheme.fs(11), UITheme.text2);
		addChild(labelTf);
		bindTf = ui.UIFonts.make(UITheme.fs(11), UITheme.text);
		addChild(bindTf);
		resize(width, UITheme.px(24));
		render();
	}

	override function click():Void {
		ui.input.UIFocus.set(this);
		super.click();
	}

	public function capturesKeyboard():Bool {
		return capturing;
	}

	public function onFocusGained():Void {
		capturing = true;
		invalidate();
	}

	public function onFocusLost():Void {
		capturing = false;
		invalidate();
	}

	public function onKeyDown(keyCode:Int, charCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool {
		if (keyCode == 27) {
			ui.input.UIFocus.clear();
			return true;
		}
		// bare modifier presses wait for the real key
		if (keyCode == 16 || keyCode == 17 || keyCode == 18)
			return true;
		editors.charting.data.EditorKeybinds.rebind(action.id, 0, {
			key: keyCode,
			ctrl: ctrl,
			shift: shift,
			alt: alt
		});
		ui.input.UIFocus.clear();
		invalidate();
		return true;
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		var fill:Int = capturing ? UITheme.panel3 : (hovered ? UITheme.panel2 : UITheme.inputBg);
		g.beginFill(ui.UIColor.rgb(fill));
		g.drawRoundRect(0, 0, w, h, UITheme.px(6), UITheme.px(6));
		g.endFill();
		g.lineStyle(1, ui.UIColor.rgb(capturing ? UITheme.accent : UITheme.border));
		g.drawRoundRect(0.5, 0.5, w - 1, h - 1, UITheme.px(6), UITheme.px(6));
		g.lineStyle();

		ui.UIFonts.restyle(labelTf, UITheme.fs(11), UITheme.text2);
		if (labelTf.text != action.label)
			labelTf.text = action.label;
		labelTf.x = UITheme.px(8);
		labelTf.y = (h - labelTf.height) / 2;

		ui.UIFonts.restyle(bindTf, UITheme.fs(11), capturing ? UITheme.highlight : UITheme.text);
		var bindText:String = capturing ? "press a key..." : editors.charting.data.EditorKeybinds.bindLabel(action.id);
		if (bindText == "")
			bindText = "unbound";
		if (bindTf.text != bindText)
			bindTf.text = bindText;
		bindTf.x = w - UITheme.px(8) - bindTf.width;
		bindTf.y = (h - bindTf.height) / 2;
	}
}

/**
	Single-column dock layout: widgets flow top-down inside a `UIScrollPane`; `UIAccordion`
	headers collapse the widgets added after them (until the next header).
**/
private final class DockFlow {
	final pane:UIScrollPane;
	final x:Float;
	final gap:Float;
	final rows:Array<UIComponent> = [];
	final rowSection:Array<Int> = [];
	final open:Array<Bool> = [];
	var section:Int = -1;

	/**
		@param pane the scroll pane the flow fills
		@param x the left inset for every row
		@param gap vertical spacing between rows
	**/
	public function new(pane:UIScrollPane, x:Float, gap:Float) {
		this.pane = pane;
		this.x = x;
		this.gap = gap;
	}

	/**
		Starts a new collapsible section headed by the accordion (its `onToggle` is taken over).
		@param acc the section header
		@return the same accordion, for chaining
	**/
	public function header(acc:UIAccordion):UIAccordion {
		open.push(acc.expanded);
		final idx:Int = open.length - 1;
		section = idx;
		rows.push(acc);
		rowSection.push(-1);
		pane.content.addChild(acc);
		acc.onToggle = function(v:Bool):Void {
			open[idx] = v;
			reflow();
		};
		return acc;
	}

	/**
		Adds a row to the current section (hidden while that section is collapsed).
		@param c the widget (its `h` drives the flow spacing)
		@return the same widget, for chaining
	**/
	public function add(c:UIComponent):UIComponent {
		rows.push(c);
		rowSection.push(section);
		pane.content.addChild(c);
		return c;
	}

	/** Re-lays every row top-down (skipping collapsed sections) and refreshes the pane. **/
	public function reflow():Void {
		var y:Float = UITheme.px(10);
		var i:Int = 0;
		var n:Int = rows.length;
		while (i < n) {
			var c:UIComponent = rows[i];
			var sec:Int = rowSection[i];
			var show:Bool = (sec < 0) || open[sec];
			c.visible = show;
			if (show) {
				if (sec < 0 && i > 0)
					y += gap;
				c.x = x;
				c.y = y;
				y += c.h + gap;
			}
			i++;
		}
		pane.refreshContent(y + UITheme.px(10));
	}
}
