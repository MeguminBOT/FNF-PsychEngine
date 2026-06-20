package substates;

#if MODS_ALLOWED
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import backend.Mods;

/**
 * In-menu editor for a mod's pack.json. Opened from ModsMenuState (P key).
 *
 * Edits a live copy of the parsed pack object and writes the whole thing back
 * via Mods.savePack on close, so keys this UI doesn't surface (custom fields,
 * features, changelog, etc.) are preserved. Fields cover the common, behaviour-
 * affecting metadata; free-text fields use an inline type-to-edit mode.
 *
 * Restart-affecting fields (`runsGlobally`, `type`) are compared against their
 * original values and reported to the parent so it can flag a game restart --
 * the global-mod set is computed at boot (Mods.pushGlobalMods).
 */
class PackSettingsSubState extends MusicBeatSubstate {
	static inline final PANEL_W:Int = 760;
	static inline final PANEL_H:Int = 560;
	static inline final BORDER:Int = 3;
	static inline final ROW_H:Int = 40;
	static inline final ROW_TOP:Int = 86;

	// Field kinds.
	static inline final K_STR:Int = 0;
	static inline final K_BOOL:Int = 1;
	static inline final K_CHOICE:Int = 2;
	static inline final K_INT:Int = 3;
	static inline final K_COLOR:Int = 4; // stored as pack.color [r,g,b], edited as hex

	static final TYPE_CHOICES:Array<String> = ['(none)', 'modpack', 'scriptpack'];

	var folder:String;
	var onClose:String->Bool->Void;
	var pack:Dynamic;

	// Original values for restart-detection.
	var origGlobal:Bool;
	var origType:String;

	// Field descriptors (key, label, kind).
	var keys:Array<String> = [];
	var labels:Array<String> = [];
	var kinds:Array<Int> = [];

	var rows:Array<FlxText> = [];
	var curField:Int = 0;

	// Inline text-edit state.
	var editing:Bool = false;
	var editBuffer:String = '';

	var px:Float;
	var py:Float;

	var titleTxt:FlxText;
	var hintTxt:FlxText;

	public function new(folder:String, ?onClose:String->Bool->Void) {
		super();
		this.folder = folder;
		this.onClose = onClose;
		var p:Dynamic = Mods.getPack(folder);
		this.pack = (p != null) ? p : {};

		origGlobal = (Reflect.field(pack, 'runsGlobally') == true);
		origType = Std.string(Reflect.field(pack, 'type'));

		defineFields();
	}

	function defineFields():Void {
		inline function addField(key:String, label:String, kind:Int) {
			keys.push(key);
			labels.push(label);
			kinds.push(kind);
		}
		addField('name', 'Name', K_STR);
		addField('description', 'Description', K_STR);
		addField('type', 'Type', K_CHOICE);
		addField('runsGlobally', 'Runs Globally', K_BOOL);
		addField('restart', 'Restart On Toggle', K_BOOL);
		addField('entryState', 'Entry State', K_STR);
		addField('menuMusic', 'Menu Music', K_STR);
		addField('iconFramerate', 'Icon Framerate', K_INT);
		addField('color', 'Color (hex RGB)', K_COLOR);
	}

