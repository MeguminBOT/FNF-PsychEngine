package backend.difficulty;

import flixel.FlxG;
import backend.difficulty.DifficultyRating.ChartRatings;
#if sys
import sys.FileSystem;
#end

/**
 * File-signature cache keyed by chart file PATH + an `(mtime, size)` signature, so an unchanged
 * chart is never re-read/parsed/hashed. Two payloads are cached: the song's display name (for the
 * Freeplay list scan) and its full `ChartRatings` (for the difficulty flyout).
 *
 * Updates dynamically with the songs on disk: a NEW chart file has no entry (miss -> scan), an
 * EDITED chart changes its mtime/size (signature miss -> rescan), and an UNCHANGED chart costs only
 * a `stat()` (hit -> return cached). Complements the content-MD5 `DifficultyCache`: on a signature
 * miss we still hit that by content, so moving/renaming a chart reuses the expensive rating calc.
 *
 * Writes are batched - callers mutate freely and call `commit()` once after a scan batch, avoiding
 * a `FlxG.save.flush()` per song. Persistence mirrors `DifficultyCache` / `backend.ModSecurity`.
 */
class ChartScanCache {
	static var names:Map<String, {sig:String, name:String}> = null;
	static var ratings:Map<String, {sig:String, data:ChartRatings}> = null;
	static var dirty:Bool = false;

	static function ensureLoaded():Void {
		if (names != null)
			return;
		names = new Map();
		ratings = new Map();
		try {
			var raw:Dynamic = FlxG.save.data.chartScanCache;
			if (raw != null) {
				if (raw.names != null)
					names = cast raw.names;
				if (raw.ratings != null)
					ratings = cast raw.ratings;
			}
		} catch (e:Dynamic) {
			names = new Map();
			ratings = new Map();
		}
	}

	/** `mtime:size` for a file, or null when it can't be statted (missing / no filesystem). */
	public static function signatureOf(path:String):String {
		#if sys
		try {
			if (path == null || !FileSystem.exists(path))
				return null;
			var st = FileSystem.stat(path);
			return st.mtime.getTime() + ':' + st.size;
		} catch (e:Dynamic) {
			return null;
		}
		#else
		return null;
		#end
	}

	/**
	 * Cached song display name for a chart file; runs `compute` (a parse) only on a signature miss.
	 * @param path the chart file path
	 * @param compute parses the chart and returns its display name (only called on a miss)
	 */
	public static function songName(path:String, compute:Void->String):String {
		var sig:String = signatureOf(path);
		if (sig == null)
			return compute(); // unstattable (packaged assets / html5): compute, don't cache
		ensureLoaded();
		var e = names.get(path);
		if (e != null && e.sig == sig)
			return e.name;
		var name:String = compute();
		names.set(path, {sig: sig, name: name});
		dirty = true;
		return name;
	}

	/**
	 * Cached ratings for a chart file; runs `compute` (parse + rate) only on a signature miss.
	 * @param path the chart file path
	 * @param compute loads + rates the chart (only called on a miss)
	 */
	public static function ratingsFor(path:String, compute:Void->ChartRatings):ChartRatings {
		var sig:String = signatureOf(path);
		if (sig == null)
			return compute();
		ensureLoaded();
		var e = ratings.get(path);
		if (e != null && e.sig == sig)
			return e.data;
		var data:ChartRatings = compute();
		if (data != null) {
			ratings.set(path, {sig: sig, data: data});
			dirty = true;
		}
		return data;
	}

	/** Persists any pending changes (call once after a scan batch). No-op when nothing changed. */
	public static function commit():Void {
		if (!dirty)
			return;
		dirty = false;
		FlxG.save.data.chartScanCache = {names: names, ratings: ratings};
		FlxG.save.flush();
	}

	public static function clear():Void {
		names = new Map();
		ratings = new Map();
		dirty = false;
		FlxG.save.data.chartScanCache = null;
		FlxG.save.flush();
	}
}
