package backend;

import openfl.utils.Assets;
import haxe.Json;

typedef ModsList = {
	enabled:Array<String>,
	disabled:Array<String>,
	all:Array<String>
};

class Mods {
	static public var currentModDirectory:String = '';

	// When false, asset resolution (Paths) ignores `currentModDirectory` so a
	// non-global mod can't override engine assets in core menus. Global mods are
	// unaffected. Reset to true on every state switch (MusicBeatState.switchState);
	// core-menu states set it false in create(). See plan: menu asset isolation.
	static public var allowCurrentModAssets:Bool = true;

	// ── Scripted state-source (session-only) ──────────────────────────────────
	// Controls whether/which scripted states may override the engine's core menus.
	// `Psych (Default)` => NONE (no overrides). A launched mod => MOD(launchedMod).
	// A scriptpack/global setup => GLOBAL. Reset every launch; never persisted.
	public static var launchedMod:String = null;
	public static var stateSourceMode:StateSourceMode = NONE;
	// Entry-state name used when a mod's pack.json omits "entryState".
	public static inline var DEFAULT_ENTRY_STATE:String = 'MainMenuState';
	public static final ignoreModFolders:Array<String> = [
		'characters',
		'custom_events',
		'custom_notetypes',
		'data',
		'songs',
		'music',
		'sounds',
		'shaders',
		'videos',
		'images',
		'stages',
		'weeks',
		'fonts',
		'scripts',
		'achievements'
	];

	private static var globalMods:Array<String> = [];

	inline public static function getGlobalMods()
		return globalMods;

	inline public static function pushGlobalMods() // prob a better way to do this but idc
	{
		globalMods = [];
		for (mod in parseList().enabled) {
			var pack:Dynamic = getPack(mod);
			if (pack == null) continue;
			// Script packs always run globally; other mods opt in via `runsGlobally`.
			var isScriptPackType:Bool = pack.type != null && Std.string(pack.type).toLowerCase() == 'scriptpack';
			if (isScriptPackType || pack.runsGlobally == true)
				globalMods.push(mod);
		}
		return globalMods;
	}

	/**
	 * Whether the given mod (or the current mod, if `folder` is null) is declared as a
	 * "script pack" via `pack.json`'s `"type": "scriptpack"` field. Script packs always
	 * run globally; other classifications (e.g. `"modpack"`) opt in via `runsGlobally`.
	 */
	public static function isScriptPack(?folder:String = null):Bool {
		var pack:Dynamic = getPack(folder);
		if (pack == null) return false;
		return pack.type != null && Std.string(pack.type).toLowerCase() == 'scriptpack';
	}

	inline public static function getModDirectories():Array<String> {
		var list:Array<String> = [];
		#if MODS_ALLOWED
		var modsFolder:String = Paths.mods();
		if (FileSystem.exists(modsFolder)) {
			for (folder in FileSystem.readDirectory(modsFolder)) {
				var path = haxe.io.Path.join([modsFolder, folder]);
				if (FileSystem.isDirectory(path) && !ignoreModFolders.contains(folder.toLowerCase()) && !list.contains(folder))
					list.push(folder);
			}
		}
		#end
		return list;
	}

	inline public static function mergeAllTextsNamed(path:String, ?defaultDirectory:String = null, allowDuplicates:Bool = false) {
		if (defaultDirectory == null)
			defaultDirectory = Paths.getSharedPath();
		defaultDirectory = defaultDirectory.trim();
		if (!defaultDirectory.endsWith('/'))
			defaultDirectory += '/';
		if (!defaultDirectory.startsWith('assets/'))
			defaultDirectory = 'assets/$defaultDirectory';

		var mergedList:Array<String> = [];
		var paths:Array<String> = directoriesWithFile(defaultDirectory, path);

		var defaultPath:String = defaultDirectory + path;
		if (paths.contains(defaultPath)) {
			paths.remove(defaultPath);
			paths.insert(0, defaultPath);
		}

		for (file in paths) {
			var list:Array<String> = CoolUtil.coolTextFile(file);
			for (value in list)
				if ((allowDuplicates || !mergedList.contains(value)) && value.length > 0)
					mergedList.push(value);
		}
		return mergedList;
	}