	override function create():Void {
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end

		var bg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0.78;
		bg.scrollFactor.set();
		add(bg);

		px = (FlxG.width - PANEL_W) * 0.5;
		py = (FlxG.height - PANEL_H) * 0.5;

		var border = new FlxSprite(px - BORDER, py - BORDER).makeGraphic(1, 1, 0xFFFFD24A);
		border.scale.set(PANEL_W + BORDER * 2, PANEL_H + BORDER * 2);
		border.updateHitbox();
		border.scrollFactor.set();
		add(border);

		var panel = new FlxSprite(px, py).makeGraphic(1, 1, 0xFF14161E);
		panel.scale.set(PANEL_W, PANEL_H);
		panel.updateHitbox();
		panel.alpha = 0.96;
		panel.scrollFactor.set();
		add(panel);

		var headerBar = new FlxSprite(px, py).makeGraphic(1, 1, 0xFF1F2230);
		headerBar.scale.set(PANEL_W, 60);
		headerBar.updateHitbox();
		headerBar.scrollFactor.set();
		add(headerBar);

		titleTxt = new FlxText(px + 18, py + 14, PANEL_W - 36, 'Pack Settings -- "$folder"', 22);
		titleTxt.setFormat(Paths.font("vcr.ttf"), 22, 0xFFFFD24A, LEFT, OUTLINE, FlxColor.BLACK);
		titleTxt.borderSize = 1.5;
		titleTxt.scrollFactor.set();
		add(titleTxt);

		for (i in 0...keys.length) {
			var t = new FlxText(px + 22, py + ROW_TOP + i * ROW_H, PANEL_W - 44, '', 18);
			t.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			t.borderSize = 1.25;
			t.scrollFactor.set();
			add(t);
			rows.push(t);
		}

		hintTxt = new FlxText(px, py + PANEL_H - 30, PANEL_W, '', 14);
		hintTxt.setFormat(Paths.font("vcr.ttf"), 14, 0xFFB0B0B0, CENTER, OUTLINE, FlxColor.BLACK);
		hintTxt.borderSize = 1;
		hintTxt.scrollFactor.set();
		add(hintTxt);

		refreshRows();
	}

	function valueString(i:Int):String {
		var key = keys[i];
		switch (kinds[i]) {
			case K_BOOL:
				return (Reflect.field(pack, key) == true) ? 'ON' : 'OFF';
			case K_CHOICE:
				var v = Std.string(Reflect.field(pack, key));
				return (v == null || v == 'null' || v.length == 0) ? '(none)' : v;
			case K_INT:
				var v = Reflect.field(pack, key);
				return (v == null) ? '0' : Std.string(Std.int(v));
			case K_COLOR:
				return colorHex();
			default: // K_STR
				var v = Reflect.field(pack, key);
				return (v == null) ? '' : Std.string(v);
		}
	}

	function refreshRows():Void {
		for (i in 0...rows.length) {
			var sel = (i == curField);
			var val = (editing && sel) ? (editBuffer + '_') : valueString(i);
			rows[i].text = (sel ? '> ' : '  ') + labels[i] + ': ' + val;
			rows[i].color = sel ? (editing ? 0xFF66FF66 : FlxColor.YELLOW) : FlxColor.WHITE;
		}
		hintTxt.text = editing ? 'Type to edit -- ENTER confirm, ESC cancel'
			: 'UP/DOWN field   LEFT/RIGHT change   ENTER edit/toggle   ESC save & close';
	}

	// ── color helpers (pack.color is an [r,g,b] Int array) ──
	function colorArray():Array<Int> {
		var c:Dynamic = Reflect.field(pack, 'color');
		if (c != null && (c is Array)) {
			var a:Array<Dynamic> = c;
			return [intAt(a, 0, 170), intAt(a, 1, 0), intAt(a, 2, 255)];
		}
		return [170, 0, 255];
	}

	inline function intAt(a:Array<Dynamic>, i:Int, def:Int):Int
		return (i < a.length && a[i] != null) ? Std.int(a[i]) : def;

	function colorHex():String {
		var c = colorArray();
		return StringTools.hex(c[0], 2) + StringTools.hex(c[1], 2) + StringTools.hex(c[2], 2);
	}

	function commitColorHex(hex:String):Void {
		hex = StringTools.trim(hex);
		if (hex.length != 6)
			return; // ignore malformed entry, keep previous color
		var r = Std.parseInt('0x' + hex.substr(0, 2));
		var g = Std.parseInt('0x' + hex.substr(2, 2));
		var b = Std.parseInt('0x' + hex.substr(4, 2));
		if (r == null || g == null || b == null)
			return;
		Reflect.setField(pack, 'color', [r, g, b]);
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);

