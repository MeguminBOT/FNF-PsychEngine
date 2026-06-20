package psychlua;

import flixel.FlxBasic;
import objects.Character;
import psychlua.LuaUtils;
import psychlua.CustomSubstate;
#if LUA_ALLOWED
import psychlua.FunkinLua;
#end
#if HSCRIPT_ALLOWED
import insanity.Script;
import insanity.backend.Interp;
import insanity.Config.ConfigBlacklistKind;
import insanity.backend.Expr.ImportMode;

typedef HScriptInfos = {
	> haxe.PosInfos,
	var ?funcName:String;
	var ?showLine:Null<Bool>;
	#if LUA_ALLOWED
	var ?isLua:Null<Bool>;
	#end
}

// Result of calling a function inside an HScript.
// Mirrors the old crowplexus IrisCall shape so call sites are unchanged.
typedef HScriptCall = {
	var funName:String;
	var signature:Dynamic;
	var returnValue:Dynamic;
}

// Wraps an insanity.Script (formerly extended crowplexus.iris.Iris).
// The public surface (preset() globals, call/set/exists, the runHaxeCode
// Lua bridge, the `instances` registry and the static error/warn loggers)
// is kept identical so the rest of the engine doesn't need to know which
// interpreter backs it.
class HScript {
	public var script:Script;

	public var interp(get, never):Interp;
	inline function get_interp():Interp
		return (script != null ? script.interp : null);

	public var name:String; // registry key (script path or parent Lua name)
	public var filePath:String;
	public var modFolder:String;
	public var returnValue:Dynamic;
	public var scriptCode:String;

	public var origin:String;
	public var blocked:Bool = false;
	public var failed:Bool = false;

	// Replaces crowplexus Iris.instances -- lets PlayState/LoadingState/FunkinLua
	// check whether a script path is already running and fetch it by name.
	public static var instances:Map<String, HScript> = new Map();

	/**
	 * One-time setup of insanity's global scripting config. Mirrors
	 * ModSecurity.BLOCKED_CLASSES into insanity's type blacklist so that scripts
	 * resolving them through the Type/Reflect/Std proxies get null back -- the
	 * defense-in-depth equivalent of the old PatchIris macro. The primary gate
	 * (per-mod trust + source pattern scanning) still lives in ModSecurity and
	 * is interpreter-agnostic, so it is unaffected by the Iris -> insanity swap.
	 *
	 * Call once at boot (see Main.setupGame).
	 */
	public static function setupConfig():Void {
		// Use our interpreter so scripts can reference the creating state's
		// fields as bare identifiers (hscript-iris CustomInterp back-compat).
		insanity.Config.interpClass = PsychInterp;

		// Auto-import the state base classes so scripts can write
		// `class MyMenu extends MusicBeatState` without an explicit import.
		// insanity makes a class scriptable by registering its BASE class
		// (here backend.MusicBeatState -> the ScriptedMusicBeatState bridge), so
		// scripts extend the real base, not the bridge. insanity resolves bare
		// names through imports and these are packaged (backend.*), so import
		// each explicitly (a package IAll import skips packaged classes).
		insanity.Config.globalImports.set('backend.MusicBeatState', INormal);
		insanity.Config.globalImports.set('backend.MusicBeatSubstate', INormal);

		#if MODS_ALLOWED
		var byType:Array<String> = insanity.Config.blacklist.get(ByType);
		if (byType == null) {
			byType = [];
			insanity.Config.blacklist.set(ByType, byType);
		}
		for (name => _ in backend.ModSecurity.BLOCKED_CLASSES)
			if (name.indexOf('.') >= 0 && !byType.contains(name)) // fully-qualified names only
				byType.push(name);
		#end
	}

	#if LUA_ALLOWED
	public var parentLua:FunkinLua;

