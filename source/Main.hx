package;

#if mobile
import mobile.backend.StorageUtil;
#end
#if android
import extension.haptics.Haptic;
#end
import debug.FPSCounter;
import flixel.graphics.FlxGraphic;
import flixel.FlxGame;
import flixel.FlxState;
import haxe.io.Path;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import lime.app.Application;
import states.TitleState;
#if (linux || mac)
import lime.graphics.Image;
#end
#if desktop
import backend.ALSoftConfig; // Just to make sure DCE doesn't remove this, since it's not directly referenced anywhere else.
#end
// crash handler stuff
#if CRASH_HANDLER
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.io.Path;
#end
import backend.Highscore;

// NATIVE API STUFF, YOU CAN IGNORE THIS AND SCROLL //
#if (linux && !debug)
@:cppInclude('./external/gamemode_client.h')
@:cppFileCode('#define GAMEMODE_AUTO')
#end
// // // // // // // // //
class Main extends Sprite {
	public static final game = {
		width: 1280, // WINDOW width
		height: 720, // WINDOW height
		initialState: TitleState, // initial game state
		framerate: 60, // default framerate
		skipSplash: true, // if the default flixel splash screen should be skipped
		startFullscreen: false // if the game should start at fullscreen mode
	};

	public static var fpsVar:FPSCounter;

	// You can pretty much ignore everything from here on - your code should go in your states.

	public static function main():Void {
		Lib.current.addChild(new Main());
	}

