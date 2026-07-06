package backend;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.math.FlxRect;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;
import openfl.geom.Matrix;

using StringTools;

typedef NoteSkinData = {
	@:optional var notes:Dynamic;
	@:optional var holds:Dynamic;
	@:optional var ends:Dynamic;
	@:optional var strums:Dynamic;
	@:optional var pressed:Dynamic;
	@:optional var confirm:Dynamic;
	@:optional var splash:Dynamic; // folder-native splash frame key (String, or per-lane object), or a sparrow atlas name
	@:optional var splashScale:Dynamic; // splash scale (Float, or per-lane); defaults to 1
	@:optional var splashFps:Dynamic; // splash fps range ([min,max] or a single Int); defaults to [22,26]
	@:optional var splashOffsets:Dynamic; // per-lane splash offsets
	@:optional var antialiasing:Dynamic; // Bool, or a per-lane object (arrow/center/col index)
	@:optional var holdAntialiasing:Bool;
	@:optional var holdsOverHeads:Bool; // draw hold trails above the note heads instead of below; overrides the global option
	@:optional var headOverlap:Float; // fraction of the note width an un-held hold's body extends up under the head (closes the head/body seam); overrides SustainSprite.headOverlap
	@:optional var holdAlpha:Dynamic; // Float, or per-lane object
	@:optional var scale:Dynamic; // Float, or per-lane object
	@:optional var pixelScale:Dynamic; // scale used while rendering pixel art (Float, or per-lane); falls back to `scale`
	@:optional var fps:Dynamic; // anim fps (Int, or per-lane object)
	@:optional var hiRes:Bool; // hint: skin ships @2x assets (@2x is auto-detected regardless)
	@:optional var endOffsets:Dynamic; // sustain-tail offsets (per-lane); falls back to holdOffsets
	@:optional var colorable:Dynamic;
	@:optional var animated:Dynamic;
	@:optional var pixel:Bool;
	@:optional var pixelVariant:Bool;
	@:optional var rotate:Bool;
	@:optional var directionAngles:Array<Float>;
	@:optional var columnAngles:Array<Float>; // per-column angle override (indexed by column, beats directionAngles)
	@:optional var noteOffsets:Dynamic;
	@:optional var strumOffsets:Dynamic;
	@:optional var holdOffsets:Dynamic;
	@:optional var keys:Dynamic;
}

typedef SkinImage = {
	graphic:FlxGraphic,
	factor:Float
}

// A resolved folder-skin config file: its real on-disk path, the config extension, and the source
// root that owns it -- `""` for the base game (`assets/shared`) or a mod directory. `root` doubles as
// the `Paths.pinModRoot` used so the skin's own images resolve from wherever it lives.
typedef LocatedSkin = {
	path:String,
	ext:String,
	root:String
}

typedef SkinAnim = {
	name:String,
	keys:Array<String>,
	?fps:Int,
	?loop:Bool,
	?angle:Float,
	?square:Bool
}

typedef BuiltAnims = {
	frames:FlxAtlasFrames,
	factor:Float,
	anims:Array<{name:String, indices:Array<Int>, fps:Int, loop:Bool}>
}

// Look details for a folder-native note splash. `NoteSkinConfig.applySplash` builds the frames/anims
// onto the splash sprite and returns this; `NoteSplash` turns it into its `NoteSplashConfig`. `names`
// and `offsets` are indexed by the 4 cardinal splash colours (note column % 4).
typedef SplashInfo = {
	source:String,
	scale:Float,
	allowRGB:Bool,
	allowPixel:Bool,
	pixel:Bool,
	fps:Array<Int>,
	names:Array<String>,
	offsets:Array<Array<Float>>
}

class NoteSkinConfig {
	static var configCache:Map<String, NoteSkinData> = new Map();
	static var folderCache:Map<String, Bool> = new Map();
	static var animCache:Map<String, BuiltAnims> = new Map();
	static var mergedCache:Map<String, NoteSkinData> = new Map();
	static var frameExistsCache:Map<String, Bool> = new Map();
	static var frameKeysCache:Map<String, Array<String>> = new Map();
	static var classicDefaultCache:Null<Bool> = null;
	static var ownerRootCache:Map<String, String> = new Map();
	static var locateCache:Map<String, LocatedSkin> = new Map();

	public static function reset() {
		configCache.clear();
		folderCache.clear();
		animCache.clear();
		mergedCache.clear();
		frameExistsCache.clear();
		frameKeysCache.clear();
		classicDefaultCache = null;
		ownerRootCache.clear();
		locateCache.clear();
		pixelVariantCache = null;
		pixelVariantComputed = false;
	}

	// Supported config formats, in resolution priority. The tabbed `.tcfg` format is primary; plain
	// JSON is the secondary fallback.
	public static final EXTS:Array<String> = ['tcfg', 'json'];

