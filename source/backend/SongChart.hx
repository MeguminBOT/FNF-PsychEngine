package backend;

import objects.notes.NoteData.KeyCountChange;
import objects.notes.NoteDefaults;
import objects.notes.ScrollVelocity.ScrollPoint;

/** A strumline's role (from Codename): the main OPPONENT, the human PLAYER, or an ADDITIONAL line
	(extra character / gf sing-track). `isPlayer` on a strumline is just `type == PLAYER`. **/
enum abstract StrumLineType(Int) from Int to Int {
	var OPPONENT = 0;
	var PLAYER = 1;
	var ADDITIONAL = 2;
}

/** One strumline descriptor in the native model. `index` is its absolute id (what a note's `s` refers
	to); `visible` lines render receptors/notes (≤3 at once), hidden lines only animate their characters.
	`type` is the authoritative role; `isPlayer` is a cached `type == PLAYER` for the runtime. **/
typedef StrumLineData = {
	var index:Int;
	var id:String;
	var type:Int;
	var isPlayer:Bool;
	var visible:Bool;
	var characters:Array<String>;
	var keyCount:Int;

	/** Per-strumline vocal track suffix (Codename-style): loads `Paths.voices(song, vocalsSuffix)` for
		this line, muted/unmuted by its own note hits/misses. `null` = derive from the line's character
		vocals file, else the side default (`Player`/`Opponent`). **/
	@:optional var vocalsSuffix:String;
}

/** A note in the native model: absolute `(strumLine, column)`, never mustHitSection-relative. `length`
	is already step-quantized (as the legacy runtime did); `gfNote` keeps the note singing gf. **/
typedef SongNote = {
	var time:Float;
	var strumLine:Int;
	var column:Int;
	var length:Float;
	var type:String;
	var altAnim:Bool;
	var gfNote:Bool;
}

/** The timing + camera spine. `cameraTarget` is the strumline index the camera focuses (replaces
	`mustHitSection`). The timing fields mirror the legacy section so the psych_v2 writer + the lazy
	legacy-section projection can reconstruct them. **/
typedef ChartSection = {
	var cameraTarget:Int;
	@:optional var bpm:Float;
	var changeBPM:Bool;
	var beats:Float;
	var denominator:Int;
}

/**
	The strumline-native chart model, and (as of the native-runtime work) the engine's primary `SONG`.

	It is a *structural superset of `Song.SwagSong`*: it carries every Song.SwagSong field -- the scalar metadata
	as real vars, `events`, and a lazily-built `notes:Array<Song.SwagSection>` legacy projection -- PLUS the
	native model (`strumLines`, `noteList`, `sections`, `keyCountChanges`, `scrollPoints`). Core systems
	read the native fields; legacy scripts/editor read `notes`, which builds the section projection on
	first access (the gated "demand" v1 view). `fromLegacy`/`fromV2` populate it from either format.
**/
class SongChart {
	// ---- Scalar metadata (mirrors Song.SwagSong field names so `SONG.bpm`/`.stage`/... read natively) ----
	public var song:String = '';
	public var bpm:Float = 100;
	public var needsVoices:Bool = true;
	public var speed:Float = 1;
	public var offset:Float = 0;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var stage:String = 'stage';
	public var format:String = 'psych_v2';
	public var timeSignature:Array<Int> = null;
	public var keyCount:Int = 4;
	public var arrowSkin:String = null;
	public var splashSkin:String = null;
	public var disableNoteRGB:Bool = false;
	public var gameOverChar:String = null;
	public var gameOverSound:String = null;
	public var gameOverLoop:String = null;
	public var gameOverEnd:String = null;

	/** Legacy grouped events (`[time, [[name, v1, v2], ...]]`) -- kept in the legacy shape the runtime,
		scripts and editor consume; the psych_v2 reader/writer convert to/from the `{t,name,values}` form. **/
	public var events:Array<Dynamic> = [];

	// ---- Native model ----
	public var strumLines:Array<StrumLineData> = [];

