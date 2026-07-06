package editors.charting.render;

import backend.Conductor;
import backend.SongChart;
import backend.SongChart.SongNote;
import backend.SongChart.StrumLineData;
import editors.charting.data.ChartEditorModel;
import editors.charting.data.SelectionModel;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.util.FlxColor;
import objects.notes.NoteData;
import objects.notes.NoteSprite;
import objects.notes.Receptor;
import ui.UITheme;

/** One realized note: chart data + the pooled drawables currently showing it. **/
private final class LiveNote {
	/** The chart note this drawable set represents. **/
	public var note:SongNote;

	/** The pooled runtime data fed to the skin. **/
	public var data:NoteData;

	/** The pooled head sprite. **/
	public var head:NoteSprite;

	/** The pooled sustain line (a simple colored bar, null for taps). **/
	public var sustain:FlxSprite;

	/** Cached selection state (drives the tint compare). **/
	public var selected:Bool = false;

	/** Quant color computed at realize (ARGB). **/
	public var quantColor:Int = 0xFFFFFFFF;

	/** Last applied head tint (avoids redundant color sets). **/
	public var lastColor:Int = 0xFFFFFFFF;

	public function new() {}
}

/**
	The Flixel notefield inside the shell's center hole: checker grid (1:1 cells, a full 4/4
	section always fits the height), event lane, visible strumlines, pooled note heads
	(`NoteSprite` skinned by `NoteSkinService`) with simple colored bars for sustains, section
	boundaries with dimmed neighbors and the fixed mid-field playhead - the grid scrolls, the
	playhead doesn't.

	Draws on the main camera in plain game coordinates: the opaque UI chrome (menu bar, docks,
	transport, status) layered above the FlxGame clips the field for free, so no extra camera is
	needed. `updateHot` realizes/releases at the window edges only; a model edit calls
	`onModelChanged` which re-realizes from scratch.
**/
final class EditorNoteField {
	final model:ChartEditorModel;
	final selection:SelectionModel;

	/** All field drawables (grid, notes, marks). Add to the state before `overlay`. **/
	public final group:FlxTypedGroup<FlxSprite>;

	/** Drawn above `group` (playhead line). Add to the state after `group`. **/
	public final overlay:FlxTypedGroup<FlxSprite>;

	/** Song time at the playhead, in ms. **/
	public var viewTime(default, null):Float = 0;

	/** Subdivision multiplier (legacy-style): cells stay square; 2x = each row is half a step,
		so a section spans twice the rows. 1x = one step per row, full section in view. **/
	public var zoom(default, null):Float = 1;

	// field rect in game coordinates
	var fx:Float;
	var fy:Float;
	var fw:Float;
	var fh:Float;

	var fieldBg:FlxSprite;

	// cell width = the 1x square size (full section fits at 1x); height scales with zoom
	var cell:Float = 40;
	var cellH:Float = 40;
	var gridX:Float = 0;
	var gridW:Float = 0;
	final laneLine:Array<Int> = [];
	final laneCol:Array<Int> = [];
	final laneX:Array<Float> = [];

	// cumulative steps at each section start (parallel to model.sectionTimes)
	final stepsAt:Array<Float> = [];

	var checker:FlxSprite;
	var waveSprite:FlxSprite;
	var ghost:FlxSprite;
	var ghostNote:NoteSprite;
	var ghostData:NoteData;
	var ghostLine:Int = -99;
	var ghostCol:Int = -99;
	var ghostKc:Int = -1;
	var dimTop:FlxSprite;
	var dimBottom:FlxSprite;
	var playhead:FlxSprite;
	var boxRect:FlxSprite;
	var waveSig:Float = -1;
	final waveScratch:Array<Array<Array<Float>>> = [[[0], [0]], [[0], [0]]];

	/** Time (ms) of the selected event group; matching marks highlight. -1 = none. **/
	public var selectedEventTime:Float = -1;

	/** Downward time axis flips to upward (notes approach from the top). **/
	public var downscroll(default, null):Bool = false;

	/** Hard scroll cap in ms (audio length); -1 = chart end. **/
	public var maxTime:Float = -1;

	/** Resolves a note type name to its list index for the on-note badge (-1 hides it). **/
	public var typeIndexOf:String->Int = null;

	/** Waveform overlay toggle (needs `waveSource`). **/
	public var waveEnabled:Bool = false;

	/** The sound sampled for the waveform (inst or a vocal track). **/
	public var waveSource(default, set):flixel.sound.FlxSound = null;

	function set_waveSource(v:flixel.sound.FlxSound):flixel.sound.FlxSound {
		if (waveSource != v) {
			waveSource = v;
			waveSig = -1;
		}
		return v;
	}

	/** When on, two waveforms are drawn -- `waveSourceA`/`waveSourceB` over the first/second strumline
		(opponent/player) -- instead of one centered track. **/
	public var wavePerStrum(default, set):Bool = false;

	function set_wavePerStrum(v:Bool):Bool {
		if (wavePerStrum != v) {
			wavePerStrum = v;
			waveSig = -1;
		}
		return v;
	}

	/** Per-strumline waveform sources (used only when `wavePerStrum` is on): A over line 0, B over line 1. **/
	public var waveSourceA(default, set):flixel.sound.FlxSound = null;

	public var waveSourceB(default, set):flixel.sound.FlxSound = null;

	function set_waveSourceA(v:flixel.sound.FlxSound):flixel.sound.FlxSound {
		if (waveSourceA != v) {
			waveSourceA = v;
			waveSig = -1;
		}
		return v;
	}

	function set_waveSourceB(v:flixel.sound.FlxSound):flixel.sound.FlxSound {
		if (waveSourceB != v) {
			waveSourceB = v;
			waveSig = -1;
		}
		return v;
	}

	var waveSprite2:FlxSprite;
	var waveCxA:Float = 0;
	var waveCxB:Float = 0;
	var _spanCx:Float = 0;
	var _spanW:Float = 0;

	/** Shows skinned receptors on the playhead row (the vortex editor look). **/
	public var vortexEnabled(default, set):Bool = false;

	function set_vortexEnabled(v:Bool):Bool {
		vortexEnabled = v;
		var i:Int = vortexReceptors.length;
		while (--i >= 0)
			vortexReceptors[i].visible = v;
		return v;
	}

	// StepMania-style quantized note colors (index = subdivisions per beat; off-grid = grey)
	static final QUANT_DIVS:Array<Int> = [1, 2, 3, 4, 6, 8, 12, 16];
	static final QUANT_COLORS:Array<Int> = [
		0xFFFF3030, // 4th  - red
		0xFF3050FF, // 8th  - blue
		0xFFC040FF, // 12th - purple
		0xFF30C030, // 16th - green
		0xFFFF60C0, // 24th - pink
		0xFFFFE030, // 32nd - yellow
		0xFFFF9030, // 48th - orange
		0xFF40D0D0 // 64th - cyan
	];
	static inline var QUANT_OFFGRID:Int = 0xFF9090A0;