	inline public static function directoriesWithFile(path:String, fileToFind:String, mods:Bool = true) {
		var foldersToCheck:Array<String> = [];
		// Main folder
		if (FileSystem.exists(path + fileToFind))
			foldersToCheck.push(path + fileToFind);

		// Week folder
		if (Paths.currentLevel != null && Paths.currentLevel != path) {
			var pth:String = Paths.getFolderPath(fileToFind, Paths.currentLevel);
			if (!foldersToCheck.contains(pth) && FileSystem.exists(pth))
				foldersToCheck.push(pth);
		}

		#if MODS_ALLOWED
		if (mods) {
			// Global mods first
			for (mod in Mods.getGlobalMods()) {
				var folder:String = Paths.mods(mod + '/' + fileToFind);
				if (FileSystem.exists(folder) && !foldersToCheck.contains(folder))
					foldersToCheck.push(folder);
			}

			// Then "PsychEngine/mods/" main folder
			var folder:String = Paths.mods(fileToFind);
			if (FileSystem.exists(folder) && !foldersToCheck.contains(folder))
				foldersToCheck.push(folder);

			// And lastly, the loaded mod's folder
			if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0) {
				var folder:String = Paths.mods(Mods.currentModDirectory + '/' + fileToFind);
				if (FileSystem.exists(folder) && !foldersToCheck.contains(folder))
					foldersToCheck.push(folder);
			}
		}
		#end
		return foldersToCheck;
	}

	public static function getPack(?folder:String = null):Dynamic {
		#if MODS_ALLOWED
		if (folder == null)
			folder = Mods.currentModDirectory;

		var path = Paths.mods(folder + '/pack.json');
		if (FileSystem.exists(path)) {
			try {
				#if sys
				var rawJson:String = File.getContent(path);
				#else
				var rawJson:String = Assets.getText(path);
				#end
				if (rawJson != null && rawJson.length > 0)
					return tjson.TJSON.parse(rawJson);
			} catch (e:Dynamic) {
				trace(e);
			}
		}
		#end
		return null;
	}

	/** Writes a mod's pack.json to disk (pretty-printed). Returns false on failure. */
	public static function savePack(folder:String, data:Dynamic):Bool {
		#if MODS_ALLOWED
		if (folder == null || folder.length < 1 || data == null)
			return false;
		try {
			var path:String = Paths.mods(folder + '/pack.json');
			File.saveContent(path, Json.stringify(data, null, '\t'));
			return true;
		} catch (e:Dynamic) {
			trace('savePack failed for $folder: $e');
		}
		#end
		return false;
	}

	public static var updatedOnState(default, set):Bool = false;
	private static var cachedList:ModsList = null;

	private static function set_updatedOnState(value:Bool):Bool {
		if (!value) cachedList = null; // state-transition: drop the cache
		return updatedOnState = value;
	}

	public static function parseList():ModsList {
		if (!updatedOnState)
			updateModList();

		// updateModList sets updatedOnState=true (and clears the cache when
		// it rewrites the file) so anything beyond this point is safe to
		// hand back the cached parse.
		if (cachedList != null)
			return cachedList;

		var list:ModsList = {enabled: [], disabled: [], all: []};

		#if MODS_ALLOWED
		try {
			for (mod in CoolUtil.coolTextFile('modsList.txt')) {
				// trace('Mod: $mod');
				if (mod.trim().length < 1)
					continue;

				var dat = mod.split("|");
				list.all.push(dat[0]);
				if (dat[1] == "1")
					list.enabled.push(dat[0]);
				else
					list.disabled.push(dat[0]);
			}
		} catch (e) {
			trace(e);
		}
		#end
		cachedList = list;
		return list;
	}

	private static function updateModList() {
		#if MODS_ALLOWED
		// Find all that are already ordered
		var list:Array<Array<Dynamic>> = [];
		var added:Array<String> = [];
		try {
			for (mod in CoolUtil.coolTextFile('modsList.txt')) {
				var dat:Array<String> = mod.split("|");
				var folder:String = dat[0];
				if (folder.trim().length > 0
					&& FileSystem.exists(Paths.mods(folder))
					&& FileSystem.isDirectory(Paths.mods(folder))
					&& !added.contains(folder)) {
					added.push(folder);
					list.push([folder, (dat[1] == "1")]);
				}
			}
		} catch (e) {
			trace(e);
		}

		// Scan for folders that aren't on modsList.txt yet
		for (folder in getModDirectories()) {
			if (folder.trim().length > 0
				&& FileSystem.exists(Paths.mods(folder))
				&& FileSystem.isDirectory(Paths.mods(folder))
				&& !ignoreModFolders.contains(folder.toLowerCase())
				&& !added.contains(folder)) {
				added.push(folder);
				list.push([folder, true]); // i like it false by default. -bb //Well, i like it True! -Shadow Mario (2022)
				// Shadow Mario (2023): What the fuck was bb thinking
			}
		}

		// Now save file
		var fileStr:String = '';
		for (values in list) {
			if (fileStr.length > 0)
				fileStr += '\n';
			fileStr += values[0] + '|' + (values[1] ? '1' : '0');
		}

		File.saveContent('modsList.txt', fileStr);
		cachedList = null; // file just changed -- force a reparse next call
		updatedOnState = true;
		// trace('Saved modsList.txt');
		#end
	}

	public static function loadTopMod() {
		Mods.currentModDirectory = '';

		#if MODS_ALLOWED
		var list:Array<String> = Mods.parseList().enabled;
		if (list != null && list[0] != null)
			Mods.currentModDirectory = list[0];
		#end
	}

	/** Entry-state name for a mod: pack.json "entryState", else DEFAULT_ENTRY_STATE. */
	public static function getEntryState(?folder:String = null):String {
		var pack:Dynamic = getPack(folder);
		if (pack != null && pack.entryState != null) {
			var s:String = Std.string(pack.entryState);
			if (s.length > 0)
				return s;
		}
		return DEFAULT_ENTRY_STATE;
	}

	/** Menu-music name for a mod: pack.json "menuMusic", else 'freakyMenu'. */
	public static function getMenuMusic(?folder:String = null):String {
		// In core menus a non-global current mod must not dictate the menu music.
		// When suppressed and no explicit folder was requested, fall back to the
		// stock track (global-mod assets still resolve via Paths normally).
		if (folder == null && !allowCurrentModAssets)
			return 'freakyMenu';

		var pack:Dynamic = getPack(folder);
		if (pack != null && pack.menuMusic != null) {
			var s:String = Std.string(pack.menuMusic);
			if (s.length > 0)
				return s;
		}
		return 'freakyMenu';
	}

	/** pack.json "nativeMobile": when true the mod handles its own mobile controls,
	 *  so the engine must NOT auto-add a default touch pad to its scripted states. */
	public static function isNativeMobile(?folder:String = null):Bool {
		var pack:Dynamic = getPack(folder);
		return pack != null && pack.nativeMobile == true;
	}

	/** A mod is launchable if it ships its entry state at states/<entry>.hx. */
	public static function isLaunchable(?folder:String = null):Bool {
		#if (MODS_ALLOWED && HSCRIPT_ALLOWED)
		if (folder == null)
			folder = currentModDirectory;
		if (folder == null || folder.length < 1)
			return false;
		return FileSystem.exists(Paths.mods(folder + '/states/' + getEntryState(folder) + '.hx'));
		#else
		return false;
		#end
	}

	/**
	 * Sets the session state-source mode from ClientPrefs.stateSource.
	 * Call once at boot (after loadTopMod) and whenever the pref changes.
	 */
	public static function applyStateSourcePref():Void {
		launchedMod = null;
		switch (Std.string(ClientPrefs.data.stateSource)) {
			case 'From Mod':
				#if (MODS_ALLOWED && HSCRIPT_ALLOWED)
				if (currentModDirectory != null && currentModDirectory.length > 0 && isLaunchable(currentModDirectory)) {
					launchedMod = currentModDirectory;
					stateSourceMode = MOD;
				} else
					stateSourceMode = NONE;
				#else
				stateSourceMode = NONE;
				#end
			case 'Global Script':
				stateSourceMode = GLOBAL;
			default: // 'Psych (Default)' / unknown -> built-in states only
				stateSourceMode = NONE;
		}
	}
}

enum StateSourceMode {
	NONE;
	MOD;
	GLOBAL;
}
