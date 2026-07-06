package states;

import backend.Highscore;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.SkinImage;
import backend.UISkinConfig;
import backend.UISkinConfig.UIJudgement;
import backend.UISkinConfig.UIPlacement;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.SongChart;
import backend.SongChart.StrumLineData;
import backend.Rating;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;
import cutscenes.DialogueBoxPsych;
import states.StoryMenuState;
import states.FreeplayState;
import editors.CharacterEditorState;
import substates.PauseSubState;
import substates.GameOverSubstate;
#if !flash
import openfl.filters.ShaderFilter;
#end
import shaders.ErrorHandledShader;
import objects.VideoSprite;
import objects.Note.EventNote;
import objects.*;
import objects.notes.NoteData;
import objects.notes.NoteData.NoteChart;
import objects.notes.NoteField;
import objects.notes.NoteField.ActiveNote;
import objects.notes.NoteSprite;
import objects.notes.SustainSprite;
import objects.notes.Receptor;
import objects.notes.ScrollVelocity;
import objects.notes.ScrollVelocity.ScrollPoint;
import backend.noteskin.NoteSkinService;
import states.stages.*;
import states.stages.objects.*;
#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.LuaUtils;
import psychlua.HScript;
#end
#if HSCRIPT_ALLOWED
import psychlua.HScript;
#end

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/
class PlayState extends MusicBeatState {
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], // From 0% to 19%
		['Shit', 0.4], // From 20% to 39%
		['Bad', 0.5], // From 40% to 49%
		['Bruh', 0.6], // From 50% to 59%
		['Meh', 0.69], // From 60% to 68%
		['Nice', 0.7], // 69%
		['Good', 0.8], // From 70% to 79%
		['Great', 0.9], // From 80% to 89%
		['Sick!', 1], // From 90% to 99%
		['Perfect!!', 1] // The value on this one isn't used actually, since Perfect is always "1"
	];

	// event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;

	public static var curStage:String = '';
	public static var stageUI(default, set):String = "normal";
	public static var uiPrefix:String = "";
	public static var uiPostfix:String = "";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function set_stageUI(value:String):String {
		uiPrefix = uiPostfix = "";
		if (value != "normal") {
			uiPrefix = value.split("-pixel")[0].trim();
			if (value == "pixel" || value.endsWith("-pixel"))
				uiPostfix = "-pixel";
		}
		return stageUI = value;
	}

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SongChart = null;
	public static var isStoryMode:Bool = false;

	// When a song is launched from a mod's scripted state (e.g. a custom main
	// menu), this holds the scripted-state name to return to on exit instead of
	// the built-in Freeplay/Story menus. Set it before switching to PlayState;
	// it is honoured only while a mod is actually launched (Mods.launchedMod).
	public static var returnToScriptedState:String = null;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	// LEGACY-ONLY (compatibilityMode): the v2 gameplay runtime is `playerField`/`opponentField`
	// (`NoteData`/`NoteSprite`). `notes` + `unspawnNotes` are the pre-v2 script API, populated by
	// `legacy.NoteCompatLayer` only when `Mods.noteCompatibilityMode()` is on; empty otherwise.
	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;

	private static var prevCamFollow:FlxObject;

	// LEGACY-ONLY (compatibilityMode): the v2 strums are `playerReceptors`/`opponentReceptors`
	// (`objects.notes.Receptor`). These `StrumNote` groups are the pre-v2 script API, filled with
	// inert mirror adapters by `legacy.NoteCompatLayer` only under `Mods.noteCompatibilityMode()`.
	public var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var opponentStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var playerStrums:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash> = new FlxTypedGroup<NoteSplash>();

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;

	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	public var combo:Int = 0;

	public var healthBar:Bar;
	public var timeBar:Bar;

	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	private var generatedMusic:Bool = false;

	public var endingSong:Bool = false;
	public var startingSong:Bool = false;

	private var updateTime:Bool = true;

	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	// Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;
	public var pressMissDamage:Float = 0.05;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxText;

	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;

	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;

	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	// Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;

	#if LUA_ALLOWED public var luaArray:Array<FunkinLua> = []; #end

	// luaDebugGroup + addTextToDebug now live on MusicBeatState (every state gets
	// the on-screen script-error overlay). PlayState still targets it at camOther
	// in create() so it ignores gameplay camera zoom.

	public var introSoundsSuffix:String = '';

	// Cache of last values pushed to scripts every frame so that we don't pay
	// for an O(scripts) reflective set when the value hasn't actually changed.
	private var _lastSentDecStep:Float = Math.NEGATIVE_INFINITY;
	private var _lastSentDecBeat:Float = Math.NEGATIVE_INFINITY;
	private var _lastSentBotplay:Null<Bool> = null;

	// Reused arg array for the every-frame onUpdate/onUpdatePost callbacks so the dispatch doesn't
	// allocate a fresh [elapsed] each frame. Read-only as far as scripts are concerned.
	private var _updateArgs:Array<Dynamic> = [0.0];

	// Less laggy controls
	private var keysArray:Array<String>;

	// Reverse-lookup of FlxKey -> strum index, rebuilt once per song from
	// keysArray + Controls.instance.keyboardBinds. getKeyFromEvent walks two
	// nested loops on every key event; this collapses it to a single Map.get.
	private var _keyToStrum:Map<FlxKey, Int> = null;

	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	private static var _lastLoadedModDirectory:String = '';
	public static var nextReloadAll:Bool = false;

	override public function create() {
		// trace('Playback Rate: ' + playbackRate);
		Mods.allowCurrentModAssets = true; // gameplay: ensure the active mod's assets resolve
		_lastLoadedModDirectory = Mods.currentModDirectory;
		Paths.clearStoredMemory();
		if (nextReloadAll) {
			Paths.clearUnusedMemory();
			Language.reloadPhrases();
		}
		nextReloadAll = false;

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		PauseSubState.songName = null; // Reset to default
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');

		// Multikey: derive the column count from the chart (absent == 4K) and feed
		// every keycount-dependent global from the Mania tables. 4K resolves to the
		// classic values, so the default path is unchanged.
		totalColumns = Mania.resolveKeyCount(SONG != null ? SONG.keyCount : null);
		applyKeyCountGlobals(totalColumns);

		keysArray = Mania.keyNames(totalColumns);
		rebuildKeyToStrumMap();

		// Reset Note's per-song hitsound dedupe set so the next song
		// re-precaches its own custom hitsounds (and we don't hold
		// references to last song's that might have been freed).
		Note.precachedHitsounds = new Map();

		NoteSkinConfig.reset();
		UISkinConfig.reset();

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);

		persistentUpdate = true;
		persistentDraw = true;

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		songName = Paths.formatToSongPath(SONG.song);
		if (SONG.stage == null || SONG.stage.length < 1)
			SONG.stage = StageData.vanillaSongStage(Paths.formatToSongPath(Song.loadedSongName));

		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else if (stageData.isPixelStage == true) // Backward compatibility
			stageUI = "pixel";

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if (stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if (boyfriendCameraOffset == null) // Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if (opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if (girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage) {
			case 'stage':
				new StageWeek1(); // Week 1
			case 'spooky':
				new Spooky(); // Week 2
			case 'philly':
				new Philly(); // Week 3
			case 'limo':
				new Limo(); // Week 4
			case 'mall':
				new Mall(); // Week 5 - Cocoa, Eggnog
			case 'mallEvil':
				new MallEvil(); // Week 5 - Winter Horrorland
			case 'school':
				new School(); // Week 6 - Senpai, Roses
			case 'schoolEvil':
				new SchoolEvil(); // Week 6 - Thorns
			case 'tank':
				new Tank(); // Week 7 - Ugh, Guns, Stress
			case 'phillyStreets':
				new PhillyStreets(); // Weekend 1 - Darnell, Lit Up, 2Hot
			case 'phillyBlazin':
				new PhillyBlazin(); // Weekend 1 - Blazin
		}
		if (isPixelStage)
			introSoundsSuffix = '-pixel';

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		if (!stageData.hide_girlfriend)
		{
			if (SONG.gfVersion == null || SONG.gfVersion.trim().length == 0) SONG.gfVersion = 'gf';
			gf = addCharacterToList(SONG.gfVersion, 2, false);
		}

		dad = addCharacterToList(SONG.player2, 1, false);
		boyfriend = addCharacterToList(SONG.player1, 0, false);

		if (stageData.objects != null && stageData.objects.length > 0) {
			var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup,
				boyfriendGroup, this);
			for (key => spr in list)
				if (!StageData.reservedNames.contains(key))
					variables.set(key, spr);
		} else {
			add(gfGroup);
			add(dadGroup);
			add(boyfriendGroup);
		}

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// "SCRIPTS FOLDER" SCRIPTS
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'scripts/'))
			for (file in getScriptLoadOrder(folder)) {
				#if LUA_ALLOWED
				if (file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if (file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if (gf != null) {
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if (dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if (gf != null)
				gf.visible = false;
		}

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// STAGE SCRIPTS
		#if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

		// CHARACTER SCRIPTS
		if (gf != null)
			startCharacterScripts(gf.curCharacter);
		startCharacterScripts(dad.curCharacter);
		startCharacterScripts(boyfriend.curCharacter);
		#end

		uiGroup = new FlxSpriteGroup();
		comboGroup = new FlxSpriteGroup();
		noteGroup = new FlxTypedGroup<FlxBasic>();
		add(comboGroup);
		add(uiGroup);
		add(noteGroup);

		Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');
		timeTxt = new FlxText(0, 19, 400, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.screenCenter(X);
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = updateTime = showTime;
		if (ClientPrefs.data.downScroll)
			timeTxt.y = FlxG.height - 44;
		if (ClientPrefs.data.timeBarType == 'Song Name')
			timeTxt.text = SONG.song;

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		uiGroup.add(timeBar);
		uiGroup.add(timeTxt);

		noteGroup.add(strumLineNotes);

		if (ClientPrefs.data.timeBarType == 'Song Name') {
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		generateSong();

		noteGroup.add(grpNoteSplashes);

		camFollow = new FlxObject();
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null) {
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();
		uiGroup.add(healthBar);

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP2);

		scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		uiGroup.add(scoreTxt);

		botplayTxt = new FlxText(400, healthBar.y - 90, FlxG.width - 800, Language.getPhrase("Botplay").toUpperCase(), 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = cpuControlled;
		uiGroup.add(botplayTxt);
		if (ClientPrefs.data.downScroll)
			botplayTxt.y = healthBar.y + 70;

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		comboGroup.cameras = [camHUD];

		startingSong = true;

		#if LUA_ALLOWED
		for (notetype in noteTypes)
			startLuasNamed('custom_notetypes/' + notetype + '.lua');
		for (event in eventsPushed)
			startLuasNamed('custom_events/' + event + '.lua');
		#end

		#if HSCRIPT_ALLOWED
		for (notetype in noteTypes)
			startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		for (event in eventsPushed)
			startHScriptsNamed('custom_events/' + event + '.hx');
		#end
		noteTypes = null;
		eventsPushed = null;

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'data/$songName/'))
			for (file in FileSystem.readDirectory(folder)) {
				#if LUA_ALLOWED
				if (file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if (file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		if (eventNotes.length > 0) {
			for (event in eventNotes)
				event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		if (debug.bench.BenchmarkRunner.active)
			debug.bench.BenchmarkRunner.onPlayStateReady(this);

		startCallback();
		RecalculateRating(false, false);

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		#if mobile
		addHitbox(totalColumns); // Back button pauses (see update()); no on-screen pause button.
		#end

		// PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		if (ClientPrefs.data.hitsoundVolume > 0)
			Paths.sound('hitsound');
		if (!ClientPrefs.data.ghostTapping)
			for (i in 1...4)
				Paths.sound('missnote$i');
		Paths.image('alphabet');

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if (Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		resetRPC();

		stagesFunc(function(stage:BaseStage) stage.createPost());
		callOnScripts('onCreatePost');

		// compatibilityMode: re-derive the typed chart from the final game.unspawnNotes, so a load-time
		// script that retuned it (flipped mustPress, reordered, replaced it -- e.g. the double-chart mod)
		// is reflected when buildNoteFields spawns the notes.
		if (noteCompat != null && _compatChart != null)
			_compatChart.notes = noteCompat.rebuildChartFromUnspawn(unspawnNotes);

		var splash:NoteSplash = new NoteSplash();
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; // cant make it invisible or it won't allow precaching

		super.create();
		Paths.clearUnusedMemory();

		cacheCountdown();
		cachePopUpScore();

		if (eventNotes.length < 1)
			checkEventNote();
	}

	function set_songSpeed(value:Float):Float {
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float {
		#if FLX_PITCH
		if (generatedMusic) {
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.offset = Reflect.hasField(PlayState.SONG, 'offset') ? (PlayState.SONG.offset / value) : 0;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if (videoCutscene != null && videoCutscene.videoSprite != null)
			videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	// addTextToDebug is inherited from MusicBeatState now.

	public function reloadHealthBarColors() {
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(json:String, type:Int = 0, cache:Bool = true):Character
	{
		var characterMap:Map<String, Character> = boyfriendMap;
		var characterGroup:FlxSpriteGroup = boyfriendGroup;
		switch (type)
		{
			case 1:
				characterMap = dadMap;
				characterGroup = dadGroup;
			case 2:
				characterMap = gfMap;
				characterGroup = gfGroup;
		}

		if (characterMap.exists(json)) return characterMap[json];
		else if (cache && type == 2 && gf == null) return null;

		var character:Character = new Character(0, 0, json, type == 0);
		characterMap.set(json, character);
		characterGroup.add(character);
		startCharacterPos(character);
		if (cache)
		{
			character.alpha = .0001;
			startCharacterScripts(character.curCharacter);
		}
		return character;
	}

	function startCharacterScripts(name:String) {
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if (FileSystem.exists(replacePath)) {
			luaFile = replacePath;
			doPush = true;
		} else {
			luaFile = Paths.getSharedPath(luaFile);
			if (FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if (Assets.exists(luaFile))
			doPush = true;
		#end

		if (doPush) {
			for (script in luaArray) {
				if (script.scriptName == luaFile) {
					doPush = false;
					break;
				}
			}
			if (doPush)
				new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if (FileSystem.exists(replacePath)) {
			scriptFile = replacePath;
			doPush = true;
		} else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if (FileSystem.exists(scriptFile))
				doPush = true;
		}

		if (doPush) {
			if (HScript.instances.exists(scriptFile))
				doPush = false;

			if (doPush)
				initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String):Dynamic
		return variables.get(tag);

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if (gfCheck && char.curCharacter.startsWith('gf')) { // IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public var videoCutscene:VideoSprite = null;

	/** Videos warmed by `precacheVideo`, keyed by name, adopted on the matching `startVideo` call. */
	public var precachedVideos:Map<String, VideoSprite> = new Map<String, VideoSprite>();

	/**
	 * Warms a video ahead of time so the matching `startVideo` starts without the open/decode hitch.
	 * Pass the same `forMidSong`/`canSkip`/`loop` you'll later hand to `startVideo`; a mismatch on
	 * `forMidSong` or `loop` (which are baked in at load time) discards the warmed copy and rebuilds.
	 */
	public function precacheVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false):Void {
		#if VIDEOS_ALLOWED
		if (precachedVideos.exists(name))
			return;

		final fileName:String = Paths.video(name);
		#if sys
		if (!FileSystem.exists(fileName))
		#else
		if (!OpenFlAssets.exists(fileName))
		#end
			return;

		precachedVideos.set(name, new VideoSprite(fileName, forMidSong, canSkip, loop, true));
		#end
	}

	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true) {
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile) {
			var reused:VideoSprite = precachedVideos.get(name);
			if (reused != null) {
				precachedVideos.remove(name);
				// The warmed copy is only valid if the load-time options match; otherwise rebuild.
				if (reused.waiting != forMidSong || reused.looping != loop) {
					reused.destroy();
					reused = null;
				}
			}

			videoCutscene = reused != null ? reused : new VideoSprite(fileName, forMidSong, canSkip, loop);
			videoCutscene.canSkip = canSkip;
			if (forMidSong)
				videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong) {
				function onVideoEnd() {
					if (!isDead
						&& generatedMusic
						&& PlayState.SONG.notes[Std.int(curStep / 16)] != null
						&& !endingSong
						&& !isCameraOnForcedPos) {
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead)
				GameOverSubstate.instance.add(videoCutscene);
			else
				add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else
			addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else
			FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd() {
		if (endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;

	public var psychDialogue:DialogueBoxPsych;

	// You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void {
		// TO DO: Make this more flexible, maybe?
		if (psychDialogue != null)
			return;

		if (dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if (endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;

	public static var startOnTime:Float = 0;

	function cacheCountdown() {
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch (stageUI) {
			case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
			case "normal": ["ready", "set", "go"];
			default: [
					'${uiPrefix}UI/ready${uiPostfix}',
					'${uiPrefix}UI/set${uiPostfix}',
					'${uiPrefix}UI/go${uiPostfix}'
				];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts)
			Paths.image(asset);

		// UI Skin: warm the active skin's countdown images (no-op when the pref has no folder skin).
		for (logical in ['ready', 'set', 'go'])
			UISkinConfig.image(logical);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown() {
		if (startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if (ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0)
				skipArrowStartTween = true;

			canPause = true;
			// NoteSystem V2
			buildNoteFields();

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted');

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			} else if (skipCountdown) {
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer) {
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch (stageUI) {
					case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
					case "normal": ["ready", "set", "go"];
					default: [
							'${uiPrefix}UI/ready${uiPostfix}',
							'${uiPrefix}UI/set${uiPostfix}',
							'${uiPrefix}UI/go${uiPostfix}'
						];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter) {
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias, 'ready');
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias, 'set');
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias, 'go');
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				if (!skipArrowStartTween) {
					notes.forEachAlive(function(note:Note) {
						if (ClientPrefs.data.opponentStrums || note.mustPress) {
							note.copyAlpha = false;
							note.alpha = note.multAlpha;
							if (ClientPrefs.data.middleScroll && !note.mustPress)
								note.alpha *= 0.35;
						}
					});
				}

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool, ?logical:String):FlxSprite {
		var spr:FlxSprite = new FlxSprite();
		// UI Skin: prefer the active skin's ready/set/go image; fall back to the base stageUI asset.
		var skinImg = (logical != null) ? UISkinConfig.image(logical) : null;
		if (skinImg != null)
			spr.loadGraphic(skinImg.graphic);
		else
			spr.loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));
		else if (skinImg != null && skinImg.factor != 1)
			spr.setGraphicSize(Std.int(spr.width * skinImg.factor));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween) {
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic) {
		insert(members.indexOf(gfGroup), obj);
	}

	public function addBehindBF(obj:FlxBasic) {
		insert(members.indexOf(boyfriendGroup), obj);
	}

	public function addBehindDad(obj:FlxBasic) {
		insert(members.indexOf(dadGroup), obj);
	}

	// NoteSystem V2
	public function clearNotesBefore(time:Float) {
		if (playerField != null)
			playerField.skipTo(time);
		if (opponentField != null)
			opponentField.skipTo(time);
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow
	public dynamic function updateScore(miss:Bool = false, scoreBop:Bool = true) {
		var ret:Dynamic = callOnScripts('preUpdateScore', [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		updateScoreText();
		if (!miss && !cpuControlled && scoreBop)
			doScoreBop();

		callOnScripts('onUpdateScore', [miss]);
	}

	public dynamic function updateScoreText() {
		var str:String = Language.getPhrase('rating_$ratingName', ratingName);
		if (totalPlayed != 0) {
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
			str += ' (${percent}%) - ' + Language.getPhrase(ratingFC);
		}

		var tempScore:String;
		if (!instakillOnMiss)
			tempScore = Language.getPhrase('score_text', 'Score: {1} | Misses: {2} | Rating: {3}', [songScore, songMisses, str]);
		else
			tempScore = Language.getPhrase('score_text_instakill', 'Score: {1} | Rating: {2}', [songScore, str]);
		scoreTxt.text = tempScore;
	}

	public dynamic function fullComboFunction() {
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;

		ratingFC = "";
		if (songMisses == 0) {
			if (bads > 0 || shits > 0)
				ratingFC = 'FC';
			else if (goods > 0)
				ratingFC = 'GFC';
			else if (sicks > 0)
				ratingFC = 'SFC';
		} else {
			if (songMisses < 10)
				ratingFC = 'SDCB';
			else
				ratingFC = 'Clear';
		}
	}

	public function doScoreBop():Void {
		if (!ClientPrefs.data.scoreZoom)
			return;

		if (scoreTxtTween != null)
			scoreTxtTween.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});
	}

	public function setSongTime(time:Float) {
		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time - Conductor.offset;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition < vocals.length) {
			vocals.time = time - Conductor.offset;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
			vocals.play();
		} else
			vocals.pause();

		if (Conductor.songPosition < opponentVocals.length) {
			opponentVocals.time = time - Conductor.offset;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
			opponentVocals.play();
		} else
			opponentVocals.pause();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}

	function startSong():Void {
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500) + Conductor.offset);
		startOnTime = 0;

		if (paused) {
			// trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		stagesFunc(function(stage:BaseStage) stage.startSong());

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		if (autoUpdateRPC)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');

		if (debug.bench.BenchmarkRunner.active)
			debug.bench.BenchmarkRunner.onSongStarted(this);
	}

	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private var totalColumns:Int = 4;

	// Multikey mid-song lane changes: sorted (songPosition ms -> new key count),
	// built from per-section changeKeyCount flags + 'Change Key Amount' events.
	// nextKeyChange marks the next pending entry as the song plays.
	private var keyCountChanges:Array<{time:Float, count:Int}> = [];
	private var nextKeyChange:Int = 0;

	private function generateSong():Void {
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch (songSpeedType) {
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try {
			if (songData.needsVoices) {
				var playerVocals = Paths.voices(songData.song,
					(boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
				vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songData.song));

				var oppVocals = Paths.voices(songData.song, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
				if (oppVocals != null && oppVocals.length > 0)
					opponentVocals.loadEmbedded(oppVocals);
			}
		} catch (e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try {
			inst.loadEmbedded(Paths.inst(songData.song));
		} catch (e:Dynamic) {}
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		try {
			// a standalone data/<song>/events.json, in EITHER the legacy grouped shape
			// ([time, [[name, v1, v2], ...]]) OR the psych_v2 object shape ({t, name, values}).
			// eventsFromV2 normalizes both to the grouped shape makeEvent consumes.
			var eventsChart:SwagSong = Song.getChart('events', songName);
			if (eventsChart != null)
				for (event in Song.eventsFromV2(eventsChart.events)) // Event Notes
					for (i in 0...event[1].length)
						makeEvent(event, i);
		} catch (e:Dynamic) {}

		// NoteSystem V2: precache note types from the native note list (types already resolved to strings).
		keyCountChanges = [];
		nextKeyChange = 0;
		for (n in PlayState.SONG.noteList) {
			var nt:String = n.type;
			if (nt != null && nt.length > 0 && !noteTypes.contains(nt))
				noteTypes.push(nt);
		}

		applyKeyCountGlobals(totalColumns);
		for (event in songData.events) // Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		// compatibilityMode: stand up the legacy-API mirror now (before onCreatePost) and pre-decode the
		// chart so old `unspawnNotes` load-time scripts have a note list to mutate. buildNoteFields reuses
		// this same decode, so those mutations are live when the notes actually spawn.
		if (Mods.noteCompatibilityMode()) {
			noteCompat = new legacy.NoteCompatLayer(notes);
			_compatChart = NoteData.generate(SONG, false);
			noteCompat.populateUnspawn(_compatChart.notes, unspawnNotes);
		}

		generatedMusic = true;
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if (eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch (event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch (event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						var parsed:Null<Int> = Std.parseInt(event.value1);
						charType = (parsed != null) ? parsed : 0;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);

			case 'Play Sound':
				Paths.sound(event.value1); // Precache sound
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true);
		if (returnedValue != null && returnedValue != 0) {
			return returnedValue;
		}

		switch (event.event) {
			case 'Kill Henchmen': // Better timing so that the kill sound matches the beat intended
				return 280; // Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int) {
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [
			subEvent.event,
			subEvent.value1 != null ? subEvent.value1 : '',
			subEvent.value2 != null ? subEvent.value2 : '',
			subEvent.strumTime
		]);
	}

	public var skipArrowStartTween:Bool = false; // for lua

	// Multikey: point every keycount-dependent global at `count`. Notes bake their
	// visuals at creation, so changing this later only affects newly-made objects.
	private function applyKeyCountGlobals(count:Int) {
		count = Mania.apply(count);
		singAnimations = Mania.singAnims(count);
	}

	// Multikey mid-song lane change: switch to `count` columns and rebuild the
	// strums + input map. Called from the per-section schedule and the
	// 'Change Key Amount' event.
	public function changeKeyCount(count:Int) {
		count = Mania.clamp(count);
		if (count == totalColumns)
			return;

		totalColumns = count;
		applyKeyCountGlobals(count);
		keysArray = Mania.keyNames(count);
		rebuildKeyToStrumMap();

		// NoteSystem V2
		if (receptorGroup != null) {
			for (r in receptorGroup.members)
				if (r != null)
					r.destroy();
			receptorGroup.clear();
		}

		var prevSkip:Bool = skipArrowStartTween;
		skipArrowStartTween = true; // no intro tween mid-song

		// Rebuild receptors for every visible line at the new column count.
		var visibleLines:Array<StrumLine> = [];
		for (line in strumLines)
			if (line.field != null)
				visibleLines.push(line);
		var centers:Array<Float> = layoutStrumLines(visibleLines);
		var firstOpp:StrumLine = null;
		var firstPlayer:StrumLine = null;
		for (i in 0...visibleLines.length) {
			var line:StrumLine = visibleLines[i];
			line.keyCount = count;
			line.receptors = buildReceptors(line.isPlayer, count, centers[i]);
			line.field.receptors = line.receptors;
			line.field.keyCount = count;
			if (line.isPlayer) {
				if (firstPlayer == null)
					firstPlayer = line;
			} else if (firstOpp == null)
				firstOpp = line;
		}

		skipArrowStartTween = prevSkip;

		opponentReceptors = (firstOpp != null) ? firstOpp.receptors : opponentReceptors;
		playerReceptors = (firstPlayer != null) ? firstPlayer.receptors : playerReceptors;

		setOnScripts('keyCount', totalColumns);
		setOnScripts('mania', totalColumns - 1);
		callOnScripts('onKeyCountChange', [totalColumns]);
	}

	// Apply any per-section key-count changes whose time the song has reached.
	private function processKeyCountChanges() {
		while (nextKeyChange < keyCountChanges.length && Conductor.songPosition >= keyCountChanges[nextKeyChange].time) {
			changeKeyCount(keyCountChanges[nextKeyChange].count);
			nextKeyChange++;
		}
	}

	override function openSubState(SubState:FlxSubState) {
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused) {
			if (FlxG.sound.music != null) {
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if (!tmr.finished)
				tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if (!twn.finished)
				twn.active = false);
		}

		super.openSubState(SubState);
	}

	public var canResync:Bool = true;

	override function closeSubState() {
		super.closeSubState();

		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused) {
			if (FlxG.sound.music != null && !startingSong && canResync) {
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if (!tmr.finished)
				tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if (!twn.finished)
				twn.active = true);

			paused = false;
			callOnScripts('onResume');
			resetRPC(startTimer != null && startTimer.finished);
		}
	}

	#if DISCORD_ALLOWED
	override public function onFocus():Void {
		super.onFocus();
		if (!paused && health > 0) {
			resetRPC(Conductor.songPosition > 0.0);
		}
	}

	override public function onFocusLost():Void {
		super.onFocusLost();
		if (!paused && health > 0 && autoUpdateRPC) {
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		}
	}
	#end

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; // performance setting for custom RPC things

	function resetRPC(?showTime:Bool = false) {
		#if DISCORD_ALLOWED
		if (!autoUpdateRPC)
			return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song
				+ " ("
				+ storyDifficultyText
				+ ")", iconP2.getCharacter(), true,
				songLength
				- Conductor.songPosition
				- ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void {
		if (finishTimer != null)
			return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals) {
			if (FlxG.sound.music.time < vocals.length) {
				voc.time = FlxG.sound.music.time;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			} else
				voc.pause();
		}
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;

	var startedCountdown:Bool = false;
	var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function update(elapsed:Float) {
		if (!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			var idleAnim:Bool = (boyfriend.getAnimationName().startsWith('idle')
				|| boyfriend.getAnimationName().startsWith('danceLeft')
				|| boyfriend.getAnimationName().startsWith('danceRight'));
			if (!startingSong && !endingSong && idleAnim) {
				boyfriendIdleTime += elapsed;
				if (boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		} else
			FlxG.camera.followLerp = 0;
		_updateArgs[0] = elapsed;
		callOnScripts('onUpdate', _updateArgs);

		super.update(elapsed);

		if (curDecStep != _lastSentDecStep) {
			_lastSentDecStep = curDecStep;
			setOnScripts('curDecStep', curDecStep);
		}
		if (curDecBeat != _lastSentDecBeat) {
			_lastSentDecBeat = curDecBeat;
			setOnScripts('curDecBeat', curDecBeat);
		}

		if (botplayTxt != null && botplayTxt.visible) {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		}

		if ((controls.PAUSE #if android || FlxG.android.justPressed.BACK #end) && startedCountdown && canPause) {
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if (ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if (!endingSong && !inCutscene && allowDebugKeys) {
			if (controls.justPressed('debug_1'))
				openChartEditor();
			else if (controls.justPressed('debug_2'))
				openCharacterEditor();
		}

		if (healthBar.bounds.max != null && health > healthBar.bounds.max)
			health = healthBar.bounds.max;

		updateIconsScale(elapsed);
		updateIconsPosition();

		if (startedCountdown && !paused) {
			Conductor.songPosition += elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= Conductor.offset) {
				Conductor.songPosition = FlxMath.lerp(FlxG.sound.music.time + Conductor.offset, Conductor.songPosition, Math.exp(-elapsed * 5));
				var timeDiff:Float = Math.abs((FlxG.sound.music.time + Conductor.offset) - Conductor.songPosition);
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}
		}

		if (startingSong) {
			if (startedCountdown && Conductor.songPosition >= Conductor.offset)
				startSong();
			else if (!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		} else if (!paused && updateTime) {
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if (ClientPrefs.data.timeBarType == 'Time Elapsed')
				songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if (secondsTotal < 0)
				secondsTotal = 0;

			if (ClientPrefs.data.timeBarType != 'Song Name')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
		}

		if (camZooming) {
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
			camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong) {
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		if (generatedMusic) {
			updateFields(); // NoteSystem V2

			if (!inCutscene) {
				if (!cpuControlled)
					keysCheck();
				else
					playerDance();
			}
			if (startedCountdown)
				processKeyCountChanges();
			checkEventNote();
		}

		#if debug
		if (!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if (FlxG.keys.justPressed.TWO) { // Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		if (_lastSentBotplay != cpuControlled) {
			_lastSentBotplay = cpuControlled;
			setOnScripts('botPlay', cpuControlled);
		}
		_updateArgs[0] = elapsed;
		callOnScripts('onUpdatePost', _updateArgs);
	}

	// Health icon updaters
	public dynamic function updateIconsScale(elapsed:Float) {
		var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP1.scale.set(mult, mult);
		iconP1.updateHitbox();

		var mult:Float = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP2.scale.set(mult, mult);
		iconP2.updateHitbox();
	}

	public dynamic function updateIconsPosition() {
		var iconOffset:Int = 26;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
	}

	var iconsAnimations:Bool = true;

	function set_health(value:Float):Float // You can alter how icon animations work here
	{
		value = FlxMath.roundDecimal(value, 5); // Fix Float imprecision
		if (!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null) {
			health = value;
			return health;
		}

		// update health bar
		health = value;
		var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max),
			healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);

		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0; // If health is under 20%, change player icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0; // If health is over 80%, change opponent icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		return health;
	}

	function openPauseMenu() {
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if (FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		if (!cpuControlled) {
			for (note in playerReceptors) // NoteSystem V2
				if (note.animation.curAnim != null && note.animation.curAnim.name != 'static') {
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if (autoUpdateRPC)
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function openChartEditor() {
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		chartingMode = true;
		paused = true;

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if (vocals != null)
			vocals.pause();
		if (opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		MusicBeatState.switchState(new editors.ChartingState());
	}

	function openCharacterEditor() {
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if (vocals != null)
			vocals.pause();
		if (opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; // Don't mess with this on Lua!!!
	public var gameOverTimer:FlxTimer;

	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead && gameOverTimer == null) {
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if (ret != LuaUtils.Function_Stop) {
				FlxG.animationTimeScale = 1;
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;
				canResync = false;
				canPause = false;
				#if VIDEOS_ALLOWED
				if (videoCutscene != null) {
					videoCutscene.destroy();
					videoCutscene = null;
				}
				#end

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				FlxG.camera.filters = [];
				if (GameOverSubstate.deathDelay > 0) {
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_) {
						vocals.stop();
						opponentVocals.stop();
						FlxG.sound.music.stop();
						openSubState(new GameOverSubstate(boyfriend));
						gameOverTimer = null;
					});
				} else {
					vocals.stop();
					opponentVocals.stop();
					FlxG.sound.music.stop();
					openSubState(new GameOverSubstate(boyfriend));
				}

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if (autoUpdateRPC)
					DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() {
		while (eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if (Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if (eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if (eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if (Math.isNaN(flValue1))
			flValue1 = null;
		if (Math.isNaN(flValue2))
			flValue2 = null;

		switch (eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch (value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if (flValue2 == null || flValue2 <= 0)
					flValue2 = 0.6;

				if (value != 0) {
					if (dad.curCharacter.startsWith('gf')) { // Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if (value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if (flValue1 == null || flValue1 < 1)
					flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if (ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if (flValue1 == null)
						flValue1 = 0.015;
					if (flValue2 == null)
						flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				// trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch (value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if (flValue2 == null)
							flValue2 = 0;
						switch (Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null) {
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if (camFollow != null) {
					isCameraOnForcedPos = false;
					if (flValue1 != null || flValue2 != null) {
						isCameraOnForcedPos = true;
						if (flValue1 == null)
							flValue1 = 0;
						if (flValue2 == null)
							flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch (value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var parsed:Null<Int> = Std.parseInt(value1);
						var val:Int = (parsed != null) ? parsed : 0;

						switch (val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null) {
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if (split[0] != null)
						duration = Std.parseFloat(split[0].trim());
					if (split[1] != null)
						intensity = Std.parseFloat(split[1].trim());
					if (Math.isNaN(duration))
						duration = 0;
					if (Math.isNaN(intensity))
						intensity = 0;

					if (duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}

			case 'Change Character':
				var type:Int = switch (value1.toLowerCase().trim())
				{
					case 'gf' | 'girlfriend': 2;
					case 'dad' | 'opponent': 1;
					default:
						Std.parseInt(value1) ?? 0;
				}

				var characterName:String = 'boyfriend';
				var character:Character = boyfriend;
				var characterMap:Map<String, Character> = boyfriendMap;
				var icon:HealthIcon = iconP1;
				switch (type)
				{
					case 1:
						characterName = 'dad';
						character = dad;
						characterMap = dadMap;
						icon = iconP2;
					case 2:
						characterName = 'gf';
						character = gf;
						characterMap = gfMap;
						icon = null;
				}

				if (character != null)
				{
					if (character.curCharacter != value2)
					{
						if (!characterMap.exists(value2))
							addCharacterToList(value2, type);

						var newCharacter:Character = characterMap[value2];
						newCharacter.alpha = 1;

						var lastAlpha:Float = character.alpha;
						character.alpha = .0001;

						var wasGf:Bool = character.curCharacter.startsWith('gf-') || character.curCharacter == 'gf';

						switch (type)
						{
							case 0:
								boyfriend = newCharacter;

							case 1:
								dad = newCharacter;
								if (!newCharacter.curCharacter.startsWith('gf-') && newCharacter.curCharacter != 'gf')
								{
									if (wasGf && gf != null)
										gf.visible = false;
								}
								else if (gf != null)
									gf.visible = false;

							case 2:
								gf = newCharacter; // character != null which would already be this.gf
						}

						// v2 note runtime sings through each strumline's cached Character list; repoint
						// any line that was singing the swapped-out character to the new one, otherwise
						// it keeps animating the old (now-hidden) instance and the new one sits idle.
						if (strumLines != null)
							for (line in strumLines)
								for (ci in 0...line.characters.length)
									if (line.characters[ci] == character)
										line.characters[ci] = newCharacter;

						icon?.changeIcon(newCharacter.healthIcon);
						reloadHealthBarColors();

						setOnScripts('${characterName}Name', newCharacter.curCharacter);
					}
				}

			case 'Change Scroll Speed':
				if (songSpeedType != "constant") {
					if (flValue1 == null)
						flValue1 = 1;
					if (flValue2 == null)
						flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if (flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {
							ease: FlxEase.linear,
							onComplete: function(twn:FlxTween) {
								songSpeedTween = null;
							}
						});
				}

			case 'Change Key Amount':
				if (flValue1 != null)
					changeKeyCount(Std.int(flValue1));

			case 'Set Property':
				try {
					var trueValue:Dynamic = value2.trim();
					if (trueValue == 'true' || trueValue == 'false')
						trueValue = trueValue == 'true';
					else if (flValue2 != null)
						trueValue = flValue2;
					else
						trueValue = value2;

					var split:Array<String> = value1.split('.');
					if (split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1], trueValue);
					} else {
						LuaUtils.setVarInArray(this, value1, trueValue);
					}
				} catch (e:Dynamic) {
					var len:Int = e.message.indexOf('\n') + 1;
					if (len <= 0)
						len = e.message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + e.message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if (flValue2 == null)
					flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		// inline stagesFunc to avoid closure allocation in event hot path
		for (stage in stages)
			if (stage != null && stage.exists && stage.active)
				stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime);
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	public function moveCameraSection(?sec:Null<Int>):Void {
		if (sec == null)
			sec = curSection;
		if (sec < 0)
			sec = 0;

		// Native path: focus the section's cameraTarget strumline. Fall back to the legacy section flags
		// when there's no native section data (e.g. SONG not built yet).
		if (SONG == null || SONG.sections == null || sec >= SONG.sections.length || SONG.sections[sec] == null) {
			if (SONG == null || SONG.notes[sec] == null)
				return;
			if (gf != null && SONG.notes[sec].gfSection) {
				moveCameraToGirlfriend();
				callOnScripts('onMoveCamera', ['gf']);
				return;
			}
			var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
			moveCamera(isDad);
			callOnScripts('onMoveCamera', [isDad ? 'dad' : 'boyfriend']);
			return;
		}

		var target:Int = SONG.sections[sec].cameraTarget;
		var line:StrumLine = (target >= 0 && target < strumLines.length) ? strumLines[target] : null;
		var char:Character = (line != null) ? line.cameraCharacter() : null;

		if (gf != null && char == gf) {
			moveCameraToGirlfriend();
			callOnScripts('onMoveCamera', ['gf']);
		} else if (line != null && line.isPlayer) {
			moveCamera(false);
			callOnScripts('onMoveCamera', ['boyfriend']);
		} else {
			moveCamera(true);
			callOnScripts('onMoveCamera', ['dad']);
		}
	}

	public function moveCameraToGirlfriend() {
		camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
		camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
		camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
		tweenCamIn();
	}

	var cameraTwn:FlxTween;

	public function moveCamera(isDad:Bool) {
		if (isDad) {
			if (dad == null)
				return;
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
		} else {
			if (boyfriend == null)
				return;
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1) {
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {
					ease: FlxEase.elasticInOut,
					onComplete: function(twn:FlxTween) {
						cameraTwn = null;
					}
				});
			}
		}
	}

	public function tweenCamIn() {
		if (songName == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {
				ease: FlxEase.elasticInOut,
				onComplete: function(twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void {
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();

		if (ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}

	public var transitioning = false;

	/**
	 * Routes an exit-to-menu back to a mod's scripted state when the song was
	 * launched from one (returnToScriptedState + a launched mod). Returns true if
	 * it handled the transition; callers fall back to Story/Freeplay otherwise.
	 */
	public static function exitToScriptedStateIfNeeded():Bool {
		#if HSCRIPT_ALLOWED
		// Target priority (both modes): explicit override set by the mod -> the
		// scripted state the song was actually launched from (auto-tracked) -> the
		// mod's declared entry state. The scope decides where it resolves from.
		var target:String = null;
		var scope:scripting.ScriptedStates.ResolveScope = null;

		// One-shot: an explicit override applies to THIS song only. Consume it now so a
		// stale value can't follow the player into another mod/menu that lacks that
		// state (e.g. a global menu's target leaking into a launched modpack).
		var explicitTarget:String = returnToScriptedState;
		returnToScriptedState = null;

		switch (Mods.stateSourceMode) {
			case MOD:
				// Only return to a scripted menu while a mod is actually launched, and
				// only if it ships an entry state (states/<entry>.hx) -- otherwise let
				// callers fall back to Story/Freeplay cleanly.
				if (Mods.launchedMod == null || Mods.launchedMod.length < 1 || !Mods.isLaunchable(Mods.launchedMod))
					return false;
				if (explicitTarget != null && explicitTarget.length > 0)
					target = explicitTarget;
				else if (scripting.ScriptedStates.activeScriptedState != null && scripting.ScriptedStates.activeScriptedState.length > 0)
					target = scripting.ScriptedStates.activeScriptedState;
				else
					target = Mods.getEntryState(Mods.launchedMod);
				scope = scripting.ScriptedStates.ResolveScope.LAUNCHED;

			case GLOBAL:
				// "Global Script" mode: the song was launched from a global scripted
				// override of a core menu (e.g. mods/states/FreeplayState.hx). There's
				// no launchedMod, but we still must rebuild that override cleanly rather
				// than let coreOverride build it mid-teardown (-> update() null-ref).
				if (explicitTarget != null && explicitTarget.length > 0)
					target = explicitTarget;
				else
					target = scripting.ScriptedStates.activeScriptedState;
				scope = scripting.ScriptedStates.ResolveScope.GLOBALS;

			default: // NONE -> built-in menus only
				return false;
		}
		if (target == null || target.length < 1)
			return false;

		FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);

		// IMPORTANT: don't build the scripted state here. From gameplay the
		// previous state (this PlayState + its mod scripts) is still alive, so a
		// scripted instance built now captures references that get destroyed on
		// teardown -> its update()/draw() null-ref. Route through a tiny native
		// state that builds the scripted state from its own create(), AFTER this
		// state is fully destroyed (same clean conditions as a fresh launch).
		MusicBeatState.switchState(new scripting.ScriptedStates.ScriptedReturnState(target, scope));
		return true;
		#else
		return false;
		#end
	}

	public function endSong() {
		// Should kill you if you tried to cheat: drain for every still-unhit note.
		if (!startingSong) {
			for (f in noteFields) // NoteSystem V2
				if (f != null)
					for (data in f.notes)
						if (!data.hit && data.time < songLength - Conductor.safeZoneOffset)
							health -= 0.05 * healthLoss;

			if (doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([
			weekNoMiss,
			'ur_bad',
			'ur_good',
			'hype',
			'two_keys',
			'toastie'
			#if BASE_GAME_FILES, 'debugger' #end
		]);
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if (ret != LuaUtils.Function_Stop && !transitioning) {
			#if !switch
			var percent:Float = ratingPercent;
			if (Math.isNaN(percent))
				percent = 0;
			Highscore.saveScore(Song.loadedSongName, songScore, storyDifficulty, percent);
			#end
			playbackRate = 1;

			if (chartingMode) {
				openChartEditor();
				return false;
			}

			if (isStoryMode) {
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0) {
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					canResync = false;
					MusicBeatState.switchState(new StoryMenuState());

					// if ()
					if (!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay')) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				} else {
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					Song.loadFromJson(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					canResync = false;
					LoadingState.prepareToSong();
					LoadingState.loadAndSwitchState(new PlayState(), false, false);
				}
			} else {
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
				canResync = false;
				if (exitToScriptedStateIfNeeded()) {
					changedDifficulty = false;
				} else {
					trace('WENT BACK TO FREEPLAY??');
					Mods.loadTopMod();
					MusicBeatState.switchState(new FreeplayState());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					changedDifficulty = false;
				}
			}
			transitioning = true;
		}
		return true;
	}

	public function KillNotes() {
		// NoteSystem V2
		if (playerField != null)
			playerField.clear();
		if (opponentField != null)
			opponentField.clear();
		eventNotes = [];
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	private function cachePopUpScore() {
		var uiFolder:String = "";
		if (stageUI != "normal")
			uiFolder = uiPrefix + "UI/";

		for (rating in ratingsData)
			Paths.image(uiFolder + rating.image + uiPostfix);
		for (i in 0...10)
			Paths.image(uiFolder + 'num' + i + uiPostfix);

		// UI Skin: warm the active skin's folder images (resolveImage caches them). No-op when the
		// pref has no folder skin, in which case the base assets above are used.
		UISkinConfig.image('combo');
		for (rating in ratingsData)
			UISkinConfig.image(rating.image);
		for (j in UISkinConfig.judgements())
			UISkinConfig.image(j.image);
		for (i in 0...10)
			UISkinConfig.image('num' + i);
	}

	// Pool of FlxSprite objects recycled across popUpScore() calls.
	// popUpScore used to allocate 3-5 fresh sprites per hit (rating + combo
	// + 3+ digit numbers) and tween-then-destroy them. Now we acquire from
	// the pool, configure, and release on tween-complete (or eagerly when
	// comboStacking is off and a new popup wipes the previous one).
	private var _popupPool:Array<FlxSprite> = [];

	inline function acquirePopupSprite():FlxSprite {
		final s:FlxSprite = (_popupPool.length > 0 ? _popupPool.pop() : new FlxSprite());
		s.revive();
		s.alpha = 1;
		s.scale.set(1, 1);
		s.offset.set(0, 0);
		s.angle = 0;
		// popUpScore mutates velocity/acceleration with -= and += against the
		// current value; without resetting these, every pool reuse carried
		// over the previous popup's momentum and the sprite shot off-screen
		// before the alpha tween could run. That looked like missing /
		// laggy judgements. Reset all physics state to a fresh-sprite baseline.
		s.velocity.set(0, 0);
		s.acceleration.set(0, 0);
		s.maxVelocity.set(10000, 10000);
		s.drag.set(0, 0);
		s.moves = true;
		return s;
	}

	function releasePopupSprite(spr:FlxSprite):Void {
		if (spr == null) return;
		FlxTween.cancelTweensOf(spr);
		if (comboGroup != null) comboGroup.remove(spr, true);
		spr.kill();
		_popupPool.push(spr);
	}

	public var strumsBlocked:Array<Bool> = [];

	private function onKeyPress(event:KeyboardEvent):Void {
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getStrumFromKey(eventKey);

		if (!controls.controllerMode) {
			#if debug
			// Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey))
				return;
			#end

			if (FlxG.keys.checkStatus(eventKey, JUST_PRESSED))
				keyPressed(key);
		}
	}

	private function onKeyRelease(event:KeyboardEvent):Void {
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getStrumFromKey(eventKey);
		if (!controls.controllerMode && key > -1)
			keyReleased(key);
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int {
		if (key != NONE) {
			for (i in 0...arr.length) {
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if (key == noteKey)
						return i;
			}
		}
		return -1;
	}

	// Build / refresh the FlxKey -> strum-index map from the current keysArray
	// and Controls bindings. Call this if the player rebinds keys mid-song.
	public function rebuildKeyToStrumMap():Void {
		final map:Map<FlxKey, Int> = new Map();
		final binds = Controls.instance.keyboardBinds;
		final keys = keysArray;
		final len = keys.length;
		for (i in 0...len) {
			final bound:Array<FlxKey> = binds[keys[i]];
			if (bound == null) continue;
			for (j in 0...bound.length) {
				final k = bound[j];
				if (k != NONE && !map.exists(k))
					map.set(k, i);
			}
		}
		_keyToStrum = map;
	}

	inline function getStrumFromKey(eventKey:FlxKey):Int {
		if (eventKey == NONE || _keyToStrum == null) return -1;
		final v = _keyToStrum.get(eventKey);
		return v == null ? -1 : v;
	}

	// Reusable per-frame buffers for keysCheck. Sized to keysArray once.
	private var _holdArray:Array<Bool> = null;
	private var _pressArray:Array<Bool> = null;
	private var _releaseArray:Array<Bool> = null;

	// NoteSystem V2
	function anyStrumBlocked():Bool {
		final sb = strumsBlocked;
		final len = sb.length;
		for (i in 0...len) if (sb[i] == true) return true;
		return false;
	}

	public function spawnNoteSplash(x:Float = 0, y:Float = 0, ?data:Int = 0, ?note:Note, ?strum:FlxSprite) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	// NOTE SYSTEM
	/** Native Scroll Velocity timeline; disabled (identity) unless the chart defines SV. **/
	public var scrollVelocity:ScrollVelocity = new ScrollVelocity();

	/** The SV control points the timeline was built from (per-section + events + runtime additions). **/
	public var svPoints:Array<ScrollPoint> = [];

	/** The active strumlines (one per chart strumline; ≤3 are rendered). `opponentField`/`playerField`
		+ their receptors are aliases into the first opponent/player line for scripts + the judgement path. **/
	public var strumLines:Array<StrumLine> = [];

	// Non-rendered strumlines (gf + extras) still "play" their notes: characters sing on time.
	var silentLines:Array<StrumLine> = [];
	var silentNotes:Array<Array<NoteData>> = [];
	var silentCursor:Array<Int> = [];
	var silentHoldEnd:Array<Float> = [];

	public var playerField:NoteField;
	public var opponentField:NoteField;
	public var noteFields:Array<NoteField> = [];
	public var playerReceptors:Array<Receptor> = [];
	public var opponentReceptors:Array<Receptor> = [];

	/** Non-null only under `Mods.noteCompatibilityMode()`; mirrors v2 onto the legacy script API. **/
	public var noteCompat:legacy.NoteCompatLayer = null;

	/** Compat-mode chart decode done early (in `generateSong`) and reused by `buildNoteFields`. **/
	var _compatChart:NoteChart = null;

	/**
		The object handed to a note's HScript callbacks / stage hooks. In `compatibilityMode` it's a
		`LegacyNote` adapter (so old scripts get the pre-v2 shape); otherwise the v2 drawable, unchanged.
		@param note the active note being spawned/judged
		@param sustain pass `true` to hand the sustain drawable rather than the head (non-compat only)
	**/
	inline function cbArg(note:ActiveNote, sustain:Bool = false):Dynamic {
		if (noteCompat != null)
			return noteCompat.callbackNote(note);
		return sustain ? note.sustain : note.head;
	}

	/**
		Accepts either a real `ActiveNote` (the runtime/internal callers) or a legacy note object a
		compatibilityMode script passed to `goodNoteHit`/`noteMiss`, and returns the matching `ActiveNote`
		(or `null` if it isn't currently active). Lets old `game.goodNoteHit(note)` calls reach the v2 path.
		@param n the note argument
		@return the resolved active note, or `null`
	**/
	inline function asActiveNote(n:Dynamic):ActiveNote {
		if (Std.isOfType(n, ActiveNote))
			return cast n;
		return (noteCompat != null) ? noteCompat.resolveActive(n) : null;
	}

	/**
		Fires the compiled stage note hooks (`BaseStage.goodNoteHit`/`opponentNoteHit`/`noteMiss`, which
		take a legacy `Note`) with the compat adapter. Only runs under `compatibilityMode` -- in v2 play
		these hooks stay skipped, since the stage API predates the `NoteSprite` the v2 path carries.
		@param which `0` = goodNoteHit, `1` = opponentNoteHit, anything else = noteMiss
		@param note the active note being judged
	**/
	inline function fireStageNote(which:Int, note:ActiveNote):Void {
		if (noteCompat != null) {
			var ln:Note = noteCompat.callbackNote(note);
			for (st in stages) {
				switch (which) {
					case 0:
						st.goodNoteHit(ln);
					case 1:
						st.opponentNoteHit(ln);
					default:
						st.noteMiss(ln);
				}
			}
		}
	}

	public var receptorGroup:flixel.group.FlxGroup.FlxTypedGroup<Receptor>;

	inline function notStopped(r:Dynamic):Bool
		return r != LuaUtils.Function_Stop && r != LuaUtils.Function_StopHScript && r != LuaUtils.Function_StopAll;

	function buildNoteFields():Void {
		// Reuse the compat early-decode (carrying any onCreatePost mutations) when present.
		var chart:NoteChart = (_compatChart != null) ? _compatChart : NoteData.generate(SONG, false);
		keyCountChanges = chart.keyCountChanges;
		nextKeyChange = 0;

		// Scroll Velocity: per-section points + 'Scroll Velocity' events, then precompute each
		// note's scroll position. No-op (identity) when the chart defines no SV.
		svPoints = chart.scrollPoints;
		for (e in eventNotes)
			if (e.event == 'Scroll Velocity' || e.event == 'Osu SV') {
				var v:Float = Std.parseFloat(e.value1);
				if (!Math.isNaN(v))
					svPoints.push(new ScrollPoint(e.strumTime, v));
			}
		scrollVelocity.build(svPoints);
		NoteData.applyScrollVelocity(chart.notes, scrollVelocity);

		receptorGroup = new flixel.group.FlxGroup.FlxTypedGroup<Receptor>();

		// Build a StrumLine per chart strumline (characters resolved so hidden lines can still serve as
		// camera targets); instantiate receptors/field only for the visible ones (≤3 rendered).
		// ADDITIONAL lines (gf + extras) never render for now -- they run silently (characters sing,
		// camera targets work) until the extra-strumline rendering pass lands.
		strumLines = [];
		var visibleLines:Array<StrumLine> = [];
		for (sd in SONG.strumLines) {
			var renderable:Bool = sd.visible && sd.type != backend.SongChart.StrumLineType.ADDITIONAL;
			var line:StrumLine = new StrumLine(sd.index, sd.id, sd.isPlayer, sd.keyCount, renderable);
			line.type = sd.type;
			line.vocalsSuffix = sd.vocalsSuffix;
			line.downScroll = ClientPrefs.data.downScroll;
			line.cpuControlled = sd.isPlayer ? cpuControlled : true;
			line.characters = [for (name in sd.characters) resolveStrumCharacter(name)];
			strumLines.push(line);
			if (renderable && visibleLines.length < 3)
				visibleLines.push(line);
		}

		// Auto-spread the visible lines across the play area (2-line case == the classic 25%/75%).
		var centers:Array<Float> = layoutStrumLines(visibleLines);
		for (i in 0...visibleLines.length)
			visibleLines[i].receptors = buildReceptors(visibleLines[i].isPlayer, visibleLines[i].keyCount, centers[i]);

		// Distribute notes into each line's field by absolute strumLine index.
		var perLine:Array<Array<NoteData>> = [for (_ in SONG.strumLines) []];
		for (n in chart.notes)
			if (n.strumLine >= 0 && n.strumLine < perLine.length)
				perLine[n.strumLine].push(n);

		// Field-less lines with notes drive their characters silently (the new "gf section" path).
		silentLines = [];
		silentNotes = [];
		silentCursor = [];
		silentHoldEnd = [];
		for (line in strumLines) {
			if (visibleLines.contains(line) || perLine[line.index].length == 0)
				continue;
			silentLines.push(line);
			silentNotes.push(perLine[line.index]);
			silentCursor.push(0);
			silentHoldEnd.push(-1);
		}

		noteFields = [];
		var firstOpp:StrumLine = null;
		var firstPlayer:StrumLine = null;
		for (line in visibleLines) {
			line.field = new NoteField(perLine[line.index], line.receptors, line.keyCount, ClientPrefs.data.downScroll);
			line.field.onSpawn = onNoteSpawned;
			noteFields.push(line.field);
			if (line.isPlayer) {
				if (firstPlayer == null)
					firstPlayer = line;
			} else if (firstOpp == null)
				firstOpp = line;
		}

		// Legacy-compatible aliases: scripts, the compat layer, splashes and the judgement path read these.
		opponentField = (firstOpp != null) ? firstOpp.field : null;
		playerField = (firstPlayer != null) ? firstPlayer.field : null;
		opponentReceptors = (firstOpp != null) ? firstOpp.receptors : [];
		playerReceptors = (firstPlayer != null) ? firstPlayer.receptors : [];

		// Note layering, per-skin (`skin.tcfg` `holdsOverHeads`) or the global `sustainsOverNotes` option.
		if (backend.NoteSkinConfig.holdsOverHeads()) {
			// Over: sustains drawn on top of the receptors and the heads.
			noteGroup.add(receptorGroup);
			for (line in visibleLines)
				noteGroup.add(line.field.headGroup);
			for (line in visibleLines)
				noteGroup.add(line.field.sustainGroup);
		} else {
			// Under (default): sustains sit at the very back, behind the receptor (press/confirm) and the
			// head, so a hold looks like it disappears into the note rather than passing over it.
			for (line in visibleLines)
				noteGroup.add(line.field.sustainGroup);
			noteGroup.add(receptorGroup);
			for (line in visibleLines)
				noteGroup.add(line.field.headGroup);
		}

		// Keep note splashes drawn above the notes (the splash group was added during create()).
		if (grpNoteSplashes != null && noteGroup.members.contains(grpNoteSplashes)) {
			noteGroup.remove(grpNoteSplashes, true);
			noteGroup.add(grpNoteSplashes);
		}

		for (i in 0...playerReceptors.length) {
			setOnScripts('defaultPlayerStrumX' + i, playerReceptors[i].x);
			setOnScripts('defaultPlayerStrumY' + i, playerReceptors[i].y);
		}
		for (i in 0...opponentReceptors.length) {
			setOnScripts('defaultOpponentStrumX' + i, opponentReceptors[i].x);
			setOnScripts('defaultOpponentStrumY' + i, opponentReceptors[i].y);
		}

		// noteCompat (if any) was created in generateSong; now that receptors exist, build the strum mirror.
		if (noteCompat != null)
			noteCompat.buildStrums(playerReceptors, opponentReceptors, strumLineNotes, playerStrums, opponentStrums);
	}

	function buildReceptors(isPlayer:Bool, keyCount:Int, targetCenter:Float):Array<Receptor> {
		var out:Array<Receptor> = [];
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		var player:Int = isPlayer ? 1 : 0;
		for (i in 0...keyCount) {
			var targetAlpha:Float = 1;
			if (!isPlayer) {
				if (!ClientPrefs.data.opponentStrums)
					targetAlpha = 0;
				else if (ClientPrefs.data.middleScroll)
					targetAlpha = 0.35;
			}
			var r:Receptor = new Receptor(strumLineX, strumLineY, i, player, keyCount);
			r.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween) {
				r.alpha = 0;
				FlxTween.tween(r, {alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			} else
				r.alpha = targetAlpha;

			if (!isPlayer && ClientPrefs.data.middleScroll) {
				r.x += 310;
				if (i > Math.floor(keyCount / 2) - 1)
					r.x += FlxG.width / 2 + 25;
			}
			out.push(r);
			receptorGroup.add(r);
			r.playerPosition();
		}

		if (targetCenter >= 0 && out.length > 0) {
			var first:Float = out[0].x;
			var last:Float = out[out.length - 1].x;
			var delta:Float = targetCenter - ((first + last) / 2 + Note.swagWidth / 2);
			for (r in out)
				r.x += delta;
		}
		return out;
	}

	/**
		Auto-spread the visible strumlines across the play area. Two lines reproduce the classic
		opponent-25% / player-75% split; N lines spread evenly. Under middlescroll the player line
		centers and the others keep their shoved-aside position (`-1` == don't recenter).
		@param lines the visible strumlines, in render order
		@return the target center X per line (`-1` = leave in place)
	**/
	function layoutStrumLines(lines:Array<StrumLine>):Array<Float> {
		var centers:Array<Float> = [];
		var n:Int = lines.length;
		if (ClientPrefs.data.middleScroll) {
			for (line in lines)
				centers.push(line.isPlayer ? FlxG.width / 2 : -1);
		} else {
			for (i in 0...n)
				centers.push(FlxG.width * ((i + 0.5) / n));
		}
		return centers;
	}

	/** The strumline a note belongs to (or `null` if its index is out of range). **/
	inline function lineOf(data:NoteData):StrumLine
		return (data.strumLine >= 0 && data.strumLine < strumLines.length) ? strumLines[data.strumLine] : null;

	/** Resolves a strumline character name to one of PlayState's live characters (bf/dad/gf). **/
	function resolveStrumCharacter(name:String):Character {
		if (name == null)
			return null;
		if (dad != null && (name == SONG.player2 || dad.curCharacter == name))
			return dad;
		if (boyfriend != null && (name == SONG.player1 || boyfriend.curCharacter == name))
			return boyfriend;
		if (gf != null && (name == SONG.gfVersion || gf.curCharacter == name))
			return gf;
		return null;
	}

	/**
		The note currently being passed to `onSpawnNote`. Exposed so plain-Lua scripts can reach it via
		`getProperty`/`setProperty` (e.g. `setProperty('spawnNote.data.ignore', true)`); only valid
		inside an `onSpawnNote` callback.
	**/
	public var spawnNote:ActiveNote = null;

	function onNoteSpawned(note:ActiveNote):Void {
		spawnNote = note;
		callOnLuas('onSpawnNote', [-1, note.data.column, note.data.type, note.data.isSustain(), note.data.time, note.data.mustPress]);
		spawnNote = null;
		callOnHScript('onSpawnNote', [cbArg(note)]);
	}

	/** Rebuilds the SV timeline from `svPoints` and re-precomputes every note's scroll position. **/
	public function recomputeScrollVelocity():Void {
		scrollVelocity.build(svPoints);
		for (f in noteFields)
			if (f != null)
				NoteData.applyScrollVelocity(f.notes, scrollVelocity);
	}

	/**
		Adds a Scroll Velocity control point at runtime and recomputes. Best used before the affected
		notes spawn (e.g. in `onCreatePost` or well ahead of `time`).
		@param time song time in ms for the change
		@param mult the scroll multiplier from `time` onward
	**/
	public function addScrollVelocity(time:Float, mult:Float):Void {
		svPoints.push(new ScrollPoint(time, mult));
		recomputeScrollVelocity();
	}

	/** Removes all Scroll Velocity, restoring constant scroll. **/
	public function clearScrollVelocity():Void {
		svPoints = [];
		recomputeScrollVelocity();
	}

	function updateFields():Void {
		if (opponentField == null)
			return;
		var songPos:Float = Conductor.songPosition;
		// One shared SV lookup per frame; every note positions against this (== songPos when SV is off).
		var scrollNow:Float = scrollVelocity.posAt(songPos);
		var sp:Float = songSpeed / playbackRate;
		var ahead:Float = spawnTime * playbackRate;
		if (songSpeed < 1)
			ahead /= songSpeed;
		for (f in noteFields) {
			f.speed = sp;
			f.downScroll = ClientPrefs.data.downScroll;
			f.spawnAhead = ahead;
			// Margin so the judgement miss (at noteKillOffset) always fires before the field
			// reclaims a late player note -- otherwise late notes vanish with no miss.
			f.killBehind = noteKillOffset + 500;
			f.update(songPos, scrollNow);
		}
		if (!startedCountdown || inCutscene)
			return;

		updateSilentLines(songPos);

		// Non-player lines auto-hit at each note's time (opponent, extra opponents, a notes-carrying gf line).
		// Backwards over active since opponentNoteHit can splice it.
		for (line in strumLines) {
			if (line.field == null || line.isPlayer)
				continue;
			var arr:Array<ActiveNote> = line.field.active;
			var oi:Int = arr.length;
			while (--oi >= 0) {
				var note:ActiveNote = arr[oi];
				var data:NoteData = note.data;
				if (!data.hit && data.time <= songPos) {
					data.canBeHit = false;
					data.hit = true;
					if (!data.hitByOpponent && !data.ignore)
						opponentNoteHit(note);
				} else if (data.hit && data.isSustain()) {
					if (songPos >= data.endTime())
						line.field.remove(note); // hold finished -- reclaim now
					else {
						var hc:Character = data.gfNote ? gf : line.cameraCharacter(); // keep the line's char singing
						if (hc != null) {
							hc.holdTimer = 0;
							hc.singHold = true;
						}
					}
				}
			}
		}

		// player: hit-window flags, cpu auto-hit, late miss
		var pi:Int = playerField.active.length;
		while (--pi >= 0) {
			var note:ActiveNote = playerField.active[pi];
			var data:NoteData = note.data;
			data.canBeHit = (data.time > songPos - (Conductor.safeZoneOffset * data.lateHitMult)
				&& data.time < songPos + (Conductor.safeZoneOffset * data.earlyHitMult));
			if (data.time < songPos - Conductor.safeZoneOffset && !data.hit)
				data.tooLate = true;

			// Bot hits exactly when the note reaches the receptor -- gated by `time <= songPos` for
			// sustains too, otherwise the hit window's early edge would fire holds ahead of time.
			if (cpuControlled && !data.blockHit && data.canBeHit && !data.hit && data.time <= songPos) {
				goodNoteHit(note);
				continue;
			}

			// A hit hold scrolls until consumed; complete it at end-time (cpu + human completion).
			// Early-release for a human is handled in keysCheck where the hold state is fresh.
			if (data.isSustain() && data.hit) {
				// A human's non-GH sustain is judged per-segment in keysCheck; skip the one-unit path here.
				if (!cpuControlled && !guitarHeroSustains)
					continue;
				var rec:Receptor = (data.column >= 0 && data.column < playerReceptors.length) ? playerReceptors[data.column] : null;
				if (songPos >= data.endTime()) {
					// The bot has no key to release, so drop its receptor back to static here.
					if (cpuControlled && rec != null) {
						rec.playAnim('static');
						rec.resetAnim = 0;
					}
					playerField.remove(note);
				} else {
					var hc:Character = data.gfNote ? gf : boyfriend; // keep singing through the hold
					if (hc != null) {
						hc.holdTimer = 0;
						hc.singHold = true;
					}
					// Keep the receptor lit for the hold's duration (no-op once it's already confirming).
					if (rec != null) {
						if (rec.animation.curAnim == null || rec.animation.curAnim.name != 'confirm')
							rec.playAnim('confirm', true);
						rec.resetAnim = 0;
					}
				}
				continue;
			}

			if (!data.hit
				&& !data.missed
				&& !data.headMissed
				&& data.mustPress
				&& !cpuControlled
				&& !data.ignore
				&& !endingSong
				&& songPos - data.time > noteKillOffset) {
				// Non-GH sustain: a missed head is one miss, but the body stays catchable (old behavior).
				if (data.isSustain() && !guitarHeroSustains)
					headMissForSustain(note);
				else
					noteMiss(note);
			}
		}

		// compatibilityMode only: mirror the live v2 state onto the legacy game.notes / strum groups.
		if (noteCompat != null) {
			noteCompat.syncNotes(noteFields);
			noteCompat.syncStrums();
		}
	}

	function keysCheck():Void {
		final keys = keysArray;
		final klen = keys.length;
		var holdArray = _holdArray;
		var pressArray = _pressArray;
		var releaseArray = _releaseArray;
		if (holdArray == null || holdArray.length != klen) {
			holdArray = _holdArray = [for (_ in 0...klen) false];
			pressArray = _pressArray = [for (_ in 0...klen) false];
			releaseArray = _releaseArray = [for (_ in 0...klen) false];
		}

		final ctrl = controls;
		var anyHeld:Bool = false;
		var anyPressed:Bool = false;
		var anyReleased:Bool = false;
		for (i in 0...klen) {
			final k = keys[i];
			final h = ctrl.pressed(k);
			final p = ctrl.justPressed(k);
			final r = ctrl.justReleased(k);
			holdArray[i] = h;
			pressArray[i] = p;
			releaseArray[i] = r;
			if (h)
				anyHeld = true;
			if (p)
				anyPressed = true;
			if (r)
				anyReleased = true;
		}

		#if mobile
		if (hitbox != null) {
			final hlen:Int = (klen < hitbox.buttons.length) ? klen : hitbox.buttons.length;
			for (i in 0...hlen) {
				final btn = hitbox.buttons[i];
				if (btn.pressed) {
					holdArray[i] = true;
					anyHeld = true;
				}
				if (btn.justPressed && strumsBlocked[i] != true)
					keyPressed(i);
				if (btn.justReleased)
					keyReleased(i);
			}
		}
		#end

		if (ctrl.controllerMode && anyPressed)
			for (i in 0...klen)
				if (pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !inCutscene && !boyfriend.stunned && generatedMusic) {
			if (!anyHeld || endingSong)
				playerDance();

			// Sustain holds. GH mode: one unit -- releasing early drops the whole remainder as one miss.
			// Non-GH: the old segmented model -- each step is judged from the live hold state, and the body
			// stays catchable even after a missed head.
			if (playerField != null) {
				var si:Int = playerField.active.length;
				while (--si >= 0) {
					var note:ActiveNote = playerField.active[si];
					var data:NoteData = note.data;
					if (!data.isSustain())
						continue;
					var held:Bool = (data.column >= 0 && data.column < holdArray.length) ? holdArray[data.column] : false;
					if (guitarHeroSustains) {
						if (!data.hit || data.missed)
							continue;
						if (Conductor.songPosition >= data.endTime())
							continue; // completion handled in updateFields
						if (!held)
							sustainRelease(note);
					} else if (data.hit || data.headMissed) {
						// Non-GH: judge each body step from the live hold state (health held, miss dropped).
						updateSegmentedSustain(note, held);
					}
				}
			}
		}

		if (anyReleased && (ctrl.controllerMode || anyStrumBlocked()))
			for (i in 0...klen)
				if (releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	// NoteSystem V2
	function keyPressed(key:Int):Void {
		if (cpuControlled || paused || inCutscene || key < 0 || key >= playerReceptors.length || !generatedMusic || endingSong || boyfriend.stunned)
			return;

		var ret:Dynamic = callOnScripts('onKeyPressPre', [key]);
		if (ret == LuaUtils.Function_Stop)
			return;

		var lastTime:Float = Conductor.songPosition;
		if (Conductor.songPosition >= 0)
			Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		playerField.pickHit(key, strumsBlocked[key] == true);
		var funny:ActiveNote = playerField.hitBest;
		if (funny != null) {
			var dbl:ActiveNote = playerField.hitSecond;
			if (dbl != null) {
				if (Math.abs(dbl.data.time - funny.data.time) < 1.0)
					playerField.remove(dbl);
				else if (dbl.data.time < funny.data.time)
					funny = dbl;
			}
			goodNoteHit(funny);
		} else {
			if (ClientPrefs.data.ghostTapping)
				callOnScripts('onGhostTap', [key]);
			else
				noteMissPress(key);
		}

		if (!keysPressed.contains(key))
			keysPressed.push(key);
		Conductor.songPosition = lastTime;

		var spr:Receptor = playerReceptors[key];
		if (strumsBlocked[key] != true && spr != null && spr.animation.curAnim != null && spr.animation.curAnim.name != 'confirm') {
			spr.playAnim('pressed');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyPress', [key]);
	}

	// NoteSystem V2
	function keyReleased(key:Int):Void {
		if (cpuControlled || !startedCountdown || paused || key < 0 || key >= playerReceptors.length)
			return;

		var ret:Dynamic = callOnScripts('onKeyReleasePre', [key]);
		if (ret == LuaUtils.Function_Stop)
			return;

		var spr:Receptor = playerReceptors[key];
		if (spr != null) {
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		callOnScripts('onKeyRelease', [key]);
	}

	// NoteSystem V2
	function strumPlayAnim(recs:Array<Receptor>, id:Int, time:Float):Void {
		var spr:Receptor = (recs != null && id >= 0 && id < recs.length) ? recs[id] : null;
		if (spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	// NoteSystem V2
	function singChar(char:Character, data:NoteData, animCheck:String):Void {
		if (char == null)
			return;
		var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, data.column)))] + data.animSuffix;
		var canPlay:Bool = true;
		if (data.isSustain()) {
			var holdAnim:String = animToPlay + '-hold';
			if (char.animation.exists(holdAnim))
				animToPlay = holdAnim;
			if (char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop')
				canPlay = false;
		}
		if (canPlay)
			char.playAnim(animToPlay, true);
		char.holdTimer = 0;
		if (data.type == 'Hey!' && animCheck != null && char.hasAnimation(animCheck)) {
			char.playAnim(animCheck, true);
			char.specialAnim = true;
			char.heyTimer = 0.6;
		}
	}

	// NoteSystem V2
	/**
		Advances the non-rendered strumlines: when a note's time passes, the line's character
		sings it (sustains keep the hold alive) — no drawables, no judgement. This is what makes
		the hidden gf line (and future extra lines) act like the old "GF Section".
	**/
	function updateSilentLines(songPos:Float):Void {
		var li:Int = silentLines.length;
		while (--li >= 0) {
			var line:StrumLine = silentLines[li];
			var notes:Array<NoteData> = silentNotes[li];
			var cursor:Int = silentCursor[li];
			var singer:Character = line.cameraCharacter();
			while (cursor < notes.length && notes[cursor].time <= songPos) {
				var data:NoteData = notes[cursor];
				cursor++;
				// skip long-stale notes (song skip/seek) instead of burst-singing them
				if (data.ignore || songPos - data.time > 1000)
					continue;
				var who:Character = data.gfNote ? gf : singer;
				if (who != null && !data.noAnimation)
					singChar(who, data, null);
				if (data.isSustain() && data.endTime() > silentHoldEnd[li])
					silentHoldEnd[li] = data.endTime();
			}
			silentCursor[li] = cursor;
			if (singer != null && songPos < silentHoldEnd[li])
				singer.holdTimer = 0;
		}
	}

	function opponentNoteHit(note:ActiveNote):Void {
		var data:NoteData = note.data;
		var line:StrumLine = lineOf(data);
		var singer:Character = data.gfNote ? gf : ((line != null) ? line.cameraCharacter() : dad);
		var result:Dynamic = callOnLuas('opponentNoteHitPre', [-1, data.column, data.type, data.isSustain()]);
		if (notStopped(result))
			result = callOnHScript('opponentNoteHitPre', [cbArg(note)]);
		if (result == LuaUtils.Function_Stop)
			return;

		if (songName != 'tutorial')
			camZooming = true;

		if (data.type == 'Hey!' && singer != null && singer.hasAnimation('hey')) {
			singer.playAnim('hey', true);
			singer.specialAnim = true;
			singer.heyTimer = 0.6;
		} else if (!data.noAnimation)
			singChar(singer, data, null);

		if (opponentVocals.length <= 0)
			vocals.volume = 1;
		strumPlayAnim((line != null) ? line.receptors : opponentReceptors, data.column, Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		data.hitByOpponent = true;

		result = callOnLuas('opponentNoteHit', [-1, data.column, data.type, data.isSustain()]);
		if (notStopped(result))
			callOnHScript('opponentNoteHit', [cbArg(note)]);
		fireStageNote(1, note);

		var f:NoteField = (line != null && line.field != null) ? line.field : opponentField;
		if (!data.isSustain())
			f.remove(note);
		else
			f.freeHead(note); // sustain: drop the head, keep the trail scrolling (matches legacy)
	}

	// NoteSystem V2 -- `noteArg` is an ActiveNote internally, or a legacy note object in compatibilityMode.
	function goodNoteHit(noteArg:Dynamic):Void {
		var note:ActiveNote = asActiveNote(noteArg);
		if (note == null)
			return;
		var data:NoteData = note.data;
		if (data.hit)
			return;
		if (cpuControlled && data.ignore)
			return;

		var isSus:Bool = data.isSustain();
		var leData:Int = data.column;
		var leType:String = data.type;

		var result:Dynamic = callOnLuas('goodNoteHitPre', [-1, leData, leType, isSus]);
		if (notStopped(result))
			result = callOnHScript('goodNoteHitPre', [cbArg(note)]);
		if (result == LuaUtils.Function_Stop)
			return;

		data.hit = true;

		if (data.hitsoundVolume() > 0 && !data.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(data.hitsound), data.hitsoundVolume());

		if (!data.hitCausesMiss) {
			if (!data.noAnimation)
				singChar(data.gfNote ? gf : boyfriend, data, data.gfNote ? 'cheer' : 'hey');

			if (!cpuControlled) {
				var spr:Receptor = playerReceptors[data.column];
				if (spr != null)
					spr.playAnim('confirm', true);
			} else
				strumPlayAnim(playerReceptors, data.column, Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			vocals.volume = 1;

				combo++;
				if (combo > 9999)
					combo = 9999;
				popUpScore(data);
			var gainHealth:Bool = !(guitarHeroSustains && isSus);
			if (gainHealth)
				health += data.hitHealth * healthGain;
		} else {
			if (!data.noMissAnimation && data.type == 'Hurt Note' && boyfriend.hasAnimation('hurt')) {
				boyfriend.playAnim('hurt', true);
				boyfriend.specialAnim = true;
			}
			noteMiss(note);
			if (!data.splashDisabled && !isSus)
				splashOnColumn(data.column);
			return;
		}

		result = callOnLuas('goodNoteHit', [-1, leData, leType, isSus]);
		if (notStopped(result))
			callOnHScript('goodNoteHit', [cbArg(note)]);
		fireStageNote(0, note);

		if (!isSus)
			playerField.remove(note);
		else
			playerField.freeHead(note);
	}

	// NoteSystem V2 -- `noteArg` is an ActiveNote internally, or a legacy note object in compatibilityMode.
	function noteMiss(noteArg:Dynamic):Void {
		var note:ActiveNote = asActiveNote(noteArg);
		if (note == null)
			return;
		var data:NoteData = note.data;
		if (data.missed)
			return;
		data.missed = true;

		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas('noteMiss', [-1, data.column, data.type, data.isSustain()]);
		if (notStopped(result))
			callOnHScript('noteMiss', [cbArg(note)]);
		fireStageNote(2, note);

		playerField.remove(note);
	}

	// Player let go of a hold before it finished -- miss the remainder and drop the trail.
	function sustainRelease(note:ActiveNote):Void {
		var data:NoteData = note.data;
		if (data.missed)
			return;
		data.missed = true;
		data.holdReleased = true;

		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas('noteMiss', [-1, data.column, data.type, true]);
		if (notStopped(result))
			callOnHScript('noteMiss', [cbArg(note, true)]);

		playerField.remove(note);
	}

	// Non-GH sustain: the head was missed but the trail stays catchable. Register the single head miss,
	// drop just the head sprite, and leave the entry alive so `updateSegmentedSustain` keeps judging the
	// body from the live hold state (matches the pre-v2 runtime where the head and each piece were
	// independent notes).
	function headMissForSustain(note:ActiveNote):Void {
		var data:NoteData = note.data;
		data.headMissed = true;
		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas('noteMiss', [-1, data.column, data.type, false]);
		if (notStopped(result))
			callOnHScript('noteMiss', [cbArg(note)]);
		fireStageNote(2, note);
		playerField.freeHead(note);
	}

	// Non-GH sustain per-frame judgement (human only; the bot uses the one-unit path in updateFields).
	// Walks the step-spaced body segments up to now -- a held segment restores health (no combo/score/
	// accuracy), a dropped one is a full miss -- keeps the receptor lit + character singing while held,
	// and reclaims the entry once the tail passes.
	function updateSegmentedSustain(note:ActiveNote, held:Bool):Void {
		var data:NoteData = note.data;
		var songPos:Float = Conductor.songPosition;
		var end:Float = data.endTime();

		if (data.nextTick < 0)
			data.nextTick = data.time + Conductor.stepCrochet;
		while (data.nextTick <= songPos && data.nextTick < end) {
			if (held)
				sustainSegmentHit(data);
			else
				sustainSegmentMiss(note);
			data.nextTick += Conductor.stepCrochet;
		}

		if (held) {
			var hc:Character = data.gfNote ? gf : boyfriend;
			if (hc != null) {
				hc.holdTimer = 0;
				hc.singHold = true;
			}
			var rec:Receptor = (data.column >= 0 && data.column < playerReceptors.length) ? playerReceptors[data.column] : null;
			if (rec != null) {
				if (rec.animation.curAnim == null || rec.animation.curAnim.name != 'confirm')
					rec.playAnim('confirm', true);
				rec.resetAnim = 0;
			}
			vocals.volume = 1;
		}

		if (songPos >= end)
			playerField.remove(note);
	}

	// A held body segment: health only, no combo/score/accuracy (the old non-GH model).
	inline function sustainSegmentHit(data:NoteData):Void {
		health += data.hitHealth * healthGain;
	}

	// A dropped body segment: a full miss, exactly like a missed sustain piece in the pre-v2 runtime.
	function sustainSegmentMiss(note:ActiveNote):Void {
		var data:NoteData = note.data;
		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas('noteMiss', [-1, data.column, data.type, true]);
		if (notStopped(result))
			callOnHScript('noteMiss', [cbArg(note, true)]);
		fireStageNote(2, note);
	}

	// NoteSystem V2
	function noteMissPress(direction:Int = 1):Void {
		if (ClientPrefs.data.ghostTapping)
			return;
		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		callOnScripts('noteMissPress', [direction]);
	}

	// NoteSystem V2
	function noteMissCommon(direction:Int, data:NoteData = null):Void {
		#if android
		if (ClientPrefs.data.vibration)
			extension.haptics.Haptic.vibrateOneShot(0.04, 1, 0.5);
		#end

		var subtract:Float = (data != null) ? data.missHealth : pressMissDamage;

		if (instakillOnMiss) {
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;

		health -= subtract * healthLoss;
		songScore -= 10;
		if (!endingSong)
			songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		var char:Character = boyfriend;
		if ((data != null && data.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection))
			char = gf;

		if (char != null && (data == null || !data.noMissAnimation) && char.hasMissAnimations) {
			var postfix:String = (data != null) ? data.animSuffix : '';
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, direction)))] + 'miss' + postfix;
			char.playAnim(animToPlay, true);
			if (char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad')) {
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		vocals.volume = 0;
	}

	// NoteSystem V2
	function splashOnColumn(col:Int):Void {
		var strum:Receptor = (col >= 0 && col < playerReceptors.length) ? playerReceptors[col] : null;
		if (strum != null)
			spawnNoteSplash(strum.x, strum.y, col, null, strum); // pass the receptor so it follows + centers (was misplaced)
	}

	// NoteSystem V2
	function popUpScore(data:NoteData):Void {
		var noteDiff:Float = Math.abs(data.time - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		vocals.volume = 1;

		if (!ClientPrefs.data.comboStacking && comboGroup.members.length > 0) {
			var i:Int = comboGroup.members.length;
			while (--i >= 0) {
				var spr = comboGroup.members[i];
				if (spr == null)
					continue;
				releasePopupSprite(spr);
			}
		}

		// All popup placement comes from the UI skin (anchor, per-element positions, digit spacing).
		var pl:UIPlacement = UISkinConfig.placement();
		var placement:Float = FlxG.width * pl.anchorX;
		var rating:FlxSprite = acquirePopupSprite();
		var score:Int = 350;

		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
		totalNotesHit += daRating.ratingMod;
		data.ratingMod = daRating.ratingMod;
		if (!data.ratingDisabled)
			daRating.hits++;
		data.rating = daRating.name;
		score = daRating.score;

		if (daRating.noteSplash && !data.splashDisabled)
			splashOnColumn(data.column);

		if (!cpuControlled) {
			songScore += score;
			if (!data.ratingDisabled) {
				songHits++;
				totalPlayed++;
				RecalculateRating(false);
			}
		}

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != "normal") {
			uiFolder = uiPrefix + "UI/";
			antialias = !isPixelStage;
		}

		// UI Skin: motion config per element (null = use the engine defaults below), and the *visual*
		// rating tier (a custom window-keyed image swap; scoring/combo already came from daRating).
		var twR:Dynamic = UISkinConfig.tweenFor('rating');
		var twC:Dynamic = UISkinConfig.tweenFor('combo');
		var twN:Dynamic = UISkinConfig.tweenFor('numbers');
		var vis:UIJudgement = UISkinConfig.pickVisual(noteDiff / playbackRate, daRating.name);

		var ratingFactor:Float = 1;
		var ratingImg = UISkinConfig.image(vis.image);
		if (ratingImg != null) {
			rating.loadGraphic(ratingImg.graphic);
			ratingFactor = ratingImg.factor;
		} else
			rating.loadGraphic(Paths.image(uiFolder + vis.image + uiPostfix));
		var ratingScaleMul:Float = (vis.scale != null) ? vis.scale : 1;
		rating.screenCenter();
		rating.x = placement + pl.rating[0];
		rating.y += pl.rating[1];
		rating.acceleration.y = UISkinConfig.tRange(twR, 'accelY', 550, 550) * playbackRate * playbackRate;
		rating.velocity.y -= UISkinConfig.tRange(twR, 'velocityY', 140, 175) * playbackRate;
		rating.velocity.x -= UISkinConfig.tRange(twR, 'velocityX', 0, 10) * playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.antialiasing = (vis.antialias != null) ? vis.antialias : antialias;

		var comboSpr:FlxSprite = acquirePopupSprite();
		var comboFactor:Float = 1;
		var comboImg = UISkinConfig.image('combo');
		if (comboImg != null) {
			comboSpr.loadGraphic(comboImg.graphic);
			comboFactor = comboImg.factor;
		} else
			comboSpr.loadGraphic(Paths.image(uiFolder + 'combo' + uiPostfix));
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = UISkinConfig.tRange(twC, 'accelY', 200, 300) * playbackRate * playbackRate;
		comboSpr.velocity.y -= UISkinConfig.tRange(twC, 'velocityY', 140, 160) * playbackRate;
		comboSpr.visible = (!ClientPrefs.data.hideHud && showCombo);
		comboSpr.antialiasing = antialias;
		comboSpr.y += pl.combo[1];
		comboSpr.velocity.x += UISkinConfig.tRange(twC, 'velocityX', 1, 10) * playbackRate;
		comboGroup.add(rating);

		if (!PlayState.isPixelStage) {
			rating.setGraphicSize(Std.int(rating.width * UISkinConfig.tFloat(twR, 'scale', 0.7) * ratingScaleMul * ratingFactor));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * UISkinConfig.tFloat(twC, 'scale', 0.7) * comboFactor));
		} else {
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (showCombo)
			comboGroup.add(comboSpr);

		var separatedScore:String = Std.string(combo).lpad('0', 3);
		for (i in 0...separatedScore.length) {
			var numScore:FlxSprite = acquirePopupSprite();
			var numFactor:Float = 1;
			var numImg = UISkinConfig.image('num' + Std.parseInt(separatedScore.charAt(i)));
			if (numImg != null) {
				numScore.loadGraphic(numImg.graphic);
				numFactor = numImg.factor;
			} else
				numScore.loadGraphic(Paths.image(uiFolder + 'num' + Std.parseInt(separatedScore.charAt(i)) + uiPostfix));
			numScore.screenCenter();
			numScore.x = placement + (pl.numSpacing * daLoop) + pl.numbers[0];
			numScore.y += pl.numbers[1];

			if (!PlayState.isPixelStage)
				numScore.setGraphicSize(Std.int(numScore.width * UISkinConfig.tFloat(twN, 'scale', 0.5) * numFactor));
			else
				numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = UISkinConfig.tRange(twN, 'accelY', 200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= UISkinConfig.tRange(twN, 'velocityY', 140, 160) * playbackRate;
			numScore.velocity.x = UISkinConfig.tRange(twN, 'velocityX', -5, 5) * playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			if (showComboNum)
				comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, UISkinConfig.tFloat(twN, 'duration', 0.2) / playbackRate, {
				ease: UISkinConfig.tEase(twN),
				onComplete: function(tween:FlxTween) {
					releasePopupSprite(numScore);
				},
				startDelay: UISkinConfig.tStartDelay(twN, Conductor.crochet * 0.002) / playbackRate
			});

			daLoop++;
			if (numScore.x > xThing)
				xThing = numScore.x;
		}
		comboSpr.x = xThing + pl.combo[0];
		FlxTween.tween(rating, {alpha: 0}, UISkinConfig.tFloat(twR, 'duration', 0.2) / playbackRate, {
			ease: UISkinConfig.tEase(twR),
			onComplete: function(tween:FlxTween) {
				releasePopupSprite(rating);
			},
			startDelay: UISkinConfig.tStartDelay(twR, Conductor.crochet * 0.001) / playbackRate
		});
		FlxTween.tween(comboSpr, {alpha: 0}, UISkinConfig.tFloat(twC, 'duration', 0.2) / playbackRate, {
			ease: UISkinConfig.tEase(twC),
			onComplete: function(tween:FlxTween) {
				releasePopupSprite(comboSpr);
			},
			startDelay: UISkinConfig.tStartDelay(twC, Conductor.crochet * 0.002) / playbackRate
		});
	}

	override function destroy() {
		if (noteCompat != null) {
			noteCompat.clear();
			noteCompat = null;
		}
		if (psychlua.CustomSubstate.instance != null) {
			closeSubState();
			resetSubState();
		}

		#if LUA_ALLOWED
		for (lua in luaArray) {
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = null;
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if (script != null) {
				if (script.exists('onDestroy'))
					script.call('onDestroy');
				script.destroy();
			}

		hscriptArray = null;
		#end
		stagesFunc(function(stage:BaseStage) stage.destroy());

		#if VIDEOS_ALLOWED
		if (videoCutscene != null) {
			videoCutscene.destroy();
			videoCutscene = null;
		}
		for (vid in precachedVideos)
			if (vid != null)
				vid.destroy();
		precachedVideos.clear();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		FlxG.camera.filters = []; #if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		FlxG.animationTimeScale = 1;

		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();

		// Multikey: restore the classic 4K globals so later states aren't left
		// using a previous song's keycount palette/anim tables.
		Mania.apply(Mania.DEFAULT);

		NoteSplash.configs.clear();
		instance = null;
		super.destroy();
	}

	var lastStepHit:Int = -1;

	override function stepHit() {
		super.stepHit();

		if (curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit() {
		if (lastBeatHit >= curBeat) {
			// trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		iconP1.scale.set(1.2, 1.2);
		iconP2.scale.set(1.2, 1.2);

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		characterBopper(curBeat);

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	public function characterBopper(beat:Int):Void {
		if (gf != null
			&& beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0
			&& !gf.getAnimationName().startsWith('sing')
			&& !gf.stunned)
			gf.dance();
		if (boyfriend != null
			&& beat % boyfriend.danceEveryNumBeats == 0
			&& !boyfriend.getAnimationName().startsWith('sing')
			&& !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void {
		var anim:String = boyfriend.getAnimationName();
		if (boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * boyfriend.singDuration
			&& anim.startsWith('sing') && !anim.endsWith('miss'))
			boyfriend.dance();
	}

	override function sectionHit() {
		if (SONG.notes[curSection] != null) {
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms) {
				FlxG.camera.zoom += 0.015 * camZoomingMult;
				camHUD.zoom += 0.03 * camZoomingMult;
			}

			if (SONG.notes[curSection].changeBPM) {
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}

			// Per-section scroll speed override (gated by changeScrollSpeed). Skipped
			// under the constant-speed mod, matching the Change Scroll Speed event.
			if (SONG.notes[curSection].changeScrollSpeed == true
				&& SONG.notes[curSection].scrollSpeed != null
				&& songSpeedType != "constant") {
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * SONG.notes[curSection].scrollSpeed;
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	/**
	 * Returns the files in a `scripts/` folder in load order.
	 *
	 * If the folder contains an order file -- `_order.txt` (checked first) or
	 * `_loadorder.txt` -- the script filenames listed in it load FIRST, in that
	 * exact order; every other file follows in the normal filesystem order. Blank
	 * lines and lines starting with `#` or `//` are ignored, matching is
	 * case-insensitive, and listed names that don't exist are skipped with a warning.
	 *
	 * With no order file present, the filesystem order is returned unchanged, so
	 * existing mods are unaffected.
	 */
	function getScriptLoadOrder(folder:String):Array<String> {
		var files:Array<String> = FileSystem.readDirectory(folder);

		var orderPath:String = folder + '_order.txt';
		if (!FileSystem.exists(orderPath)) {
			orderPath = folder + '_loadorder.txt';
			if (!FileSystem.exists(orderPath))
				return files; // no override -> keep filesystem order
		}

		// lowercase filename -> actual filename, for case-insensitive matching
		var lookup:Map<String, String> = new Map();
		for (file in files)
			lookup.set(file.toLowerCase(), file);

		var ordered:Array<String> = [];
		var used:Map<String, Bool> = new Map();
		for (rawLine in sys.io.File.getContent(orderPath).split('\n')) {
			var line:String = rawLine.trim();
			if (line.length == 0 || line.startsWith('#') || line.startsWith('//'))
				continue;

			var actual:String = lookup.get(line.toLowerCase());
			if (actual == null) {
				FlxG.log.warn('Script load order: "$line" listed in $orderPath was not found in $folder');
				continue;
			}
			if (!used.exists(actual)) {
				ordered.push(actual);
				used.set(actual, true);
			}
		}

		// everything not explicitly ordered keeps its filesystem position
		for (file in files)
			if (!used.exists(file))
				ordered.push(file);

		return ordered;
	}
	#end

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String) {
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if (!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getSharedPath(luaFile);

		if (FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getSharedPath(luaFile);
		if (OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if (script.scriptName == luaToLoad)
					return false;

			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String) {
		#if MODS_ALLOWED
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if (!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getSharedPath(scriptFile);
		#else
		var scriptToLoad:String = Paths.getSharedPath(scriptFile);
		#end

		if (FileSystem.exists(scriptToLoad)) {
			if (HScript.instances.exists(scriptToLoad))
				return false;

			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String) {
		// insanity.Script reports parse/exec errors through HScript's static
		// loggers instead of throwing, so we check `failed` rather than catch.
		var newScript:HScript = new HScript(null, file);
		if (newScript.failed) {
			newScript.destroy();
			return;
		}
		if (!newScript.blocked) {
			if (newScript.exists('onCreate'))
				newScript.call('onCreate');
			trace('initialized hscript interp successfully: $file');
		}
		hscriptArray.push(newScript);
	}
	#end

	// Read-only sentinels so per-call default arguments don't allocate.
	// Anything assigned EMPTY_EXCLUSIONS / DEFAULT_EXCLUDE_VALUES must NOT
	// be mutated -- the dispatchers below treat them as immutable.
	private static final EMPTY_EXCLUSIONS:Array<String> = [];
	private static final DEFAULT_EXCLUDE_VALUES:Array<Dynamic> = [LuaUtils.Function_Continue];

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		if (args == null)
			args = [];
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		if (excludeValues == null)
			excludeValues = DEFAULT_EXCLUDE_VALUES;

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if (result == null || excludeValues.contains(result))
			result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;
		#if LUA_ALLOWED
		if (args == null)
			args = [];
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		if (excludeValues == null)
			excludeValues = DEFAULT_EXCLUDE_VALUES;

		var arr:Array<FunkinLua> = null;
		for (script in luaArray) {
			if (script.closed) {
				if (arr == null) arr = [];
				arr.push(script);
				continue;
			}

			if (exclusions.contains(script.scriptName))
				continue;

			var myValue:Dynamic = script.call(funcToCall, args);
			if ((myValue == LuaUtils.Function_StopLua || myValue == LuaUtils.Function_StopAll)
				&& !excludeValues.contains(myValue)
				&& !ignoreStops) {
				returnVal = myValue;
				break;
			}

			if (myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if (script.closed) {
				if (arr == null) arr = [];
				arr.push(script);
			}
		}

		if (arr != null)
			for (script in arr)
				luaArray.remove(script);
		#end
		return returnVal;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = LuaUtils.Function_Continue;

		#if HSCRIPT_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		if (excludeValues == null)
			excludeValues = DEFAULT_EXCLUDE_VALUES;
		else if (!excludeValues.contains(LuaUtils.Function_Continue))
			excludeValues.push(LuaUtils.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;

		for (script in hscriptArray) {
			@:privateAccess
			if (script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var callValue = script.call(funcToCall, args);
			if (callValue != null) {
				var myValue:Dynamic = callValue.returnValue;

				if ((myValue == LuaUtils.Function_StopHScript || myValue == LuaUtils.Function_StopAll)
					&& !excludeValues.contains(myValue)
					&& !ignoreStops) {
					returnVal = myValue;
					break;
				}

				if (myValue != null && !excludeValues.contains(myValue))
					returnVal = myValue;
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		for (script in luaArray) {
			if (exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if (exclusions == null)
			exclusions = EMPTY_EXCLUSIONS;
		for (script in hscriptArray) {
			if (exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;

	public function RecalculateRating(badHit:Bool = false, scoreBop:Bool = true) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if (ret != LuaUtils.Function_Stop) {
			ratingName = '?';
			if (totalPlayed != 0) // Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				// trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length - 1][0]; // Uses last string
				if (ratingPercent < 1)
					for (i in 0...ratingStuff.length - 1)
						if (ratingPercent < ratingStuff[i][1]) {
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit, scoreBop); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null) {
		if (chartingMode)
			return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if (cpuControlled)
			return;

		for (name in achievesToCheck) {
			if (!Achievements.exists(name))
				continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch (name) {
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

					#if BASE_GAME_FILES
					case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
					#end
				}
			} else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if (isStoryMode
					&& campaignMisses + songMisses < 1
					&& Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1
					&& !changedDifficulty
					&& !usedPractice)
					unlock = true;
			}

			if (unlock)
				Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end

	public function createRuntimeShader(shaderName:String):ErrorHandledRuntimeShader {
		#if (!flash && sys)
		if (!ClientPrefs.data.shaders)
			return new ErrorHandledRuntimeShader(shaderName);

		if (!runtimeShaders.exists(shaderName) && !initLuaShader(shaderName)) {
			FlxG.log.warn('Shader $shaderName is missing!');
			return new ErrorHandledRuntimeShader(shaderName);
		}

		var arr:Array<String> = runtimeShaders.get(shaderName);
		return new ErrorHandledRuntimeShader(shaderName, arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120) {
		if (!ClientPrefs.data.shaders)
			return false;

		#if (!flash && sys)
		if (runtimeShaders.exists(name)) {
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/')) {
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if (FileSystem.exists(frag)) {
				frag = File.getContent(frag);
				found = true;
			} else
				frag = null;

			if (FileSystem.exists(vert)) {
				vert = File.getContent(vert);
				found = true;
			} else
				vert = null;

			if (found) {
				runtimeShaders.set(name, [frag, vert]);
				// trace('Found shader $name!');
				return true;
			}
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
		#else
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}
}