	public static function initHaxeModule(parent:FunkinLua) {
		if (parent.hscript == null) {
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent);
		}
	}

	public static function initHaxeModuleCode(parent:FunkinLua, code:String, ?varsToBring:Any = null) {
		var hs:HScript = try parent.hscript catch (e) null;
		if (hs == null) {
			trace('initializing haxe interp for: ${parent.scriptName}');
			parent.hscript = new HScript(parent, code, varsToBring);
		} else {
			hs.scriptCode = code;
			hs.varsToBring = varsToBring;
			hs.script.parse(code);
			hs.run();
		}
	}
	#end

	public function new(?parent:Dynamic, ?file:String, ?varsToBring:Any = null, ?manualRun:Bool = false) {
		if (file == null)
			file = '';

		filePath = file;
		if (filePath != null && filePath.length > 0) {
			this.origin = filePath;
			#if MODS_ALLOWED
			var myFolder:Array<String> = filePath.split('/');
			if (myFolder[0] + '/' == Paths.mods()
				&& (Mods.currentModDirectory == myFolder[1] || Mods.getGlobalMods().contains(myFolder[1]))) // is inside mods folder
				this.modFolder = myFolder[1];
			#end
		}

		#if MODS_ALLOWED
		// Security gate: standalone HScripts loaded from a blocked mod are not run.
		// HScripts spawned by a Lua parent inherit the parent's already-vetted trust state.
		if (parent == null && this.modFolder != null && backend.ModSecurity.isBlocked(this.modFolder)) {
			this.blocked = true;
			trace('HScript: blocked $file -- mod "${this.modFolder}" not trusted');
			return;
		}
		#end

		var scriptThing:String = file;
		var scriptName:String = null;
		if (parent == null && file != null) {
			var f:String = file.replace('\\', '/');
			if (f.contains('/') && !f.contains('\n')) {
				scriptThing = File.getContent(f);
				scriptName = f;
			}
		}
		#if LUA_ALLOWED
		if (scriptName == null && parent != null)
			scriptName = parent.scriptName;
		#end

		this.scriptCode = scriptThing;
		this.name = (scriptName != null ? scriptName : (origin != null ? origin : 'hscript'));

		script = new Script(scriptThing, this.name);
		hookErrors();
		// Bare-identifier access to the creating state's fields (back-compat).
		if (interp != null && (interp is PsychInterp))
			cast(interp, PsychInterp).parentInstance = FlxG.state;
		// insanity.Script parses in its constructor with the default (trace)
		// handler; re-parse so parse errors reach our debug-console logger.
		if (script.program == null)
			script.parse(scriptThing);

		#if LUA_ALLOWED
		parentLua = parent;
		if (parent != null) {
			this.origin = parent.scriptName;
			this.modFolder = parent.modFolder;
		}
		#end

		instances.set(this.name, this);

		this.varsToBring = varsToBring;

		if (!manualRun)
			run();
	}

	var _presetDone:Bool = false;

	/**
	 * Executes the parsed program. We deliberately bypass `insanity.Script.start()`
	 * because it calls `interp.setDefaults()` which WIPES the variables map -- that
	 * would erase every global we inject in `preset()`.
	 *
	 * setDefaults()/preset() run ONCE, on the first execution. Re-runs (e.g.
	 * `runHaxeCode` re-using a Lua parent's HScript) must NOT wipe, otherwise
	 * variables set between runs -- like classes added via `addHaxeLibrary` -- are
	 * lost before the new code executes.
	 */
	public function run():Dynamic {
		returnValue = null;
		if (script == null || script.program == null)
			return null;

		if (!_presetDone) {
			script.setDefaults(); // wipes variables + restores this/script/interp + Config globals
			preset(); // inject engine globals AFTER the wipe
			_presetDone = true;
		}
		applyVarsToBring();

		try {
			returnValue = interp.execute(script.program);
		} catch (e:haxe.Exception) {
			failed = true;
			returnValue = null;
			HScript.error('${e.message}', errorPos());
		}
		return returnValue;
	}

	function applyVarsToBring():Void {
		if (varsToBring == null)
			return;
		for (key in Reflect.fields(varsToBring)) {
			var k:String = key.trim();
			set(k, Reflect.field(varsToBring, k));
		}
	}

	function hookErrors() {
		script.onParsingError = function(e:haxe.Exception) {
			failed = true;
			HScript.error('${e.message}', errorPos());
		};
		script.onProgramError = function(e:haxe.Exception) {
			failed = true;
			HScript.error('${e.message}', errorPos());
		};
	}

	function errorPos(?funcName:String):HScriptInfos {
		var pos:HScriptInfos = (interp != null) ? cast interp.posInfos() : cast {fileName: this.name, showLine: false};
		if (funcName != null)
			pos.funcName = funcName;
		#if LUA_ALLOWED
		if (parentLua != null) {
			pos.isLua = true;
			if (parentLua.lastCalledFunction != '')
				pos.funcName = parentLua.lastCalledFunction;
		}
		#end
		return pos;
	}

	public var varsToBring:Any = null;

	public function set(name:String, value:Dynamic):Void {
		if (script != null)
			script.variables.set(name, value);
	}

	public function get(name:String):Dynamic
		return (script != null) ? script.variables.get(name) : null;

	public function exists(name:String):Bool
		return (script != null && script.variables.exists(name));

	function preset() {
		// Some very commonly used classes
		#if android
		set('File', mobile.backend.ScriptFile);
		set('FileSystem', mobile.backend.ScriptFileSystem);
		#elseif sys
		set('File', File);
		set('FileSystem', FileSystem);
		#end
		set('FlxG', flixel.FlxG);
		set('FlxMath', flixel.math.FlxMath);
		set('FlxSprite', flixel.FlxSprite);
		set('FlxText', flixel.text.FlxText);
		set('FlxCamera', flixel.FlxCamera);
		set('PsychCamera', backend.PsychCamera);
		set('FlxTimer', flixel.util.FlxTimer);
		set('FlxTween', flixel.tweens.FlxTween);
		set('FlxEase', flixel.tweens.FlxEase);
		set('FlxColor', CustomFlxColor);
		set('Countdown', backend.BaseStage.Countdown);
		set('PlayState', PlayState);
		set('Paths', Paths);
		set('Conductor', Conductor);
		set('ClientPrefs', ClientPrefs);
		#if ACHIEVEMENTS_ALLOWED
		set('Achievements', Achievements);
		#end
		set('Character', Character);
		set('Alphabet', Alphabet);
		set('Note', objects.Note);
		set('CustomSubstate', CustomSubstate);
		#if (!flash && sys)
		set('FlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
		set('ErrorHandledRuntimeShader', shaders.ErrorHandledShader.ErrorHandledRuntimeShader);
		#end
		set('ShaderFilter', openfl.filters.ShaderFilter);
		#if flixel_animate
		set('FlxAnimate', FlxAnimate);
		#end

		// Functions & Variables
		set('setVar', function(name:String, value:Dynamic) {
			MusicBeatState.getVariables().set(name, value);
			return value;
		});
		set('getVar', function(name:String) {
			var result:Dynamic = null;
			if (MusicBeatState.getVariables().exists(name))
				result = MusicBeatState.getVariables().get(name);
			return result;
		});
		set('removeVar', function(name:String) {
			if (MusicBeatState.getVariables().exists(name)) {
				MusicBeatState.getVariables().remove(name);
				return true;
			}
			return false;
		});
		set('debugPrint', function(text:String, ?color:FlxColor = null) {
			if (color == null)
				color = FlxColor.WHITE;
			PlayState.instance.addTextToDebug(text, color);
		});
		set('getModSetting', function(saveTag:String, ?modName:String = null) {
			if (modName == null) {
				if (this.modFolder == null) {
					HScript.error('getModSetting: Argument #2 is null and script is not inside a packed Mod folder!', errorPos());
					return null;
				}
				modName = this.modFolder;
			}
			return LuaUtils.getModSetting(saveTag, modName);
		});

		// Keyboard & Gamepads
		set('keyboardJustPressed', function(name:String) return Reflect.getProperty(FlxG.keys.justPressed, name));
		set('keyboardPressed', function(name:String) return Reflect.getProperty(FlxG.keys.pressed, name));
		set('keyboardReleased', function(name:String) return Reflect.getProperty(FlxG.keys.justReleased, name));

		set('anyGamepadJustPressed', function(name:String) return FlxG.gamepads.anyJustPressed(name));
		set('anyGamepadPressed', function(name:String) return FlxG.gamepads.anyPressed(name));
		set('anyGamepadReleased', function(name:String) return FlxG.gamepads.anyJustReleased(name));

		set('gamepadAnalogX', function(id:Int, ?leftStick:Bool = true) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
				return 0.0;

			return controller.getXAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		set('gamepadAnalogY', function(id:Int, ?leftStick:Bool = true) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
				return 0.0;

			return controller.getYAxis(leftStick ? LEFT_ANALOG_STICK : RIGHT_ANALOG_STICK);
		});
		set('gamepadJustPressed', function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
				return false;

			return Reflect.getProperty(controller.justPressed, name) == true;
		});
		set('gamepadPressed', function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
				return false;

			return Reflect.getProperty(controller.pressed, name) == true;
		});
		set('gamepadReleased', function(id:Int, name:String) {
			var controller = FlxG.gamepads.getByID(id);
			if (controller == null)
				return false;

			return Reflect.getProperty(controller.justReleased, name) == true;
		});

		set('keyJustPressed', function(name:String = '') {
			name = name.toLowerCase();
			switch (name) {
				case 'left':
					return Controls.instance.NOTE_LEFT_P;
				case 'down':
					return Controls.instance.NOTE_DOWN_P;
				case 'up':
					return Controls.instance.NOTE_UP_P;
				case 'right':
					return Controls.instance.NOTE_RIGHT_P;
				default:
					return Controls.instance.justPressed(name);
			}
			return false;
		});
		set('keyPressed', function(name:String = '') {
			name = name.toLowerCase();
			switch (name) {
				case 'left':
					return Controls.instance.NOTE_LEFT;
				case 'down':
					return Controls.instance.NOTE_DOWN;
				case 'up':
					return Controls.instance.NOTE_UP;
				case 'right':
					return Controls.instance.NOTE_RIGHT;
				default:
					return Controls.instance.pressed(name);
			}
			return false;
		});
		set('keyReleased', function(name:String = '') {
			name = name.toLowerCase();
			switch (name) {
				case 'left':
					return Controls.instance.NOTE_LEFT_R;
				case 'down':
					return Controls.instance.NOTE_DOWN_R;
				case 'up':
					return Controls.instance.NOTE_UP_R;
				case 'right':
					return Controls.instance.NOTE_RIGHT_R;
				default:
					return Controls.instance.justReleased(name);
			}
			return false;
		});

		// For adding your own callbacks
		// not very tested but should work
		#if LUA_ALLOWED
		set('createGlobalCallback', function(name:String, func:Dynamic) {
			for (script in PlayState.instance.luaArray)
				if (script != null && script.lua != null && !script.closed)
					Lua_helper.add_callback(script.lua, name, func);

			FunkinLua.customFunctions.set(name, func);
		});

		// this one was tested
		set('createCallback', function(name:String, func:Dynamic, ?funk:FunkinLua = null) {
			if (funk == null)
				funk = parentLua;

			if (funk != null)
				funk.addLocalCallback(name, func);
			else
				HScript.error('createCallback ($name): 3rd argument is null', errorPos());
		});
		#end

		set('addHaxeLibrary', function(libName:String, ?libPackage:String = '') {
			try {
				var str:String = '';
				if (libPackage.length > 0)
					str = libPackage + '.';

				set(libName, #if MODS_ALLOWED backend.ModSecurity.safeResolveClass(str + libName) #else Type.resolveClass(str + libName) #end);
			} catch (e:haxe.Exception) {
				HScript.error('${e.message}', errorPos());
			}
		});
		#if LUA_ALLOWED
		set('parentLua', parentLua);
		#else
		set('parentLua', null);
		#end
		set('this', this);
		set('game', FlxG.state);
		set('controls', Controls.instance);

		set('buildTarget', LuaUtils.getBuildTarget());
		set('customSubstate', CustomSubstate.instance);
		set('customSubstateName', CustomSubstate.name);

		// Class-based scripted states (states/<Name>.hx extending ScriptedMusicBeatState).
		set('switchToState', function(name:String, ?args:Array<Dynamic>) return scripting.ScriptedStates.switchToState(name, args));
		set('openScriptedSubstate', function(name:String, ?args:Array<Dynamic>) return scripting.ScriptedStates.openSubstate(name, args));
		set('exitToEngine', function() scripting.ScriptedStates.exitToEngine());
		set('launchMod', function(folder:String) return scripting.ScriptedStates.launchMod(folder));

		set('Function_Stop', LuaUtils.Function_Stop);
		set('Function_Continue', LuaUtils.Function_Continue);
		set('Function_StopLua', LuaUtils.Function_StopLua); // doesnt do much cuz HScript has a lower priority than Lua
		set('Function_StopHScript', LuaUtils.Function_StopHScript);
		set('Function_StopAll', LuaUtils.Function_StopAll);
	}

	#if LUA_ALLOWED
	public static function implement(funk:FunkinLua) {
		funk.addLocalCallback("runHaxeCode",
			function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
				initHaxeModuleCode(funk, codeToRun, varsToBring);
				if (funk.hscript != null) {
					final retVal:HScriptCall = funk.hscript.call(funcToRun, funcArgs);
					if (retVal != null) {
						return (LuaUtils.isLuaSupported(retVal.returnValue)) ? retVal.returnValue : null;
					} else if (funk.hscript.returnValue != null) {
						return funk.hscript.returnValue;
					}
				}
				return null;
			});

		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			if (funk.hscript != null) {
				final retVal:HScriptCall = funk.hscript.call(funcToRun, funcArgs);
				if (retVal != null) {
					return (LuaUtils.isLuaSupported(retVal.returnValue)) ? retVal.returnValue : null;
				}
			} else {
				var pos:HScriptInfos = cast {fileName: funk.scriptName, showLine: false};
				if (funk.lastCalledFunction != '')
					pos.funcName = funk.lastCalledFunction;
				HScript.error("runHaxeFunction: HScript has not been initialized yet! Use \"runHaxeCode\" to initialize it", pos);
			}
			return null;
		});
		// This function is unnecessary because import already exists in HScript as a native feature
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			var str:String = '';
			if (libPackage.length > 0)
				str = libPackage + '.';
			else if (libName == null)
				libName = '';

			var c:Dynamic = #if MODS_ALLOWED backend.ModSecurity.safeResolveClass(str + libName) #else Type.resolveClass(str + libName) #end;
			if (c == null)
				c = Type.resolveEnum(str + libName);

			if (funk.hscript == null)
				initHaxeModule(funk);

			// initHaxeModule may fail to assign funk.hscript (e.g. constructor
			// throws); without this guard the next line NPEs.
			if (funk.hscript == null)
				return;

			var pos:HScriptInfos = funk.hscript.errorPos();
			pos.showLine = false;
			if (funk.lastCalledFunction != '')
				pos.funcName = funk.lastCalledFunction;

			try {
				if (c != null)
					funk.hscript.set(libName, c);
			} catch (e:haxe.Exception) {
				HScript.error('${e.message}', pos);
			}
			FunkinLua.lastCalledScript = funk;
			if (FunkinLua.getBool('luaDebugMode') && FunkinLua.getBool('luaDeprecatedWarnings'))
				HScript.warn("addHaxeLibrary is deprecated! Import classes through \"import\" in HScript!", pos);
		});
	}
	#end

	public function call(funcToRun:String, ?args:Array<Dynamic>):HScriptCall {
		if (funcToRun == null || script == null)
			return null;

		if (!exists(funcToRun)) {
			HScript.error('No function named: $funcToRun', errorPos());
			return null;
		}

		try {
			var func:Dynamic = script.variables.get(funcToRun); // function signature
			if (!Reflect.isFunction(func)) {
				// `exists()` is true for any variable; calling a non-function
				// would throw a generic exception, so bail quietly instead.
				return null;
			}
			final ret = Reflect.callMethod(null, func, args ?? []);
			return {funName: funcToRun, signature: func, returnValue: ret};
		} catch (e:haxe.Exception) {
			HScript.error('${e.message}', errorPos(funcToRun));
		}
		return null;
	}

	public function destroy():Void {
		if (this.name != null && instances.get(this.name) == this)
			instances.remove(this.name);
		origin = null;
		#if LUA_ALLOWED parentLua = null; #end
		script = null;
	}

	// ___________________________ Debug-console logging ___________________________
	// Replaces the crowplexus Iris.error / Iris.warn / Iris.fatal hooks that
	// Main.hx used to wire up. Formats a position-aware message and mirrors it
	// to the in-game debug overlay.
	public static function error(x:String, ?pos:HScriptInfos):Void
		logToDebug('ERROR', x, pos, FlxColor.RED);

	public static function warn(x:String, ?pos:HScriptInfos):Void
		logToDebug('WARNING', x, pos, FlxColor.YELLOW);

	public static function fatal(x:String, ?pos:HScriptInfos):Void
		logToDebug('FATAL', x, pos, 0xFFBB0000);

	static function logToDebug(level:String, x:String, ?pos:HScriptInfos, color:FlxColor):Void {
		var newPos:HScriptInfos = (pos != null) ? pos : cast {fileName: 'hscript', showLine: false};
		if (newPos.showLine == null)
			newPos.showLine = true;
		var msgInfo:String = (newPos.funcName != null ? '(${newPos.funcName}) - ' : '') + '${newPos.fileName}:';
		#if LUA_ALLOWED
		if (newPos.isLua == true) {
			msgInfo += 'HScript:';
			newPos.showLine = true;
		}
		#end
		if (newPos.showLine == true)
			msgInfo += '${newPos.lineNumber}:';
		msgInfo += ' $x';
		trace('$level: $msgInfo');
		// Show on-screen in WHATEVER state is active (scripted menus included),
		// not just PlayState -- every MusicBeatState now has addTextToDebug.
		if (FlxG.state != null && (FlxG.state is backend.MusicBeatState))
			cast(FlxG.state, backend.MusicBeatState).addTextToDebug('$level: $msgInfo', color);
		else if (PlayState.instance != null)
			PlayState.instance.addTextToDebug('$level: $msgInfo', color);
	}
}

