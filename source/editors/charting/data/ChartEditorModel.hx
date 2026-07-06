package editors.charting.data;

import backend.Conductor;
import backend.SongChart;
import backend.SongChart.ChartSection;
import backend.SongChart.SongNote;
import backend.SongChart.StrumLineData;
import objects.notes.NoteData.KeyCountChange;
import objects.notes.ScrollVelocity.ScrollPoint;

/**
	The editing model around the native `SongChart`: section timing cache, snap math, effective
	(inherited) section values and every chart mutation. ALL edits go through here so undo
	snapshots and script hooks have one choke point.

	Inheritance semantics (user-directed): sections carry NO "change X" flags in the editor's
	eyes - each section's BPM / time signature / key count / scroll velocity is the previous
	section's effective value until edited, and an override simply IS a differing value.
	Setting a value propagates forward through sections that inherited the old value and stops
	at the next explicit override; setting it back to the inherited value removes the override.
**/
final class ChartEditorModel {
	/** The chart being edited (assigned via `load`). **/
	public var chart(default, null):SongChart = null;

	/** Section start times in ms (index-aligned with `chart.sections`). **/
	public final sectionTimes:Array<Float> = [];

	/** End of the last section in ms. **/
	public var endTime(default, null):Float = 0;

	/** Fired after any mutation (panels/notefield refresh from here). **/
	public var onChanged:Void->Void = null;

	/** Time tolerance in ms for matching change-points and note spots. **/
	static inline var EPS:Float = 1.0;

	/** Adapt mode: notes keep their absolute ms time (the grid shifts under them). **/
	public static inline var ADAPT_KEEP:Int = 0;

	/** Adapt mode: notes keep their musical position (step within section); ms times rescale. **/
	public static inline var ADAPT_RESCALE:Int = 1;

	/** Adapt mode: keep ms time, then re-snap every note to the 1/16 grid at the new timing. **/
	public static inline var ADAPT_SNAP:Int = 2;

	public function new() {}

	/** Adopts a chart and rebuilds the timing cache. **/
	public function load(chart:SongChart):Void {
		this.chart = chart;
		rebuildTiming();
	}

	/** Fires `onChanged` (call after any direct chart mutation outside the model's own setters). **/
	public inline function markDirty():Void {
		if (onChanged != null)
			onChanged();
	}

	/** One 16th-note step at a BPM, in ms. **/
	static inline function stepMsOf(bpm:Float):Float {
		return (60 / bpm * 1000) / 4;
	}

	/** A section's duration in ms from its timing fields. **/
	static inline function sectionLengthOf(sc:ChartSection):Float {
		return sc.beats * Conductor.stepsPerBeat(sc.denominator) * stepMsOf(sc.bpm);
	}

	/** Recomputes `sectionTimes`/`endTime` from the sections. **/
	public function rebuildTiming():Void {
		sectionTimes.resize(0);
		endTime = 0;
		if (chart == null)
			return;
		var acc:Float = 0;
		var secs:Array<ChartSection> = chart.sections;
		var i:Int = 0;
		var n:Int = secs.length;
		while (i < n) {
			sectionTimes.push(acc);
			acc += sectionLengthOf(secs[i]);
			i++;
		}
		endTime = acc;
	}

	/** The number of sections in the chart. **/
	public inline function sectionCount():Int {
		return (chart != null) ? chart.sections.length : 0;
	}

	/** A section's start time in ms (past-the-end clamps to `endTime`). **/
	public function sectionStart(sec:Int):Float {
		if (sec <= 0 || sectionTimes.length == 0)
			return 0;
		return (sec < sectionTimes.length) ? sectionTimes[sec] : endTime;
	}

	/** A section's end time in ms (== the next section's start). **/
	public function sectionEnd(sec:Int):Float {
		return (sec + 1 < sectionTimes.length) ? sectionTimes[sec + 1] : endTime;
	}

