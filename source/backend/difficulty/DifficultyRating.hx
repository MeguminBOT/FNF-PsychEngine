package backend.difficulty;

import backend.Song;
import backend.Song.SwagSong;
import backend.Highscore;
import backend.patterns.ChartNote;
import haxe.crypto.Md5;

/**
 * Derived stats + every provider's rating for one chart (song at one difficulty).
 * `results` is keyed by `RatingProvider.id()`.
 */
typedef ChartRatings = {
	var md5:String;
	var keyCount:Int;
	var bpm:Float; // base/starting BPM
	var bpmMin:Float;
	var bpmMax:Float;
	var timeSignatures:Array<Array<Int>>; // distinct [num, den] in order of first appearance
	var playerNotes:Int;
	var opponentNotes:Int;
	var lengthMs:Float;
	var results:Map<String, RatingResult>;
}

/**
 * Orchestrates difficulty rating: load the per-difficulty chart the same way
 * FreeplayState does, flatten it to the shared `ChartNote` currency (player lanes
 * only -- the side you actually play), hash it, then run each registered
 * `RatingProvider` cache-first via `DifficultyCache`.
 *
 * Pure CPU + cached I/O; the osu! provider is cheap enough to run inline. Heavier
 * providers (Etterna MSD, Phase B) can be moved off-thread later -- the cache
 * read/write would then stay on the calling (main) thread, only `compute()` threaded.
 *
 * The caller must have set `Mods.currentModDirectory` to the song's folder first
 * (FreeplayState.changeSelection already does this before refreshing the flyout).
 */
class DifficultyRating {
	public static var providers:Array<RatingProvider> = [new OsuManiaStarCalc()];

	/**
	 * Ratings + stats for `songName` at difficulty index `diff`, cache-first by chart-file
	 * signature: an unchanged file returns the cached result without a re-read/parse, a new or
	 * edited file (changed mtime/size) is rescanned. Returns null if the chart can't be loaded.
	 */
	public static function ratingsFor(songName:String, diff:Int):Null<ChartRatings> {
		var path:String = chartPathOf(songName, diff);
		var result:Null<ChartRatings> = ChartScanCache.ratingsFor(path, function():ChartRatings return computeRatings(songName, diff));
		ChartScanCache.commit();
		return result;
	}

	/** The resolved chart file path for a song+difficulty (matches `Song.getChart`'s resolution). */
	static function chartPathOf(songName:String, diff:Int):String {
		var key:String = Highscore.formatSong(songName, diff);
		return Paths.json('${Paths.formatToSongPath(songName)}/${Paths.formatToSongPath(key)}');
	}

	/** Loads + rates a chart from disk (the signature-miss path behind `ratingsFor`). */
	static function computeRatings(songName:String, diff:Int):Null<ChartRatings> {
		var song:SwagSong = loadChart(songName, diff);
		if (song == null)
			return null;

		var keyCount:Int = (song.keyCount != null && song.keyCount > 0) ? song.keyCount : 4;
		var playerNotes:Array<ChartNote> = [];
		var totalNotes:Int = 0;
		var lengthMs:Float = 0;

		if (song.notes != null) {
			for (section in song.notes) {
				if (section == null || section.sectionNotes == null)
					continue;
				for (note in section.sectionNotes) {
					totalNotes++;
					var time:Float = note[0];
					var lane:Int = Std.int(note[1]);
					var length:Float = (note.length > 2 && note[2] != null) ? note[2] : 0;
					var end:Float = time + (length > 0 ? length : 0);
					if (end > lengthMs)
						lengthMs = end;
					if (lane >= 0 && lane < keyCount) {
						var type:String = (note.length > 3 && note[3] != null) ? Std.string(note[3]) : '';
						playerNotes.push({time: time, lane: lane, length: length, type: type});
					}
				}
			}
		}

		playerNotes.sort((a, b) -> (a.time < b.time) ? -1 : (a.time > b.time ? 1 : (a.lane - b.lane)));

		var rate:Float = 1.0;
		var md5:String = hashNotes(playerNotes, keyCount, rate);

		var results:Map<String, RatingResult> = new Map();
		for (provider in providers) {
			var pid:String = provider.id();
			var cached:RatingResult = DifficultyCache.get(md5, pid, provider.algoVersion());
			if (cached == null) {
				cached = provider.compute(playerNotes, keyCount, rate);
				DifficultyCache.put(md5, pid, provider.algoVersion(), cached);
			}
			results.set(pid, cached);
		}

		// BPM range + distinct time signatures across the chart's sections (variable-BPM /
		// mid-song time-signature charts show a range instead of a single value).
		var bpmMin:Float = song.bpm;
		var bpmMax:Float = song.bpm;
		var running:Float = song.bpm;
		var sigs:Array<Array<Int>> = [];
		var baseSig:Array<Int> = (song.timeSignature != null && song.timeSignature.length >= 2) ? [song.timeSignature[0], song.timeSignature[1]] : [4, 4];
		pushSig(sigs, baseSig);
		var runSig:Array<Int> = baseSig;

		if (song.notes != null) {
			for (section in song.notes) {
				if (section == null)
					continue;
				if (section.changeBPM == true && section.bpm != null && section.bpm > 0)
					running = section.bpm;
				if (running < bpmMin)
					bpmMin = running;
				if (running > bpmMax)
					bpmMax = running;
				if (section.changeTimeSignature == true) {
					var num:Int = (section.sectionBeats > 0) ? Std.int(section.sectionBeats) : runSig[0];
					var den:Int = (section.sectionDenominator != null && section.sectionDenominator > 0) ? section.sectionDenominator : 4;
					runSig = [num, den];
					pushSig(sigs, runSig);
				}
			}
		}

		return {
			md5: md5,
			keyCount: keyCount,
			bpm: song.bpm,
			bpmMin: bpmMin,
			bpmMax: bpmMax,
			timeSignatures: sigs,
			playerNotes: playerNotes.length,
			opponentNotes: totalNotes - playerNotes.length,
			lengthMs: lengthMs,
			results: results
		};
	}

	/** Appends a [num, den] time signature to the list if it isn't already present. */
	static function pushSig(into:Array<Array<Int>>, sig:Array<Int>):Void {
		for (s in into)
			if (s[0] == sig[0] && s[1] == sig[1])
				return;
		into.push([sig[0], sig[1]]);
	}

	/** Loads the chart JSON for a song+difficulty without touching PlayState (unlike Song.loadFromJson). */
	static function loadChart(songName:String, diff:Int):Null<SwagSong> {
		try {
			var key:String = Highscore.formatSong(songName, diff);
			return Song.getChart(key, songName);
		} catch (e:Dynamic) {
			return null;
		}
	}

	/** Deterministic content hash over the flattened player notes (+ keyCount + rate), formatting-independent. */
	static function hashNotes(notes:Array<ChartNote>, keyCount:Int, rate:Float):String {
		var buf:StringBuf = new StringBuf();
		buf.add('k');
		buf.add(keyCount);
		buf.add('r');
		buf.add(rate);
		buf.add(';');
		for (n in notes) {
			buf.add(n.time);
			buf.add(':');
			buf.add(n.lane);
			buf.add(':');
			buf.add(n.length);
			buf.add(';');
		}
		return Md5.encode(buf.toString());
	}
}
