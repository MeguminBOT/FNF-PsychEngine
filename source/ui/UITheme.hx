package ui;

/**
	The active UI palette + metric scale.

	Surfaces are neutral material-dark ramps; the brand accents are reserved for active/selected
	states only. All values are plain `0xAARRGGBB` ints so the library carries no framework color
	dependency. Widgets read these at `render()` time, so calling `changed()` after mutating any
	value (or `setScale`) re-skins every live widget through `UIRoot.invalidateAll`.
**/
final class UITheme {
	/** Window/backdrop — the darkest step of the neutral surface ramp. **/
	public static var bg:Int = 0xFF121214;

	/** Base panel surface (docks, scroll panes). **/
	public static var panel:Int = 0xFF1E1E21;

	/** Raised surface (buttons, chips, value boxes). **/
	public static var panel2:Int = 0xFF26262B;

	/** Highest surface (hover pills, active rows). **/
	public static var panel3:Int = 0xFF34343B;

	/** Card surface (grouped content blocks). **/
	public static var card:Int = 0xFF2C2C32;

	/** Text-input well (recessed). **/
	public static var inputBg:Int = 0xFF17171B;

	/** Standard 1px border. **/
	public static var border:Int = 0xFF3C3C44;

	/** Emphasized border (popups, focus-adjacent chrome). **/
	public static var border2:Int = 0xFF585864;

	/** Primary text. **/
	public static var text:Int = 0xFFE9E7EF;

	/** Secondary text (labels, inactive titles). **/
	public static var text2:Int = 0xFFB2B0BC;

	/** Tertiary text (hints, captions). **/
	public static var text3:Int = 0xFF7F7D8A;

	/** Primary brand accent — active/selected/primary states ONLY, never surfaces. **/
	public static var accent:Int = 0xFF8A5EE0;

	/** Darker accent fill (primary buttons, checked boxes). **/
	public static var accentDark:Int = 0xFF6B3FC4;

	/** Alternate accent hue (secondary emphasis). **/
	public static var accentAlt:Int = 0xFFC558D6;

	/** Bright accent tint (selection highlights). **/
	public static var highlight:Int = 0xFFE6AEEF;

	/** Positive state (enabled dots, confirmations). **/
	public static var success:Int = 0xFF63D68A;

	/** Destructive state (delete buttons, errors). **/
	public static var danger:Int = 0xFFF05C7C;

	/** Caution state. **/
	public static var warning:Int = 0xFFFFCA6E;

	/** Global UI density multiplier (user setting). Apply via `setScale`. **/
	public static var scale(default, null):Float = 1.0;

	/** Base corner radius, pre-scale. **/
	public static var radius:Float = 7;

	/** Fired after theme mutations; `UIRoot` assigns this to re-render every widget. **/
	public static var onChanged:Void->Void = null;

	/**
		Scales a base pixel metric by the global UI scale.
		@param base the design-size value (at scale 1)
		@return the scaled value
	**/
	public static inline function px(base:Float):Float {
		return base * scale;
	}

	/**
		Scales a base font size by the global UI scale.
		@param base the design font size (at scale 1)
		@return the scaled size, rounded to the nearest int
	**/
	public static inline function fs(base:Int):Int {
		return Std.int(base * scale + 0.5);
	}

	/**
		Sets the density multiplier and re-skins live widgets.
		@param value the new scale (> 0; no-op when unchanged)
	**/
	public static function setScale(value:Float):Void {
		if (value <= 0 || value == scale)
			return;
		scale = value;
		changed();
	}

	/** Notifies live widgets that theme values changed. **/
	public static function changed():Void {
		if (onChanged != null)
			onChanged();
	}

	/**
		Replaces every palette colour at once and re-skins live widgets.
		@param p the palette to adopt
	**/
	public static function apply(p:UIPalette):Void {
		bg = p.bg;
		panel = p.panel;
		panel2 = p.panel2;
		panel3 = p.panel3;
		card = p.card;
		inputBg = p.inputBg;
		border = p.border;
		border2 = p.border2;
		text = p.text;
		text2 = p.text2;
		text3 = p.text3;
		accent = p.accent;
		accentDark = p.accentDark;
		accentAlt = p.accentAlt;
		highlight = p.highlight;
		success = p.success;
		danger = p.danger;
		warning = p.warning;
		changed();
	}