	final sectionLines:Array<FlxSprite> = [];
	final eventMarks:Array<FlxSprite> = [];

	final headPool:Array<NoteSprite> = [];
	final sustainPool:Array<FlxSprite> = [];
	final dataPool:Array<NoteData> = [];
	final livePool:Array<LiveNote> = [];
	final active:Array<LiveNote> = [];

	final eventScratch:Array<Dynamic> = [];

	var layoutSig:Float = -1;
	var lastSectionKc:Int = -1;
	var maxSustain:Float = 0;
	final typeLabels:Array<flixel.text.FlxText> = [];
	var usedTypeLabels:Int = 0;
	final eventLabels:Array<flixel.text.FlxText> = [];
	var usedEventLabels:Int = 0;
	final vortexReceptors:Array<Receptor> = [];

	/**
		@param model the chart data source
		@param selection the live selection (drives note tinting)
		@param fx the field rect left edge in game coordinates
		@param fy the field rect top edge
		@param fw the field rect width
		@param fh the field rect height
	**/
	public function new(model:ChartEditorModel, selection:SelectionModel, fx:Float, fy:Float, fw:Float, fh:Float) {
		this.model = model;
		this.selection = selection;
		this.fx = fx;
		this.fy = fy;
		this.fw = fw;
		this.fh = fh;

		group = new FlxTypedGroup<FlxSprite>();
		overlay = new FlxTypedGroup<FlxSprite>();

		fieldBg = new FlxSprite();
		fieldBg.makeGraphic(1, 1, FlxColor.WHITE);
		fieldBg.color = FlxColor.fromInt(0xFF0E0E10);
		group.add(fieldBg);

		checker = new FlxSprite();
		group.add(checker);

		waveSprite = new FlxSprite();
		waveSprite.alpha = 0.55;
		waveSprite.visible = false;
		group.add(waveSprite);

		waveSprite2 = new FlxSprite();
		waveSprite2.alpha = 0.55;
		waveSprite2.visible = false;
		group.add(waveSprite2);

		ghost = new FlxSprite();
		ghost.makeGraphic(1, 1, FlxColor.WHITE);
		ghost.alpha = 0.16;
		ghost.visible = false;
		group.add(ghost);

		// a faded, correctly-skinned note preview of what a click would place (legacy dummy-arrow feel)
		ghostData = new NoteData();
		ghostNote = new NoteSprite();
		ghostNote.visible = false;
		group.add(ghostNote);

		// the dim overlays live ABOVE the notes so out-of-section notes dim too (legacy look)
		dimTop = new FlxSprite();
		dimTop.makeGraphic(1, 1, FlxColor.BLACK);
		dimTop.alpha = 0.45;
		overlay.add(dimTop);
		dimBottom = new FlxSprite();
		dimBottom.makeGraphic(1, 1, FlxColor.BLACK);
		dimBottom.alpha = 0.45;
		overlay.add(dimBottom);

		playhead = new FlxSprite();
		playhead.makeGraphic(1, 1, FlxColor.WHITE);
		playhead.color = FlxColor.fromInt(UITheme.accent & 0xFFFFFF | 0xFF000000);
		playhead.alpha = 0.9;
		overlay.add(playhead);

		boxRect = new FlxSprite();
		boxRect.makeGraphic(1, 1, FlxColor.WHITE);
		boxRect.color = FlxColor.fromInt(UITheme.accent & 0xFFFFFF | 0xFF000000);
		boxRect.alpha = 0.18;
		boxRect.visible = false;
		overlay.add(boxRect);

		refreshTiming();
		refreshLayout();
	}

	/** Rebuilds the cumulative-steps cache (call after any timing mutation). **/
	public function refreshTiming():Void {
		stepsAt.resize(0);
		var acc:Float = 0;
		var secs = model.chart.sections;
		var i:Int = 0;
		var n:Int = secs.length;
		while (i < n) {
			stepsAt.push(acc);
			acc += secs[i].beats * Conductor.stepsPerBeat(secs[i].denominator);
			i++;
		}
	}

	/**
		Absolute position in 16th-note steps (piecewise across BPM/time-signature changes).
		@param time the song time in ms
		@return the cumulative step position
	**/
	public function stepsOf(time:Float):Float {
		if (stepsAt.length == 0)
			return 0;
		var sec:Int = model.sectionAt(time);
		return stepsAt[sec] + (time - model.sectionStart(sec)) / model.stepMs(sec);
	}

	/**
		Inverse of `stepsOf` (binary search over the section step cache).
		@param steps the cumulative step position
		@return the song time in ms
	**/
	public function timeOfSteps(steps:Float):Float {
		var n:Int = stepsAt.length;
		if (n == 0)
			return 0;
		var lo:Int = 0;
		var hi:Int = n - 1;
		while (lo < hi) {
			var mid:Int = (lo + hi + 1) >> 1;
			if (stepsAt[mid] <= steps)
				lo = mid;
			else
				hi = mid - 1;
		}
		return model.sectionStart(lo) + (steps - stepsAt[lo]) * model.stepMs(lo);
	}

	inline function playheadY():Float {
		return fy + fh * 0.5;
	}

	inline function dirF():Float {
		return downscroll ? -1 : 1;
	}

	inline function yOfSteps(steps:Float, viewSteps:Float):Float {
		return playheadY() + (steps - viewSteps) * cellH * dirF();
	}

	/** Raw (unsnapped) time at a field-space y. **/
	public function timeAtY(gy:Float):Float {
		var steps:Float = stepsOf(viewTime) + (gy - playheadY()) / cellH * dirF();
		if (steps < 0)
			steps = 0;
		return timeOfSteps(steps);
	}

	/**
		Flips the scroll direction (drawables re-realize with flipped sustains).
		@param on `true` = time flows upward
	**/
	public function setDownscroll(on:Bool):Void {
		if (downscroll == on)
			return;
		downscroll = on;
		releaseAll();
	}