	/** The section containing `time` (binary search; clamps to the ends). **/
	public function sectionAt(time:Float):Int {
		var n:Int = sectionTimes.length;
		if (n == 0 || time <= 0)
			return 0;
		var lo:Int = 0;
		var hi:Int = n - 1;
		while (lo < hi) {
			var mid:Int = (lo + hi + 1) >> 1;
			if (sectionTimes[mid] <= time)
				lo = mid;
			else
				hi = mid - 1;
		}
		return lo;
	}

	/** One 16th at the section's effective BPM. **/
	public function stepMs(sec:Int):Float {
		return stepMsOf(bpmAt(sec));
	}

	/** One snap unit (`snapDiv` divisions of a 4/4 measure) at the section's BPM. **/
	public inline function snapMs(sec:Int, snapDiv:Int):Float {
		return stepMs(sec) * 16 / snapDiv;
	}

	/** Quantizes an absolute time to the section-relative snap grid (nearest). **/
	public function snapTime(time:Float, snapDiv:Int):Float {
		var sec:Int = sectionAt(time);
		var start:Float = sectionStart(sec);
		var unit:Float = snapMs(sec, snapDiv);
		if (unit <= 0)
			return time;
		return start + Math.round((time - start) / unit) * unit;
	}

	/** Quantizes DOWN to the snap grid - the cell the pointer is inside (placement). **/
	public function floorTime(time:Float, snapDiv:Int):Float {
		var sec:Int = sectionAt(time);
		var start:Float = sectionStart(sec);
		var unit:Float = snapMs(sec, snapDiv);
		if (unit <= 0)
			return time;
		return start + Math.ffloor((time - start) / unit + 0.0001) * unit;
	}

	/** The section's effective BPM (sections carry the running value). **/
	public function bpmAt(sec:Int):Float {
		if (chart == null || chart.sections.length == 0)
			return (chart != null) ? chart.bpm : 100;
		return chart.sections[clampSec(sec)].bpm;
	}

	/** The section's beats-per-section (time signature numerator). **/
	public function beatsAt(sec:Int):Float {
		return (sectionCount() > 0) ? chart.sections[clampSec(sec)].beats : 4;
	}

	/** The section's time signature denominator. **/
	public function denominatorAt(sec:Int):Int {
		return (sectionCount() > 0) ? chart.sections[clampSec(sec)].denominator : 4;
	}

	/** The strumline index the camera focuses during the section. **/
	public function cameraTargetAt(sec:Int):Int {
		return (sectionCount() > 0) ? chart.sections[clampSec(sec)].cameraTarget : 0;
	}

	/** The section's effective key count (base + change-points at/before its start). **/
	public function keyCountAt(sec:Int):Int {
		var count:Int = (chart != null) ? chart.keyCount : 4;
		if (chart == null)
			return count;
		var start:Float = sectionStart(clampSec(sec));
		var list:Array<KeyCountChange> = chart.keyCountChanges;
		var i:Int = 0;
		var n:Int = list.length;
		while (i < n) {
			if (list[i].time <= start + EPS)
				count = list[i].count;
			else
				break;
			i++;
		}
		return count;
	}

	/** The section's effective scroll velocity (base 1.0 + points at/before its start). **/
	public function velocityAt(sec:Int):Float {
		var vel:Float = 1.0;
		if (chart == null)
			return vel;
		var start:Float = sectionStart(clampSec(sec));
		var list:Array<ScrollPoint> = chart.scrollPoints;
		var i:Int = 0;
		var n:Int = list.length;
		while (i < n) {
			if (list[i].time <= start + EPS)
				vel = list[i].vel;
			else
				break;
			i++;
		}
		return vel;
	}