class CustomFlxColor {
	public static var TRANSPARENT(default, null):Int = FlxColor.TRANSPARENT;
	public static var BLACK(default, null):Int = FlxColor.BLACK;
	public static var WHITE(default, null):Int = FlxColor.WHITE;
	public static var GRAY(default, null):Int = FlxColor.GRAY;

	public static var GREEN(default, null):Int = FlxColor.GREEN;
	public static var LIME(default, null):Int = FlxColor.LIME;
	public static var YELLOW(default, null):Int = FlxColor.YELLOW;
	public static var ORANGE(default, null):Int = FlxColor.ORANGE;
	public static var RED(default, null):Int = FlxColor.RED;
	public static var PURPLE(default, null):Int = FlxColor.PURPLE;
	public static var BLUE(default, null):Int = FlxColor.BLUE;
	public static var BROWN(default, null):Int = FlxColor.BROWN;
	public static var PINK(default, null):Int = FlxColor.PINK;
	public static var MAGENTA(default, null):Int = FlxColor.MAGENTA;
	public static var CYAN(default, null):Int = FlxColor.CYAN;

	public static function fromInt(Value:Int):Int
		return cast FlxColor.fromInt(Value);

	public static function fromRGB(Red:Int, Green:Int, Blue:Int, Alpha:Int = 255):Int
		return cast FlxColor.fromRGB(Red, Green, Blue, Alpha);

