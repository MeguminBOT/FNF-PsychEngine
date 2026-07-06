package options;

import options.Option;
import options.Option.OptionType;

using StringTools;

/**
	A row inside a category: a configurable `Setting`, a `Section` sub-heading that groups the rows
	beneath it, or an `Action` that opens a dedicated editor (Controls, Note Colours, calibration...).
**/
enum OptionRow {
	Setting(o:Option);
	Section(title:String);
	Action(name:String, desc:String, which:String);
}

/** One rail entry: a titled category with an optional description and its rows. **/
typedef OptionCategory = {
	var name:String;
	var ?desc:String;
	var rows:Array<OptionRow>;
}

/**
	Builds the category model for the Options menu (`options.OptionsState`), which renders each
	category as a rail entry and each row as a `source/ui` widget. Data only - no UI side effects.

	The internal `ClientPrefs` field names and the `gameplaySettings` map keys are the source of
	truth and never change here; only labels, grouping and ordering are the catalog's concern.
**/
class OptionsCatalog {
	/**
		The full ordered list of categories shown in the rail.
		@return every category, in rail order, each already populated with its rows
	**/
	public static function build():Array<OptionCategory> {
		var list:Array<OptionCategory> = [
			{name: phrase('Gameplay'), desc: 'How notes behave and how tightly they are judged.', rows: gameplayRows()},
			{name: phrase('Modifiers'), desc: 'Per-session gameplay changers - reset when you close the game.', rows: modifierRows()},
			{name: phrase('Visuals'), desc: 'Skins, HUD and on-screen effects.', rows: visualsRows()},
			{name: phrase('Performance'), desc: 'Quality and framerate trade-offs.', rows: performanceRows()},
			{name: phrase('Audio'), desc: 'Volume, pause music and audio sync.', rows: audioRows()},
			{name: phrase('Freeplay'), desc: 'Freeplay menu extras.', rows: freeplayRows()},
			{name: phrase('Controls'), desc: 'Rebind keyboard / controller controls.', rows: [Action('Rebind...', 'Rebind keyboard / controller controls.', 'controls')]},
			{name: phrase('System'), desc: 'Engine, updates and mod behavior.', rows: systemRows()}
		];
		return list;
	}