	/** Flat, absolute note list (the native gameplay note data). **/
	public var noteList:Array<SongNote> = [];

	public var sections:Array<ChartSection> = [];
	public var keyCountChanges:Array<KeyCountChange> = [];
	public var scrollPoints:Array<ScrollPoint> = [];

	/** The legacy per-section view (`Song.SwagSection[]` with `sectionNotes`/`mustHitSection`/...). A REAL field
		(not a property) so structural `Song.SwagSong`-typed access stays correct + fast on hxcpp. Seeded verbatim
		by `fromLegacy` for v1 (authored sections stay authoritative + editable) and built once from the
		native model by `fromV2`. The editor edits this; it's the authoritative source when re-serializing
		to legacy (native fields are re-derived via `fromLegacy` on save/test). **/
	public var notes:Array<Song.SwagSection> = [];

	public function new() {}

	// The fixed strumline indices for translated legacy charts.
	public static inline var LEGACY_OPPONENT:Int = 0;
	public static inline var LEGACY_PLAYER:Int = 1;
	public static inline var LEGACY_GF:Int = 2;

	/**
		Copies the scalar metadata from a legacy `Song.SwagSong` onto this chart.
		@param song the source chart
	**/
	function copyMetaFromLegacy(song:Song.SwagSong):Void {
		if (song.song != null) this.song = song.song;
		this.bpm = song.bpm;
		this.needsVoices = song.needsVoices;
		this.speed = song.speed;
		this.offset = song.offset;
		if (song.player1 != null) this.player1 = song.player1;
		if (song.player2 != null) this.player2 = song.player2;
		if (song.gfVersion != null) this.gfVersion = song.gfVersion;
		if (song.stage != null) this.stage = song.stage;
		if (song.format != null) this.format = song.format;
		this.timeSignature = song.timeSignature;
		if (song.keyCount != null) this.keyCount = song.keyCount;
		this.arrowSkin = song.arrowSkin;
		this.splashSkin = song.splashSkin;
		this.disableNoteRGB = (song.disableNoteRGB == true);
		this.gameOverChar = song.gameOverChar;
		this.gameOverSound = song.gameOverSound;
		this.gameOverLoop = song.gameOverLoop;
		this.gameOverEnd = song.gameOverEnd;
		this.events = (song.events != null) ? song.events : [];
	}