	/** `true` when the section's non-player notes all carry `altAnim` (the legacy section flag). **/
	public function sectionAltState(sec:Int):Bool {
		var from:Float = sectionStart(sec);
		var to:Float = sectionEnd(sec);
		var found:Bool = false;
		var list:Array<SongNote> = chart.noteList;
		var i:Int = firstNoteIndex(from);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time >= to)
				break;
			if (!isPlayerLine(note.strumLine)) {
				if (!note.altAnim)
					return false;
				found = true;
			}
			i++;
		}
		return found;
	}

	inline function clampSec(sec:Int):Int {
		var n:Int = sectionCount();
		return (sec < 0) ? 0 : (sec >= n ? n - 1 : sec);
	}

	inline function isPlayerLine(line:Int):Bool {
		return line >= 0 && line < chart.strumLines.length && chart.strumLines[line].isPlayer;
	}

	/**
		Sets the section's effective BPM, propagating through inheriting sections.
		@param adapt how existing notes react (default `ADAPT_RESCALE`: keep musical position, retime)
	**/
	public function setBpm(sec:Int, v:Float, adapt:Int = ADAPT_RESCALE):Void {
		if (sectionCount() == 0 || v <= 0)
			return;
		sec = clampSec(sec);
		var secs:Array<ChartSection> = chart.sections;
		var positions:MusicalPositions = (adapt == ADAPT_RESCALE) ? capturePositions() : null;

		if (sec == 0)
			chart.bpm = v;
		var i:Int = sec;
		var n:Int = secs.length;
		while (i < n) {
			if (i > sec && secs[i].changeBPM)
				break;
			secs[i].bpm = v;
			i++;
		}
		secs[sec].changeBPM = (sec > 0 && secs[sec].bpm != secs[sec - 1].bpm);

		rebuildTiming();
		if (positions != null)
			restorePositions(positions);
		if (adapt == ADAPT_SNAP)
			snapAllNotes(16);
		markDirty();
	}

	/**
		Sets the section's beats-per-section, propagating through equal-valued followers.
		@param adapt how existing notes react (default `ADAPT_KEEP`: keep absolute ms time)
	**/
	public function setBeats(sec:Int, v:Float, adapt:Int = ADAPT_KEEP):Void {
		if (sectionCount() == 0 || v <= 0)
			return;
		sec = clampSec(sec);
		var secs:Array<ChartSection> = chart.sections;
		var positions:MusicalPositions = (adapt == ADAPT_RESCALE) ? capturePositions() : null;
		var old:Float = secs[sec].beats;
		var i:Int = sec;
		var n:Int = secs.length;
		while (i < n) {
			if (i > sec && secs[i].beats != old)
				break;
			secs[i].beats = v;
			i++;
		}
		rebuildTiming();
		if (positions != null)
			restorePositions(positions);
		if (adapt == ADAPT_SNAP)
			snapAllNotes(16);
		markDirty();
	}

	/**
		Sets the section's time-signature denominator, propagating like `setBeats`.
		@param adapt how existing notes react (default `ADAPT_KEEP`: keep absolute ms time)
	**/
	public function setDenominator(sec:Int, v:Int, adapt:Int = ADAPT_KEEP):Void {
		if (sectionCount() == 0 || v <= 0)
			return;
		sec = clampSec(sec);
		var secs:Array<ChartSection> = chart.sections;
		var positions:MusicalPositions = (adapt == ADAPT_RESCALE) ? capturePositions() : null;
		var old:Int = secs[sec].denominator;
		var i:Int = sec;
		var n:Int = secs.length;
		while (i < n) {
			if (i > sec && secs[i].denominator != old)
				break;
			secs[i].denominator = v;
			i++;
		}
		rebuildTiming();
		if (positions != null)
			restorePositions(positions);
		if (adapt == ADAPT_SNAP)
			snapAllNotes(16);
		markDirty();
	}

	/**
		Re-snaps every note's start time to the section-relative grid and re-sorts the list.
		@param snapDiv the snap division (e.g. 16 for 1/16)
		@return how many notes moved
	**/
	public function snapAllNotes(snapDiv:Int):Int {
		var list:Array<SongNote> = chart.noteList;
		var moved:Int = 0;
		var i:Int = 0;
		var n:Int = list.length;
		while (i < n) {
			var t:Float = snapTime(list[i].time, snapDiv);
			if (Math.abs(t - list[i].time) > 0.001) {
				list[i].time = t;
				moved++;
			}
			i++;
		}
		if (moved > 0)
			list.sort(compareNoteTime);
		return moved;
	}

	static function compareNoteTime(a:SongNote, b:SongNote):Int {
		return (a.time < b.time) ? -1 : (a.time > b.time ? 1 : 0);
	}

	/** Sets the effective key count from this section on (change-point at the section start). **/
	public function setKeyCount(sec:Int, v:Int):Void {
		if (chart == null)
			return;
		sec = clampSec(sec);
		var start:Float = sectionStart(sec);
		var list:Array<KeyCountChange> = chart.keyCountChanges;
		if (sec == 0) {
			var oldBase:Int = chart.keyCount;
			chart.keyCount = v;
			for (line in chart.strumLines)
				if (line.keyCount == oldBase)
					line.keyCount = v;
			removeKeyChangeAt(start);
		} else {
			var inherited:Int = keyCountAt(sec - 1);
			if (v == inherited)
				removeKeyChangeAt(start);
			else
				upsertKeyChange(start, v);
		}
		markDirty();
	}

	function removeKeyChangeAt(time:Float):Void {
		var list:Array<KeyCountChange> = chart.keyCountChanges;
		var i:Int = list.length;
		while (--i >= 0)
			if (Math.abs(list[i].time - time) <= EPS)
				list.splice(i, 1);
	}

	function upsertKeyChange(time:Float, count:Int):Void {
		var list:Array<KeyCountChange> = chart.keyCountChanges;
		var i:Int = 0;
		var n:Int = list.length;
		while (i < n) {
			if (Math.abs(list[i].time - time) <= EPS) {
				list[i].count = count;
				return;
			}
			if (list[i].time > time)
				break;
			i++;
		}
		list.insert(i, {time: time, count: count});
	}

	/** Sets the effective scroll velocity from this section on (point at the section start). **/
	public function setVelocity(sec:Int, v:Float):Void {
		if (chart == null)
			return;
		sec = clampSec(sec);
		var start:Float = sectionStart(sec);
		var inherited:Float = (sec == 0) ? 1.0 : velocityAt(sec - 1);
		var list:Array<ScrollPoint> = chart.scrollPoints;
		if (v == inherited) {
			var i:Int = list.length;
			while (--i >= 0)
				if (Math.abs(list[i].time - start) <= EPS)
					list.splice(i, 1);
		} else {
			var i:Int = 0;
			var n:Int = list.length;
			var done:Bool = false;
			while (i < n) {
				if (Math.abs(list[i].time - start) <= EPS) {
					list[i].vel = v;
					done = true;
					break;
				}
				if (list[i].time > start)
					break;
				i++;
			}
			if (!done)
				list.insert(i, new ScrollPoint(start, v));
		}
		markDirty();
	}

	/**
		Sets which strumline the camera focuses during a section.
		@param sec the section
		@param line the strumline index
	**/
	public function setCameraTarget(sec:Int, line:Int):Void {
		if (sectionCount() == 0)
			return;
		chart.sections[clampSec(sec)].cameraTarget = line;
		markDirty();
	}

	/** Applies/clears `altAnim` on the section's non-player notes (legacy section-alt semantics). **/
	public function setSectionAlt(sec:Int, on:Bool):Void {
		var from:Float = sectionStart(sec);
		var to:Float = sectionEnd(sec);
		var list:Array<SongNote> = chart.noteList;
		var i:Int = firstNoteIndex(from);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time >= to)
				break;
			if (!isPlayerLine(note.strumLine))
				note.altAnim = on;
			i++;
		}
		markDirty();
	}

	/** Appends inherited sections until at least `count` exist. **/
	public function ensureSectionCount(count:Int):Void {
		if (chart == null)
			return;
		var secs:Array<ChartSection> = chart.sections;
		var grew:Bool = false;
		while (secs.length < count) {
			var last:ChartSection = (secs.length > 0) ? secs[secs.length - 1] : null;
			secs.push({
				cameraTarget: (last != null) ? last.cameraTarget : 0,
				bpm: (last != null) ? last.bpm : chart.bpm,
				changeBPM: false,
				beats: (last != null) ? last.beats : 4,
				denominator: (last != null) ? last.denominator : 4
			});
			grew = true;
		}
		if (grew) {
			rebuildTiming();
			markDirty();
		}
	}

	function capturePositions():MusicalPositions {
		var pos:MusicalPositions = {
			noteSec: [],
			noteSteps: [],
			noteLenSteps: [],
			eventSec: [],
			eventSteps: [],
			keySec: [],
			velSec: []
		};
		var i:Int;
		var notes:Array<SongNote> = chart.noteList;
		i = 0;
		while (i < notes.length) {
			var n:SongNote = notes[i];
			var sec:Int = sectionAt(n.time);
			var ms:Float = stepMs(sec);
			pos.noteSec.push(sec);
			pos.noteSteps.push((n.time - sectionStart(sec)) / ms);
			pos.noteLenSteps.push(n.length / ms);
			i++;
		}
		var events:Array<Dynamic> = chart.events;
		i = 0;
		while (i < events.length) {
			var group:Array<Dynamic> = events[i];
			var t:Float = group[0];
			var sec:Int = sectionAt(t);
			pos.eventSec.push(sec);
			pos.eventSteps.push((t - sectionStart(sec)) / stepMs(sec));
			i++;
		}
		i = 0;
		while (i < chart.keyCountChanges.length) {
			pos.keySec.push(sectionAt(chart.keyCountChanges[i].time));
			i++;
		}
		i = 0;
		while (i < chart.scrollPoints.length) {
			pos.velSec.push(sectionAt(chart.scrollPoints[i].time));
			i++;
		}
		return pos;
	}

	function restorePositions(pos:MusicalPositions):Void {
		var i:Int;
		var notes:Array<SongNote> = chart.noteList;
		i = 0;
		while (i < notes.length) {
			var sec:Int = pos.noteSec[i];
			var ms:Float = stepMs(sec);
			notes[i].time = sectionStart(sec) + pos.noteSteps[i] * ms;
			notes[i].length = pos.noteLenSteps[i] * ms;
			i++;
		}
		var events:Array<Dynamic> = chart.events;
		i = 0;
		while (i < events.length) {
			var group:Array<Dynamic> = events[i];
			var sec:Int = pos.eventSec[i];
			group[0] = sectionStart(sec) + pos.eventSteps[i] * stepMs(sec);
			i++;
		}
		i = 0;
		while (i < chart.keyCountChanges.length) {
			chart.keyCountChanges[i].time = sectionStart(pos.keySec[i]);
			i++;
		}
		i = 0;
		while (i < chart.scrollPoints.length) {
			chart.scrollPoints[i].time = sectionStart(pos.velSec[i]);
			i++;
		}
	}

	/** Index of the first note at/after `time` (noteList stays time-sorted). **/
	public function firstNoteIndex(time:Float):Int {
		var list:Array<SongNote> = chart.noteList;
		var lo:Int = 0;
		var hi:Int = list.length;
		while (lo < hi) {
			var mid:Int = (lo + hi) >> 1;
			if (list[mid].time < time)
				lo = mid + 1;
			else
				hi = mid;
		}
		return lo;
	}

	/** Collects notes with `from <= time < to` into `out` (cleared first; no allocation). **/
	public function notesBetween(from:Float, to:Float, out:Array<SongNote>):Void {
		out.resize(0);
		var list:Array<SongNote> = chart.noteList;
		var i:Int = firstNoteIndex(from);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time >= to)
				break;
			out.push(note);
			i++;
		}
	}

	/** Adds a note (kept time-sorted) and returns it. **/
	public function addNote(time:Float, strumLine:Int, column:Int, length:Float = 0, type:String = '', altAnim:Bool = false, gfNote:Bool = false):SongNote {
		var note:SongNote = {
			time: time,
			strumLine: strumLine,
			column: column,
			length: length,
			type: type,
			altAnim: altAnim,
			gfNote: gfNote
		};
		chart.noteList.insert(firstNoteIndex(time), note);
		markDirty();
		return note;
	}

	/**
		Removes a note from the chart.
		@param note the note (identity match)
		@return `true` when it was found and removed
	**/
	public function removeNote(note:SongNote):Bool {
		var ok:Bool = chart.noteList.remove(note);
		if (ok)
			markDirty();
		return ok;
	}

	/** Finds an existing note on the exact spot (snap-tolerant via `EPS`). **/
	public function noteAt(time:Float, strumLine:Int, column:Int):SongNote {
		var list:Array<SongNote> = chart.noteList;
		var i:Int = firstNoteIndex(time - EPS);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time > time + EPS)
				break;
			if (note.strumLine == strumLine && note.column == column)
				return note;
			i++;
		}
		return null;
	}

	/** Moves a note in time/lane, keeping the list sorted. **/
	public function moveNote(note:SongNote, newTime:Float, newStrumLine:Int, newColumn:Int):Void {
		chart.noteList.remove(note);
		note.time = newTime;
		note.strumLine = newStrumLine;
		note.column = newColumn;
		chart.noteList.insert(firstNoteIndex(newTime), note);
		markDirty();
	}

	/**
		Sets a note's sustain length.
		@param note the note
		@param length the new length in ms (negative clamps to 0)
	**/
	public function setNoteLength(note:SongNote, length:Float):Void {
		note.length = (length > 0) ? length : 0;
		markDirty();
	}

	/** Adds a sub-event, merging into an existing group at the same time. **/
	public function addEvent(time:Float, name:String, v1:String, v2:String):Void {
		var events:Array<Dynamic> = chart.events;
		var i:Int = 0;
		var n:Int = events.length;
		while (i < n) {
			var group:Array<Dynamic> = events[i];
			var t:Float = group[0];
			if (Math.abs(t - time) <= EPS) {
				var subs:Array<Dynamic> = group[1];
				subs.push([name, v1, v2]);
				markDirty();
				return;
			}
			if (t > time)
				break;
			i++;
		}
		events.insert(i, [time, [[name, v1, v2]]]);
		markDirty();
	}

	/** Removes one sub-event; drops the group when it empties. **/
	public function removeEvent(group:Array<Dynamic>, subIndex:Int):Void {
		var subs:Array<Dynamic> = group[1];
		if (subIndex >= 0 && subIndex < subs.length)
			subs.splice(subIndex, 1);
		if (subs.length == 0)
			chart.events.remove(group);
		markDirty();
	}

	/** Collects event groups with `from <= time < to` into `out` (cleared first). **/
	public function eventsBetween(from:Float, to:Float, out:Array<Dynamic>):Void {
		out.resize(0);
		var events:Array<Dynamic> = chart.events;
		var i:Int = 0;
		var n:Int = events.length;
		while (i < n) {
			var group:Array<Dynamic> = events[i];
			var t:Float = group[0];
			if (t >= to)
				break;
			if (t >= from)
				out.push(group);
			i++;
		}
	}

	/** Deletes the section's notes (and events when `alsoEvents`). Returns how many went. **/
	public function clearSection(sec:Int, notes:Bool, alsoEvents:Bool):Int {
		var from:Float = sectionStart(sec);
		var to:Float = sectionEnd(sec);
		var removed:Int = 0;
		if (notes) {
			var list:Array<SongNote> = chart.noteList;
			var i:Int = list.length;
			while (--i >= 0) {
				if (list[i].time >= from && list[i].time < to) {
					list.splice(i, 1);
					removed++;
				}
			}
		}
		if (alsoEvents) {
			var events:Array<Dynamic> = chart.events;
			var i:Int = events.length;
			while (--i >= 0) {
				var t:Float = (events[i] : Array<Dynamic>)[0];
				if (t >= from && t < to) {
					events.splice(i, 1);
					removed++;
				}
			}
		}
		markDirty();
		return removed;
	}

	/** Swaps notes between the first opponent and first player strumline within the section. **/
	public function swapSection(sec:Int):Void {
		var from:Float = sectionStart(sec);
		var to:Float = sectionEnd(sec);
		var list:Array<SongNote> = chart.noteList;
		var i:Int = firstNoteIndex(from);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time >= to)
				break;
			if (note.strumLine == SongChart.LEGACY_OPPONENT)
				note.strumLine = SongChart.LEGACY_PLAYER;
			else if (note.strumLine == SongChart.LEGACY_PLAYER)
				note.strumLine = SongChart.LEGACY_OPPONENT;
			i++;
		}
		markDirty();
	}

	/** Copies each side's notes onto the other (skips occupied spots). **/
	public function duetSection(sec:Int):Int {
		var from:Float = sectionStart(sec);
		var to:Float = sectionEnd(sec);
		var scratch:Array<SongNote> = [];
		notesBetween(from, to, scratch);
		var added:Int = 0;
		var i:Int = 0;
		var n:Int = scratch.length;
		while (i < n) {
			var note:SongNote = scratch[i];
			var target:Int = -1;
			if (note.strumLine == SongChart.LEGACY_OPPONENT)
				target = SongChart.LEGACY_PLAYER;
			else if (note.strumLine == SongChart.LEGACY_PLAYER)
				target = SongChart.LEGACY_OPPONENT;
			if (target >= 0 && noteAt(note.time, target, note.column) == null) {
				addNote(note.time, target, note.column, note.length, note.type, note.altAnim, note.gfNote);
				added++;
			}
			i++;
		}
		markDirty();
		return added;
	}

	/** Mirrors columns within each note's strumline (`col -> keyCount-1-col`). **/
	public function mirrorSection(sec:Int):Void {
		var from:Float = sectionStart(sec);
		var to:Float = sectionEnd(sec);
		var list:Array<SongNote> = chart.noteList;
		var i:Int = firstNoteIndex(from);
		var n:Int = list.length;
		while (i < n) {
			var note:SongNote = list[i];
			if (note.time >= to)
				break;
			var kc:Int = (note.strumLine >= 0
				&& note.strumLine < chart.strumLines.length) ? chart.strumLines[note.strumLine].keyCount : chart.keyCount;
			note.column = kc - 1 - note.column;
			i++;
		}
		markDirty();
	}

	/** Appends an ADDITIONAL strumline and returns its index. **/
	public function addStrumLine(id:String, character:String, keyCount:Int):Int {
		var idx:Int = chart.strumLines.length;
		chart.strumLines.push({
			index: idx,
			id: id,
			type: 2,
			isPlayer: false,
			visible: true,
			characters: [character],
			keyCount: keyCount
		});
		markDirty();
		return idx;
	}

	/** Removes a strumline: its notes are deleted and higher line indices shift down. **/
	public function removeStrumLine(idx:Int):Void {
		if (idx < 0 || idx >= chart.strumLines.length)
			return;
		var list:Array<SongNote> = chart.noteList;
		var i:Int = list.length;
		while (--i >= 0) {
			var n:SongNote = list[i];
			if (n.strumLine == idx)
				list.splice(i, 1);
			else if (n.strumLine > idx)
				n.strumLine--;
		}
		chart.strumLines.splice(idx, 1);
		i = 0;
		while (i < chart.strumLines.length) {
			chart.strumLines[i].index = i;
			i++;
		}
		for (sc in chart.sections) {
			if (sc.cameraTarget == idx)
				sc.cameraTarget = 0;
			else if (sc.cameraTarget > idx)
				sc.cameraTarget--;
		}
		markDirty();
	}

	/** Changes a line's key count; notes past the new range are deleted. **/
	public function setLineKeyCount(idx:Int, keyCount:Int):Int {
		if (idx < 0 || idx >= chart.strumLines.length)
			return 0;
		chart.strumLines[idx].keyCount = keyCount;
		var removed:Int = 0;
		var list:Array<SongNote> = chart.noteList;
		var i:Int = list.length;
		while (--i >= 0) {
			var n:SongNote = list[i];
			if (n.strumLine == idx && n.column >= keyCount) {
				list.splice(i, 1);
				removed++;
			}
		}
		markDirty();
		return removed;
	}

	/**
		Shows/hides a strumline's lanes in the grid and gameplay.
		@param idx the strumline index
		@param visible the new state
	**/
	public function setLineVisible(idx:Int, visible:Bool):Void {
		if (idx < 0 || idx >= chart.strumLines.length)
			return;
		chart.strumLines[idx].visible = visible;
		markDirty();
	}

	/**
		Replaces a strumline's character list with a single character.
		@param idx the strumline index
		@param character the character name
	**/
	public function setLineCharacter(idx:Int, character:String):Void {
		if (idx < 0 || idx >= chart.strumLines.length)
			return;
		chart.strumLines[idx].characters = [character];
		markDirty();
	}

	/** Swaps two strumlines' order (visual/lane order only - notes stay on their lines). **/
	public function swapStrumLines(a:Int, b:Int):Void {
		var n:Int = chart.strumLines.length;
		if (a < 0 || b < 0 || a >= n || b >= n || a == b)
			return;
		var tmp:StrumLineData = chart.strumLines[a];
		chart.strumLines[a] = chart.strumLines[b];
		chart.strumLines[b] = tmp;
		chart.strumLines[a].index = a;
		chart.strumLines[b].index = b;
		for (note in chart.noteList) {
			if (note.strumLine == a)
				note.strumLine = b;
			else if (note.strumLine == b)
				note.strumLine = a;
		}
		for (sc in chart.sections) {
			if (sc.cameraTarget == a)
				sc.cameraTarget = b;
			else if (sc.cameraTarget == b)
				sc.cameraTarget = a;
		}
		markDirty();
	}

	/** How many strumlines currently render receptor lanes. **/
	public function visibleLineCount():Int {
		var count:Int = 0;
		for (line in chart.strumLines)
			if (line.visible)
				count++;
		return count;
	}

	/** Copies notes from `sec + offset` into `sec` (times shifted; occupied spots skipped). **/
	public function copyFromSection(sec:Int, offset:Int):Int {
		var src:Int = sec + offset;
		if (src < 0 || src >= sectionCount())
			return 0;
		var delta:Float = sectionStart(sec) - sectionStart(src);
		var scratch:Array<SongNote> = [];
		notesBetween(sectionStart(src), sectionEnd(src), scratch);
		var added:Int = 0;
		var i:Int = 0;
		var n:Int = scratch.length;
		while (i < n) {
			var note:SongNote = scratch[i];
			var t:Float = note.time + delta;
			if (noteAt(t, note.strumLine, note.column) == null) {
				addNote(t, note.strumLine, note.column, note.length, note.type, note.altAnim, note.gfNote);
				added++;
			}
			i++;
		}
		markDirty();
		return added;
	}
}

/** Captured musical positions (section + step offsets) for BPM rescaling. **/
private typedef MusicalPositions = {
	var noteSec:Array<Int>;
	var noteSteps:Array<Float>;
	var noteLenSteps:Array<Float>;
	var eventSec:Array<Int>;
	var eventSteps:Array<Float>;
	var keySec:Array<Int>;
	var velSec:Array<Int>;
}
