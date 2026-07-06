package backend.tools.chartconvert;

#if sys
import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import backend.Song;
import backend.SongChart;
import editors.content.PsychJsonPrinter;

/** Which on-disk chart format a file was authored in (drives the reported migration + whether we skip). **/
enum abstract ChartKind(Int) from Int to Int {
	var V2 = 0; // already psych_v2
	var V1 = 1; // psych_v1
	var LEGACY = 2; // older: Week 7 / psych 0.1-0.3 / event-in-notes
}

/** One convertible chart file discovered by the scan. **/
typedef ChartEntry = {
	var songFolder:String; // e.g. "bopeebo"
	var fileName:String; // e.g. "hard.json"
	var absPath:String; // full path under mods/
	var relPath:String; // <mod>/data/<song>/<file>
	var kind:ChartKind;
}

/** All charts in one `data/<song>/` folder, plus the shared `events.json` (if any) folded into them. **/
typedef FolderJob = {
	var mod:String;
	var songFolder:String;
	var charts:Array<ChartEntry>;
	var eventsPath:String; // the folder's events.json, or null
}

/** A scan of one mod: every convertible chart folder under its `data/`. **/
typedef ModScan = {
	var mod:String;
	var folders:Array<FolderJob>;
	var chartCount:Int;
	var v2Count:Int; // charts already in psych_v2
	var eventFileCount:Int; // standalone events.json files that will be merged + removed
}

/** Tally of a conversion run, surfaced to the UI. **/
typedef ConvertSummary = {
	var converted:Int; // charts rewritten to psych_v2
	var alreadyV2:Int; // charts left untouched (already v2, nothing to merge)
	var failed:Int;
	var eventsMerged:Int; // events.json files folded in + removed
	var backedUp:Int; // files copied to the backup tree
	var errors:Array<String>;
}

/**
	The engine behind the Chart Converter menu. Scans a mod's `data/<song>/` folders for legacy /
	psych_v1 charts, migrates each to the native psych_v2 format (via `Song.parseJSON` +
	`Song.buildPsychV2`), and folds any standalone `events.json` into every difficulty of the same song
	so the resulting chart is self-contained. Overwrites the originals in place; an optional backup
	mirrors each touched file into `<exe>/chartConvertERBackup/<mod>/data/<song>/…` before it is changed,
	preserving the folder layout so the user can restore by copying back.
**/
class ChartConvertJob {
	/** The backup root beside the executable (folder layout preserved underneath). **/
	public static inline var BACKUP_DIR:String = 'chartConvertERBackup';

	/** Absolute backup root, with a trailing slash. **/
	public static function backupRoot():String
		return Path.addTrailingSlash(Sys.getCwd()) + BACKUP_DIR + '/';

	/**
		Scans the given mod folders for convertible chart files.
		@param mods the mod directory names (as returned by `Mods.getModDirectories`)
		@return one `ModScan` per mod that actually contains chart data
	**/
	public static function scanMods(mods:Array<String>):Array<ModScan> {
		var out:Array<ModScan> = [];
		for (mod in mods) {
			var scan:ModScan = scanMod(mod);
			if (scan.chartCount > 0)
				out.push(scan);
		}
		return out;
	}

	/** Scans a single mod's `data/` tree; returns an (possibly empty) `ModScan`. **/
	public static function scanMod(mod:String):ModScan {
		var scan:ModScan = {mod: mod, folders: [], chartCount: 0, v2Count: 0, eventFileCount: 0};
		var dataDir:String = Paths.mods(mod + '/data');
		if (!FileSystem.exists(dataDir) || !FileSystem.isDirectory(dataDir))
			return scan;

		for (name in FileSystem.readDirectory(dataDir)) {
			var songDir:String = dataDir + '/' + name;
			if (!FileSystem.isDirectory(songDir))
				continue;

			var charts:Array<ChartEntry> = [];
			var eventsPath:String = null;
			for (file in FileSystem.readDirectory(songDir)) {
				if (!file.toLowerCase().endsWith('.json'))
					continue;
				var abs:String = songDir + '/' + file;
				if (FileSystem.isDirectory(abs))
					continue;

				if (file.toLowerCase() == 'events.json') {
					eventsPath = abs;
					continue;
				}

				var kind:Null<ChartKind> = detectKind(abs);
				if (kind == null)
					continue; // not a chart (metadata/dialogue/etc.)
				charts.push({
					songFolder: name,
					fileName: file,
					absPath: abs,
					relPath: relFromMods(abs),
					kind: kind
				});
			}

			if (charts.length == 0)
				continue; // an orphan events.json with no charts is left untouched

			scan.folders.push({mod: mod, songFolder: name, charts: charts, eventsPath: eventsPath});
			scan.chartCount += charts.length;
			for (c in charts)
				if (c.kind == V2)
					scan.v2Count++;
			if (eventsPath != null)
				scan.eventFileCount++;
		}
		return scan;
	}

