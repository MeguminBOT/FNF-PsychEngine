package backend;

import flixel.input.gamepad.FlxGamepadButton;
import flixel.input.gamepad.FlxGamepadInputID;
import flixel.input.gamepad.mappings.FlxGamepadMapping;
import flixel.input.keyboard.FlxKey;

class Controls {
	// Keeping same use cases on stuff for it to be easier to understand/use
	// I'd have removed it but this makes it a lot less annoying to use in my opinion
	// You do NOT have to create these variables/getters for adding new keys,
	// but you will instead have to use:
	//   controls.justPressed("ui_up")   instead of   controls.UI_UP
	// Dumb but easily usable code, or Smart but complicated? Your choice.
	// Also idk how to use macros they're weird as fuck lol
	// Pressed buttons (directions)
	public var UI_UP_P(get, never):Bool;
	public var UI_DOWN_P(get, never):Bool;
	public var UI_LEFT_P(get, never):Bool;
	public var UI_RIGHT_P(get, never):Bool;
	public var NOTE_UP_P(get, never):Bool;
	public var NOTE_DOWN_P(get, never):Bool;
	public var NOTE_LEFT_P(get, never):Bool;
	public var NOTE_RIGHT_P(get, never):Bool;

	private function get_UI_UP_P()
		return justPressed('ui_up');

	private function get_UI_DOWN_P()
		return justPressed('ui_down');

	private function get_UI_LEFT_P()
		return justPressed('ui_left');

	private function get_UI_RIGHT_P()
		return justPressed('ui_right');

	private function get_NOTE_UP_P()
		return justPressed('note_up');

	private function get_NOTE_DOWN_P()
		return justPressed('note_down');

	private function get_NOTE_LEFT_P()
		return justPressed('note_left');

	private function get_NOTE_RIGHT_P()
		return justPressed('note_right');

	// Held buttons (directions)
	public var UI_UP(get, never):Bool;
	public var UI_DOWN(get, never):Bool;
	public var UI_LEFT(get, never):Bool;
	public var UI_RIGHT(get, never):Bool;
	public var NOTE_UP(get, never):Bool;
	public var NOTE_DOWN(get, never):Bool;
	public var NOTE_LEFT(get, never):Bool;
	public var NOTE_RIGHT(get, never):Bool;

	private function get_UI_UP()
		return pressed('ui_up');

	private function get_UI_DOWN()
		return pressed('ui_down');

	private function get_UI_LEFT()
		return pressed('ui_left');

	private function get_UI_RIGHT()
		return pressed('ui_right');

	private function get_NOTE_UP()
		return pressed('note_up');

	private function get_NOTE_DOWN()
		return pressed('note_down');

	private function get_NOTE_LEFT()
		return pressed('note_left');

	private function get_NOTE_RIGHT()
		return pressed('note_right');

	// Released buttons (directions)
	public var UI_UP_R(get, never):Bool;
	public var UI_DOWN_R(get, never):Bool;
	public var UI_LEFT_R(get, never):Bool;
	public var UI_RIGHT_R(get, never):Bool;
	public var NOTE_UP_R(get, never):Bool;
	public var NOTE_DOWN_R(get, never):Bool;
	public var NOTE_LEFT_R(get, never):Bool;
	public var NOTE_RIGHT_R(get, never):Bool;

	private function get_UI_UP_R()
		return justReleased('ui_up');

	private function get_UI_DOWN_R()
		return justReleased('ui_down');

	private function get_UI_LEFT_R()
		return justReleased('ui_left');

	private function get_UI_RIGHT_R()
		return justReleased('ui_right');

	private function get_NOTE_UP_R()
		return justReleased('note_up');

	private function get_NOTE_DOWN_R()
		return justReleased('note_down');

	private function get_NOTE_LEFT_R()
		return justReleased('note_left');

	private function get_NOTE_RIGHT_R()
		return justReleased('note_right');