	/**
		Shows the placement preview under the cursor: a faded, correctly-skinned note in the hovered
		lane, plus (optionally) a box marking the whole snap region it will land in.
		@param lane the hovered lane index (0 = event lane)
		@param time the snapped placement time in ms
		@param snapSteps the snap region height in steps (only used when `spanRegion`)
		@param spanRegion `true` marks the full snap region (the "N grids" highlight); off by default
	**/
	public function showGhost(lane:Int, time:Float, snapSteps:Float, spanRegion:Bool = false):Void {
		if (lane < 0 || lane >= laneX.length) {
			hideGhost();
			return;
		}
		var viewSteps:Float = stepsOf(viewTime);
		var s:Float = stepsOf(time);

		// optional snap-region box: highlights every grid cell the snap covers
		if (spanRegion) {
			var y0:Float = yOfSteps(s, viewSteps);
			var y1:Float = yOfSteps(s + snapSteps, viewSteps);
			var top:Float = (y0 < y1) ? y0 : y1;
			var hgt:Float = Math.abs(y1 - y0);
			if (hgt < 2)
				hgt = 2;
			ghost.visible = true;
			ghost.setGraphicSize(Std.int(cell), Std.int(hgt));
			ghost.updateHitbox();
			ghost.x = laneX[lane];
			ghost.y = top;
		} else
			ghost.visible = false;

		// the note-shaped preview (the event lane places events, not notes, so show nothing there)
		var line:Int = laneLine[lane];
		if (line < 0) {
			ghostNote.visible = false;
			return;
		}
		var col:Int = laneCol[lane];
		var kc:Int = lineKeyCount(line);
		if (line != ghostLine || col != ghostCol || kc != ghostKc)
			skinGhost(line, col, kc);
		var scl:Float = (ghostNote.frameWidth > 0) ? cell / ghostNote.frameWidth : 1;
		ghostNote.scale.set(scl, scl);
		ghostNote.updateHitbox();
		ghostNote.alpha = 0.4;
		ghostNote.visible = true;
		var y:Float = yOfSteps(s, viewSteps);
		var rowTop:Float = downscroll ? (y - cell) : y;
		ghostNote.x = laneX[lane] + (cell - ghostNote.width) / 2;
		ghostNote.y = rowTop + (cell - ghostNote.height) / 2;
	}

	/** (Re)skins the ghost preview for a lane's column/key count. **/
	function skinGhost(line:Int, col:Int, kc:Int):Void {
		ghostLine = line;
		ghostCol = col;
		ghostKc = kc;
		ghostData.time = 0;
		ghostData.column = col;
		ghostData.strumLine = line;
		ghostData.length = 0;
		ghostData.gfNote = false;
		ghostData.type = '';
		ghostNote.apply(ghostData, kc);
		ghostNote.copyX = ghostNote.copyY = ghostNote.copyAngle = ghostNote.copyAlpha = false;
		ghostNote.angle = 0;
		ghostNote.color = FlxColor.WHITE;
	}

	/** Hides the placement preview (note + region box). **/
	public function hideGhost():Void {
		ghost.visible = false;
		if (ghostNote != null)
			ghostNote.visible = false;
	}

	/** Shows the box-select rectangle between two game-space corners. **/
	public function showBoxRect(x0:Float, y0:Float, x1:Float, y1:Float):Void {
		var lx:Float = (x0 < x1) ? x0 : x1;
		var ly:Float = (y0 < y1) ? y0 : y1;
		var bw:Float = Math.abs(x1 - x0);
		var bh:Float = Math.abs(y1 - y0);
		if (bw < 1)
			bw = 1;
		if (bh < 1)
			bh = 1;
		boxRect.visible = true;
		boxRect.setGraphicSize(Std.int(bw), Std.int(bh));
		boxRect.updateHitbox();
		boxRect.x = lx;
		boxRect.y = ly;
	}

	/** Hides the box-select rectangle. **/
	public function hideBoxRect():Void {
		boxRect.visible = false;
	}

	/** Screen x of a (strumline, column) lane, or -1 when it isn't laid out. **/
	public function laneScreenX(line:Int, column:Int):Float {
		var lane:Int = laneIndexOf(line, column);
		return (lane >= 0) ? laneX[lane] : -1;
	}

	/** The square cell size in px (lane width). **/
	public var cellSize(get, never):Float;

	inline function get_cellSize():Float {
		return cell;
	}

	/** StepMania-style quant color for a time (called once per realize). **/
	function quantColorOf(time:Float):Int {
		var sec:Int = model.sectionAt(time);
		var spb:Int = Conductor.stepsPerBeat(model.denominatorAt(sec));
		var rel:Float = (stepsAt.length > 0) ? (stepsOf(time) - stepsAt[sec]) : 0;
		var beatPos:Float = rel / spb;
		var frac:Float = beatPos - Math.ffloor(beatPos);
		var i:Int = 0;
		var n:Int = QUANT_DIVS.length;
		while (i < n) {
			var v:Float = frac * QUANT_DIVS[i];
			if (Math.abs(v - Math.fround(v)) < 0.002 * QUANT_DIVS[i])
				return QUANT_COLORS[i];
			i++;
		}
		return QUANT_OFFGRID;
	}

	/** Moves/resizes the field rect (combined-dock toggle). **/
	public function resize(fx:Float, fy:Float, fw:Float, fh:Float):Void {
		this.fx = fx;
		this.fy = fy;
		this.fw = fw;
		this.fh = fh;
		refreshLayout();
	}

	/** Recomputes lanes + cell size and redraws the checker (cheap when nothing changed). **/
	public function refreshLayout():Void {
		fieldBg.setGraphicSize(Std.int(fw), Std.int(fh));
		fieldBg.updateHitbox();
		fieldBg.x = fx;
		fieldBg.y = fy;

		laneLine.resize(0);
		laneCol.resize(0);

		laneLine.push(-1); // event lane
		laneCol.push(0);
		// lines that follow the global key count reflect this section's effective count
		var effKc:Int = model.keyCountAt(model.sectionAt(viewTime));
		lastSectionKc = effKc;
		// the classic skin reads the GLOBAL Mania state for atlases/colors/sizes
		if (Mania.current != effKc)
			Mania.apply(effKc);
		var lines:Array<StrumLineData> = model.chart.strumLines;
		var li:Int = 0;
		while (li < lines.length) {
			var line:StrumLineData = lines[li];
			if (line.visible) {
				var kc:Int = (line.keyCount == model.chart.keyCount) ? effKc : line.keyCount;
				var c:Int = 0;
				while (c < kc) {
					laneLine.push(li);
					laneCol.push(c);
					c++;
				}
			}
			li++;
		}

		var laneCount:Int = laneLine.length;
		var gapCount:Int = countGaps();
		var gapW:Float = 10;
		var maxCell:Float = fh / 16;
		var fitCell:Float = (fw - 24 - gapCount * gapW) / laneCount;
		cell = fitCell < maxCell ? fitCell : maxCell;
		if (cell < 6)
			cell = 6;
		// zoom stretches rows only: 1x = square cells with the full section in view
		cellH = cell * zoom;
		if (cellH < 4)
			cellH = 4;

		gridW = laneCount * cell + gapCount * gapW;
		gridX = fx + (fw - gridW) / 2;

		laneX.resize(0);
		var x:Float = gridX;
		var i:Int = 0;
		var prevLine:Int = -2;
		while (i < laneCount) {
			if (i > 0 && laneLine[i] != prevLine)
				x += gapW;
			prevLine = laneLine[i];
			laneX.push(x);
			x += cell;
			i++;
		}

		var sig:Float = laneCount * 10000 + cell;
		if (sig != layoutSig) {
			layoutSig = sig;
			drawChecker();
		}

		playhead.setGraphicSize(Std.int(gridW + 12), 2);
		playhead.updateHitbox();
		playhead.x = gridX - 6;
		playhead.y = playheadY() - 1;

		rebuildVortexReceptors();
		ghostLine = -99; // force the hover preview to re-skin under the new layout/Mania state
		releaseAll();
	}