	// The mod directories (and the bare `mods/` root, as `""`) to search for a folder skin, in priority
	// order: the current mod, then global mods, then the bare root, then every other ENABLED mod. This
	// is what lets a folder skin live in any `mods/<MOD>/images/noteSkins/` -- not only a global/current
	// mod -- and still be found and resolved.
	#if (sys && MODS_ALLOWED)
	static function skinModRoots():Array<String> {
		var roots:Array<String> = [];
		if (Mods.allowCurrentModAssets && Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			roots.push(Mods.currentModDirectory);
		for (m in Mods.getGlobalMods())
			if (!roots.contains(m))
				roots.push(m);
		roots.push(''); // the always-scanned bare mods/ root
		for (m in Mods.parseList().enabled)
			if (!roots.contains(m))
				roots.push(m);
		return roots;
	}
	#end

	// Resolves `images/<name>/skin.<ext>` to its real on-disk path + owning root, scanning the base game
	// first (so a mod can't shadow a base skin) then every enabled mod. Cached; cleared by `reset()`.
	static function locateSkinFile(name:String):Null<LocatedSkin> {
		if (name == null || name.length < 1)
			return null;
		if (locateCache.exists(name))
			return locateCache.get(name);

		var found:LocatedSkin = null;
		#if sys
		var rel:String = 'images/$name/skin.';
		for (ext in EXTS) {
			var base:String = Paths.getSharedPath('$rel$ext');
			if (sys.FileSystem.exists(base)) {
				found = {path: base, ext: ext, root: ''};
				break;
			}
		}
		#if MODS_ALLOWED
		if (found == null) {
			for (root in skinModRoots()) {
				for (ext in EXTS) {
					var p:String = (root.length > 0) ? Paths.mods('$root/$rel$ext') : Paths.mods('$rel$ext');
					if (sys.FileSystem.exists(p)) {
						found = {path: p, ext: ext, root: root};
						break;
					}
				}
				if (found != null)
					break;
			}
		}
		#end
		#end
		locateCache.set(name, found);
		return found;
	}

	public static function isFolderSkin(name:String):Bool {
		if (name == null || name.length < 1)
			return false;
		if (folderCache.exists(name))
			return folderCache.get(name);
		var exists:Bool = locateSkinFile(name) != null;
		folderCache.set(name, exists);
		return exists;
	}

	public static function get(name:String):NoteSkinData {
		if (configCache.exists(name))
			return configCache.get(name);

		var data:NoteSkinData = null;
		var file:LocatedSkin = locateSkinFile(name);
		if (file != null) {
			#if sys
			var raw:String = sys.FileSystem.exists(file.path) ? sys.io.File.getContent(file.path) : null;
			#else
			var raw:String = Paths.getTextFromFile('images/$name/skin.${file.ext}');
			#end
			if (raw != null) {
				// Both parsers (TcfgParser for .tcfg, tjson for .json) emit the internal
				// NoteSkinData shape directly, so no remap step is needed here.
				data = cast backend.config.ConfigParser.parse(file.ext, raw);
			}
		}
		configCache.set(name, data);
		return data;
	}

	public static inline var DEFAULT:String = 'noteSkins/Default';

	public static var editorOverride:String = null;

	public static var pixelMode:Bool = false;

	public static function setConfig(name:String, data:NoteSkinData) {
		configCache.set(name, data);
		folderCache.set(name, true);
	}

	public static function clearAnimCache() {
		animCache.clear();
		mergedCache.clear();
		frameExistsCache.clear();
		frameKeysCache.clear();
	}

	public static function forCurrentKeys(name:String):NoteSkinData {
		var base:NoteSkinData = get(name);
		if (base == null || base.keys == null)
			return base;

		var count:Int = Mania.clamp(Mania.current);
		var cacheKey:String = '$name|$count';
		if (mergedCache.exists(cacheKey))
			return mergedCache.get(cacheKey);

		var over:Dynamic = Reflect.field(base.keys, Std.string(count));
		var merged:NoteSkinData = (over == null) ? base : mergeOverride(base, over);
		mergedCache.set(cacheKey, merged);
		return merged;
	}

	static function mergeOverride(base:NoteSkinData, over:Dynamic):NoteSkinData {
		var out:NoteSkinData = Reflect.copy(base);
		for (f in Reflect.fields(over)) {
			var v:Dynamic = Reflect.field(over, f);
			if (v != null)
				Reflect.setField(out, f, v);
		}
		return out;
	}

	public static function list():Array<String> {
		var result:Array<String> = [];
		#if sys
		var roots:Array<String> = ['assets/shared/images/noteSkins'];
		#if MODS_ALLOWED
		roots.push('mods/images/noteSkins'); // bare mods/ root
		// Every enabled mod contributes its skins so a folder skin in any mods/<MOD>/ is selectable,
		// not only global/current ones (they resolve via the owner-root pin at apply time).
		for (mod in Mods.parseList().enabled)
			roots.push('mods/$mod/images/noteSkins');
		#end
		for (root in roots) {
			if (!sys.FileSystem.exists(root) || !sys.FileSystem.isDirectory(root))
				continue;
			for (entry in sys.FileSystem.readDirectory(root)) {
				var dir:String = '$root/$entry';
				if (!sys.FileSystem.isDirectory(dir))
					continue;
				var hasSkin:Bool = false;
				for (ext in EXTS)
					if (sys.FileSystem.exists('$dir/skin.$ext')) {
						hasSkin = true;
						break;
					}
				if (hasSkin) {
					var name:String = 'noteSkins/$entry';
					if (!result.contains(name))
						result.push(name);
				}
			}
		}
		#end
		return result;
	}

	public static function activeSkin():String {
		if (editorOverride != null)
			return editorOverride;

		var sel:String = selectSkin();

		// On a pixel stage, swap a non-pixel folder skin (or the classic default) for a skin flagged
		// `pixelVariant: true` so its pixel art is used. A song that explicitly picked a classic
		// `arrowSkin` is left alone -- it brings its own `pixelUI/` sheet.
		if (PlayState.isPixelStage) {
			var cfg:NoteSkinData = (sel != null) ? get(sel) : null;
			var hasPixel:Bool = (cfg != null) && (cfg.pixelVariant == true || cfg.pixel == true);
			var song = PlayState.SONG;
			var explicitClassic:Bool = (sel == null) && (song != null && song.arrowSkin != null && song.arrowSkin.length > 1);
			if (!hasPixel && !explicitClassic) {
				var pv:String = pixelVariantSkin();
				if (pv != null)
					return pv;
			}
		}

		return sel;
	}

	// The selected skin from chart `arrowSkin` / the player's `noteSkin` pref / the default, or null
	// when none resolve to a folder skin (the classic skin then renders).
	static function selectSkin():String {
		// Force Selected Skin: ignore the chart's arrowSkin so a song can't swap the player's choice.
		var song = PlayState.SONG;
		if (!ClientPrefs.data.forceNoteSkin && song != null && song.arrowSkin != null && song.arrowSkin.length > 1)
			return isFolderSkin(song.arrowSkin) ? song.arrowSkin : null;

		var pref:String = ClientPrefs.data.noteSkin;
		if (pref != null && pref != ClientPrefs.defaultData.noteSkin) {
			var p:String = 'noteSkins/' + pref.trim();
			return isFolderSkin(p) ? p : null;
		}

		// Default pref: a mod shipping a classic NOTE_assets sheet renders classic (null) rather than the
		// base Default folder skin, so a mod's legacy full-sheet skin still applies -- unless the skin is
		// forced, in which case the base Default is kept (the mod's override is ignored).
		if (!ClientPrefs.data.forceNoteSkin && modProvidesClassicDefault())
			return null;
		return isFolderSkin(DEFAULT) ? DEFAULT : null;
	}

	// Whether a mod (the current one, when its assets are allowed, or any global mod) ships a classic
	// default NOTE_assets sheet -- at `images/noteSkins/NOTE_assets.png` OR the `images/`-root
	// `images/NOTE_assets.png` some mods use, plus the matching `pixelUI/` form on pixel stages. Cached;
	// cleared by `reset()`.
	static function modProvidesClassicDefault():Bool {
		if (classicDefaultCache != null)
			return classicDefaultCache;
		var found:Bool = false;
		#if (sys && MODS_ALLOWED)
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';
		var names:Array<String> = ['images/${path}noteSkins/NOTE_assets.png', 'images/${path}NOTE_assets.png'];
		if (Mods.allowCurrentModAssets && Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			found = modHasAny(Mods.currentModDirectory, names);
		if (!found)
			for (mod in Mods.getGlobalMods())
				if (modHasAny(mod, names)) {
					found = true;
					break;
				}
		#end
		classicDefaultCache = found;
		return found;
	}

	#if (sys && MODS_ALLOWED)
	static function modHasAny(mod:String, names:Array<String>):Bool {
		for (n in names)
			if (sys.FileSystem.exists(Paths.mods('$mod/$n')))
				return true;
		return false;
	}
	#end

	// The single source that owns a folder skin, base-first so a base skin can't be shadowed by a mod's
	// same-named folder: "" (base) if `assets/shared` ships it, else the owning mod dir, else "" (base).
	static function skinOwnerRoot(name:String):String {
		var loc:LocatedSkin = locateSkinFile(name);
		return (loc != null) ? loc.root : '';
	}

	/**
		The `Paths.pinModRoot` to use while applying the active note skin, or `null` for normal resolution.

		- FORCED: pins to the skin's single owner (`""` = base-only, a mod dir = that mod) so another mod
		  can't shadow the chosen skin's assets.
		- NOT forced: pins only when the active folder skin lives in a specific MOD, so its own images
		  resolve from that mod even when it isn't the current/global one. Base-owned skins stay unpinned
		  so a mod may still override individual base arrows. Classic skins are never pinned.
	**/
	public static function activeSkinPinRoot():Null<String> {
		var active:String = activeSkin();
		if (active == null)
			return null;
		var owner:String = skinOwnerRoot(active);
		if (ClientPrefs.data.forceNoteSkin)
			return owner;
		return (owner != null && owner.length > 0) ? owner : null;
	}

	static var pixelVariantCache:String = null;
	static var pixelVariantComputed:Bool = false;

	// The first available folder skin flagged `pixelVariant: true` (the `Default` skin preferred), or
	// null. Cached; cleared by `reset()`. Drives the pixel-stage auto-swap in `activeSkin`.
	public static function pixelVariantSkin():Null<String> {
		if (pixelVariantComputed)
			return pixelVariantCache;
		pixelVariantComputed = true;

		var def:NoteSkinData = get(DEFAULT);
		if (def != null && def.pixelVariant == true) {
			pixelVariantCache = DEFAULT;
			return pixelVariantCache;
		}
		for (name in list()) {
			var cfg:NoteSkinData = get(name);
			if (cfg != null && cfg.pixelVariant == true) {
				pixelVariantCache = name;
				return pixelVariantCache;
			}
		}
		pixelVariantCache = null;
		return null;
	}

	/**
		Whether hold trails should render ABOVE the note heads instead of below them. The active folder
		skin's `holdsOverHeads` (in `skin.tcfg`) wins when set; otherwise the global
		`ClientPrefs.data.sustainsOverNotes` option decides.
		@return `true` to draw sustains over the heads
	**/
	public static function holdsOverHeads():Bool {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.holdsOverHeads != null)
				return cfg.holdsOverHeads;
		}
		return ClientPrefs.data.sustainsOverNotes;
	}