		if (editing) {
			handleEditInput();
			return;
		}

		if (controls.BACK) {
			saveAndClose();
			return;
		}

		if (controls.UI_UP_P) {
			curField = (curField - 1 + keys.length) % keys.length;
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			refreshRows();
		} else if (controls.UI_DOWN_P) {
			curField = (curField + 1) % keys.length;
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			refreshRows();
		}

		if (controls.UI_LEFT_P)
			changeValue(-1);
		else if (controls.UI_RIGHT_P)
			changeValue(1);

		if (controls.ACCEPT)
			activateField();
	}

	function activateField():Void {
		switch (kinds[curField]) {
			case K_BOOL:
				changeValue(1);
			case K_STR, K_COLOR:
				editing = true;
				editBuffer = (kinds[curField] == K_COLOR) ? colorHex() : valueString(curField);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
				refreshRows();
			default:
				changeValue(1);
		}
	}

	function changeValue(dir:Int):Void {
		var key = keys[curField];
		switch (kinds[curField]) {
			case K_BOOL:
				Reflect.setField(pack, key, !(Reflect.field(pack, key) == true));
			case K_CHOICE:
				var cur = valueString(curField);
				var idx = TYPE_CHOICES.indexOf(cur);
				if (idx < 0)
					idx = 0;
				idx = (idx + dir + TYPE_CHOICES.length) % TYPE_CHOICES.length;
				var chosen = TYPE_CHOICES[idx];
				if (chosen == '(none)')
					Reflect.deleteField(pack, key);
				else
					Reflect.setField(pack, key, chosen);
			case K_INT:
				var v:Int = (Reflect.field(pack, key) == null) ? 0 : Std.int(Reflect.field(pack, key));
				v += dir;
				if (v < 0)
					v = 0;
				else if (v > 240)
					v = 240;
				Reflect.setField(pack, key, v);
			default:
				return; // strings/colors are edited via type mode
		}
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refreshRows();
	}

	function handleEditInput():Void {
		var k:Int = FlxG.keys.firstJustPressed();
		if (k <= 0)
			return;

		if (k == 13) { // enter -> commit
			commitEdit();
			return;
		}
		if (k == 27) { // escape -> cancel
			editing = false;
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.5);
			refreshRows();
			return;
		}
		if (k == 8) { // backspace
			if (editBuffer.length > 0)
				editBuffer = editBuffer.substr(0, editBuffer.length - 1);
		} else if (kinds[curField] == K_COLOR) {
			// hex only, max 6 chars
			if (editBuffer.length < 6 && ((k >= 48 && k <= 57) || (k >= 65 && k <= 70)))
				editBuffer += String.fromCharCode(k);
		} else {
			// free text: letters (case via shift), digits, space, a few symbols
			if (k == 32)
				editBuffer += ' ';
			else if (k >= 65 && k <= 90)
				editBuffer += FlxG.keys.pressed.SHIFT ? String.fromCharCode(k) : String.fromCharCode(k).toLowerCase();
			else if (k >= 48 && k <= 57)
				editBuffer += String.fromCharCode(k);
			else if (k == 189 || k == 45)
				editBuffer += '-';
			else if (k == 190)
				editBuffer += '.';
			else
				return;
		}
		refreshRows();
	}

	function commitEdit():Void {
		var key = keys[curField];
		if (kinds[curField] == K_COLOR)
			commitColorHex(editBuffer);
		else
			Reflect.setField(pack, key, editBuffer);
		editing = false;
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		refreshRows();
	}

	function saveAndClose():Void {
		Mods.savePack(folder, pack);
		var needsRestart:Bool = (origGlobal != (Reflect.field(pack, 'runsGlobally') == true))
			|| (origType != Std.string(Reflect.field(pack, 'type')));
		FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		if (onClose != null)
			onClose(folder, needsRestart);
		close();
	}
}
#end