	/** Flashes a lane's receptor (vortex key feedback). Lane 1 = first note lane. **/
	public function confirmReceptor(lane:Int):Void {
		var idx:Int = lane - 1;
		if (idx >= 0 && idx < vortexReceptors.length)
			flashReceptor(vortexReceptors[idx]);
	}

	/** Flashes the vortex receptor for a chart note (called as notes pass the playhead in playback). **/
	public function confirmForNote(line:Int, column:Int):Void {
		if (!vortexEnabled)
			return;
		var lane:Int = laneIndexOf(line, column);
		var idx:Int = lane - 1;
		if (idx >= 0 && idx < vortexReceptors.length)
			flashReceptor(vortexReceptors[idx]);
	}

	inline function flashReceptor(r:Receptor):Void {
		r.playAnim('confirm', true);
		// return it to the static look shortly after (playAnim alone leaves it stuck on confirm)
		r.resetAnim = (cellH > 0) ? Math.min(0.35, cellH / 200) : 0.2;
	}

	/** One skinned receptor per note lane, parked on the playhead row (vortex look). **/
	function rebuildVortexReceptors():Void {
		var i:Int = vortexReceptors.length;
		while (--i >= 0) {
			overlay.remove(vortexReceptors[i], true);
			vortexReceptors[i].destroy();
		}
		vortexReceptors.resize(0);

		var lane:Int = 1; // skip the event lane
		while (lane < laneLine.length) {
			var line:Int = laneLine[lane];
			var kc:Int = lineKeyCount(line);
			var receptor:Receptor = new Receptor(0, 0, laneCol[lane], 0, kc);
			var s:Float = (receptor.frameWidth > 0) ? cell / receptor.frameWidth : 1;
			receptor.scale.set(s, s);
			receptor.updateHitbox();
			receptor.x = laneX[lane] + (cell - receptor.width) / 2;
			receptor.y = playheadY() - receptor.height / 2;
			receptor.alpha = 0.85;
			receptor.visible = vortexEnabled;
			overlay.insert(0, receptor);
			vortexReceptors.push(receptor);
			lane++;
		}
	}

	function countGaps():Int {
		var gaps:Int = 0;
		var i:Int = 1;
		while (i < laneLine.length) {
			if (laneLine[i] != laneLine[i - 1])
				gaps++;
			i++;
		}
		return gaps;
	}

	function drawChecker():Void {
		// rows are FIXED cell-sized squares; zooming in makes each row a finer subdivision
		var rows:Int = Std.int(fh / cell) + 4;
		var w:Int = Std.int(gridW);
		var h:Int = Std.int(rows * cell);
		if (w < 1 || h < 1)
			return;
		checker.makeGraphic(w, h, 0x00000000, true);
		var bmp = checker.pixels;
		bmp.lock();
		var dark:Int = 0xFF17171A;
		var light:Int = 0xFF1E1E22;
		var eventTint:Int = 0xFF1A1622;
		var r:Int = 0;
		while (r < rows) {
			var y0:Int = Std.int(r * cell);
			var rowH:Int = Std.int((r + 1) * cell) - y0;
			var i:Int = 0;
			while (i < laneX.length) {
				// span each cell to the NEXT cell's left edge so fractional cell widths tile with no
				// 1px transparent seam (which showed the near-black field bg as a vertical line)
				var lx:Float = laneX[i] - gridX;
				var x0:Int = Std.int(lx);
				var x1:Int = Std.int(lx + cell);
				var isEvent:Bool = (laneLine[i] < 0);
				var base:Int = ((r + i) & 1 == 0) ? light : dark;
				if (isEvent)
					base = ((r & 1) == 0) ? eventTint : dark;
				bmp.fillRect(new openfl.geom.Rectangle(x0, y0, x1 - x0, rowH), base);
				i++;
			}
			r++;
		}
		bmp.unlock();
		checker.dirty = true;
		checker.x = gridX;
	}

	/** Scrolls the playhead by a signed number of steps (clamped to the chart). **/
	public function scrollSteps(deltaSteps:Float):Void {
		setViewTime(timeOfSteps(stepsOf(viewTime) + deltaSteps));
	}

	/**
		Moves the playhead by whole snap units, landing on the grid (re-snaps first so a scrub or
		seek that left it off-grid gets corrected).
		@param dir signed number of snap units to move
		@param snapDiv the current snap division (e.g. 16 for 1/16)
	**/
	public function scrollBySnap(dir:Float, snapDiv:Int):Void {
		var t:Float = model.snapTime(viewTime, snapDiv);
		var unit:Float = model.snapMs(model.sectionAt(t), snapDiv);
		setViewTime(model.snapTime(t + dir * unit, snapDiv));
	}

	/**
		Moves the playhead.
		@param t the target time in ms, clamped to [0, min(`maxTime`, chart end)]
	**/
	public function setViewTime(t:Float):Void {
		if (t < 0)
			t = 0;
		var cap:Float = (maxTime >= 0 && maxTime < model.endTime) ? maxTime : model.endTime;
		if (t > cap)
			t = cap;
		viewTime = t;
	}

	/**
		Sets the subdivision zoom and relayouts.
		@param mult rows per step: 2 = each row is half a step, 0.5 = two steps per row
	**/
	public function setZoom(mult:Float):Void {
		if (mult == zoom)
			return;
		zoom = mult;
		refreshLayout();
	}

	/** Timing/notes changed: drop all realized drawables (they re-realize next frame). **/
	public function onModelChanged():Void {
		refreshTiming();
		var list:Array<SongNote> = model.chart.noteList;
		maxSustain = 0;
		var i:Int = list.length;
		while (--i >= 0)
			if (list[i].length > maxSustain)
				maxSustain = list[i].length;
		refreshLayout();
	}

	/** Re-realizes all visible notes (quant toggle, skin change). **/
	public function refreshNotes():Void {
		releaseAll();
	}

	/** Whether a game-space point is inside the field rect. **/
	public inline function contains(gx:Float, gy:Float):Bool {
		return gx >= fx && gx < fx + fw && gy >= fy && gy < fy + fh;
	}

	/** Lane index at a game-space x (-1 outside). Lane 0 is the event lane. **/
	public function laneAt(gx:Float):Int {
		var i:Int = 0;
		var n:Int = laneX.length;
		while (i < n) {
			if (gx >= laneX[i] && gx < laneX[i] + cell)
				return i;
			i++;
		}
		return -1;
	}

	/** The strumline index a lane belongs to (-1 for the event lane/out of range). **/
	public inline function laneStrumLine(lane:Int):Int {
		return (lane >= 0 && lane < laneLine.length) ? laneLine[lane] : -1;
	}