	// Pressed buttons (others)
	public var ACCEPT(get, never):Bool;
	public var BACK(get, never):Bool;
	public var PAUSE(get, never):Bool;
	public var RESET(get, never):Bool;

	private function get_ACCEPT()
		return justPressed('accept');

	private function get_BACK()
		return justPressed('back');

	private function get_PAUSE()
		return justPressed('pause');

	private function get_RESET()
		return justPressed('reset');

	// Gamepad & Keyboard stuff
	public var keyboardBinds:Map<String, Array<FlxKey>>;
	public var gamepadBinds:Map<String, Array<FlxGamepadInputID>>;

	public function justPressed(key:String):Bool {
		final kb = keyboardBinds[key];
		if (kb != null && FlxG.keys.anyJustPressed(kb)) {
			controllerMode = false;
			return true;
		}
		#if android
		if (key == 'back' && FlxG.android.justPressed.BACK) return true;
		#end
		#if mobile
		if (touchJustPressed(key)) return true;
		#end
		return _myGamepadJustPressed(gamepadBinds[key]);
	}

	public function pressed(key:String):Bool {
		final kb = keyboardBinds[key];
		if (kb != null && FlxG.keys.anyPressed(kb)) {
			controllerMode = false;
			return true;
		}
		#if mobile
		if (touchPressed(key)) return true;
		#end
		return _myGamepadPressed(gamepadBinds[key]);
	}

	public function justReleased(key:String):Bool {
		final kb = keyboardBinds[key];
		if (kb != null && FlxG.keys.anyJustReleased(kb)) {
			controllerMode = false;
			return true;
		}
		#if mobile
		if (touchJustReleased(key)) return true;
		#end
		return _myGamepadJustReleased(gamepadBinds[key]);
	}

	#if mobile
	// OR-in the active on-screen virtual gamepad so all existing control checks
	// (controls.UI_UP, ACCEPT, BACK, ...) work on touch without per-call-site changes.
	inline function touchTag(key:String):String
		return mobile.input.TouchPad.controlToTag.get(key);

	function touchJustPressed(key:String):Bool {
		final pad = mobile.input.TouchPad.current;
		final tag = touchTag(key);
		return pad != null && tag != null && pad.buttonJustPressed(tag);
	}

	function touchPressed(key:String):Bool {
		final pad = mobile.input.TouchPad.current;
		final tag = touchTag(key);
		return pad != null && tag != null && pad.buttonPressed(tag);
	}

	function touchJustReleased(key:String):Bool {
		final pad = mobile.input.TouchPad.current;
		final tag = touchTag(key);
		return pad != null && tag != null && pad.buttonJustReleased(tag);
	}
	#end

	public var controllerMode:Bool = false;

	private function _myGamepadJustPressed(keys:Array<FlxGamepadInputID>):Bool {
		if (keys == null) return false;
		final len:Int = keys.length;
		for (i in 0...len) {
			if (FlxG.gamepads.anyJustPressed(keys[i])) {
				controllerMode = true;
				return true;
			}
		}
		return false;
	}

	private function _myGamepadPressed(keys:Array<FlxGamepadInputID>):Bool {
		if (keys == null) return false;
		final len:Int = keys.length;
		for (i in 0...len) {
			if (FlxG.gamepads.anyPressed(keys[i])) {
				controllerMode = true;
				return true;
			}
		}
		return false;
	}

	private function _myGamepadJustReleased(keys:Array<FlxGamepadInputID>):Bool {
		if (keys == null) return false;
		final len:Int = keys.length;
		for (i in 0...len) {
			if (FlxG.gamepads.anyJustReleased(keys[i])) {
				controllerMode = true;
				return true;
			}
		}
		return false;
	}

	// IGNORE THESE
	public static var instance:Controls;

	public function new() {
		keyboardBinds = ClientPrefs.keyBinds;
		gamepadBinds = ClientPrefs.gamepadBinds;
	}
}
