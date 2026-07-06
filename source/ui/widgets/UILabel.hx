package ui.widgets;

import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormatAlign;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UITheme;

/**
	A themed, non-interactive text label. `tone` picks the theme text ramp (0 = primary,
	1 = secondary, 2 = tertiary) so theme swaps restyle it; `colorOverride` pins an explicit
	ARGB color instead. Set `key` (+ `fallback`) for localized text, or assign `text` directly.
**/
final class UILabel extends UIComponent {
	/** Localization key; when set, `render()` resolves the text via `UILocale`. **/
	public var key(default, set):String = null;

	/** Fallback (and English source) for `key`. **/
	public var fallback:String = "";

	/** Raw text (used when `key` is null). **/
	public var text(default, set):String = "";

	/** 0 = theme.text, 1 = theme.text2, 2 = theme.text3. **/
	public var tone(default, set):Int = 0;

	/** Explicit ARGB color; overrides `tone` when != 0. **/
	public var colorOverride(default, set):Int = 0;

	/** Base (unscaled) font size. **/
	public var size(default, set):Int;

	public var align(default, set):TextFormatAlign;

	/** When `> 0`, the label word-wraps to this width (multi-line); `0` keeps the single-line auto-size. **/
	public var wrapWidth(default, set):Float = 0;

	final tf:TextField;

	/**
		@param text the initial raw text
		@param size base font size (scaled by the theme)
		@param tone theme text ramp: 0 = primary, 1 = secondary, 2 = tertiary
		@param align paragraph alignment (default LEFT)
	**/
	public function new(text:String = "", size:Int = 13, tone:Int = 0, ?align:TextFormatAlign) {
		super(false, false);
		this.size = size;
		this.tone = tone;
		this.align = (align != null) ? align : TextFormatAlign.LEFT;
		tf = UIFonts.make(UITheme.fs(size), resolveColor());
		addChild(tf);
		this.text = text;
		render();
	}

	/**
		Switches the label to a localized string.
		@param key the translation key
		@param fallback the source-language text
	**/
	public function localize(key:String, fallback:String):Void {
		this.fallback = fallback;
		this.key = key;
	}

	inline function resolveColor():Int {
		return (colorOverride != 0) ? colorOverride : switch (tone) {
			case 1: UITheme.text2;
			case 2: UITheme.text3;
			default: UITheme.text;
		};
	}

	override public function render():Void {
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : text;
		UIFonts.restyle(tf, UITheme.fs(size), resolveColor(), align);
		if (wrapWidth > 0) {
			tf.multiline = true;
			tf.wordWrap = true;
			tf.autoSize = TextFieldAutoSize.NONE;
			tf.width = wrapWidth;
			if (tf.text != resolved)
				tf.text = resolved;
			w = wrapWidth;
			h = tf.textHeight + 4;
			tf.height = h;
		} else {
			tf.multiline = false;
			tf.wordWrap = false;
			tf.autoSize = TextFieldAutoSize.LEFT;
			if (tf.text != resolved)
				tf.text = resolved;
			w = tf.width;
			h = tf.height;
		}
	}

	function set_wrapWidth(v:Float):Float {
		if (wrapWidth == v)
			return v;
		wrapWidth = v;
		invalidate();
		return v;
	}

	/**
		Forces an immediate (re)layout so `w`/`h` are valid right now instead of on the next frame.
		Use before positioning sibling widgets below a wrapped label in a flow layout, where the
		deferred render would otherwise report a stale (often zero) height.
		@return the measured height
	**/
	public function measure():Float {
		render();
		return h;
	}

	function set_key(v:String):String {
		key = v;
		invalidate();
		return v;
	}

	function set_text(v:String):String {
		if (text == v)
			return v;
		text = v;
		invalidate();
		return v;
	}

	function set_tone(v:Int):Int {
		tone = v;
		invalidate();
		return v;
	}

	function set_colorOverride(v:Int):Int {
		colorOverride = v;
		invalidate();
		return v;
	}

	function set_size(v:Int):Int {
		size = v;
		invalidate();
		return v;
	}

	function set_align(v:TextFormatAlign):TextFormatAlign {
		align = v;
		invalidate();
		return v;
	}
}