	public static function fromRGBFloat(Red:Float, Green:Float, Blue:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromRGBFloat(Red, Green, Blue, Alpha);

	public static inline function fromCMYK(Cyan:Float, Magenta:Float, Yellow:Float, Black:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromCMYK(Cyan, Magenta, Yellow, Black, Alpha);

	public static function fromHSB(Hue:Float, Sat:Float, Brt:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromHSB(Hue, Sat, Brt, Alpha);

	public static function fromHSL(Hue:Float, Sat:Float, Light:Float, Alpha:Float = 1):Int
		return cast FlxColor.fromHSL(Hue, Sat, Light, Alpha);

	public static function fromString(str:String):Int
		return cast FlxColor.fromString(str);
}
#else
class HScript {
	#if LUA_ALLOWED
	public static function implement(funk:FunkinLua) {
		funk.addLocalCallback("runHaxeCode",
			function(codeToRun:String, ?varsToBring:Any = null, ?funcToRun:String = null, ?funcArgs:Array<Dynamic> = null):Dynamic {
				PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
				return null;
			});
		funk.addLocalCallback("runHaxeFunction", function(funcToRun:String, ?funcArgs:Array<Dynamic> = null) {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
		funk.addLocalCallback("addHaxeLibrary", function(libName:String, ?libPackage:String = '') {
			PlayState.instance.addTextToDebug('HScript is not supported on this platform!', FlxColor.RED);
			return null;
		});
	}
	#end
}
#end
