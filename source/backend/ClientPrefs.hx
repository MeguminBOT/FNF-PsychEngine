package backend;

import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.input.gamepad.FlxGamepadInputID;
import states.TitleState;

// Add a variable here and it will get automatically saved
@:structInit class SaveVariables {
	public var downScroll:Bool = false;
	public var middleScroll:Bool = false;
	public var opponentStrums:Bool = true;
	// NOTE: the debug/performance counter settings (showFPS + fps*) live in
	// backend.DebugPrefs, in their own save file, so mod scripts can't tamper
	// with them via ClientPrefs.data. See DebugPrefs for the field list.
	public var flashing:Bool = true;
	public var autoPause:Bool = true;
	public var antialiasing:Bool = true;
	public var noteSkin:String = 'Default';
	// Locks the selected note skin: mods can't replace it via chart arrowSkin, per-note textures, or
	// their own same-named assets. Custom note TYPES still keep their own look.
	public var forceNoteSkin:Bool = false;
	public var uiSkin:String = 'Default';
	public var splashSkin:String = 'From Noteskin';
	public var splashAlpha:Float = 0.6;
	public var lowQuality:Bool = false;
	public var shaders:Bool = true;
	public var cacheOnGPU:Bool = #if !switch false #else true #end; // GPU Caching made by Raltyro
	public var framerate:Int = 60;
	public var uncapFramerate:Bool = false;
	public var camZooms:Bool = true;
	public var hideHud:Bool = false;
	public var noteOffset:Int = 0;
	public var arrowRGB:Array<Array<FlxColor>> = [
		[0xFFC24B99, 0xFFFFFFFF, 0xFF3C1F56],
		[0xFF00FFFF, 0xFFFFFFFF, 0xFF1542B7],
		[0xFF12FA05, 0xFFFFFFFF, 0xFF0A4447],
		[0xFFF9393F, 0xFFFFFFFF, 0xFF651038]
	];
	public var arrowRGBPixel:Array<Array<FlxColor>> = [
		[0xFFE276FF, 0xFFFFF9FF, 0xFF60008D],
		[0xFF3DCAFF, 0xFFF4FFFF, 0xFF003060],
		[0xFF71E300, 0xFFF6FFE6, 0xFF003100],
		[0xFFFF884E, 0xFFFFFAF5, 0xFF6C0000]
	];

	public var arrowRGBExtra:Array<Array<FlxColor>> = [
		[0xFFCCCCCC, 0xFFFFFFFF, 0xFF3E3E3E],
		[0xFFFFFF00, 0xFFFFFFFF, 0xFF993300],
		[0xFF8B4AFF, 0xFFFFFFFF, 0xFF3B177D],
		[0xFFFF0000, 0xFFFFFFFF, 0xFF660000],
		[0xFF0033FF, 0xFFFFFFFF, 0xFF000066]
	];
	public var arrowRGBExtraPixel:Array<Array<FlxColor>> = [
		[0xFFCCCCCC, 0xFFFFFFFF, 0xFF3E3E3E],
		[0xFFFFFF00, 0xFFFFFFFF, 0xFF993300],
		[0xFF8B4AFF, 0xFFFFFFFF, 0xFF3B177D],
		[0xFFFF0000, 0xFFFFFFFF, 0xFF660000],
		[0xFF0033FF, 0xFFFFFFFF, 0xFF000066]
	];
	public var arrowRGBByKey:Array<Array<Array<FlxColor>>> = [[], [], [], [], [], [], [], [], []];
	public var arrowRGBByKeyPixel:Array<Array<Array<FlxColor>>> = [[], [], [], [], [], [], [], [], []];
	public var noteColorPerKeycount:Bool = true;
	public var noteColorOneColor:Bool = false;
	public var noteColorOneValue:Array<FlxColor> = [0xFFFFFFFF, 0xFFFFFFFF, 0xFF555555];
	public var linkSplashColor:Bool = true;
	public var linkSustainColor:Bool = true;
	public var linkPressedColor:Bool = true;
	public var linkConfirmColor:Bool = true;
	public var linkStrumColor:Bool = false;

	// Independent per-asset colours, used when that asset's link is OFF. Keyed by element name
	// ('holds'/'splash'/'pressed'/'confirm'/'strums'); each entry mirrors the note colour shape
	// (shared per-lane triples, plus per-keycount overrides). Empty/missing entries fall back to notes.
	public var assetRGB:Map<String, Array<Array<FlxColor>>> = new Map();
	public var assetRGBByKey:Map<String, Array<Array<Array<FlxColor>>>> = new Map();
	public var assetRGBPixel:Map<String, Array<Array<FlxColor>>> = new Map();
	public var assetRGBByKeyPixel:Map<String, Array<Array<Array<FlxColor>>>> = new Map();

	public var ghostTapping:Bool = true;
	public var sustainsOverNotes:Bool = false;
	public var timeBarType:String = 'Time Left';
	public var scoreZoom:Bool = true;
	public var noReset:Bool = false;
	public var healthBarAlpha:Float = 1;
	public var hitsoundVolume:Float = 0;
	public var pauseMusic:String = 'Tea Time';
	public var checkForUpdates:Bool = true;
	public var updateChannel:String = 'stable'; // 'stable' | 'bleeding' (in-engine self-updater)
	public var comboStacking:Bool = true;
	// Freeplay difficulty-rating flyout (objects.../states.freeplay.FreeplayInfoFlyout)
	public var difficultyFlyout:Bool = true; // master toggle for the Freeplay info flyout
	public var showOsuRating:Bool = true; // show the osu!mania star rating block
	public var showMsdRating:Bool = true; // show the Etterna MSD rating block
	// Mobile on-screen controls
	public var controlsAlpha:Float = 0.6;
	public var vibration:Bool = true;
	public var gameplaySettings:Map<String, Dynamic> = [
		'scrollspeed' => 1.0,
		'scrolltype' => 'multiplicative',
		// anyone reading this, amod is multiplicative speed mod, cmod is constant speed mod, and xmod is bpm based speed mod.
		// an amod example would be chartSpeed * multiplier
		// cmod would just be constantSpeed = chartSpeed
		// and xmod basically works by basing the speed on the bpm.
		// iirc (beatsPerSecond * (conductorToNoteDifference / 1000)) * noteSize (110 or something like that depending on it, prolly just use note.height)
		// bps is calculated by bpm / 60
		// oh yeah and you'd have to actually convert the difference to seconds which I already do, because this is based on beats and stuff. but it should work
		// just fine. but I wont implement it because I don't know how you handle sustains and other stuff like that.
		// oh yeah when you calculate the bps divide it by the songSpeed or rate because it wont scroll correctly when speeds exist.
		// -kade
		'songspeed' => 1.0,
		'healthgain' => 1.0,
		'healthloss' => 1.0,
		'instakill' => false,
		'practice' => false,
		'botplay' => false,
		'opponentplay' => false
	];

	public var comboOffset:Array<Int> = [0, 0, 0, 0];
	public var ratingOffset:Int = 0;
	public var sickWindow:Float = 45.0;
	public var goodWindow:Float = 90.0;
	public var badWindow:Float = 135.0;
	public var safeFrames:Float = 10.0;
	public var guitarHeroSustains:Bool = true;
	public var discordRPC:Bool = true;
	public var loadingScreen:Bool = true;
	public var language:String = 'en-US';
	// Where the engine sources its core menu states from:
	//   'Psych (Default)' - built-in states only; mods never auto-override menus.
	//   'From Mod'        - the launched/top mod's scripted states override menus.
	//   'Global Script'   - scriptpack/global mods + shared scripted states override menus.
	public var stateSource:String = 'Psych (Default)';
	// Default Lua script mode:
	//   'compat' - legacy PsychLua callback API + the real-Lua object proxies.
	//   'raw'    - real Lua only (direct object access via game.*, import('...'));
	//              the legacy callback API is not registered.
	// Overridable per-mod (pack.json "luaMode") and per-script (-- @luamode ...).
	public var luaMode:String = 'compat';
	public var modSecurityEnabled:Bool = true;
	// Per-pattern toggles for mod-security scanning. Key = ModSecurity pattern
	// name (e.g. "saveFile", "Sys.command"). Missing entries default to enabled
	// so newly-added checks are on by default without needing a migration.
	// Edited via options.ModSecurityChecksSubState.
	public var modSecurityChecks:Map<String, Bool> = new Map();
	public var scriptDeprecationWarnings:Bool = true;
}