	/** The column within its strumline a lane maps to. **/
	public inline function laneColumn(lane:Int):Int {
		return (lane >= 0 && lane < laneCol.length) ? laneCol[lane] : 0;
	}

	/** The realized note under the pointer, or `null`. **/
	public function noteUnder(gx:Float, gy:Float):SongNote {
		var i:Int = active.length;
		while (--i >= 0) {
			var live:LiveNote = active[i];
			var head:NoteSprite = live.head;
			if (gx >= head.x && gx < head.x + head.width && gy >= head.y && gy < head.y + head.height)
				return live.note;
		}
		return null;
	}

	function isRealized(note:SongNote):Bool {
		var i:Int = active.length;
		while (--i >= 0)
			if (active[i].note == note)
				return true;
		return false;
	}

	function releaseAll():Void {
		var i:Int = active.length;
		while (--i >= 0)
			release(active[i]);
		active.resize(0);
	}

	function release(live:LiveNote):Void {
		var cap:Int = editors.charting.data.EditorPrefs.notePoolCap;
		if (live.head != null) {
			live.head.exists = live.head.visible = false;
			if (cap > 0 && headPool.length >= cap) {
				group.remove(live.head, true);
				live.head.destroy();
			} else
				headPool.push(live.head);
			live.head = null;
		}
		if (live.sustain != null) {
			live.sustain.exists = live.sustain.visible = false;
			if (cap > 0 && sustainPool.length >= cap) {
				group.remove(live.sustain, true);
				live.sustain.destroy();
			} else
				sustainPool.push(live.sustain);
			live.sustain = null;
		}
		if (live.data != null) {
			dataPool.push(live.data);
			live.data = null;
		}
		live.note = null;
		livePool.push(live);
	}

	function realize(note:SongNote):Void {
		var live:LiveNote = (livePool.length > 0) ? livePool.pop() : new LiveNote();
		live.note = note;
		live.selected = false;

		live.quantColor = quantColorOf(note.time);
		live.lastColor = 0xFFFFFFFF;

		var data:NoteData = (dataPool.length > 0) ? dataPool.pop() : new NoteData();
		data.time = note.time;
		data.column = note.column;
		data.strumLine = note.strumLine;
		data.length = note.length;
		data.gfNote = note.gfNote;
		data.type = '';
		if (note.type != null && note.type.length > 0)
			data.applyType(note.type);
		live.data = data;

		var kc:Int = lineKeyCount(note.strumLine);

		var head:NoteSprite = (headPool.length > 0) ? headPool.pop() : newHead();
		head.apply(data, kc);
		head.copyX = head.copyY = head.copyAngle = head.copyAlpha = false;
		head.angle = 0;
		head.color = FlxColor.WHITE;
		var s:Float = (head.frameWidth > 0) ? cell / head.frameWidth : 1;
		head.scale.set(s, s);
		head.updateHitbox();
		live.head = head;

		// quant recolor goes through the RGB palette (r = hue, g = white highlight, b = darkened
		// hue), like the note-color option - a flat FlxSprite tint oversaturates the arrow art
		var quantOn:Bool = editors.charting.data.EditorPrefs.quantColors && (note.type == null || note.type.length == 0);
		if (quantOn && head.rgbShader != null) {
			var qc:FlxColor = FlxColor.fromInt(live.quantColor);
			head.rgbShader.enabled = true;
			head.rgbShader.r = qc;
			head.rgbShader.g = FlxColor.WHITE;
			head.rgbShader.b = qc.getDarkened(0.6);
		}

		if (note.length > 0) {
			// a simple colored bar (like the legacy editor) instead of real skin sustain art
			var sus:FlxSprite = (sustainPool.length > 0) ? sustainPool.pop() : newSustain();
			sus.exists = sus.visible = true;
			sus.color = FlxColor.fromInt(quantOn ? live.quantColor : sustainColorFor(note.column));
			live.sustain = sus;
		}

		active.push(live);
	}

	// Classic per-direction arrow colors for the editor sustain line (indexed by column % 4).
	static final SUSTAIN_COLORS:Array<Int> = [0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F];

	inline function sustainColorFor(column:Int):Int {
		return SUSTAIN_COLORS[column % SUSTAIN_COLORS.length];
	}

	inline function lineKeyCount(line:Int):Int {
		var lines = model.chart.strumLines;
		return (line >= 0 && line < lines.length) ? lines[line].keyCount : model.chart.keyCount;
	}

	function newHead():NoteSprite {
		var head:NoteSprite = new NoteSprite();
		group.add(head);
		return head;
	}

	function newSustain():FlxSprite {
		var sus:FlxSprite = new FlxSprite();
		sus.makeGraphic(1, 1, FlxColor.WHITE);
		sus.alpha = 0.55;
		group.insert(3, sus); // under heads, over the checker/dims
		return sus;
	}

	function laneIndexOf(line:Int, column:Int):Int {
		var i:Int = 0;
		var n:Int = laneLine.length;
		while (i < n) {
			if (laneLine[i] == line && laneCol[i] == column)
				return i;
			i++;
		}
		return -1;
	}