	/**
		Recolours the whole accent family from one base hue (a custom-accent override on top of any
		preset), deriving the darker fill / bright highlight from it.
		@param base the accent colour (RGB; alpha forced opaque)
	**/
	public static function applyAccent(base:Int):Void {
		accent = 0xFF000000 | (base & 0xFFFFFF);
		accentDark = UIColor.darken(accent, 0.22);
		accentAlt = UIColor.lighten(accent, 0.12);
		highlight = UIColor.lighten(accent, 0.4);
		changed();
	}

	/** The built-in palettes, in menu order (the first is the default dark theme). **/
	public static final PRESETS:Array<UIThemePreset> = [
		{
			name: 'Dark',
			palette: {
				bg: 0xFF121214, panel: 0xFF1E1E21, panel2: 0xFF26262B, panel3: 0xFF34343B, card: 0xFF2C2C32,
				inputBg: 0xFF17171B, border: 0xFF3C3C44, border2: 0xFF585864, text: 0xFFE9E7EF, text2: 0xFFB2B0BC,
				text3: 0xFF7F7D8A, accent: 0xFF8A5EE0, accentDark: 0xFF6B3FC4, accentAlt: 0xFFC558D6,
				highlight: 0xFFE6AEEF, success: 0xFF63D68A, danger: 0xFFF05C7C, warning: 0xFFFFCA6E
			}
		},
		{
			name: 'Light',
			palette: {
				bg: 0xFFF1F1F5, panel: 0xFFE7E7ED, panel2: 0xFFDCDCE4, panel3: 0xFFCCCCD6, card: 0xFFFFFFFF,
				inputBg: 0xFFFFFFFF, border: 0xFFC2C2CC, border2: 0xFF9A9AA6, text: 0xFF1A1A22, text2: 0xFF4C4C58,
				text3: 0xFF86868F, accent: 0xFF7A4ED0, accentDark: 0xFF5F35B8, accentAlt: 0xFFB048C8,
				highlight: 0xFF9A6FE0, success: 0xFF2FA85E, danger: 0xFFD0435F, warning: 0xFFB9821A
			}
		},
		{
			name: 'Midnight',
			palette: {
				bg: 0xFF0C0E16, panel: 0xFF141826, panel2: 0xFF1C2133, panel3: 0xFF283048, card: 0xFF1A1F30,
				inputBg: 0xFF0F131F, border: 0xFF2C3350, border2: 0xFF465274, text: 0xFFE4E8F4, text2: 0xFFA8B0C8,
				text3: 0xFF6E7690, accent: 0xFF5A8CFF, accentDark: 0xFF3E63D6, accentAlt: 0xFF56C7E0,
				highlight: 0xFFA9C4FF, success: 0xFF63D68A, danger: 0xFFF05C7C, warning: 0xFFFFCA6E
			}
		},
		{
			name: 'Slate',
			palette: {
				bg: 0xFF1A1D22, panel: 0xFF23272E, panel2: 0xFF2C313A, panel3: 0xFF3A404B, card: 0xFF2A2F38,
				inputBg: 0xFF1D2026, border: 0xFF404650, border2: 0xFF5C6470, text: 0xFFE6E8EC, text2: 0xFFAEB4BE,
				text3: 0xFF7C828E, accent: 0xFF4CB0A0, accentDark: 0xFF388A7E, accentAlt: 0xFF6AC0D0,
				highlight: 0xFF8CD8CC, success: 0xFF63D68A, danger: 0xFFF05C7C, warning: 0xFFFFCA6E
			}
		}
	];
}

/** A full set of UI palette colours (see `UITheme.apply`). **/
typedef UIPalette = {
	bg:Int, panel:Int, panel2:Int, panel3:Int, card:Int, inputBg:Int,
	border:Int, border2:Int, text:Int, text2:Int, text3:Int,
	accent:Int, accentDark:Int, accentAlt:Int, highlight:Int,
	success:Int, danger:Int, warning:Int
};

/** A named palette for the theme picker. **/
typedef UIThemePreset = {
	name:String,
	palette:UIPalette
};
