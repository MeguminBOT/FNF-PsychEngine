package ui.widgets;

import openfl.text.TextField;
import openfl.text.TextFormatAlign;
import ui.UIColor;
import ui.UIComponent;
import ui.UIFonts;
import ui.UILocale;
import ui.UIRoot;
import ui.UITheme;

/**
	A labelled numeric `- value +` row: label left, stepper box right. Clicking -/+ changes by
	`step`, clamped to [min, max]; holding repeats after a delay with acceleration. Clicking
	the value itself types a number directly (Enter/blur commits, Escape cancels).
	`onChange(value)` fires on every change; `decimals` controls display rounding.
**/
final class UIStepper extends UIComponent implements ui.input.IUIFocusable {
	public var key(default, set):String = null;
	public var fallback:String = "";
	public var label(default, set):String;

	public var value(default, set):Float;
	public var step:Float = 1;
	public var min:Float = -1e15;
	public var max:Float = 1e15;
	public var decimals:Int = 0;

	/** Text appended after the value (e.g. " ms", "X", "%"); rendered in the box. **/
	public var suffix:String = "";
	public var onChange:Float->Void = null;
	public var fontSize(default, set):Int = 12;

	/** Width of the `- value +` box on the right. **/
	public var boxWidth:Float;

	final tf:TextField;
	final valueTf:TextField;

	var holdDir:Int = 0;
	var holdTime:Float = 0;
	var repeatInterval:Float = 140;

	var editing:Bool = false;
	var editBuffer:String = "";
	var cancelEdit:Bool = false;