	/** Note-behavior toggles, then a Timing section with the hit-window and offset steppers. **/
	static function gameplayRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];
		rows.push(Setting(new Option('Downscroll', 'If checked, notes go Down instead of Up, simple enough.', 'downScroll', BOOL)));
		rows.push(Setting(new Option('Middlescroll', 'If checked, your notes get centered.', 'middleScroll', BOOL)));
		rows.push(Setting(new Option('Opponent Notes', 'If unchecked, opponent notes get hidden.', 'opponentStrums', BOOL)));
		rows.push(Setting(new Option('Ghost Tapping', "If checked, you won't get misses from pressing keys\nwhile there are no notes able to be hit.", 'ghostTapping',
			BOOL)));
		rows.push(Setting(new Option('Sustains as One Note',
			"If checked, Hold Notes can't be pressed if you miss,\nand count as a single Hit/Miss.\nUncheck this if you prefer the old Input System.",
			'guitarHeroSustains', BOOL)));
		rows.push(Setting(new Option('Sustains Over Notes',
			"If checked, hold trails draw on top of the note heads instead of below them.\nA note skin can override this.", 'sustainsOverNotes', BOOL)));
		rows.push(Setting(new Option('Disable Reset Button', "If checked, pressing Reset won't do anything.", 'noReset', BOOL)));

		rows.push(Section(phrase('Timing')));

		var ratingOffset:Option = new Option('Rating Offset', 'Changes how late/early you have to hit for a "Sick!"\nHigher values mean you have to hit later.',
			'ratingOffset', INT);
		ratingOffset.displayFormat = '%vms';
		ratingOffset.scrollSpeed = 20;
		ratingOffset.minValue = -30;
		ratingOffset.maxValue = 30;
		rows.push(Setting(ratingOffset));

		rows.push(Setting(window('Sick! Hit Window', 'Changes the amount of time you have\nfor hitting a "Sick!" in milliseconds.', 'sickWindow', 15, 15.0, 45.0)));
		rows.push(Setting(window('Good Hit Window', 'Changes the amount of time you have\nfor hitting a "Good" in milliseconds.', 'goodWindow', 30, 15.0, 90.0)));
		rows.push(Setting(window('Bad Hit Window', 'Changes the amount of time you have\nfor hitting a "Bad" in milliseconds.', 'badWindow', 60, 15.0, 135.0)));

		var safeFrames:Option = new Option('Safe Frames', 'Changes how many frames you have for\nhitting a note earlier or late.', 'safeFrames', FLOAT);
		safeFrames.scrollSpeed = 5;
		safeFrames.minValue = 2;
		safeFrames.maxValue = 10;
		safeFrames.changeValue = 0.1;
		rows.push(Setting(safeFrames));
		return rows;
	}

	/** Session gameplay changers, stored in the `gameplaySettings` map rather than top-level fields (see `gsOption`). **/
	static function modifierRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var constant:Bool = ClientPrefs.data.gameplaySettings.get('scrolltype') == 'constant';

		var scrollType:Option = gsOption('Scroll Type', 'Multiplicative scales the chart speed; Constant sets a fixed speed.', 'scrolltype', STRING,
			'multiplicative', ['multiplicative', 'constant']);
		scrollType.rebuildOnChange = true;
		scrollType.onChange = function() {
			var s:Float = ClientPrefs.data.gameplaySettings.get('scrollspeed');
			if (ClientPrefs.data.gameplaySettings.get('scrolltype') != 'constant' && s > 3)
				ClientPrefs.data.gameplaySettings.set('scrollspeed', 3);
		};
		rows.push(Setting(scrollType));

		// Constant speed takes a wider raw value (shown plain); multiplicative caps at 3 and shows an X.
		var scrollSpeed:Option = gsOption('Scroll Speed', 'Note scroll speed multiplier.', 'scrollspeed', FLOAT, 1.0);
		scrollSpeed.scrollSpeed = 2.0;
		scrollSpeed.minValue = 0.35;
		scrollSpeed.maxValue = constant ? 6 : 3;
		scrollSpeed.changeValue = 0.05;
		scrollSpeed.decimals = 2;
		scrollSpeed.displayFormat = constant ? '%v' : '%vX';
		rows.push(Setting(scrollSpeed));

		#if FLX_PITCH
		var songSpeed:Option = gsOption('Playback Rate', 'Song + chart speed (pitch-shifted).', 'songspeed', FLOAT, 1.0);
		songSpeed.scrollSpeed = 1;
		songSpeed.minValue = 0.5;
		songSpeed.maxValue = 3.0;
		songSpeed.changeValue = 0.05;
		songSpeed.decimals = 2;
		songSpeed.displayFormat = '%vX';
		rows.push(Setting(songSpeed));
		#end

		var healthGain:Option = gsOption('Health Gain Multiplier', 'How much health hitting a note restores.', 'healthgain', FLOAT, 1.0);
		healthGain.scrollSpeed = 2.5;
		healthGain.minValue = 0;
		healthGain.maxValue = 5;
		healthGain.changeValue = 0.1;
		healthGain.displayFormat = '%vX';
		rows.push(Setting(healthGain));

		var healthLoss:Option = gsOption('Health Loss Multiplier', 'How much health missing a note drains.', 'healthloss', FLOAT, 1.0);
		healthLoss.scrollSpeed = 2.5;
		healthLoss.minValue = 0.5;
		healthLoss.maxValue = 5;
		healthLoss.changeValue = 0.1;
		healthLoss.displayFormat = '%vX';
		rows.push(Setting(healthLoss));

		rows.push(Setting(gsOption('Instakill on Miss', 'Any miss ends the song instantly.', 'instakill', BOOL, false)));
		rows.push(Setting(gsOption('Practice Mode', "Can't die; useful for learning a chart.", 'practice', BOOL, false)));
		rows.push(Setting(gsOption('Botplay', 'Auto-plays the song; no score is saved.', 'botplay', BOOL, false)));
		return rows;
	}

	/**
		Skins, HUD toggles, then a Note Colours section. The note-skin / UI-skin / splash dropdowns are
		populated from `list.txt` merges plus the folder-skin configs, and reset the pref to default when
		the saved value no longer exists. The colour-link toggles are added conditionally by `linkRow`.
	**/
	static function visualsRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var noteSkins:Array<String> = Mods.mergeAllTextsNamed('images/noteSkins/list.txt');
		for (folder in backend.NoteSkinConfig.list()) {
			var name:String = folder.substr(folder.lastIndexOf('/') + 1);
			if (!noteSkins.contains(name))
				noteSkins.push(name);
		}
		if (!noteSkins.contains(ClientPrefs.data.noteSkin))
			ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin;
		noteSkins.insert(0, ClientPrefs.defaultData.noteSkin);
		rows.push(Setting(new Option('Note Skins:', 'Select your prefered Note skin.', 'noteSkin', STRING, noteSkins)));
		rows.push(Setting(new Option('Force Selected Skin',
			"Locks your chosen note skin: mods can't replace it via chart arrowSkin, per-note textures, or their own same-named assets.\nCustom note types keep their own look.",
			'forceNoteSkin', BOOL)));

		var uiSkins:Array<String> = Mods.mergeAllTextsNamed('images/uiSkins/list.txt');
		for (folder in backend.UISkinConfig.list()) {
			var name:String = folder.substr(folder.lastIndexOf('/') + 1);
			if (!uiSkins.contains(name))
				uiSkins.push(name);
		}
		if (!uiSkins.contains(ClientPrefs.data.uiSkin))
			ClientPrefs.data.uiSkin = ClientPrefs.defaultData.uiSkin;
		uiSkins.remove(ClientPrefs.defaultData.uiSkin);
		uiSkins.insert(0, ClientPrefs.defaultData.uiSkin);
		rows.push(Setting(new Option('UI Skin:', 'Select your prefered judgement UI skin\n(rating popups, combo, countdown).', 'uiSkin', STRING, uiSkins)));

		// "From Noteskin" defers to the active note skin's own splash; "Psych" is the base atlas.
		var noteSplashes:Array<String> = Mods.mergeAllTextsNamed('images/noteSplashes/list.txt');
		if (!noteSplashes.contains(objects.NoteSplash.BASE_SKIN))
			noteSplashes.insert(0, objects.NoteSplash.BASE_SKIN);
		noteSplashes.insert(0, objects.NoteSplash.FROM_NOTESKIN);
		if (!noteSplashes.contains(ClientPrefs.data.splashSkin))
			ClientPrefs.data.splashSkin = ClientPrefs.defaultData.splashSkin;
		rows.push(Setting(new Option('Note Splashes:', 'Select your prefered Note Splash variation.', 'splashSkin', STRING, noteSplashes)));

		rows.push(Setting(percent('Note Splash Opacity', 'How much transparent should the Note Splashes be.', 'splashAlpha')));
		rows.push(Setting(new Option('Hide HUD', 'If checked, hides most HUD elements.', 'hideHud', BOOL)));
		rows.push(Setting(new Option('Time Bar:', 'What should the Time Bar display?', 'timeBarType', STRING,
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled'])));
		rows.push(Setting(new Option('Flashing Lights', "Uncheck this if you're sensitive to flashing lights!", 'flashing', BOOL)));
		rows.push(Setting(new Option('Camera Zooms', "If unchecked, the camera won't zoom in on a beat hit.", 'camZooms', BOOL)));
		rows.push(Setting(new Option('Score Text Grow on Hit', "If unchecked, disables the Score text growing\neverytime you hit a note.", 'scoreZoom', BOOL)));
		rows.push(Setting(percent('Health Bar Opacity', 'How much transparent should the health bar and icons be.', 'healthBarAlpha')));
		rows.push(Setting(new Option('Combo Stacking', "If unchecked, Ratings and Combo won't stack, saving on System Memory and making them easier to read",
			'comboStacking', BOOL)));

		rows.push(Section(phrase('Note Colours')));
		rows.push(Action('Edit Colors...', 'Open the colour picker to set per-lane note colours.', 'noteColors'));
		rows.push(Setting(new Option('Per-keycount Colours',
			"If checked, each keycount can have its own lane colours.\nIf unchecked, every keycount uses the shared base palette.", 'noteColorPerKeycount', BOOL)));
		rows.push(Setting(new Option('One Colour for All Notes', 'If checked, every note in every keycount uses a single colour.', 'noteColorOneColor', BOOL)));

		var cfg:backend.NoteSkinConfig.NoteSkinData = null;
		var skin:String = backend.NoteSkinConfig.activeSkin();
		if (skin != null)
			cfg = backend.NoteSkinConfig.forCurrentKeys(skin);

		linkRow(rows, cfg, 'splash', 'Link Splash Colour', "Note splashes take the note's colour\n(otherwise they keep the skin's own colour).", 'linkSplashColor');
		linkRow(rows, cfg, 'holds', 'Link Hold Colour', "Hold/sustain pieces take the note's colour.", 'linkSustainColor');
		linkRow(rows, cfg, 'pressed', 'Link Pressed Colour', "The pressed strum animation takes the note's colour.", 'linkPressedColor');
		linkRow(rows, cfg, 'confirm', 'Link Confirm Colour', "The confirm strum animation takes the note's colour.", 'linkConfirmColor');
		linkRow(rows, cfg, 'strums', 'Link Strum Colour', "The idle strum takes the note's colour.", 'linkStrumColor');
		return rows;
	}

	/**
		Appends a "link ... to note colour" toggle only when the active skin can colour that element.
		@param rows the row list to append to
		@param cfg the active skin config, or null for a classic (non-folder) skin
		@param element the colourable element key (`splash`/`holds`/`pressed`/`confirm`/`strums`)
		@param name the toggle label
		@param desc the toggle description
		@param variable the backing `ClientPrefs` field
	**/
	static function linkRow(rows:Array<OptionRow>, cfg:backend.NoteSkinConfig.NoteSkinData, element:String, name:String, desc:String, variable:String):Void {
		var supported:Bool = (cfg != null) ? backend.NoteSkinConfig.colorableFor(cfg, element) : (element == 'splash');
		if (supported)
			rows.push(Setting(new Option(name, desc, variable, BOOL)));
	}

	/** Quality toggles, framerate, and the FPS counter plus its settings editor. **/
	static function performanceRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];
		rows.push(Setting(new Option('Low Quality', 'If checked, disables some background details,\ndecreases loading times and improves performance.',
			'lowQuality', BOOL)));

		var aa:Option = new Option('Anti-Aliasing', 'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.',
			'antialiasing', BOOL);
		aa.onChange = function() flixel.FlxSprite.defaultAntialiasing = ClientPrefs.data.antialiasing;
		rows.push(Setting(aa));

		rows.push(Setting(new Option('Shaders', "If unchecked, disables shaders.\nIt's used for some visual effects, and also CPU intensive for weaker PCs.",
			'shaders', BOOL)));
		rows.push(Setting(new Option('GPU Caching',
			"If checked, allows the GPU to be used for caching textures, decreasing RAM usage.\nDon't turn this on if you have a shitty Graphics Card.",
			'cacheOnGPU', BOOL)));

		#if !html5
		var framerate:Option = new Option('Framerate', "Pretty self explanatory, isn't it?", 'framerate', INT);
		final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
		framerate.minValue = 60;
		framerate.maxValue = ClientPrefs.FRAMERATE_MAX;
		framerate.defaultValue = Std.int(FlxMath.bound(refreshRate, framerate.minValue, framerate.maxValue));
		framerate.displayFormat = '%v FPS';
		framerate.onChange = onChangeFramerate;
		rows.push(Setting(framerate));

		var uncapFramerate:Option = new Option('Uncap FPS',
			"Render as fast as your hardware allows. The Framerate cap above is ignored while this is on, but the game's logic still runs at "
			+ ClientPrefs.FRAMERATE_MAX + " updates/sec. May introduce weird behaviors.", 'uncapFramerate', BOOL);
		uncapFramerate.onChange = onChangeFramerate;
		rows.push(Setting(uncapFramerate));
		#end

		#if !mobile
		// showFPS lives in DebugPrefs (its own save file), not ClientPrefs.data - bindDebugOption reroutes get/set.
		var showFPS:Option = new Option('FPS Counter', 'If unchecked, hides FPS Counter.', 'showFPS', BOOL);
		FPSCounterSettingsSubState.bindDebugOption(showFPS);
		showFPS.onChange = function() if (Main.fpsVar != null)
			Main.fpsVar.visible = DebugPrefs.data.showFPS;
		rows.push(Setting(showFPS));

		rows.push(Action('FPS Counter Settings...', 'Customize the performance counter: position, font size, update rate and which metrics are shown.',
			'fpsSettings'));
		#end
		return rows;
	}

	/** Volumes, pause music, the audio-offset stepper and the calibration editor. **/
	static function audioRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var hitsound:Option = new Option('Hitsound Volume', 'Funny notes does "Tick!" when you hit them.', 'hitsoundVolume', PERCENT);
		hitsound.scrollSpeed = 1.6;
		hitsound.minValue = 0.0;
		hitsound.maxValue = 1;
		hitsound.changeValue = 0.1;
		hitsound.decimals = 1;
		hitsound.onChange = function() FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);
		rows.push(Setting(hitsound));

		rows.push(Setting(new Option('Pause Music:', 'What song do you prefer for the Pause Screen?', 'pauseMusic', STRING,
			['None', 'Tea Time', 'Breakfast', 'Breakfast (Pico)'])));

		var offset:Option = new Option('Audio Offset', 'Delay to line the song up with what you see + hear.', 'noteOffset', INT);
		offset.displayFormat = '%vms';
		offset.scrollSpeed = 200;
		offset.minValue = -500;
		offset.maxValue = 500;
		rows.push(Setting(offset));

		rows.push(Action('Calibrate...', 'Calibrate the audio offset by feel with a beat test.', 'noteOffset'));
		return rows;
	}

	/** The Freeplay info-flyout toggle and its rating toggles. **/
	static function freeplayRows():Array<OptionRow> {
		return [
			Setting(new Option('Freeplay Info Flyout', "If checked, lets you press I in Freeplay to open the song info / difficulty-rating panel.",
				'difficultyFlyout', BOOL)),
			Setting(new Option('Show osu! Star Rating', "Show the osu!mania star rating in the Freeplay info flyout.", 'showOsuRating', BOOL)),
			Setting(new Option('Show Etterna MSD', "Show the Etterna MSD rating in the Freeplay info flyout.", 'showMsdRating', BOOL))
		];
	}

	/** Engine / update / mod-behavior settings, plus the Mod Security, Language and Mobile editors. **/
	static function systemRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var autoPause:Option = new Option('Auto Pause', "If checked, the game automatically pauses if the screen isn't on focus.", 'autoPause', BOOL);
		autoPause.onChange = function() FlxG.autoPause = ClientPrefs.data.autoPause;
		rows.push(Setting(autoPause));

		#if DISCORD_ALLOWED
		rows.push(Setting(new Option('Discord Rich Presence',
			"Uncheck this to prevent accidental leaks, it will hide the Application from your \"Playing\" box on Discord", 'discordRPC', BOOL)));
		#end

		#if CHECK_FOR_UPDATES
		rows.push(Setting(new Option('Check for Updates', 'On Release builds, turn this on to check for updates when you start the game.', 'checkForUpdates',
			BOOL)));

		// The pref stores 'stable'/'bleeding'; the dropdown shows friendly labels, so get/set translate.
		var channel:Option = new Option('Update Channel', 'Stable: official release builds.\nBleeding Edge: latest dev prereleases (may be unstable).',
			'updateChannel', STRING, ['Stable', 'Bleeding Edge']);
		channel.getValue = function():Dynamic return (ClientPrefs.data.updateChannel == 'bleeding') ? 'Bleeding Edge' : 'Stable';
		channel.setValue = function(value:Dynamic):Dynamic {
			ClientPrefs.data.updateChannel = (value == 'Bleeding Edge') ? 'bleeding' : 'stable';
			return value;
		};
		rows.push(Setting(channel));
		#end

		rows.push(Setting(new Option('Script Deprecation Warnings',
			"If checked, scripts that use deprecated functions will print a warning to the debug console.\nDisable to silence noisy mods.",
			'scriptDeprecationWarnings', BOOL)));

		#if (MODS_ALLOWED && HSCRIPT_ALLOWED)
		var stateSource:Option = new Option('State Source',
			"Where the engine loads its core menu states from.\n'Psych (Default)': built-in menus only.\n'From Mod': the top mod's scripted states override menus.\n'Global Script': scriptpack/global mods override menus.",
			'stateSource', STRING, ['Psych (Default)', 'From Mod', 'Global Script']);
		stateSource.onChange = function() Mods.applyStateSourcePref();
		rows.push(Setting(stateSource));
		#end

		#if LUA_ALLOWED
		rows.push(Setting(new Option('Lua Mode',
			"Default mode for Lua scripts.\n'compat': legacy PsychLua callbacks + direct object access.\n'raw': real Lua only.\nMods can override via pack.json \"luaMode\".",
			'luaMode', STRING, ['compat', 'raw'])));
		#end

		#if MODS_ALLOWED
		rows.push(Action('Mod Security Checks...',
			'Configure which suspicious script calls (saveFile, Sys.command, etc.) the Mod Security scanner looks for.', 'modSecurity'));
		#end

		#if TRANSLATIONS_ALLOWED
		rows.push(Action('Language...', 'Change the game language.', 'language'));
		#end

		#if mobile
		rows.push(Action('Mobile...', 'Mobile-specific controls and options.', 'mobile'));
		#end
		return rows;
	}

	/**
		Builds an Option backed by the `ClientPrefs.data.gameplaySettings` map (session modifiers)
		instead of a top-level field, seeding the map default and rerouting get/set to it.
		@param name the row label
		@param desc the row description
		@param key the `gameplaySettings` map key (the internal modifier name)
		@param type the option type
		@param def the default value, also seeded into the map when missing
		@param options the choice list for STRING options
		@return the map-backed option
	**/
	static function gsOption(name:String, desc:String, key:String, type:OptionType, def:Dynamic, ?options:Array<String>):Option {
		if (!ClientPrefs.data.gameplaySettings.exists(key))
			ClientPrefs.data.gameplaySettings.set(key, def);

		var o:Option = new Option(name, desc, key, type, options);
		o.defaultValue = def;
		o.getValue = function():Dynamic {
			var v:Dynamic = ClientPrefs.data.gameplaySettings.get(key);
			return (v == null) ? def : v;
		};
		o.setValue = function(v:Dynamic):Dynamic {
			ClientPrefs.data.gameplaySettings.set(key, v);
			return v;
		};
		if (type == STRING && options != null) {
			var idx:Int = options.indexOf(Std.string(o.getValue()));
			o.curOption = (idx < 0) ? 0 : idx;
		}
		return o;
	}

	/**
		A FLOAT hit-window option displayed in milliseconds.
		@param name the row label
		@param desc the row description
		@param variable the backing `ClientPrefs` field
		@param scroll the hold-to-scroll speed
		@param min the minimum value
		@param max the maximum value
		@return the configured option
	**/
	static function window(name:String, desc:String, variable:String, scroll:Float, min:Float, max:Float):Option {
		var o:Option = new Option(name, desc, variable, FLOAT);
		o.displayFormat = '%vms';
		o.scrollSpeed = scroll;
		o.minValue = min;
		o.maxValue = max;
		o.changeValue = 0.1;
		return o;
	}

	/**
		A PERCENT (0..1) option with the standard opacity/volume range and increment.
		@param name the row label
		@param desc the row description
		@param variable the backing `ClientPrefs` field
		@return the configured option
	**/
	static function percent(name:String, desc:String, variable:String):Option {
		var o:Option = new Option(name, desc, variable, PERCENT);
		o.scrollSpeed = 1.6;
		o.minValue = 0.0;
		o.maxValue = 1;
		o.changeValue = 0.1;
		o.decimals = 1;
		return o;
	}

	/** Applies a framerate/uncap change live (draw + update rates, respecting the uncap pin). **/
	static function onChangeFramerate():Void {
		ClientPrefs.applyFramerate();
	}

	/**
		Localizes a category / section title via the `options_*` phrase keys.
		@param name the source-language title
		@return the localized title, or `name` when no translation exists
	**/
	static inline function phrase(name:String):String
		return Language.getPhrase('options_$name', name);
}