	public function new() {
		super();

		#if (cpp && windows)
		backend.Native.fixScaling();
		#end

		// Mobile storage: point the engine at a public, file-manager-browsable folder
		// (/storage/emulated/0/PsychEngine) so users can add mods/read saves freely.
		// Credits to MAJigsaw77 (he's the og author for the original android code)
		#if mobile
		#if android
		StorageUtil.requestPermissions();
		Haptic.initialize();
		#end
		StorageUtil.prepareDirectories();
		Sys.setCwd(StorageUtil.getStorageDirectory());
		#end
		#if VIDEOS_ALLOWED
		hxvlc.util.Handle.init(#if (hxvlc >= "1.8.0") ['--no-lua'] #end);
		#end

		#if LUA_ALLOWED
		Mods.pushGlobalMods();
		#end
		Mods.loadTopMod();

		FlxG.save.bind('funkin', CoolUtil.getSavePath());
		Highscore.load();

		// HScript error/warn/fatal logging is handled by psychlua.HScript's
		// static loggers (they mirror messages to the in-game debug overlay).
		#if HSCRIPT_ALLOWED
		psychlua.HScript.setupConfig();
		#end

		Controls.instance = new Controls();
		ClientPrefs.loadDefaultKeys();
		flixel.FlxSprite.defaultAntialiasing = ClientPrefs.data.antialiasing;
		#if ACHIEVEMENTS_ALLOWED Achievements.load(); #end
		addChild(new FlxGame(game.width, game.height, game.initialState, game.framerate, game.framerate, game.skipSplash, game.startFullscreen));

		#if android
		// Without this the OS handles Back (minimise/close) before we can read it.
		FlxG.signals.postGameStart.addOnce(() -> FlxG.android.preventDefaultKeys = [flixel.input.android.FlxAndroidKey.BACK]);
		#end

		#if !mobile
		fpsVar = new FPSCounter(10, 3, 0xFFFFFF);
		addChild(fpsVar);
		Lib.current.stage.align = "tl";
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		if (fpsVar != null) {
			fpsVar.visible = DebugPrefs.data.showFPS;
		}
		#end

		#if (linux || mac) // fix the app icon not showing up on the Linux Panel / Mac Dock
		var icon = Image.fromFile("icon.png");
		Lib.current.stage.window.setIcon(icon);
		#end

		#if html5
		FlxG.autoPause = false;
		FlxG.mouse.visible = false;
		#end

		FlxG.fixedTimestep = false;
		FlxG.game.focusLostFramerate = 60;
		FlxG.keys.preventDefaultKeys = [TAB];

		#if CRASH_HANDLER
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
		#end

		#if DISCORD_ALLOWED
		DiscordClient.prepare();
		#end

		// shader coords fix
		FlxG.signals.gameResized.add(function(w, h) {
			if (FlxG.cameras != null) {
				for (cam in FlxG.cameras.list) {
					if (cam != null && cam.filters != null)
						resetSpriteCache(cam.flashSprite);
				}
			}

			if (FlxG.game != null)
				resetSpriteCache(FlxG.game);
		});

		// Scripted-state setup: runs right BEFORE a scripted state's create(), so
		// the state is mod-sandboxed and has a camera even if the script never calls
		// super.create(). A scripted state carries the mod it was loaded from in
		// `scriptOwnerMod` (set by scripting.ScriptedStates).
		FlxG.signals.preStateCreate.add(function(state:flixel.FlxState) {
			#if HSCRIPT_ALLOWED
			// Only SCRIPTED states need this prep (compiled states set up their own
			// camera in super.create()). Detect them by the scriptable bridge base
			// class -- NOT by scriptOwnerMod: a bare-root global script
			// (mods/states/X.hx) has no owning mod but STILL needs a guaranteed
			// camera. Without it, it renders/updates against whatever camera the
			// previous state left -- fine coming from a menu, but a torn-down camera
			// when returned to from gameplay -> update()/draw() null-ref.
			if (state != null && (state is scripting.ScriptedMusicBeatState)) {
				var st:backend.MusicBeatState = cast state;
				#if MODS_ALLOWED
				// Re-establish the mod context for EVERY scripted state -- including
				// bare-root global ones (scriptOwnerMod == null -> '' = no mod, just
				// global mods + shared). This must run for ALL of them, not only
				// mod-owned ones: leaving the previous (gameplay) state's mod context
				// in place left a bare-root menu's interpreter pointing at torn-down
				// global state, so its NEXT update() null-ref'd. Mod-owned states
				// additionally scope to their own folder.
				backend.Mods.currentModDirectory = (st.scriptOwnerMod != null) ? st.scriptOwnerMod : '';
				backend.Mods.pushGlobalMods();
				#end
				// Guarantee a camera before the (possibly super-less) create().
				st.initPsychCamera();
			}
			#end
		});
	}

	static function resetSpriteCache(sprite:Sprite):Void {
		@:privateAccess {
			sprite.__cacheBitmap = null;
			sprite.__cacheBitmapData = null;
		}
	}

	// Code was entirely made by sqirra-rng for their fnf engine named "Izzy Engine", big props to them!!!
	// very cool person for real they don't get enough credit for their work
	#if CRASH_HANDLER
	function onCrash(e:UncaughtErrorEvent):Void {
		var errMsg:String = "";
		var path:String;
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();

		dateNow = dateNow.replace(" ", "_");
		dateNow = dateNow.replace(":", "'");

		path = "./crash/" + "PsychEngine_" + dateNow + ".txt";

		for (stackItem in callStack) {
			switch (stackItem) {
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += "\nUncaught Error: " + e.error;
		// remove if you're modding and want the crash log message to contain the link
		// please remember to actually modify the link for the github page to report the issues to.
		errMsg += "\nPlease report this error to the GitHub page: https://github.com/MeguminBOT/FNF-PsychEngine";
		errMsg += "\n\n> Crash Handler written by: sqirra-rng";

		if (!FileSystem.exists("./crash/"))
			FileSystem.createDirectory("./crash/");

		File.saveContent(path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));

		#if mobile
		// Desktop-style modal alert isn't reliable on mobile; the saved log file (and
		// logcat via the println above) is what matters there.
		#if android
		try extension.androidtools.widget.Toast.makeText('Crashed -- log saved to crash/', extension.androidtools.widget.Toast.LENGTH_LONG) catch (_:Dynamic) {}
		#end
		#else
		Application.current.window.alert(errMsg, "Error!");
		#end
		#if DISCORD_ALLOWED
		DiscordClient.shutdown();
		#end
		Sys.exit(1);
	}
	#end
}
