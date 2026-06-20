package mobile.backend;

#if android
import lime.app.Application;
import lime.ui.KeyCode;
import lime.ui.KeyModifier;

/**
 * On-screen keyboard capture for custom text fields that read raw input (e.g. the
 * Freeplay/Mods search box), which PsychUIInputText's per-instance hook doesn't cover.
 * open() pops the keyboard and routes typed text / backspace / done(enter/esc) to callbacks.
 */
class SoftKeyboard
{
	static var onText:String->Void;
	static var onBackspace:Void->Void;
	static var onClose:Void->Void;
	static var active:Bool = false;

	public static function open(text:String->Void, backspace:Void->Void, close:Void->Void):Void
	{
		final window = Application.current.window;
		if (window == null)
			return;
		onText = text;
		onBackspace = backspace;
		onClose = close;
		if (!active)
		{
			window.onTextInput.add(handleText);
			window.onKeyDown.add(handleKey);
			active = true;
		}
		window.textInputEnabled = true;
	}

	public static function close():Void
	{
		final window = Application.current.window;
		if (active && window != null)
		{
			window.onTextInput.remove(handleText);
			window.onKeyDown.remove(handleKey);
			window.textInputEnabled = false;
		}
		active = false;
		onText = null;
		onBackspace = null;
		onClose = null;
	}

	static function handleText(input:String):Void
	{
		if (onText != null)
			onText(input);
	}

	static function handleKey(code:KeyCode, modifier:KeyModifier):Void
	{
		switch (code)
		{
			case BACKSPACE: if (onBackspace != null) onBackspace();
			case RETURN | NUMPAD_ENTER | ESCAPE: if (onClose != null) onClose();
			default:
		}
	}
}
#end