class ClientPrefs {
	public static var data:SaveVariables = {};
	public static var defaultData:SaveVariables = {};

	/** Upper bound of the capped framerate slider; also the pinned update/logic rate while FPS is uncapped. **/
	public static inline var FRAMERATE_MAX:Int = 240;

	/** Draw framerate target used when `uncapFramerate` is on -- high enough to be hardware-limited in practice. **/
	public static inline var FRAMERATE_UNCAPPED:Int = 1000;

	/**
		Pushes `framerate`/`uncapFramerate` onto flixel. When uncapped, the draw rate is raised to
		`FRAMERATE_UNCAPPED` while the update/logic rate stays pinned at `FRAMERATE_MAX`; otherwise both
		track `data.framerate`. Call after changing either pref (boot + options).
	**/
	public static function applyFramerate():Void {
		if (data.uncapFramerate) {
			FlxG.updateFramerate = FRAMERATE_MAX;
			FlxG.drawFramerate = FRAMERATE_UNCAPPED;
			return;
		}

		final fps:Int = data.framerate;
		if (fps > FlxG.drawFramerate) {
			FlxG.updateFramerate = fps;
			FlxG.drawFramerate = fps;
		} else {
			FlxG.drawFramerate = fps;
			FlxG.updateFramerate = fps;
		}
	}