	/**
		Translates a legacy `Song.SwagSong` up into the native strumline model: copies metadata, seeds the
		legacy `notes` projection with the source sections (v1 authored sections stay authoritative +
		editable), builds the opponent/player strumlines (+ a hidden gf line when the chart uses gf
		sections), flattens `sectionNotes` into absolute `SongNote`s with step-quantized sustains, and
		records the per-section camera target, mid-song key changes and scroll-velocity points.
		@param song the legacy chart
		@return the native model
	**/
	public static function fromLegacy(song:Song.SwagSong):SongChart {
		var chart:SongChart = new SongChart();
		if (song == null)
			return chart;
		// a noteless file - e.g. a standalone `events.json` loaded via getChart('events', ...) - carries
		// only events; take those and bail (skip copyMetaFromLegacy, which has no bpm/notes to read).
		if (song.notes == null) {
			chart.events = (song.events != null) ? song.events : [];
			return chart;
		}
		chart.copyMetaFromLegacy(song);
		chart.notes = song.notes; // v1: authored sections are authoritative + editable

		var baseKeyCount:Int = Mania.resolveKeyCount(song.keyCount);
		var daBpm:Float = song.bpm;
		var curKeyCount:Int = baseKeyCount;
		var sectionStartTime:Float = 0;
		var secIndex:Int = 0;

		for (section in song.notes) {
			if (section.changeBPM == true && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			// Step length (16th) for this section's BPM; sustains quantise to whole steps.
			var stepMs:Float = (60 / daBpm * 1000) / 4;

			if (section.changeKeyCount == true && section.keyCount != null) {
				var newCount:Int = Mania.clamp(section.keyCount);
				if (newCount != curKeyCount) {
					curKeyCount = newCount;
					chart.keyCountChanges.push({time: sectionStartTime, count: curKeyCount});
				}
			}

			// Raw section-start SV point; NoteData.generate applies the note offset.
			if (section.changeScrollVelocity == true && section.scrollVelocity != null)
				chart.scrollPoints.push(new ScrollPoint(sectionStartTime, section.scrollVelocity));

			for (raw in section.sectionNotes) {
				var songNotes:Array<Dynamic> = raw;
				var lane:Int = Std.int(songNotes[1]);
				var mustPress:Bool = (lane < curKeyCount);

				var holdLength:Float = songNotes[2];
				if (Math.isNaN(holdLength))
					holdLength = 0;
				if (holdLength > 0 && stepMs > 0)
					holdLength = Math.floor(holdLength / stepMs + 0.0001) * stepMs;

				var typeName:String = !Std.isOfType(songNotes[3], String) ? NoteDefaults.defaultNoteTypes[songNotes[3]] : songNotes[3];
				var gfNote:Bool = (section.gfSection == true && mustPress == section.mustHitSection);

				chart.noteList.push({
					time: songNotes[0],
					strumLine: mustPress ? LEGACY_PLAYER : LEGACY_OPPONENT,
					column: Std.int(lane % curKeyCount),
					length: holdLength,
					type: typeName,
					altAnim: (section.altAnim == true && !mustPress),
					gfNote: gfNote
				});
			}

			// gf sections focus the gf strumline; else the must-hit side.
			var camTarget:Int;
			if (section.gfSection == true)
				camTarget = LEGACY_GF;
			else
				camTarget = (section.mustHitSection == true) ? LEGACY_PLAYER : LEGACY_OPPONENT;

			var beats:Float = Conductor.getSectionBeats(song, secIndex);
			var denom:Int = Conductor.getSectionDenominator(song, secIndex);
			chart.sections.push({
				cameraTarget: camTarget,
				bpm: daBpm,
				changeBPM: (section.changeBPM == true),
				beats: beats,
				denominator: denom
			});

			sectionStartTime += (beats * Conductor.stepsPerBeat(denom)) * stepMs;
			secIndex++;
		}

		var oppChar:String = (song.player2 != null) ? song.player2 : 'dad';
		var plrChar:String = (song.player1 != null) ? song.player1 : 'bf';
		var gfChar:String = (song.gfVersion != null) ? song.gfVersion : 'gf';
		chart.strumLines.push({index: LEGACY_OPPONENT, id: 'opponent', type: OPPONENT, isPlayer: false, visible: true, characters: [oppChar], keyCount: baseKeyCount});
		chart.strumLines.push({index: LEGACY_PLAYER, id: 'player', type: PLAYER, isPlayer: true, visible: true, characters: [plrChar], keyCount: baseKeyCount});
		// The gf line always exists (hidden): it's the native replacement for "GF Section" —
		// notes charted on it make GF sing without relying on gfNote flags or GF note types.
		chart.strumLines.push({index: LEGACY_GF, id: 'gf', type: ADDITIONAL, isPlayer: false, visible: false, characters: [gfChar], keyCount: baseKeyCount});
		return chart;
	}

	/**
		Parses a raw psych_v2 chart object into the native model. Direct inverse of `Song.buildPsychV2`:
		reads metadata, the `strumlines`, flat absolute `notes` (`t/s/d/l/k/a/g`) and timing `sections`.
		Note lengths are taken verbatim (v2 authors already step-aligned). The legacy `notes` projection
		stays lazy (built on first access). Running bpm is tracked so every section's `bpm` mirrors
		`fromLegacy`.
		@param json the raw parsed psych_v2 object
		@return the native model
	**/
	public static function fromV2(json:Dynamic):SongChart {
		var chart:SongChart = new SongChart();
		if (json == null)
			return chart;

		// Song-level metadata lives under `metadata`; fall back to the top level for older v2 files.
		var meta:Dynamic = (json.metadata != null) ? json.metadata : json;
		if (meta.song != null) chart.song = meta.song;
		if (meta.bpm != null) chart.bpm = meta.bpm;
		if (meta.speed != null) chart.speed = meta.speed;
		chart.needsVoices = (meta.needsVoices != false);
		if (meta.offset != null) chart.offset = meta.offset;
		if (meta.player1 != null) chart.player1 = meta.player1;
		if (meta.player2 != null) chart.player2 = meta.player2;
		if (meta.gfVersion != null) chart.gfVersion = meta.gfVersion;
		if (meta.stage != null) chart.stage = meta.stage;
		chart.format = 'psych_v2';
		if (meta.timeSignature != null) chart.timeSignature = meta.timeSignature;
		if (meta.arrowSkin != null) chart.arrowSkin = meta.arrowSkin;
		if (meta.splashSkin != null) chart.splashSkin = meta.splashSkin;
		if (meta.disableNoteRGB != null) chart.disableNoteRGB = meta.disableNoteRGB;
		if (meta.gameOverChar != null) chart.gameOverChar = meta.gameOverChar;
		if (meta.gameOverSound != null) chart.gameOverSound = meta.gameOverSound;
		if (meta.gameOverLoop != null) chart.gameOverLoop = meta.gameOverLoop;
		if (meta.gameOverEnd != null) chart.gameOverEnd = meta.gameOverEnd;
		chart.events = Song.eventsFromV2(json.events);

		var rawLines:Array<Dynamic> = json.strumlines;
		if (rawLines != null) {
			for (i in 0...rawLines.length) {
				var e:Dynamic = rawLines[i];
				var chars:Array<String> = (e.characters != null) ? e.characters : [];
				// `type` is authoritative; fall back to the old `isPlayer` bool for pre-type v2 files.
				var lineType:Int = (e.type != null) ? Std.int(e.type) : ((e.isPlayer == true) ? PLAYER : OPPONENT);
				chart.strumLines.push({
					index: i,
					id: (e.id != null) ? e.id : ('line' + i),
					type: lineType,
					isPlayer: (lineType == PLAYER),
					visible: (e.visible != false),
					characters: chars,
					keyCount: Mania.resolveKeyCount(e.keyCount),
					vocalsSuffix: e.vocalsSuffix
				});
			}
		}
		// keyCount for multikey globals: the first player line's, else the first line's.
		if (chart.strumLines.length > 0) {
			chart.keyCount = chart.strumLines[0].keyCount;
			for (sd in chart.strumLines)
				if (sd.isPlayer) {
					chart.keyCount = sd.keyCount;
					break;
				}
		}

		var rawNotes:Array<Dynamic> = json.notes;
		if (rawNotes != null) {
			for (n in rawNotes) {
				chart.noteList.push({
					time: (n.t != null) ? n.t : 0.0,
					strumLine: (n.s != null) ? Std.int(n.s) : 0,
					column: (n.d != null) ? Std.int(n.d) : 0,
					length: (n.l != null) ? n.l : 0.0,
					type: (n.k != null) ? n.k : '',
					altAnim: (n.a == true),
					gfNote: (n.g == true)
				});
			}
		}

		var daBpm:Float = chart.bpm;
		var rawSecs:Array<Dynamic> = json.sections;
		if (rawSecs != null) {
			for (s in rawSecs) {
				var changeBPM:Bool = (s.changeBPM == true);
				if (changeBPM && s.bpm != null)
					daBpm = s.bpm;
				var ts:Array<Dynamic> = s.timeSignature;
				chart.sections.push({
					cameraTarget: (s.cameraTarget != null) ? Std.int(s.cameraTarget) : 0,
					bpm: daBpm,
					changeBPM: changeBPM,
					beats: (ts != null && ts.length > 0) ? ts[0] : 4,
					denominator: (ts != null && ts.length > 1) ? ts[1] : 4
				});
			}
		}
		// Legacy section view for scripts/editor (native `noteList`/`sections` remain authoritative for play).
		chart.notes = chart.buildLegacySections();
		return chart;
	}

	/**
		Builds a clean legacy `Song.SwagSong` (only the v1 fields -- no native `strumLines`/`noteList`/`sections`)
		for serializing a legacy `psych_v1` chart. The native model carries extra fields that must not leak
		into a v1 save.
		@return the legacy-only chart object
	**/
	public function toLegacySwag():Song.SwagSong {
		var s:Song.SwagSong = {
			song: song,
			notes: notes,
			events: events,
			bpm: bpm,
			needsVoices: needsVoices,
			speed: speed,
			offset: offset,
			player1: player1,
			player2: player2,
			gfVersion: gfVersion,
			stage: stage,
			format: (format != null && format.startsWith('psych_v1')) ? format : 'psych_v1'
		};
		s.keyCount = keyCount;
		if (timeSignature != null) s.timeSignature = timeSignature;
		if (arrowSkin != null) s.arrowSkin = arrowSkin;
		if (splashSkin != null) s.splashSkin = splashSkin;
		if (disableNoteRGB) s.disableNoteRGB = true;
		if (gameOverChar != null) s.gameOverChar = gameOverChar;
		if (gameOverSound != null) s.gameOverSound = gameOverSound;
		if (gameOverLoop != null) s.gameOverLoop = gameOverLoop;
		if (gameOverEnd != null) s.gameOverEnd = gameOverEnd;
		return s;
	}

	/** First section whose start time is <= `time` (sections ascending; buckets flat notes into sections). **/
	static inline function sectionForTime(starts:Array<Float>, time:Float):Int {
		var idx:Int = 0;
		for (i in 0...starts.length) {
			if (time >= starts[i])
				idx = i;
			else
				break;
		}
		return idx;
	}

	/**
		Builds the legacy `Song.SwagSection[]` view from the native model: each section carries its timing +
		a `mustHitSection`/`gfSection` derived from `cameraTarget`, and the flat `noteList` is bucketed
		back into sections with absolute lanes (`column` for player lines, `column + keyCount` for
		others). Notes on strumlines beyond the first player/opponent can't be represented in the 2-side
		legacy shape (they collide onto the opponent side) -- gameplay is unaffected (it reads the native
		fields); this is only the legacy compat view.
		@return the legacy sections
	**/
	function buildLegacySections():Array<Song.SwagSection> {
		var starts:Array<Float> = [];
		var acc:Float = 0;
		for (sc in sections) {
			starts.push(acc);
			var stepMs:Float = (60 / sc.bpm * 1000) / 4;
			acc += (sc.beats * Conductor.stepsPerBeat(sc.denominator)) * stepMs;
		}

		var out:Array<Song.SwagSection> = [];
		for (sc in sections) {
			var camLine:StrumLineData = (sc.cameraTarget >= 0 && sc.cameraTarget < strumLines.length) ? strumLines[sc.cameraTarget] : null;
			var sec:Song.SwagSection = {
				sectionNotes: [],
				sectionBeats: sc.beats,
				mustHitSection: (camLine != null && camLine.isPlayer)
			};
			if (camLine != null && !camLine.isPlayer && camLine.id == 'gf')
				sec.gfSection = true;
			if (sc.changeBPM) {
				sec.changeBPM = true;
				sec.bpm = sc.bpm;
			}
			if (sc.denominator != 4) {
				sec.sectionDenominator = sc.denominator;
				sec.changeTimeSignature = true;
			}
			out.push(sec);
		}

		for (n in noteList) {
			var si:Int = sectionForTime(starts, n.time);
			if (si < 0 || si >= out.length)
				continue;
			var line:StrumLineData = (n.strumLine >= 0 && n.strumLine < strumLines.length) ? strumLines[n.strumLine] : null;
			if (line == null)
				continue;
			var lane:Int = n.column + (line.isPlayer ? 0 : line.keyCount);
			var typeVal:Dynamic = (n.type != null && n.type.length > 0) ? n.type : '';
			out[si].sectionNotes.push([n.time, lane, n.length, typeVal]);
		}
		return out;
	}
}