	/**
		The per-frame pass: window realize/release at the edges, drawable positioning, grid
		scroll, dim overlays, section lines, event marks and the waveform.
		@param elapsed frame time in seconds (unused directly; positions derive from `viewTime`)
	**/
	public function updateHot(elapsed:Float):Void {
		// mid-song key count changes re-shape the lanes as the playhead crosses them
		if (model.keyCountAt(model.sectionAt(viewTime)) != lastSectionKc)
			refreshLayout();

		var viewSteps:Float = stepsOf(viewTime);
		// realize well outside the visible field so notes are never seen popping in at the edges
		var padSteps:Float = 6;
		var stepsTop:Float = viewSteps - (fh * 0.5) / cellH - padSteps;
		var stepsBottom:Float = viewSteps + (fh * 0.5) / cellH + padSteps;
		var timeLow:Float = timeOfSteps(stepsTop < 0 ? 0 : stepsTop) - 1;
		var timeHigh:Float = timeOfSteps(stepsBottom) + 1;

		// checker scroll: rows are 1/zoom steps each; anchor to the last even-ROW boundary
		// beyond the field top so the fixed-size squares track the time mapping
		var stepsAtTop:Float = viewSteps + (fy - playheadY()) / cellH * dirF();
		var rowsAtTop:Float = stepsAtTop * zoom;
		var anchorRows:Float = downscroll ? (Math.fceil(rowsAtTop / 2) * 2) : (Math.ffloor(rowsAtTop / 2) * 2);
		checker.y = yOfSteps(anchorRows / zoom, viewSteps);
		checker.x = gridX;

		updateWaveform(viewSteps);

		// section dim overlays (min/max handles both scroll directions)
		var curSec:Int = model.sectionAt(viewTime);
		var secStartY:Float = yOfSteps(stepsAt.length > 0 ? stepsAt[curSec] : 0, viewSteps);
		var secEndSteps:Float = (curSec + 1 < stepsAt.length) ? stepsAt[curSec + 1] : stepsOf(model.endTime);
		var secEndY:Float = yOfSteps(secEndSteps, viewSteps);
		var yLo:Float = (secStartY < secEndY) ? secStartY : secEndY;
		var yHi:Float = (secStartY < secEndY) ? secEndY : secStartY;
		dimTop.setGraphicSize(Std.int(gridW), Std.int(Math.max(1, yLo - fy)));
		dimTop.updateHitbox();
		dimTop.x = gridX;
		dimTop.y = fy;
		dimTop.visible = yLo > fy;
		dimBottom.setGraphicSize(Std.int(gridW), Std.int(Math.max(1, fy + fh - yHi)));
		dimBottom.updateHitbox();
		dimBottom.x = gridX;
		dimBottom.y = yHi;
		dimBottom.visible = yHi < fy + fh;

		updateSectionLines(viewSteps, stepsTop, stepsBottom);

		// release out-of-window (a long sustain keeps its note alive until the TAIL leaves)
		var i:Int = active.length;
		while (--i >= 0) {
			var note:SongNote = active[i].note;
			if (note.time + note.length < timeLow || note.time >= timeHigh) {
				release(active[i]);
				active.splice(i, 1);
			}
		}

		// realize in-window: scan back far enough to catch sustains reaching into view
		var list:Array<SongNote> = model.chart.noteList;
		var idx:Int = model.firstNoteIndex(timeLow - maxSustain);
		var n:Int = list.length;
		while (idx < n) {
			var note:SongNote = list[idx];
			if (note.time >= timeHigh)
				break;
			if (note.time + note.length >= timeLow && !isRealized(note))
				realize(note);
			idx++;
		}

		// position pass
		usedTypeLabels = 0;
		i = active.length;
		while (--i >= 0)
			positionLive(active[i], viewSteps);
		i = typeLabels.length;
		while (--i >= usedTypeLabels)
			typeLabels[i].exists = typeLabels[i].visible = false;

		updateEventMarks(timeLow, timeHigh, viewSteps);
	}