	/**
		Per-skin override for an un-held hold's head/body seam overlap (`SustainSprite.headOverlap`), set
		via `headOverlap` in `skin.tcfg`.
		@return the skin's overlap fraction, or `null` to keep the engine / script default
	**/
	public static function headOverlap():Null<Float> {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.headOverlap != null)
				return cfg.headOverlap;
		}
		return null;
	}

	// The active folder skin's splash as a legacy *sparrow atlas* name (`<skin>/` + its `splash` key),
	// or null. Returns null when the active skin's `splash` resolves to folder-native frames (handled
	// by `applySplash`) or when there's no skin splash. Used by `NoteSplash` for "From Noteskin".
	public static function currentSplash():Null<String> {
		var active:String = activeSkin();
		if (active == null)
			return null;
		var cfg:NoteSkinData = forCurrentKeys(active);
		if (cfg == null || cfg.splash == null)
			return null;
		if (splashSourceKey() != null) // folder-native splash -> not a sparrow atlas name
			return null;
		var key:String = columnKey(cfg.splash, 0);
		return key == null ? null : folder(active) + key;
	}

	// Pixel-mode decision for a skin (matches `FolderNoteSkin.isPixel`): an explicit `pixel`, or a
	// `pixelVariant` while on a pixel stage.
	static inline function pixelForSkin(cfg:NoteSkinData):Bool
		return (cfg.pixel == true) || (cfg.pixelVariant == true && PlayState.isPixelStage);

	// A cache identity for the active skin's folder-native splash (skin|keycount|pixel), or null when
	// the active skin provides no folder splash (no `splash`, or it resolves only as a sparrow atlas).
	// Setting up `pixelMode` here lets `resolveFrames` resolve the splash's pixel/@2x frames.
	public static function splashSourceKey():String {
		var active:String = activeSkin();
		if (active == null)
			return null;
		var cfg:NoteSkinData = forCurrentKeys(active);
		if (cfg == null || cfg.splash == null)
			return null;

		var pix:Bool = pixelForSkin(cfg);
		if (editorOverride == null)
			pixelMode = pix;

		var key:String = columnKey(cfg.splash, 0);
		if (key == null || resolveFrames(folder(active) + key) == null)
			return null; // not folder-native (single image / sequence) -> caller uses the legacy path
		return '$active|${Mania.clamp(Mania.current)}|$pix';
	}

	static function splashFpsRange(cfg:NoteSkinData):Array<Int> {
		var f:Dynamic = cfg.splashFps;
		if (f == null)
			return [22, 26];
		if (Std.isOfType(f, Array)) {
			var a:Array<Dynamic> = f;
			var lo:Int = a.length > 0 ? Std.int(num(a[0])) : 22;
			var hi:Int = a.length > 1 ? Std.int(num(a[1])) : lo;
			return [lo, hi];
		}
		var n:Int = Std.int(num(f));
		return [n, n];
	}

	/**
		Builds a folder-native splash onto `spr` (frames + `splash0..3` anims, one per cardinal colour),
		reusing the same individual-image / sequence / `@2x` / `pixel/` machinery as notes. Returns the
		non-sprite look details, or null when the active skin has no folder splash (the caller then uses
		the legacy `NoteSplash` sparrow path).
	**/
	public static function applySplash(spr:flixel.FlxSprite):SplashInfo {
		var source:String = splashSourceKey();
		if (source == null)
			return null;
		var active:String = activeSkin();
		var cfg:NoteSkinData = forCurrentKeys(active);
		var base:String = folder(active);

		// Per-colour keys (dir/index/arrow), defaulting a missing lane to colour 0's key so a single
		// `splash: burst` covers all four; identical keys are built once and shared.
		var keyByCol:Array<String> = [];
		for (col in 0...4) {
			var k:String = columnKey(cfg.splash, col);
			keyByCol[col] = (k != null) ? k : columnKey(cfg.splash, 0);
		}
		var uniqueKeys:Array<String> = [];
		for (k in keyByCol)
			if (!uniqueKeys.contains(k))
				uniqueKeys.push(k);

		var fps:Array<Int> = splashFpsRange(cfg);
		var anims:Array<SkinAnim> = [];
		for (i in 0...uniqueKeys.length) {
			var frames:Array<String> = resolveFrames(base + uniqueKeys[i]);
			if (frames == null)
				return null;
			anims.push({name: 'splashU$i', keys: frames, fps: fps[1], loop: false});
		}

		var factor:Float = applyAnims(spr, anims);

		var names:Array<String> = [];
		var offsets:Array<Array<Float>> = [];
		for (col in 0...4) {
			names[col] = 'splashU' + uniqueKeys.indexOf(keyByCol[col]);
			offsets[col] = offsetFor(cfg.splashOffsets, col);
		}

		return {
			source: source,
			scale: numForColumn(cfg.splashScale, 0, 1) * factor,
			allowRGB: colorableFor(cfg, 'splash'), // skin support; the link gating happens in NoteSplash
			allowPixel: false, // folder skins ship their own pixel art; no extra shader blocking
			pixel: pixelForSkin(cfg), // but still drop antialiasing so that art stays crisp
			fps: fps,
			names: names,
			offsets: offsets
		};
	}

	public static inline function folder(name:String):String
		return '$name/';

	static inline function num(v:Dynamic):Float
		return v == null ? 0 : ((Std.isOfType(v, Float) || Std.isOfType(v, Int)) ? v : Std.parseFloat(Std.string(v)));

	public static function offsetFor(field:Dynamic, col:Int):Array<Float> {
		if (field == null)
			return [0, 0];
		if (Std.isOfType(field, Array)) {
			var a:Array<Dynamic> = field;
			// Per-column form: an array of [x,y] pairs indexed by column.
			if (a.length > 0 && Std.isOfType(a[0], Array)) {
				if (col >= 0 && col < a.length && Std.isOfType(a[col], Array))
					return pair(a[col]);
				return [0, 0];
			}
			// Single [x, y] applied to every column.
			return pair(a);
		}
		// Object: resolve per lane (column index -> square/center -> name -> arrow).
		var v:Dynamic = rawForColumn(field, col);
		return Std.isOfType(v, Array) ? pair(v) : [0, 0];
	}

	static inline function pair(a:Array<Dynamic>):Array<Float>
		return [a.length > 0 ? num(a[0]) : 0, a.length > 1 ? num(a[1]) : 0];

	// Pick the value for a column from a per-lane field. Scalars apply to every lane; an object is
	// resolved column-index -> square/center (center lane) -> direction name -> arrow. Returns the
	// raw value or null. Shared by the scalar/bool/offset resolvers.
	static function rawForColumn(field:Dynamic, col:Int):Dynamic {
		if (field == null)
			return null;
		if (Std.isOfType(field, Bool) || Std.isOfType(field, Float) || Std.isOfType(field, Int) || Std.isOfType(field, String))
			return field; // scalar applies to all lanes
		if (Std.isOfType(field, Array))
			return field; // an array value is itself the per-lane payload (e.g. an [x,y] offset)
		var byIdx:Dynamic = Reflect.field(field, Std.string(col));
		if (byIdx != null)
			return byIdx;
		var dir:String = direction(col);
		if (dir == 'square') {
			var sq:Dynamic = Reflect.field(field, 'square');
			if (sq == null)
				sq = Reflect.field(field, 'center');
			if (sq != null)
				return sq;
		}
		var dname:Dynamic = Reflect.field(field, dir);
		if (dname != null)
			return dname;
		return Reflect.field(field, 'arrow');
	}

	public static function numForColumn(field:Dynamic, col:Int, fallback:Float):Float {
		var v:Dynamic = rawForColumn(field, col);
		return v == null ? fallback : num(v);
	}

	// Base note/strum/hold scale for a column. Uses `pixelScale` when the skin is rendering in pixel
	// mode and defines one (low-res pixel art usually needs a larger zoom than the HD art), otherwise
	// `scale` (default 0.7). The multikey size ratio is applied on top of this by the caller.
	public static function scaleForColumn(cfg:NoteSkinData, col:Int):Float {
		if (pixelMode && cfg.pixelScale != null)
			return numForColumn(cfg.pixelScale, col, numForColumn(cfg.scale, col, 0.7));
		return numForColumn(cfg.scale, col, 0.7);
	}

	public static function boolForColumn(field:Dynamic, col:Int, fallback:Bool):Bool {
		var v:Dynamic = rawForColumn(field, col);
		if (v == null)
			return fallback;
		return Std.isOfType(v, Bool) ? v : (Std.string(v) == 'true');
	}

	// Animation fps for a lane (`fps`, scalar or per-lane; defaults to 24).
	public static function fpsForColumn(cfg:NoteSkinData, col:Int):Int {
		return Std.int(numForColumn(cfg.fps, col, 24));
	}

	public static function colorableFor(cfg:NoteSkinData, element:String):Bool {
		var c:Dynamic = cfg.colorable;
		if (c == null)
			return false;
		if (Std.isOfType(c, Bool))
			return element == 'strums' ? false : (c == true);
		var v:Dynamic = Reflect.field(c, element);
		if (v == null)
			return element != 'strums';
		return v == true;
	}

	/**
		Whether `element` should be tinted with the note's colour in gameplay: the skin must support
		colouring it (`colorableFor`) AND the player's matching "Link ... to note colour" option is on.
		`notes` (and anything not user-linkable) follows `colorableFor` directly.
		@param element one of `splash` / `holds` / `ends` / `pressed` / `confirm` / `strums` / `notes`
	**/
	public static function linkedColorable(cfg:NoteSkinData, element:String):Bool {
		if (!colorableFor(cfg, element))
			return false;
		return switch (element) {
			case 'splash': ClientPrefs.data.linkSplashColor;
			case 'holds' | 'ends': ClientPrefs.data.linkSustainColor;
			case 'pressed': ClientPrefs.data.linkPressedColor;
			case 'confirm': ClientPrefs.data.linkConfirmColor;
			case 'strums': ClientPrefs.data.linkStrumColor;
			default: true;
		}
	}

	public static function animatedFor(cfg:NoteSkinData, element:String):Bool {
		var a:Dynamic = cfg.animated;
		if (a == null)
			return true;
		if (Std.isOfType(a, Bool))
			return a == true;
		var v:Dynamic = Reflect.field(a, element);
		return v == null ? true : (v == true);
	}

	public static function staticFrame(keys:Array<String>, animated:Bool):Array<String> {
		if (animated || keys == null || keys.length <= 1)
			return keys;
		return [keys[0]];
	}

	public static function direction(col:Int):String {
		var table:Array<String> = Mania.noteAnimations[Mania.clamp(Mania.current) - 1];
		if (table != null && col >= 0 && col < table.length)
			return table[col];
		return ['left', 'down', 'up', 'right'][col % 4];
	}

	static function angleForDir(cfg:NoteSkinData, dir:String):Float {
		var a:Array<Float> = cfg.directionAngles == null ? [-90, 180, 0, 90] : cfg.directionAngles;
		return switch (dir) {
			case 'left': a[0];
			case 'down': a[1];
			case 'up': a[2];
			case 'right': a[3];
			default: 0;
		}
	}

	// Rotation for a column: a per-column `columnAngles` entry wins (lets two same-named
	// directions, e.g. the two "left" lanes in 6K, rotate differently); else fall back to
	// the cardinal `directionAngles` lookup by direction name.
	static function angleForColumn(cfg:NoteSkinData, col:Int, dir:String):Float {
		var ca:Dynamic = cfg.columnAngles;
		if (ca != null && Std.isOfType(ca, Array)) {
			var a:Array<Dynamic> = ca;
			if (col >= 0 && col < a.length && a[col] != null)
				return num(a[col]);
		}
		return angleForDir(cfg, dir);
	}

	static function allCardinalsSame(field:Dynamic):Bool {
		var l:Dynamic = Reflect.field(field, 'left');
		if (l == null)
			return false;
		var first:String = Std.string(l);
		for (d in ['down', 'up', 'right']) {
			var v:Dynamic = Reflect.field(field, d);
			if (v == null || Std.string(v) != first)
				return false;
		}
		return true;
	}

	public static function resolveColumn(cfg:NoteSkinData, field:Dynamic, col:Int):Null<{key:String, angle:Float}> {
		if (field == null)
			return null;
		var dir:String = direction(col);
		var rotateOn:Bool = cfg.rotate != false;

		if (Std.isOfType(field, String)) {
			if (dir == 'square')
				return null;
			return {key: field, angle: rotateOn ? angleForColumn(cfg, col, dir) : 0};
		}
		if (Std.isOfType(field, Array)) {
			var arr:Array<Dynamic> = field;
			if (col < 0 || col >= arr.length || arr[col] == null)
				return null;
			// Per-column array images are assumed pre-oriented (angle 0), unless an explicit
			// columnAngles is provided -- then honor it so array skins can rotate per lane too.
			var ang:Float = (rotateOn && dir != 'square' && cfg.columnAngles != null) ? angleForColumn(cfg, col, dir) : 0;
			return {key: Std.string(arr[col]), angle: ang};
		}

		// Column-index keys win (e.g. { "0": "...", "1": "..." }) -- this disambiguates lanes that
		// share a direction name in multikey. Direction-name keys (below) are the fallback.
		var byIdx:Dynamic = Reflect.field(field, Std.string(col));
		if (byIdx != null)
			return {key: Std.string(byIdx), angle: (rotateOn && dir != 'square') ? angleForColumn(cfg, col, dir) : 0};

		var direct:Dynamic = Reflect.field(field, dir);
		if (direct != null) {
			var ang:Float = (rotateOn && dir != 'square' && allCardinalsSame(field)) ? angleForColumn(cfg, col, dir) : 0;
			return {key: Std.string(direct), angle: ang};
		}
		if (dir == 'square') {
			var sq:Dynamic = Reflect.field(field, 'square');
			if (sq == null)
				sq = Reflect.field(field, 'center');
			return sq == null ? null : {key: Std.string(sq), angle: 0};
		}
		var arrow:Dynamic = Reflect.field(field, 'arrow');
		return arrow == null ? null : {key: Std.string(arrow), angle: rotateOn ? angleForColumn(cfg, col, dir) : 0};
	}

	public static function columnKey(field:Dynamic, col:Int):String {
		if (field == null)
			return null;
		if (Std.isOfType(field, String))
			return field;
		if (Std.isOfType(field, Array)) {
			var arr:Array<Dynamic> = field;
			return (col >= 0 && col < arr.length && arr[col] != null) ? Std.string(arr[col]) : null;
		}
		// Column-index key first, direction-name fallback.
		var byIdx:Dynamic = Reflect.field(field, Std.string(col));
		if (byIdx != null)
			return Std.string(byIdx);
		var dir:String = direction(col);
		var d:Dynamic = Reflect.field(field, dir);
		if (d != null)
			return Std.string(d);
		var key:String = dir == 'square' ? 'square' : 'arrow';
		var v:Dynamic = Reflect.field(field, key);
		return v == null ? null : Std.string(v);
	}

	public static function resolveImage(key:String, allowGPU:Bool = true):SkinImage {
		if (Paths.fileExists('images/$key@2x.png', IMAGE)) {
			var g:FlxGraphic = Paths.image('$key@2x', null, allowGPU);
			if (g != null)
				return {graphic: g, factor: 0.5};
		}
		var g:FlxGraphic = Paths.image(key, null, allowGPU);
		return g == null ? null : {graphic: g, factor: 1.0};
	}

	static function frameExists(key:String):Bool {
		if (frameExistsCache.exists(key))
			return frameExistsCache.get(key);
		var exists:Bool = Paths.fileExists('images/$key.png', IMAGE) || Paths.fileExists('images/$key@2x.png', IMAGE);
		frameExistsCache.set(key, exists);
		return exists;
	}

	// Frame list for a key: a single image, or a numbered sequence (any of `0001`/`001`/`1`, with no
	// separator or a `-`/`_`). `suffix`, when given, is appended AFTER the frame number -- this is how
	// the `-pixel` per-frame naming (`confirmArrow1-pixel`) resolves.
	public static function frameKeys(key:String, ?suffix:String = ''):Array<String> {
		if (key == null || key.length < 1)
			return null;
		if (suffix == null)
			suffix = '';
		var cacheKey:String = (suffix.length == 0) ? key : '$key|$suffix';
		if (frameKeysCache.exists(cacheKey))
			return frameKeysCache.get(cacheKey);

		var result:Array<String> = resolveFrameKeys(key, suffix);
		frameKeysCache.set(cacheKey, result);
		return result;
	}

	// Pixel-variant-aware frame list for `key`: in pixel mode prefers a pixel variant, else the base
	// art. The single resolver the skin builders use so every element finds its pixel art the same way.
	public static function resolveFrames(key:String):Array<String> {
		if (pixelMode) {
			var p:Array<String> = pixelFrameKeys(key);
			if (p != null)
				return p;
		}
		return frameKeys(key);
	}

	// Tries the pixel variants of `key`, or null when none exist. Covers every common layout: a
	// `pixel/` subfolder (bare `pixel/x` or per-frame `pixel/x<N>-pixel`) and a `-pixel` suffix on the
	// key itself (`x-pixel` single, or `x<N>-pixel` sequence). Falls through to null so `resolveFrames`
	// can use the base art when a skin genuinely ships no pixel variant for this element.
	static function pixelFrameKeys(key:String):Array<String> {
		var slash:Int = key.lastIndexOf('/');
		if (slash >= 0) {
			var sub:String = key.substr(0, slash) + '/pixel' + key.substr(slash);
			var r:Array<String> = frameKeys(sub);
			if (r != null)
				return r;
			r = frameKeys(sub, '-pixel');
			if (r != null)
				return r;
		}
		return frameKeys(key, '-pixel');
	}

	static function resolveFrameKeys(key:String, suffix:String):Array<String> {
		if (frameExists(key + suffix))
			return [key + suffix];

		for (sep in ['', '-', '_']) {
			for (pad in [4, 3, 2, 1]) {
				for (start in [0, 1]) {
					if (frameExists(key + sep + zeroPad(start, pad) + suffix)) {
						var list:Array<String> = [];
						var i:Int = start;
						while (frameExists(key + sep + zeroPad(i, pad) + suffix)) {
							list.push(key + sep + zeroPad(i, pad) + suffix);
							i++;
						}
						return list;
					}
				}
			}
		}
		return null;
	}

	static function zeroPad(n:Int, width:Int):String {
		var s:String = Std.string(n);
		while (s.length < width)
			s = '0' + s;
		return s;
	}

	public static function applyAnims(sprite:flixel.FlxSprite, anims:Array<SkinAnim>):Float {
		var cacheKey:String = [
			for (a in anims)
				a.name + '@' + (a.angle == null ? 0 : a.angle) + (a.square == true ? 'sq' : '') + 'f' + (a.fps == null ? 24 : a.fps) + '='
				+ a.keys.join(',')
		].join('|');
		var built:BuiltAnims = animCache.get(cacheKey);

		if (built == null) {
			built = build(anims, cacheKey);
			if (built == null)
				return 1.0;
			animCache.set(cacheKey, built);
		}

		sprite.frames = built.frames;
		for (a in built.anims)
			sprite.animation.add(a.name, a.indices, a.fps, a.loop);
		return built.factor;
	}

	static function build(anims:Array<SkinAnim>, cacheKey:String):BuiltAnims {
		var bitmaps:Array<BitmapData> = [];
		var ranges:Array<{name:String, indices:Array<Int>, fps:Int, loop:Bool}> = [];
		var factor:Float = 1.0;

		for (a in anims) {
			var indices:Array<Int> = [];
			var angle:Float = a.angle == null ? 0 : a.angle;
			var square:Bool = a.square == true;
			for (k in a.keys) {
				var img:SkinImage = resolveImage(k, false);
				if (img == null || img.graphic.bitmap == null)
					continue;
				factor = img.factor;
				indices.push(bitmaps.length);
				bitmaps.push((angle != 0 || square) ? rotateBitmap(img.graphic.bitmap, angle, square) : img.graphic.bitmap);
			}
			if (indices.length > 0)
				ranges.push({name: a.name, indices: indices, fps: a.fps == null ? 24 : a.fps, loop: a.loop == true});
		}

		if (bitmaps.length < 1)
			return null;

		var totalW:Int = 0;
		var maxH:Int = 0;
		for (b in bitmaps) {
			totalW += b.width;
			if (b.height > maxH)
				maxH = b.height;
		}

		var sheet:BitmapData = new BitmapData(totalW, maxH, true, 0x00000000);
		var x:Int = 0;
		var rects:Array<FlxRect> = [];
		for (b in bitmaps) {
			sheet.copyPixels(b, new Rectangle(0, 0, b.width, b.height), new Point(x, 0));
			rects.push(FlxRect.get(x, 0, b.width, b.height));
			x += b.width;
		}

		var graphic:FlxGraphic = FlxGraphic.fromBitmapData(sheet, false, cacheKey);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;

		var atlas:FlxAtlasFrames = new FlxAtlasFrames(graphic);
		for (i in 0...rects.length) {
			var r:FlxRect = rects[i];
			atlas.addAtlasFrame(r, FlxPoint.get(r.width, r.height), FlxPoint.get(0, 0), 'f$i');
		}

		return {frames: atlas, factor: factor, anims: ranges};
	}

	static function rotateBitmap(src:BitmapData, deg:Float, square:Bool = false):BitmapData {
		var rad:Float = deg * Math.PI / 180;
		var cos:Float = Math.abs(Math.cos(rad));
		var sin:Float = Math.abs(Math.sin(rad));

		// Snap near-zero/near-one cos/sin so cardinal rotations (90/180/270) 
		// keep exact integer dimensions so no 1px growth, no half-pixel offset.
		if (cos < 1e-9)
			cos = 0;
		else if (cos > 1 - 1e-9)
			cos = 1;
		if (sin < 1e-9)
			sin = 0;
		else if (sin > 1 - 1e-9)
			sin = 1;

		var nw:Int = Math.ceil(src.width * cos + src.height * sin);
		var nh:Int = Math.ceil(src.width * sin + src.height * cos);
		if (square) {
			var side:Int = Std.int(Math.max(nw, nh));
			nw = side;
			nh = side;
		}

		var m:Matrix = new Matrix();
		m.translate(-src.width / 2, -src.height / 2);
		m.rotate(rad);
		m.translate(nw / 2, nh / 2);

		var out:BitmapData = new BitmapData(nw, nh, true, 0x00000000);
		out.draw(src, m, null, null, null, !pixelMode);
		return out;
	}
}