	// Every key has two binds, add your key bind down here and then add your control on options/ControlsSubState.hx and Controls.hx
	public static var keyBinds:Map<String, Array<FlxKey>> = [
		// Key Bind, Name for ControlsSubState
		'note_up' => [W, UP],
		'note_left' => [A, LEFT],
		'note_down' => [S, DOWN],
		'note_right' => [D, RIGHT],
		'ui_up' => [W, UP],
		'ui_left' => [A, LEFT],
		'ui_down' => [S, DOWN],
		'ui_right' => [D, RIGHT],
		'accept' => [SPACE, ENTER],
		'back' => [BACKSPACE, ESCAPE],
		'pause' => [ENTER, ESCAPE],
		'reset' => [R],
		'volume_mute' => [ZERO],
		'volume_up' => [NUMPADPLUS, PLUS],
		'volume_down' => [NUMPADMINUS, MINUS],
		'debug_1' => [SEVEN],
		'debug_2' => [EIGHT]
	];
	public static var gamepadBinds:Map<String, Array<FlxGamepadInputID>> = [
		'note_up' => [DPAD_UP, Y],
		'note_left' => [DPAD_LEFT, X],
		'note_down' => [DPAD_DOWN, A],
		'note_right' => [DPAD_RIGHT, B],
		'ui_up' => [DPAD_UP, LEFT_STICK_DIGITAL_UP],
		'ui_left' => [DPAD_LEFT, LEFT_STICK_DIGITAL_LEFT],
		'ui_down' => [DPAD_DOWN, LEFT_STICK_DIGITAL_DOWN],
		'ui_right' => [DPAD_RIGHT, LEFT_STICK_DIGITAL_RIGHT],
		'accept' => [A, START],
		'back' => [B],
		'pause' => [START],
		'reset' => [BACK]
	];
	public static var defaultKeys:Map<String, Array<FlxKey>> = null;
	public static var defaultButtons:Map<String, Array<FlxGamepadInputID>> = null;

	public static function resetKeys(controller:Null<Bool> = null) // Null = both, False = Keyboard, True = Controller
	{
		if (controller != true)
			for (key in keyBinds.keys())
				if (defaultKeys.exists(key))
					keyBinds.set(key, defaultKeys.get(key).copy());

		if (controller != false)
			for (button in gamepadBinds.keys())
				if (defaultButtons.exists(button))
					gamepadBinds.set(button, defaultButtons.get(button).copy());
	}

	public static function clearInvalidKeys(key:String) {
		var keyBind:Array<FlxKey> = keyBinds.get(key);
		var gamepadBind:Array<FlxGamepadInputID> = gamepadBinds.get(key);
		while (keyBind != null && keyBind.contains(NONE))
			keyBind.remove(NONE);
		while (gamepadBind != null && gamepadBind.contains(NONE))
			gamepadBind.remove(NONE);
	}

	// Seed default note binds for every non-4K keycount (multikey support). 4K
	// reuses the classic note_left/down/up/right binds, so it's skipped. Only
	// fills in binds that don't already exist so saved overrides aren't clobbered.
	public static function generateManiaBinds() {
		for (count in Mania.MIN...Mania.MAX + 1) {
			if (count == Mania.DEFAULT)
				continue;
			var binds:Array<FlxKey> = Mania.defaultBinds[count - 1];
			for (col in 0...count) {
				var name:String = Mania.bindName(count, col);
				if (!keyBinds.exists(name))
					keyBinds.set(name, [binds[col]]);
			}
		}
	}