	/** A small index badge over a typed note's head ("3" for Hurt Note etc). **/
	function showTypeBadge(head:NoteSprite, typeIdx:Int):Void {
		var label:flixel.text.FlxText;
		if (usedTypeLabels < typeLabels.length)
			label = typeLabels[usedTypeLabels];
		else {
			label = new flixel.text.FlxText(0, 0, 0, "", 12);
			label.setFormat(null, 12, FlxColor.WHITE, CENTER, flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			group.add(label);
			typeLabels.push(label);
		}
		usedTypeLabels++;
		label.exists = label.visible = true;
		var txt:String = Std.string(typeIdx);
		if (label.text != txt)
			label.text = txt;
		label.x = head.x + (head.width - label.width) / 2;
		label.y = head.y + (head.height - label.height) / 2;
	}

	function positionLive(live:LiveNote, viewSteps:Float):Void {
		var note:SongNote = live.note;
		var lane:Int = laneIndexOf(note.strumLine, note.column);
		var head:NoteSprite = live.head;
		if (lane < 0) {
			head.visible = false;
			if (live.sustain != null)
				live.sustain.visible = false;
			return;
		}
		head.visible = true;
		// the head sits centered on its row (row top at its time going with the scroll direction)
		var y:Float = yOfSteps(stepsOf(note.time), viewSteps);
		var rowTop:Float = downscroll ? (y - cell) : y;
		head.x = laneX[lane] + (cell - head.width) / 2;
		head.y = rowTop + (cell - head.height) / 2;

		var isSel:Bool = selection.has(note);
		live.selected = isSel;
		var wantColor:Int = isSel ? 0xFFE6AEEF : 0xFFFFFFFF;
		if (wantColor != live.lastColor) {
			live.lastColor = wantColor;
			head.color = FlxColor.fromInt(wantColor);
		}

		if (note.type != null && note.type.length > 0 && typeIndexOf != null) {
			var typeIdx:Int = typeIndexOf(note.type);
			if (typeIdx > 0)
				showTypeBadge(head, typeIdx);
		}

		var sus:FlxSprite = live.sustain;
		if (sus != null) {
			// simple bar from the head-cell centre to the endTime step line, centred in the lane
			var headMid:Float = rowTop + cell * 0.5;
			var endMid:Float = yOfSteps(stepsOf(note.time + note.length), viewSteps);
			var top:Float = (headMid < endMid) ? headMid : endMid;
			var span:Float = Math.abs(endMid - headMid);
			if (span < 1)
				span = 1;
			var barW:Float = cell * 0.22;
			if (barW < 3)
				barW = 3;
			sus.visible = true;
			sus.scale.set(barW, span);
			sus.updateHitbox();
			sus.x = laneX[lane] + (cell - barW) / 2;
			sus.y = top;
		}
	}

	function updateSectionLines(viewSteps:Float, stepsTop:Float, stepsBottom:Float):Void {
		var used:Int = 0;
		var i:Int = 0;
		var n:Int = stepsAt.length;
		while (i < n) {
			var s:Float = stepsAt[i];
			if (s >= stepsTop && s <= stepsBottom) {
				var line:FlxSprite;
				if (used < sectionLines.length)
					line = sectionLines[used];
				else {
					line = new FlxSprite();
					line.makeGraphic(1, 1, FlxColor.WHITE);
					line.color = FlxColor.fromInt(0xFF585864);
					group.add(line);
					sectionLines.push(line);
				}
				line.exists = line.visible = true;
				line.setGraphicSize(Std.int(gridW), 1);
				line.updateHitbox();
				line.x = gridX;
				line.y = yOfSteps(s, viewSteps);
				used++;
			}
			i++;
		}
		i = sectionLines.length;
		while (--i >= used)
			sectionLines[i].exists = sectionLines[i].visible = false;
	}

	function updateEventMarks(timeLow:Float, timeHigh:Float, viewSteps:Float):Void {
		model.eventsBetween(timeLow, timeHigh, eventScratch);
		var used:Int = 0;
		usedEventLabels = 0;
		var mx:Float = FlxG.mouse.x;
		var my:Float = FlxG.mouse.y;
		var i:Int = 0;
		var n:Int = eventScratch.length;
		while (i < n) {
			var group2:Array<Dynamic> = eventScratch[i];
			var t:Float = group2[0];
			var mark:FlxSprite;
			if (used < eventMarks.length)
				mark = eventMarks[used];
			else {
				mark = new FlxSprite();
				var icon = backend.Paths.image('editors/eventIcon');
				if (icon != null)
					mark.loadGraphic(icon);
				else {
					mark.makeGraphic(1, 1, FlxColor.WHITE);
					mark.color = FlxColor.fromInt(UITheme.accentAlt & 0xFFFFFF);
				}
				group.add(mark);
				eventMarks.push(mark);
			}
			mark.exists = mark.visible = true;
			var size:Int = Std.int(cell * 0.82);
			mark.setGraphicSize(size, size);
			mark.updateHitbox();
			mark.color = (selectedEventTime >= 0 && Math.abs(t - selectedEventTime) <= 1) ? FlxColor.fromInt(0xFFE6AEEF) : FlxColor.WHITE;
			mark.x = laneX[0] + (cell - size) / 2;
			var rowTop:Float = yOfSteps(stepsOf(t), viewSteps) - (downscroll ? cell : 0);
			mark.y = rowTop + (cell - size) / 2;

			// name label left of the grid; hovering the mark reveals every stacked event
			var subs:Array<Dynamic> = group2[1];
			if (subs != null && subs.length > 0) {
				var hovering:Bool = (mx >= mark.x && mx < mark.x + size && my >= mark.y && my < mark.y + size);
				var text:String;
				if (hovering && subs.length > 1) {
					var names:Array<String> = [for (sub in subs) (sub : Array<Dynamic>) [0]];
					text = names.join('\n');
				} else {
					text = (subs[0] : Array<Dynamic>)[0];
					if (subs.length > 1)
						text += ' +${subs.length - 1}';
				}
				showEventLabel(text, mark.x - UITheme.px(6), rowTop + cell / 2);
			}
			used++;
			i++;
		}
		i = eventMarks.length;
		while (--i >= used)
			eventMarks[i].exists = eventMarks[i].visible = false;
		i = eventLabels.length;
		while (--i >= usedEventLabels)
			eventLabels[i].exists = eventLabels[i].visible = false;
	}

	function showEventLabel(text:String, rightX:Float, centerY:Float):Void {
		var label:flixel.text.FlxText;
		if (usedEventLabels < eventLabels.length)
			label = eventLabels[usedEventLabels];
		else {
			label = new flixel.text.FlxText(0, 0, 0, "", 11);
			label.setFormat(null, 11, FlxColor.WHITE, RIGHT, flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			group.add(label);
			eventLabels.push(label);
		}
		usedEventLabels++;
		label.exists = label.visible = true;
		if (label.text != text)
			label.text = text;
		label.x = rightX - label.width;
		label.y = centerY - label.height / 2;
	}

	function updateWaveform(viewSteps:Float):Void {
		var haveSrc:Bool = wavePerStrum ? (waveSourceA != null || waveSourceB != null) : (waveSource != null);
		if (!waveEnabled || !haveSrc || stepsAt.length == 0) {
			waveSprite.visible = false;
			waveSprite2.visible = false;
			waveSig = -1;
			return;
		}
		var sec:Int = model.sectionAt(viewTime);
		if (wavePerStrum) {
			// two tracks, each over its own strumline: opponent (line 0) + player (line 1).
			var sig:Float = sec * 1000000.0 + cellH * 100 + gridW * 3 + cell + (downscroll ? 0.5 : 0) + 3.0;
			if (sig != waveSig) {
				waveSig = sig;
				redrawPerStrum(sec);
			}
			positionWave(waveSprite, waveCxA, sec, viewSteps);
			positionWave(waveSprite2, waveCxB, sec, viewSteps);
			return;
		}

		waveSprite2.visible = false;
		var sig:Float = sec * 1000000.0 + cellH * 100 + waveWidth() + (downscroll ? 0.5 : 0);
		if (sig != waveSig) {
			waveSig = sig;
			// centered across the note lanes (not biased by the event lane), fixed width: it sits in the
			// gutter between the two fields, it does NOT stretch to span them.
			paintWave(waveSprite, waveSource, sec, Std.int(waveWidth()));
		}
		positionWave(waveSprite, noteCenterX(), sec, viewSteps);
	}

	/** Positions a (already painted, visible) wave sprite centered at `cx` over the current section. **/
	inline function positionWave(spr:FlxSprite, cx:Float, sec:Int, viewSteps:Float):Void {
		if (!spr.visible)
			return;
		var y0:Float = yOfSteps(stepsAt[sec], viewSteps);
		var secEndSteps:Float = (sec + 1 < stepsAt.length) ? stepsAt[sec + 1] : stepsOf(model.endTime);
		var y1:Float = yOfSteps(secEndSteps, viewSteps);
		spr.x = cx - spr.width / 2;
		spr.y = (y0 < y1) ? y0 : y1;
	}

	/** Repaints both per-strumline waveforms: `waveSourceA` over line 0, `waveSourceB` over line 1. **/
	function redrawPerStrum(sec:Int):Void {
		if (waveSourceA != null && spanForLine(0)) {
			waveCxA = _spanCx;
			paintWave(waveSprite, waveSourceA, sec, Std.int(_spanW));
		} else
			waveSprite.visible = false;
		if (waveSourceB != null && spanForLine(1)) {
			waveCxB = _spanCx;
			paintWave(waveSprite2, waveSourceB, sec, Std.int(_spanW));
		} else
			waveSprite2.visible = false;
	}

	/** Centre-x (`_spanCx`) + capped width (`_spanW`) of strumline `lineIdx`'s lanes; false if it has none. **/
	function spanForLine(lineIdx:Int):Bool {
		var first:Int = -1;
		var last:Int = -1;
		var i:Int = 0;
		var n:Int = laneLine.length;
		while (i < n) {
			if (laneLine[i] == lineIdx) {
				if (first < 0)
					first = i;
				last = i;
			}
			i++;
		}
		if (first < 0 || first >= laneX.length || last >= laneX.length)
			return false;
		var left:Float = laneX[first];
		var right:Float = laneX[last] + cell;
		_spanCx = (left + right) / 2;
		var span:Float = right - left;
		var cap:Float = cell * 6;
		_spanW = (cap < span) ? cap : span;
		return true;
	}

	/** Left-to-right span of the note lanes only (excludes the event lane). **/
	inline function noteSpanW():Float {
		return (laneX.length > 1) ? (laneX[laneX.length - 1] + cell - laneX[1]) : gridW;
	}

	/** Horizontal centre of the note lanes only (the midpoint between the two fields). **/
	inline function noteCenterX():Float {
		return (laneX.length > 1) ? (laneX[1] + laneX[laneX.length - 1] + cell) / 2 : gridX + gridW / 2;
	}

	inline function waveWidth():Float {
		var span:Float = noteSpanW();
		var wv:Float = cell * 6;
		return (wv < span) ? wv : span;
	}

	/** Paints one section of `source`'s waveform into `spr`, `w` px wide. Sets `spr.visible`. **/
	function paintWave(spr:FlxSprite, source:flixel.sound.FlxSound, sec:Int, w:Int):Void {
		#if (lime_cffi && !macro)
		var startMs:Float = model.sectionStart(sec);
		var endMs:Float = model.sectionEnd(sec);
		var secEndSteps:Float = (sec + 1 < stepsAt.length) ? stepsAt[sec + 1] : stepsOf(model.endTime);
		var pxH:Float = (secEndSteps - stepsAt[sec]) * cellH;
		var bmpH:Int = Std.int(Math.min(pxH, 2048));
		if (source == null || bmpH < 2 || w < 2 || endMs <= startMs) {
			spr.visible = false;
			return;
		}

		var snd:openfl.media.Sound = @:privateAccess source._sound;
		var buffer:lime.media.AudioBuffer = (snd != null) ? @:privateAccess snd.__buffer : null;
		if (buffer == null) {
			spr.visible = false;
			return;
		}

		if (spr.pixels == null || spr.pixels.width != w || spr.pixels.height != bmpH)
			spr.makeGraphic(w, bmpH, 0x00FFFFFF, true);
		else
			spr.pixels.fillRect(new openfl.geom.Rectangle(0, 0, w, bmpH), 0x00FFFFFF);

		waveScratch[0][0].resize(0);
		waveScratch[0][1].resize(0);
		waveScratch[1][0].resize(0);
		waveScratch[1][1].resize(0);
		var bytes:haxe.io.Bytes = buffer.data.toBytes();
		var data:Array<Array<Array<Float>>> = waveformData(buffer, bytes, startMs, endMs, 1, waveScratch, bmpH);

		var hSize:Float = w / 2;
		var leftLength:Int = (data[0][0].length > data[0][1].length) ? data[0][0].length : data[0][1].length;
		var rightLength:Int = (data[1][0].length > data[1][1].length) ? data[1][0].length : data[1][1].length;
		var length:Int = (leftLength > rightLength) ? leftLength : rightLength;

		var pixels = spr.pixels;
		pixels.lock();
		var index:Int = 0;
		while (index < length && index < bmpH) {
			var lmin:Float = clampAmp((index < data[0][0].length ? data[0][0][index] : 0) * (w / 1.12), hSize) / 2;
			var lmax:Float = clampAmp((index < data[0][1].length ? data[0][1][index] : 0) * (w / 1.12), hSize) / 2;
			var rmin:Float = clampAmp((index < data[1][0].length ? data[1][0][index] : 0) * (w / 1.12), hSize) / 2;
			var rmax:Float = clampAmp((index < data[1][1].length ? data[1][1][index] : 0) * (w / 1.12), hSize) / 2;
			pixels.fillRect(new openfl.geom.Rectangle(hSize - (lmin + rmin), index, (lmin + rmin) + (lmax + rmax), 1), 0xFFFFFFFF);
			index++;
		}
		pixels.unlock();
		spr.dirty = true;
		spr.visible = true;
		spr.scale.x = 1;
		spr.scale.y = pxH / bmpH;
		spr.updateHitbox();
		spr.flipY = downscroll;
		#else
		spr.visible = false;
		#end
	}

	static inline function clampAmp(v:Float, hSize:Float):Float {
		return (v < -hSize) ? -hSize : (v > hSize ? hSize : v);
	}

	/**
		Per-row min/max PCM envelope for a slice of an audio buffer (ported from the legacy
		editor's sampler).
	**/
	static function waveformData(buffer:lime.media.AudioBuffer, bytes:haxe.io.Bytes, time:Float, endTime:Float, multiply:Float = 1,
			?array:Array<Array<Array<Float>>>, ?steps:Float):Array<Array<Array<Float>>> {
		#if (lime_cffi && !macro)
		if (buffer == null || buffer.data == null)
			return [[[0], [0]], [[0], [0]]];

		var khz:Float = (buffer.sampleRate / 1000);
		var channels:Int = buffer.channels;
		var index:Int = Std.int(time * khz);
		var samples:Float = ((endTime - time) * khz);

		if (steps == null)
			steps = 1280;

		var samplesPerRow:Float = samples / steps;
		var samplesPerRowI:Int = Std.int(samplesPerRow);
		var gotIndex:Int = 0;
		var lmin:Float = 0;
		var lmax:Float = 0;
		var rmin:Float = 0;
		var rmax:Float = 0;
		var rows:Float = 0;
		var simpleSample:Bool = false;
		var v1:Bool = false;

		if (array == null)
			array = [[[0], [0]], [[0], [0]]];

		while (index < (bytes.length - 1)) {
			if (index >= 0) {
				var byte:Int = bytes.getUInt16(index * channels * 2);
				if (byte > 65535 / 2)
					byte -= 65535;
				var sample:Float = (byte / 65535);
				if (sample > 0) {
					if (sample > lmax)
						lmax = sample;
				} else if (sample < 0) {
					if (sample < lmin)
						lmin = sample;
				}

				if (channels >= 2) {
					byte = bytes.getUInt16((index * channels * 2) + 2);
					if (byte > 65535 / 2)
						byte -= 65535;
					sample = (byte / 65535);
					if (sample > 0) {
						if (sample > rmax)
							rmax = sample;
					} else if (sample < 0) {
						if (sample < rmin)
							rmin = sample;
					}
				}
			}

			v1 = samplesPerRowI > 0 ? (index % samplesPerRowI == 0) : false;
			while (simpleSample ? v1 : rows >= samplesPerRow) {
				v1 = false;
				rows -= samplesPerRow;
				gotIndex++;

				var lRMin:Float = Math.abs(lmin) * multiply;
				var lRMax:Float = lmax * multiply;
				var rRMin:Float = Math.abs(rmin) * multiply;
				var rRMax:Float = rmax * multiply;

				if (gotIndex > array[0][0].length)
					array[0][0].push(lRMin);
				else
					array[0][0][gotIndex - 1] = array[0][0][gotIndex - 1] + lRMin;
				if (gotIndex > array[0][1].length)
					array[0][1].push(lRMax);
				else
					array[0][1][gotIndex - 1] = array[0][1][gotIndex - 1] + lRMax;

				if (channels >= 2) {
					if (gotIndex > array[1][0].length)
						array[1][0].push(rRMin);
					else
						array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + rRMin;
					if (gotIndex > array[1][1].length)
						array[1][1].push(rRMax);
					else
						array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + rRMax;
				} else {
					if (gotIndex > array[1][0].length)
						array[1][0].push(lRMin);
					else
						array[1][0][gotIndex - 1] = array[1][0][gotIndex - 1] + lRMin;
					if (gotIndex > array[1][1].length)
						array[1][1].push(lRMax);
					else
						array[1][1][gotIndex - 1] = array[1][1][gotIndex - 1] + lRMax;
				}

				lmin = 0;
				lmax = 0;
				rmin = 0;
				rmax = 0;
			}

			index++;
			rows++;
			if (gotIndex > steps)
				break;
		}
		return array;
		#else
		return [[[0], [0]], [[0], [0]]];
		#end
	}

	/** Full teardown (state destroy; the groups die with the state). **/
	public function dispose():Void {
		releaseAll();
	}
}