	/**
		@param label the row text on the left
		@param width layout width (the stepper box sits at the right edge)
		@param value the initial value
		@param step the per-click delta
		@param onChange fired on every value change (clicks, holds and typed commits)
	**/
	public function new(label:String, width:Float, value:Float, step:Float = 1, ?onChange:Float->Void) {
		super(true, true);
		this.label = label;
		@:bypassAccessor this.value = value;
		this.step = step;
		this.onChange = onChange;
		boxWidth = UITheme.px(88);
		tf = UIFonts.make(UITheme.fs(fontSize), UITheme.text2);
		addChild(tf);
		valueTf = UIFonts.make(UITheme.fs(fontSize), UITheme.text, TextFormatAlign.CENTER);
		valueTf.autoSize = openfl.text.TextFieldAutoSize.NONE;
		addChild(valueTf);
		resize(width, UITheme.px(24));
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

	/**
		Applies a delta and notifies `onChange`.
		@param dir -1 or +1 (0 is ignored)
		@param multiplier scales the step for accelerated input
	**/
	public function bump(dir:Int, multiplier:Float = 1):Void {
		if (!enabled || dir == 0)
			return;
		var next:Float = value + dir * step * multiplier;
		var factor:Float = Math.pow(10, decimals);
		next = Math.round(next * factor) / factor;
		if (next < min)
			next = min;
		if (next > max)
			next = max;
		if (next == value)
			return;
		@:bypassAccessor value = next;
		invalidate();
		if (onChange != null)
			onChange(value);
	}

	override function onPress(localX:Float, localY:Float):Void {
		var dir:Int = zoneAt(localX);
		if (dir == 0) {
			if (localX >= w - boxWidth)
				ui.input.UIFocus.set(this);
			return;
		}
		bump(dir);
		holdDir = dir;
		holdTime = -500; // initial delay before auto-repeat kicks in
		repeatInterval = 140;
		UIRoot.addTicker(tick);
		beginCapture();
	}

	override function onDragEnd():Void {
		holdDir = 0;
		UIRoot.removeTicker(tick);
	}

	function tick(dtMs:Float):Void {
		if (holdDir == 0 || !pressed) {
			UIRoot.removeTicker(tick);
			return;
		}
		holdTime += dtMs;
		while (holdTime >= repeatInterval) {
			holdTime -= repeatInterval;
			bump(holdDir);
			// accelerate the longer the button is held
			repeatInterval *= 0.92;
			if (repeatInterval < 28)
				repeatInterval = 28;
		}
	}

	public function capturesKeyboard():Bool {
		return editing;
	}

	public function onFocusGained():Void {
		editing = true;
		cancelEdit = false;
		editBuffer = "";
		invalidate();
	}

	public function onFocusLost():Void {
		if (!cancelEdit && editBuffer.length > 0) {
			var parsed:Float = Std.parseFloat(editBuffer);
			if (!Math.isNaN(parsed)) {
				var factor:Float = Math.pow(10, decimals);
				parsed = Math.round(parsed * factor) / factor;
				if (parsed < min)
					parsed = min;
				if (parsed > max)
					parsed = max;
				if (parsed != value) {
					@:bypassAccessor value = parsed;
					if (onChange != null)
						onChange(value);
				}
			}
		}
		editing = false;
		editBuffer = "";
		invalidate();
	}

	public function onKeyDown(keyCode:Int, charCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool {
		if (!editing)
			return false;
		switch (keyCode) {
			case 27: // escape
				cancelEdit = true;
				ui.input.UIFocus.clear(this);
			case 13: // enter
				ui.input.UIFocus.clear(this);
			case 8: // backspace
				if (editBuffer.length > 0)
					editBuffer = editBuffer.substr(0, editBuffer.length - 1);
				invalidate();
			default:
				var ch:String = null;
				if (keyCode >= 48 && keyCode <= 57)
					ch = String.fromCharCode(keyCode);
				else if (keyCode >= 96 && keyCode <= 105)
					ch = String.fromCharCode(keyCode - 48);
				else if (keyCode == 190 || keyCode == 188 || keyCode == 110)
					ch = '.';
				else if (keyCode == 189 || keyCode == 109)
					ch = '-';
				if (ch == '-') {
					editBuffer = editBuffer.startsWith('-') ? editBuffer.substr(1) : '-$editBuffer';
					invalidate();
				} else if (ch != null) {
					if (ch != '.' || editBuffer.indexOf('.') < 0)
						editBuffer += ch;
					invalidate();
				}
		}
		return true;
	}

	function zoneAt(localX:Float):Int {
		var bx:Float = w - boxWidth;
		if (localX < bx)
			return 0;
		var third:Float = boxWidth / 3;
		if (localX < bx + third)
			return -1;
		if (localX >= w - third)
			return 1;
		return 0;
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		g.beginFill(0, 0);
		g.drawRect(0, 0, w, h);
		g.endFill();

		var bx:Float = w - boxWidth;
		var r:Float = UITheme.px(6);
		var fill:Int = editing ? UITheme.inputBg : UITheme.panel2;
		if (hovered && !editing)
			fill = UIColor.lighten(fill, 0.06);
		g.beginFill(UIColor.rgb(fill));
		g.drawRoundRect(bx, 1, boxWidth, h - 2, r, r);
		g.endFill();
		g.lineStyle(1, UIColor.rgb(editing ? UITheme.accent : UITheme.border));
		g.drawRoundRect(bx + 0.5, 1.5, boxWidth - 1, h - 3, r, r);
		g.lineStyle();

		var mc:Int = UIColor.rgb(UITheme.text2);
		var cy:Float = h / 2;
		g.lineStyle(2, mc);
		g.moveTo(bx + UITheme.px(8), cy);
		g.lineTo(bx + UITheme.px(15), cy);
		g.moveTo(w - UITheme.px(15), cy);
		g.lineTo(w - UITheme.px(8), cy);
		g.moveTo(w - UITheme.px(11.5), cy - UITheme.px(3.5));
		g.lineTo(w - UITheme.px(11.5), cy + UITheme.px(3.5));
		g.lineStyle();

		UIFonts.restyle(tf, UITheme.fs(fontSize), UITheme.text2);
		var resolved:String = (key != null) ? UILocale.t(key, fallback) : label;
		if (tf.text != resolved)
			tf.text = resolved;
		tf.x = 0;
		tf.y = (h - tf.height) / 2;

		UIFonts.restyle(valueTf, UITheme.fs(fontSize), editing ? UITheme.highlight : UITheme.text, TextFormatAlign.CENTER);
		var text:String = editing ? (editBuffer.length > 0 ? editBuffer : "_") : formatValue();
		if (valueTf.text != text)
			valueTf.text = text;
		valueTf.width = boxWidth - UITheme.px(36);
		valueTf.height = valueTf.textHeight + 4;
		valueTf.x = bx + UITheme.px(18);
		valueTf.y = (h - valueTf.height) / 2;
	}

	function formatValue():String {
		var s:String;
		if (decimals <= 0)
			s = Std.string(Std.int(value));
		else {
			var factor:Float = Math.pow(10, decimals);
			s = Std.string(Math.round(value * factor) / factor);
		}
		return s + suffix;
	}

	override public function dispose():Void {
		ui.input.UIFocus.clear(this);
		UIRoot.removeTicker(tick);
		super.dispose();
	}

	function set_key(v:String):String {
		key = v;
		invalidate();
		return v;
	}

	function set_label(v:String):String {
		label = v;
		invalidate();
		return v;
	}

	function set_value(v:Float):Float {
		if (value == v)
			return v;
		value = v;
		invalidate();
		return v;
	}

	function set_fontSize(v:Int):Int {
		fontSize = v;
		invalidate();
		return v;
	}
}