	/**
		Runs the conversion over the given scans, mutating `summary` with the tallies.
		@param scans the folders to convert
		@param backup whether to mirror each touched file into the backup tree first
		@param summary the running tally to accumulate into
	**/
	public static function convert(scans:Array<ModScan>, backup:Bool, summary:ConvertSummary):Void {
		for (scan in scans) {
			for (folder in scan.folders) {
				var allOk:Bool = true;
				for (entry in folder.charts) {
					if (!convertOne(entry, folder.eventsPath, backup, summary))
						allOk = false;
				}
				// Only retire the shared events.json once every difficulty absorbed it, so a failed
				// chart never orphans its events.
				if (folder.eventsPath != null && allOk) {
					try {
						if (backup)
							backupFile(folder.eventsPath, summary);
						FileSystem.deleteFile(folder.eventsPath);
						summary.eventsMerged++;
					} catch (e:Dynamic) {
						summary.errors.push('events.json (' + folder.songFolder + '): ' + Std.string(e));
					}
				}
			}
		}
	}

	/**
		Converts one chart file in place, folding in the folder's `events.json` when present.
		@return true on success (including an intentional skip), false on failure
	**/
	static function convertOne(entry:ChartEntry, eventsPath:String, backup:Bool, summary:ConvertSummary):Bool {
		// Already-v2 charts with nothing to merge are left exactly as-is.
		if (entry.kind == V2 && eventsPath == null) {
			summary.alreadyV2++;
			return true;
		}
		try {
			var raw:String = File.getContent(entry.absPath);
			var chart:SongChart = Song.parseJSON(raw, entry.songFolder);
			if (chart == null)
				throw 'unparseable chart';

			if (eventsPath != null)
				mergeEventsFile(eventsPath, chart);

			var obj:Dynamic = Song.buildPsychV2(chart, chart);
			var out:String = PsychJsonPrinter.print(obj, Song.PSYCH_V2_INLINE, Song.PSYCH_V2_KEY_ORDER);

			if (backup)
				backupFile(entry.absPath, summary);
			File.saveContent(entry.absPath, out);
			summary.converted++;
			return true;
		} catch (e:Dynamic) {
			summary.failed++;
			summary.errors.push(entry.relPath + ': ' + Std.string(e));
			return false;
		}
	}

	/** Appends the events from a standalone `events.json` onto `chart.events` (grouped legacy shape). **/
	static function mergeEventsFile(eventsPath:String, chart:SongChart):Void {
		var raw:String = File.getContent(eventsPath);
		var json:Dynamic = Json.parse(raw);
		if (Reflect.hasField(json, 'song')) {
			var sub:Dynamic = Reflect.field(json, 'song');
			if (sub != null && Type.typeof(sub) == TObject)
				json = sub;
		}
		var extra:Array<Dynamic> = Song.eventsFromV2(cast Reflect.field(json, 'events'));
		if (chart.events == null)
			chart.events = [];
		for (e in extra)
			chart.events.push(e);
	}

	/** Copies `absPath` into the backup tree, preserving its `<mod>/data/<song>/<file>` layout. **/
	static function backupFile(absPath:String, summary:ConvertSummary):Void {
		var dest:String = backupRoot() + relFromMods(absPath);
		var dir:String = Path.directory(dest);
		if (dir != null && dir.length > 0 && !FileSystem.exists(dir))
			FileSystem.createDirectory(dir);
		File.copy(absPath, dest);
		summary.backedUp++;
	}

	/** The path relative to the `mods/` root (drives both `relPath` display and the backup layout). **/
	static inline function relFromMods(absPath:String):String {
		var root:String = Paths.mods();
		return absPath.startsWith(root) ? absPath.substr(root.length) : absPath;
	}

	/**
		Classifies a json file as a chart format, or `null` when it is not a chart (no `notes` array --
		e.g. metadata / dialogue files). Cheap: parses only to read `format` + `notes`.
	**/
	static function detectKind(absPath:String):Null<ChartKind> {
		try {
			var json:Dynamic = Json.parse(File.getContent(absPath));
			if (Reflect.hasField(json, 'song')) {
				var sub:Dynamic = Reflect.field(json, 'song');
				if (sub != null && Type.typeof(sub) == TObject)
					json = sub;
			}
			if (!Std.isOfType(Reflect.field(json, 'notes'), Array))
				return null;
			var fmt:String = Reflect.field(json, 'format');
			if (fmt != null && fmt.startsWith('psych_v2'))
				return V2;
			if (fmt != null && fmt.startsWith('psych_v1'))
				return V1;
			return LEGACY;
		} catch (e:Dynamic) {
			return null;
		}
	}

	/** A short human label for the migration a file will undergo (used by the results list). **/
	public static function actionText(kind:ChartKind, hasEvents:Bool):String {
		var base:String = switch (kind) {
			case V2: hasEvents ? 'psych_v2 (merge events)' : 'already psych_v2 - skip';
			case V1: 'psych_v1 -> psych_v2';
			case LEGACY: 'legacy -> psych_v2';
		}
		if (hasEvents && kind != V2)
			base += ' + merge events';
		return base;
	}

	/** The result-row colour for a chart kind (muted = already v2, accent = a real migration). **/
	public static function colorForKind(kind:ChartKind, hasEvents:Bool):Int {
		if (kind == V2 && !hasEvents)
			return 0xFF8A93A6;
		return switch (kind) {
			case LEGACY: 0xFFFFB84A;
			default: 0xFF6FD3A0;
		}
	}
}
#end