	public static function loadDefaultKeys() {
		generateManiaBinds();
		defaultKeys = keyBinds.copy();
		defaultButtons = gamepadBinds.copy();
	}

	public static function saveSettings() {
		for (key in Reflect.fields(data))
			Reflect.setField(FlxG.save.data, key, Reflect.field(data, key));

		#if ACHIEVEMENTS_ALLOWED Achievements.save(); #end
		FlxG.save.flush();

		// Debug-counter settings live in their own (script-inaccessible) save.
		DebugPrefs.save();

		// Placing this in a separate save so that it can be manually deleted without removing your Score and stuff
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		save.data.keyboard = keyBinds;
		save.data.gamepad = gamepadBinds;
		save.flush();
		FlxG.log.add("Settings saved!");
	}

	public static function loadPrefs() {
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end

		for (key in Reflect.fields(data))
			if (key != 'gameplaySettings' && Reflect.hasField(FlxG.save.data, key))
				Reflect.setField(data, key, Reflect.field(FlxG.save.data, key));

		// Load the separate debug-counter save (migrates any legacy values out of
		// the main save on first run).
		DebugPrefs.load();

		if (Main.fpsVar != null) {
			Main.fpsVar.visible = DebugPrefs.data.showFPS;
			Main.fpsVar.updateConfiguration();
		}

		#if (!html5 && !switch)
		FlxG.autoPause = ClientPrefs.data.autoPause;

		if (FlxG.save.data.framerate == null) {
			final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
			data.framerate = Std.int(FlxMath.bound(refreshRate, 60, 240));
		}
		#end

		applyFramerate();

		if (FlxG.save.data.gameplaySettings != null) {
			var savedMap:Map<String, Dynamic> = FlxG.save.data.gameplaySettings;
			for (name => value in savedMap)
				data.gameplaySettings.set(name, value);
		}

		// flixel automatically saves your volume!
		if (FlxG.save.data.volume != null)
			FlxG.sound.volume = FlxG.save.data.volume;
		if (FlxG.save.data.mute != null)
			FlxG.sound.muted = FlxG.save.data.mute;

		#if DISCORD_ALLOWED DiscordClient.check(); #end

		// controls on a separate save file
		var save:FlxSave = new FlxSave();
		save.bind('controls_v3', CoolUtil.getSavePath());
		if (save != null) {
			if (save.data.keyboard != null) {
				var loadedControls:Map<String, Array<FlxKey>> = save.data.keyboard;
				for (control => keys in loadedControls)
					if (keyBinds.exists(control))
						keyBinds.set(control, keys);
			}
			if (save.data.gamepad != null) {
				var loadedControls:Map<String, Array<FlxGamepadInputID>> = save.data.gamepad;
				for (control => keys in loadedControls)
					if (gamepadBinds.exists(control))
						gamepadBinds.set(control, keys);
			}
			reloadVolumeKeys();
		}
	}

	inline public static function getGameplaySetting(name:String, defaultValue:Dynamic = null, ?customDefaultValue:Bool = false):Dynamic {
		if (!customDefaultValue)
			defaultValue = defaultData.gameplaySettings.get(name);
		return /*PlayState.isStoryMode ? defaultValue : */ (data.gameplaySettings.exists(name) ? data.gameplaySettings.get(name) : defaultValue);
	}

	public static function reloadVolumeKeys() {
		final mute = keyBinds.get('volume_mute');
		final down = keyBinds.get('volume_down');
		final up = keyBinds.get('volume_up');
		TitleState.muteKeys = (mute != null) ? mute.copy() : [];
		TitleState.volumeDownKeys = (down != null) ? down.copy() : [];
		TitleState.volumeUpKeys = (up != null) ? up.copy() : [];
		toggleVolumeKeys(true);
	}

	public static function toggleVolumeKeys(?turnOn:Bool = true) {
		final emptyArray = [];
		FlxG.sound.muteKeys = turnOn ? TitleState.muteKeys : emptyArray;
		FlxG.sound.volumeDownKeys = turnOn ? TitleState.volumeDownKeys : emptyArray;
		FlxG.sound.volumeUpKeys = turnOn ? TitleState.volumeUpKeys : emptyArray;
	}
}
