package editors.charting.data;

/** One note within a generated pattern: a snap-step offset and a column (relative to the line). **/
typedef PatternNote = {
	step:Int,
	col:Int
};

/**
	Predefined VSRG note patterns (osu!mania style), generated for the active key count. A pattern is
	a pure list of `{step, col}` offsets; the editor turns each offset into a real note by advancing
	`step` snap units from the placement time and mapping `col` onto the target strumline.

	Patterns adapt to any column count: single-lane motifs wrap/mirror across `keyCount`, and chord
	motifs (jumps/hands/chords) scale to the available lanes.
**/
class ChartPattern {
	/** Pattern names in menu order (index = the `id` passed to `build`). **/
	public static final NAMES:Array<String> = [
		"Stairs Up",
		"Stairs Down",
		"Zigzag",
		"Trill",
		"Jacks",
		"Jumps",
		"Jumpstream",
		"Hands",
		"Chords"
	];

	/**
		Generates a pattern's note offsets. Patterns that can be built more than one way pick a random
		variation each call (random start lane, random lane pair, random hand columns, ...), so repeated
		placements aren't identical.
		@param id the pattern index (into `NAMES`)
		@param keyCount the target line's column count
		@param steps how many snap steps the pattern spans
		@return the `{step, col}` offsets (columns already clamped to `[0, keyCount)`)
	**/
	public static function build(id:Int, keyCount:Int, steps:Int):Array<PatternNote> {
		var out:Array<PatternNote> = [];
		var kc:Int = (keyCount < 1) ? 1 : keyCount;
		var n:Int = (steps < 1) ? 1 : steps;
		var i:Int = 0;
		switch (id) {
			case 0: // Stairs Up: ascending run from a random start lane, wrapping
				var start:Int = rnd(kc);
				while (i < n) {
					out.push({step: i, col: (start + i) % kc});
					i++;
				}
			case 1: // Stairs Down: descending run from a random start lane
				var start:Int = rnd(kc);
				while (i < n) {
					out.push({step: i, col: wrap(start - i, kc)});
					i++;
				}
			case 2: // Zigzag: bounce across the lanes from a random phase
				var start:Int = rnd(kc);
				while (i < n) {
					out.push({step: i, col: zigzag(i + start, kc)});
					i++;
				}
			case 3: // Trill: alternate a random distinct lane pair
				var a:Int = rnd(kc);
				var b:Int = otherCol(a, kc);
				while (i < n) {
					out.push({step: i, col: (i % 2 == 0) ? a : b});
					i++;
				}
			case 4: // Jacks: a single random lane repeated
				var c:Int = rnd(kc);
				while (i < n) {
					out.push({step: i, col: c});
					i++;
				}
			case 5: // Jumps: a random distinct pair each step
				var a:Int = rnd(kc);
				var b:Int = otherCol(a, kc);
				while (i < n) {
					out.push({step: i, col: a});
					if (kc > 1)
						out.push({step: i, col: b});
					i++;
				}
			case 6: // Jumpstream: a stream from a random start with a random jump every other step
				var start:Int = rnd(kc);
				while (i < n) {
					var c:Int = (start + i) % kc;
					out.push({step: i, col: c});
					if (kc > 1 && (i % 2 == 1))
						out.push({step: i, col: otherCol(c, kc)});
					i++;
				}
			case 7: // Hands: three random distinct lanes each step (every lane when kc < 3)
				while (i < n) {
					for (c in handCols(kc))
						out.push({step: i, col: c});
					i++;
				}
			case 8: // Chords: every lane on every step (only one form)
				while (i < n) {
					var c:Int = 0;
					while (c < kc) {
						out.push({step: i, col: c});
						c++;
					}
					i++;
				}
			default:
				out.push({step: 0, col: 0});
		}
		return out;
	}

	/** A random column in `[0, kc)`. **/
	static inline function rnd(kc:Int):Int {
		return (kc <= 1) ? 0 : flixel.FlxG.random.int(0, kc - 1);
	}

	/** Wraps a (possibly negative) column into `[0, kc)`. **/
	static inline function wrap(col:Int, kc:Int):Int {
		return ((col % kc) + kc) % kc;
	}

	/** A random column distinct from `a`. **/
	static function otherCol(a:Int, kc:Int):Int {
		if (kc <= 1)
			return 0;
		var b:Int = flixel.FlxG.random.int(0, kc - 1);
		return (b == a) ? (b + 1) % kc : b;
	}

	/** Triangle-wave column index: 0..kc-1..0 (single point at each end). **/
	static function zigzag(i:Int, kc:Int):Int {
		if (kc <= 1)
			return 0;
		var period:Int = 2 * (kc - 1);
		var p:Int = ((i % period) + period) % period;
		return (p < kc) ? p : period - p;
	}

	/** Three random distinct lanes for a "hand" (every lane when kc <= 3), sorted low to high. **/
	static function handCols(kc:Int):Array<Int> {
		if (kc <= 3) {
			var all:Array<Int> = [];
			var c:Int = 0;
			while (c < kc) {
				all.push(c);
				c++;
			}
			return all;
		}
		var a:Int = rnd(kc);
		var b:Int = otherCol(a, kc);
		var c:Int = a;
		while (c == a || c == b)
			c = flixel.FlxG.random.int(0, kc - 1);
		var arr:Array<Int> = [a, b, c];
		arr.sort(function(x:Int, y:Int):Int return x - y);
		return arr;
	}
}
