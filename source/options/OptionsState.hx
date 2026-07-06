package options;

import flixel.FlxSprite;
import flixel.input.keyboard.FlxKey;
import openfl.display.Shape;
import openfl.text.TextField;
import backend.InputFormatter;
import backend.Mania;
import options.Option;
import options.Option.OptionType;
import options.OptionsCatalog;
import options.OptionsCatalog.OptionCategory;
import options.OptionsCatalog.OptionRow;
import states.MainMenuState;
import backend.StageData;
import ui.UIRoot;
import ui.UITheme;
import ui.UIFonts;
import ui.UILocale;
import ui.UIComponent;
import ui.UIColor;
import ui.UIFonts;
import ui.input.UIFocus;
import ui.input.IUIFocusable;
import ui.widgets.UIPanel;
import ui.widgets.UIScrollPane;
import ui.widgets.UILabel;
import ui.widgets.UIAccordion;
import ui.widgets.UIButton;
import ui.widgets.UICheckbox;
import ui.widgets.UIDropdown;
import ui.widgets.UIStepper;
import ui.widgets.UITextInput;
import ui.widgets.UIModal;
import ui.widgets.UITooltip;

/**
	The Options menu, built on the in-engine UI framework (`source/ui/`): a category rail on the left
	and a `UIScrollPane` of widget rows on the right. It reuses the `OptionsCatalog` + `Option` model
	verbatim - this state is only a *renderer*, mapping each `Option` to a `source/ui` widget - so the
	internal `ClientPrefs` names and behavior are unchanged.

	Specialized editors (Controls, Note Colours, Gameplay Changers, offset calibration, ...) still
	launch their existing substates from a launcher entry / action row.
**/
class OptionsState extends MusicBeatState {
	public static var onPlayState:Bool = false;

	static inline var RAIL_X:Int = 24;
	static inline var RAIL_W:Int = 250;
	static inline var CONTENT_X:Int = 290;
	static inline var CONTENT_W:Int = 966;
	static inline var PANEL_Y:Int = 72;
	static inline var PANEL_H:Int = 596;
	static inline var ROW_H:Int = 52;
	static inline var ROW_FONT:Int = 16;
	static inline var RAIL_FONT:Int = 17;

	var uiRoot:UIRoot;
	var categories:Array<OptionCategory> = [];
	var curCat:Int = 0;

	var railButtons:Array<UIButton> = [];
	var pane:UIScrollPane;
	var headerLabel:UILabel;
	var descLabel:UILabel;

	/** Collapsed sub-sections, keyed by `category/section`; absent = expanded. **/
	var collapsed:Map<String, Bool> = new Map();

	/** Set from a widget callback to rebuild the rows next frame (avoids disposing a widget mid-callback). **/
	var needsRebuild:Bool = false;

	/** Keyboard/controller focus depth: true = browsing the category rail, false = editing rows. **/
	var onSidebar:Bool = true;

	/** Selected index into `rowEntries` while editing rows. **/
	var curRow:Int = 0;

	/** The rendered, keyboard-focusable rows of the current category (settings, actions, section headers). **/
	var rowEntries:Array<RowEntry> = [];

	/** Selection background drawn behind the focused row, inside the scroll pane's content. **/
	var selHighlight:Shape;

	var hintLabel:UILabel;
	var searchInput:UITextInput;

	/** Current search query; when non-empty the pane shows matches across every category. **/
	var query:String = '';

	/** Whether the pause-music preview swapped the menu track (restored to freakyMenu on exit). **/
	var changedMusic:Bool = false;

	var holdTime:Float = 0;
	var holdValue:Float = 0;
	var nextAccept:Int = 0;

	/** Builds the background, the hosted UI root and the rail/pane chrome, then shows the first category. **/
	override function create():Void {
		backend.Mods.allowCurrentModAssets = true;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
		persistentUpdate = true;
		// Hardware cursor: the UI root sits above the flixel layer, so the software cursor draws under it.
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		categories = OptionsCatalog.build();
		wireDynamicOptions();

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.color = 0xFF1A1A2E;
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		UITooltip.install();
		FlxG.signals.gameResized.add(onGameResized);

		buildChrome();
		selectCategory(0);
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end
	}

	/** Layers the UI root above the game view but below the FPS counter (mirrors ChartingState). **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	/** Re-syncs the UI viewport when the game window is resized. **/
	function onGameResized(_:Int, _:Int):Void
		syncViewport();

	/** Maps the UI root over the game's letterboxed viewport so UI coordinates match game coordinates. **/
	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	/** Builds the static chrome: panels, title/header/hint labels, category rail and the scroll pane. **/
	function buildChrome():Void {
		var railPanel:UIPanel = new UIPanel(RAIL_W, PANEL_H, UITheme.panel);
		railPanel.x = RAIL_X;
		railPanel.y = PANEL_Y;
		uiRoot.content.addChild(railPanel);

		var contentPanel:UIPanel = new UIPanel(CONTENT_W, PANEL_H, UITheme.panel);
		contentPanel.x = CONTENT_X;
		contentPanel.y = PANEL_Y;
		uiRoot.content.addChild(contentPanel);

		var title:UILabel = new UILabel('OPTIONS', 30, 0);
		title.x = RAIL_X;
		title.y = 18;
		uiRoot.content.addChild(title);

		var searchW:Int = 340;
		searchInput = new UITextInput('', searchW, '', onSearchChanged);
		searchInput.fontSize = 15;
		searchInput.x = FlxG.width - 24 - searchW;
		searchInput.y = 22;
		uiRoot.content.addChild(searchInput);

		headerLabel = new UILabel('', 26, 0);
		headerLabel.x = CONTENT_X + 16;
		headerLabel.y = PANEL_Y + 12;
		uiRoot.content.addChild(headerLabel);

		descLabel = new UILabel('', 14, 2);
		descLabel.x = CONTENT_X + 16;
		descLabel.y = PANEL_Y + 46;
		uiRoot.content.addChild(descLabel);

		hintLabel = new UILabel('', 14, 2);
		hintLabel.x = RAIL_X;
		hintLabel.y = FlxG.height - 28;
		uiRoot.content.addChild(hintLabel);

		pane = new UIScrollPane(CONTENT_W - 16, PANEL_H - 84);
		pane.x = CONTENT_X + 8;
		pane.y = PANEL_Y + 72;
		uiRoot.content.addChild(pane);

		railButtons = [];
		for (i in 0...categories.length) {
			var idx:Int = i;
			var btn:UIButton = new UIButton(categories[i].name, RAIL_W - 20, 50, function() selectCategory(idx));
			btn.fontSize = RAIL_FONT;
			btn.x = RAIL_X + 10;
			btn.y = PANEL_Y + 16 + i * 58;
			uiRoot.content.addChild(btn);
			railButtons.push(btn);
		}
	}

	/**
		Selects a rail category: highlights it, updates the header/description and rebuilds its rows.
		@param i the category index
	**/
	function selectCategory(i:Int):Void {
		curCat = i;
		onSidebar = true;
		curRow = 0;
		rebuildRows();
		pane.setScroll(0);
		updateHint();
	}

	/** Clears the pane and rebuilds either the search matches or the current category's rows. **/
	function rebuildRows():Void {
		clearPane();
		rowEntries = [];
		selHighlight = new Shape();
		selHighlight.visible = false;
		pane.content.addChild(selHighlight); // sits behind the widgets added after it

		var innerW:Float = pane.w - 24;
		var y:Float = 8;

		if (query.length > 0)
			y = buildSearchRows(innerW, y);
		else
			y = buildCategoryRows(innerW, y);

		if (curRow >= rowEntries.length)
			curRow = rowEntries.length - 1;
		if (curRow < 0)
			curRow = 0;
		pane.refreshContent(y + 8);
		positionHighlight();
	}

	/** Fills the pane with settings/actions from every category matching the current query. **/
	function buildSearchRows(innerW:Float, y:Float):Float {
		var q:String = query.toLowerCase();
		for (cat in categories) {
			for (row in cat.rows) {
				switch (row) {
					case Setting(o):
						if (o.name.toLowerCase().indexOf(q) >= 0 || (o.description != null && o.description.toLowerCase().indexOf(q) >= 0))
							y = addSetting(o, innerW, y);
					case Action(name, desc, which):
						var label:String = Language.getPhrase('options_$name', name);
						if (label.toLowerCase().indexOf(q) >= 0 || (desc != null && desc.toLowerCase().indexOf(q) >= 0))
							y = addAction(name, desc, which, innerW, y);
					default:
				}
			}
		}
		headerLabel.text = 'Search';
		descLabel.text = (rowEntries.length == 0) ? 'No matches for "$query"' : '${rowEntries.length} result(s)';
		for (b in railButtons)
			b.accent = false;
		return y;
	}

	/** Fills the pane with the current category's rows, honouring collapsed sub-sections. **/
	function buildCategoryRows(innerW:Float, y:Float):Float {
		var sectionOpen:Bool = true; // rows before the first Section always show
		for (row in categories[curCat].rows) {
			switch (row) {
				case Section(title):
					var key:String = sectionKey(title);
					var isCollapsed:Bool = collapsed.exists(key) && collapsed.get(key);
					if (y > 8)
						y += 10;
					var acc:UIAccordion = new UIAccordion(title, innerW, !isCollapsed, function(expanded:Bool) {
						collapsed.set(key, !expanded);
						needsRebuild = true;
					});
					acc.x = 12;
					acc.y = y;
					pane.content.addChild(acc);
					rowEntries.push({kind: 2, y: y, h: 24, secTitle: title});
					y += 32;
					sectionOpen = !isCollapsed;

				case Setting(o):
					if (sectionOpen)
						y = addSetting(o, innerW, y);

				case Action(name, desc, which):
					if (sectionOpen)
						y = addAction(name, desc, which, innerW, y);
			}
		}
		headerLabel.text = categories[curCat].name;
		descLabel.text = (categories[curCat].desc != null) ? categories[curCat].desc : '';
		for (n in 0...railButtons.length)
			railButtons[n].accent = (n == curCat);
		return y;
	}

	/** Appends a Setting row (widget vertically centered in the row) and returns the next y. **/
	function addSetting(o:Option, innerW:Float, y:Float):Float {
		var wdg:UIComponent = makeWidget(o, innerW);
		wdg.x = 12;
		wdg.y = y + (ROW_H - wdg.h) / 2;
		pane.content.addChild(wdg);
		rowEntries.push({kind: 0, y: y, h: ROW_H - 6, option: o, widget: wdg});
		return y + ROW_H;
	}

	/** Appends an Action row (button + focus entry) and returns the next y. **/
	function addAction(name:String, desc:String, which:String, innerW:Float, y:Float):Float {
		var b:UIButton = new UIButton(Language.getPhrase('options_$name', name), innerW, 40, function() launch(which));
		b.fontSize = ROW_FONT;
		b.tooltip = desc;
		b.x = 12;
		b.y = y + (ROW_H - 40) / 2;
		pane.content.addChild(b);
		rowEntries.push({kind: 1, y: y, h: 40, which: which});
		return y + ROW_H;
	}

	/** The collapse-state map key for a section within the current category. **/
	inline function sectionKey(title:String):String
		return curCat + '/' + title;

	/** Disposes and removes every widget currently in the scroll pane. **/
	function clearPane():Void {
		var i:Int = pane.content.numChildren;
		while (--i >= 0) {
			var c = pane.content.getChildAt(i);
			if (c is UIComponent)
				(cast c : UIComponent).dispose();
		}
		pane.content.removeChildren();
	}

	// ---------------------------------------------------- keyboard / controller

	/** Keyboard / controller navigation: rail depth (categories) versus row depth (settings). **/
	function handleKeyboard(elapsed:Float):Void {
		if (FlxG.keys.justPressed.SLASH) {
			UIFocus.set(searchInput);
			return;
		}

		if (onSidebar) {
			if (controls.UI_UP_P)
				cycleCategory(-1);
			if (controls.UI_DOWN_P)
				cycleCategory(1);
			if ((controls.ACCEPT && nextAccept <= 0) || controls.UI_RIGHT_P) {
				nextAccept = 6;
				enterRows();
			}
			if (controls.BACK)
				exitState();
			return;
		}

		if (controls.UI_UP_P)
			moveRow(-1);
		if (controls.UI_DOWN_P)
			moveRow(1);
		if (rowEntries.length > 0)
			editFocused(elapsed);
		if (controls.BACK) {
			if (query.length > 0)
				clearSearch();
			else {
				onSidebar = true;
				positionHighlight();
				updateHint();
			}
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
		}
	}

	/** Search box edited: filter across all categories (an empty query restores the category view). **/
	function onSearchChanged(text:String):Void {
		query = StringTools.trim(text);
		onSidebar = (query.length == 0);
		curRow = 0;
		rebuildRows();
		pane.setScroll(0);
		updateHint();
	}

	/** Clears the search field and returns to the category view. **/
	function clearSearch():Void {
		query = '';
		searchInput.text = '';
		onSidebar = true;
		curRow = 0;
		rebuildRows();
		pane.setScroll(0);
		updateHint();
	}

	/** Updates the bottom hint line for the current focus depth. **/
	function updateHint():Void {
		hintLabel.text = onSidebar ? 'Up/Down  Category      Enter / Right  Open      /  Search      Esc  Exit' : 'Up/Down  Move      Left/Right  Change      Enter  Toggle / Open      Reset  Default      /  Search      Esc  Back';
	}

	/** Moves the rail selection by `dir` and shows that category. **/
	function cycleCategory(dir:Int):Void {
		selectCategory(FlxMath.wrap(curCat + dir, 0, categories.length - 1));
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	/** Enters the current category's rows from the rail (focuses the first row). **/
	function enterRows():Void {
		if (rowEntries.length == 0)
			return;
		onSidebar = false;
		curRow = 0;
		FlxG.sound.play(Paths.sound('scrollMenu'));
		positionHighlight();
		updateHint();
	}

	/** Moves the focused row by `dir`, wrapping and scrolling it into view. **/
	function moveRow(dir:Int):Void {
		if (rowEntries.length == 0)
			return;
		curRow = FlxMath.wrap(curRow + dir, 0, rowEntries.length - 1);
		holdTime = 0;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		positionHighlight();
	}

	/** True on a debounced confirm press (avoids re-triggering while ACCEPT is held). **/
	inline function accept():Bool {
		if (controls.ACCEPT && nextAccept <= 0) {
			nextAccept = 6;
			return true;
		}
		return false;
	}

	/** Handles Left/Right/Enter/Reset for the focused row. **/
	function editFocused(elapsed:Float):Void {
		var e:RowEntry = rowEntries[curRow];
		switch (e.kind) {
			case 2:
				if (accept())
					toggleSection(e.secTitle);
			case 1:
				if (accept())
					launch(e.which);
			default:
				var o:Option = e.option;
				switch (o.type) {
					case BOOL:
						if (accept()) {
							o.setValue(!(o.getValue() == true));
							o.change();
							syncWidget(e);
							FlxG.sound.play(Paths.sound('scrollMenu'));
							if (o.rebuildOnChange)
								needsRebuild = true;
						}
					case STRING:
						if (accept())
							cycleString(e, 1);
						else if (controls.UI_LEFT_P)
							cycleString(e, -1);
						else if (controls.UI_RIGHT_P)
							cycleString(e, 1);
					default:
						numericEdit(e, elapsed);
				}
				if (controls.RESET)
					resetOption(e);
		}
	}

	/** Cycles a STRING option's choice and updates its dropdown. **/
	function cycleString(e:RowEntry, dir:Int):Void {
		var o:Option = e.option;
		if (o.options == null || o.options.length == 0)
			return;
		o.curOption = FlxMath.wrap(o.curOption + dir, 0, o.options.length - 1);
		o.setValue(o.options[o.curOption]);
		o.change();
		var dd:UIDropdown = cast e.widget;
		dd.select(o.curOption);
		FlxG.sound.play(Paths.sound('scrollMenu'));
		if (o.rebuildOnChange)
			needsRebuild = true;
	}

	/** Steps a numeric option by keyboard, with press-to-step and hold-to-repeat acceleration. **/
	function numericEdit(e:RowEntry, elapsed:Float):Void {
		var o:Option = e.option;
		if (controls.UI_LEFT || controls.UI_RIGHT) {
			var pressed:Bool = (controls.UI_LEFT_P || controls.UI_RIGHT_P);
			if (holdTime > 0.5 || pressed) {
				var dir:Float = controls.UI_LEFT ? -1 : 1;
				if (pressed) {
					var cur:Float = o.getValue();
					var cv:Float = o.changeValue;
					holdValue = clampNum(o, cur + dir * cv);
					applyNum(e, holdValue);
					FlxG.sound.play(Paths.sound('scrollMenu'));
				} else {
					holdValue = clampNum(o, holdValue + o.scrollSpeed * elapsed * dir);
					applyNum(e, holdValue);
				}
			}
			holdTime += elapsed;
		} else if (controls.UI_LEFT_R || controls.UI_RIGHT_R) {
			if (holdTime > 0.5)
				FlxG.sound.play(Paths.sound('scrollMenu'));
			holdTime = 0;
		}
	}

	/** Writes a numeric value to the option (correctly rounded) and syncs the stepper display. **/
	function applyNum(e:RowEntry, v:Float):Void {
		setNum(e.option, v);
		e.option.change();
		syncWidget(e);
	}

	/** Clamps `v` into the option's min/max range. **/
	inline function clampNum(o:Option, v:Float):Float {
		if (o.minValue != null) {
			var mn:Float = o.minValue;
			if (v < mn)
				v = mn;
		}
		if (o.maxValue != null) {
			var mx:Float = o.maxValue;
			if (v > mx)
				v = mx;
		}
		return v;
	}

	/** Refreshes a row's widget display from its option value (fires no widget callbacks). **/
	function syncWidget(e:RowEntry):Void {
		var o:Option = e.option;
		switch (o.type) {
			case BOOL:
				var cb:UICheckbox = cast e.widget;
				cb.checked = (o.getValue() == true);
			case STRING:
				var dd:UIDropdown = cast e.widget;
				dd.select(o.curOption);
			default:
				var st:UIStepper = cast e.widget;
				var scale:Float = (o.type == PERCENT) ? 100 : 1;
				var gv:Float = o.getValue();
				st.value = gv * scale;
		}
	}

	/** Resets the focused option to its default and syncs the widget. **/
	function resetOption(e:RowEntry):Void {
		var o:Option = e.option;
		o.setValue(o.defaultValue);
		if (o.type == STRING && o.options != null)
			o.curOption = o.options.indexOf(Std.string(o.getValue()));
		o.change();
		syncWidget(e);
		FlxG.sound.play(Paths.sound('cancelMenu'));
		if (o.rebuildOnChange)
			needsRebuild = true;
	}

	/** Toggles a section's collapse state (from a focused accordion header). **/
	function toggleSection(title:String):Void {
		var key:String = sectionKey(title);
		var cur:Bool = collapsed.exists(key) && collapsed.get(key);
		collapsed.set(key, !cur);
		FlxG.sound.play(Paths.sound('scrollMenu'));
		needsRebuild = true;
	}

	/** Redraws the selection background under the focused row, or hides it on the rail. **/
	function positionHighlight():Void {
		if (selHighlight == null)
			return;
		var g = selHighlight.graphics;
		g.clear();
		if (onSidebar || curRow < 0 || curRow >= rowEntries.length) {
			selHighlight.visible = false;
			return;
		}
		var e:RowEntry = rowEntries[curRow];
		g.beginFill(UIColor.rgb(UITheme.panel3));
		g.drawRoundRect(8, e.y - 4, pane.w - 16, e.h + 8, 8, 8);
		g.endFill();
		selHighlight.visible = true;
		scrollToRow(e);
	}

	/** Scrolls the pane so the focused row is fully visible. **/
	function scrollToRow(e:RowEntry):Void {
		if (e.y < pane.scrollY)
			pane.setScroll(e.y - 8);
		else if (e.y + e.h > pane.scrollY + pane.h)
			pane.setScroll(e.y + e.h - pane.h + 8);
	}

	/** Maps a single `Option` to the matching `source/ui` widget, wired back to its get/set/change. **/
	function makeWidget(o:Option, width:Float):UIComponent {
		switch (o.type) {
			case BOOL:
				var cb:UICheckbox = new UICheckbox(o.name, width, o.getValue() == true, function(v:Bool) {
					o.setValue(v);
					o.change();
				});
				cb.fontSize = ROW_FONT;
				cb.tooltip = o.description;
				return cb;

			case STRING:
				var dd:UIDropdown = new UIDropdown(o.name, width, function(i:Int, val:String) {
					o.curOption = i;
					o.setValue(val);
					o.change();
					if (o.rebuildOnChange)
						needsRebuild = true;
				});
				dd.fontSize = ROW_FONT;
				if (o.options != null)
					dd.setItems(o.options);
				var sel:Int = (o.options != null) ? o.options.indexOf(Std.string(o.getValue())) : -1;
				dd.select(sel < 0 ? o.curOption : sel);
				dd.tooltip = o.description;
				return dd;

			default: // INT / FLOAT / PERCENT
				// PERCENT values are stored 0..1 but edited on a 0..100 scale so the box reads e.g. "60%".
				var isPercent:Bool = (o.type == PERCENT);
				var scale:Float = isPercent ? 100 : 1;
				var gv:Float = o.getValue();
				var cv:Float = o.changeValue;
				var st:UIStepper = new UIStepper(o.name, width, gv * scale, cv * scale, function(v:Float) {
					setNum(o, isPercent ? v / scale : v);
					o.change();
				});
				st.fontSize = ROW_FONT;
				if (o.minValue != null) {
					var mn:Float = o.minValue;
					st.min = mn * scale;
				}
				if (o.maxValue != null) {
					var mx:Float = o.maxValue;
					st.max = mx * scale;
				}
				st.decimals = isPercent ? 0 : ((o.type == INT) ? 0 : o.decimals);
				st.suffix = isPercent ? '%' : suffixOf(o.displayFormat);
				st.tooltip = o.description;
				return st;
		}
	}

	/**
		Writes a numeric value back to an option with the correct rounding for its type.
		@param o the option to update
		@param v the raw new value
	**/
	function setNum(o:Option, v:Float):Void {
		if (o.type == INT)
			o.setValue(Math.round(v));
		else
			o.setValue(FlxMath.roundDecimal(v, o.decimals));
	}

	/** Pulls the display unit out of an Option's displayFormat (text after `%v`, e.g. "ms", "X"). **/
	function suffixOf(fmt:String):String {
		if (fmt == null)
			return '';
		var i:Int = fmt.indexOf('%v');
		return (i < 0) ? '' : fmt.substr(i + 2);
	}

	/** Wires state-specific live behavior onto catalog options after they're built (pause-music preview). **/
	function wireDynamicOptions():Void {
		var pm:Option = findOption('pauseMusic');
		if (pm != null)
			pm.onChange = onChangePauseMusic;
	}

	/** Finds a built option by its `ClientPrefs` variable name, or null. **/
	function findOption(variable:String):Option {
		for (cat in categories)
			for (row in cat.rows)
				switch (row) {
					case Setting(o):
						if (o.variable == variable)
							return o;
					default:
				}
		return null;
	}

	/** Previews the chosen pause-music track by swapping the menu music (restored to freakyMenu on exit). **/
	function onChangePauseMusic():Void {
		if (ClientPrefs.data.pauseMusic == 'None') {
			if (FlxG.sound.music != null)
				FlxG.sound.music.volume = 0;
		} else
			FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)));
		changedMusic = true;
	}

	/**
		Opens the specialized editor for an Action row (a substate, or a state switch for calibration).
		@param which the editor id carried by the catalog Action
	**/
	function launch(which:String):Void {
		FlxG.sound.play(Paths.sound('confirmMenu'));
		ClientPrefs.saveSettings();
		switch (which) {
			case 'controls':
				openControlsModal();
			case 'noteColors':
				openSubState(new NotesColorSubState());
			case 'noteOffset':
				MusicBeatState.switchState(new NoteOffsetState());
			case 'fpsSettings':
				openOptionsModal(Language.getPhrase('fps_counter_menu', 'FPS Counter Settings'), FPSCounterSettingsSubState.buildOptions());
			#if TRANSLATIONS_ALLOWED
			case 'language':
				openSubState(new LanguageSubState());
			#end
			#if MODS_ALLOWED
			case 'modSecurity':
				openOptionsModal(Language.getPhrase('mod_security_checks_menu', 'Mod Security Checks'), ModSecurityChecksSubState.buildOptions(),
					ModSecurityChecksSubState.commit);
			#end
			#if mobile
			case 'mobile':
				openSubState(new mobile.options.MobileOptionsSubState());
			#end
			default:
		}
	}

	/**
		Opens an embedded modal that renders a flat option list as `source/ui` widgets - used for the
		list-only editors that don't need flixel sprites (FPS counter, Mod Security).
		@param title the modal title
		@param opts the options to render (each wired via `makeWidget`)
		@param onClose optional commit hook run when the modal closes (before the pref save)
	**/
	function openOptionsModal(title:String, opts:Array<Option>, ?onClose:Void->Void):Void {
		var mw:Float = 720;
		var mh:Float = 540;
		var modal:UIModal = new UIModal(title, mw, mh);
		var sp:UIScrollPane = new UIScrollPane(mw - 24, mh - 64);
		sp.x = 12;
		sp.y = 4;
		modal.body.addChild(sp);

		var innerW:Float = sp.w - 24;
		var y:Float = 6;
		for (o in opts) {
			var wdg:UIComponent = makeWidget(o, innerW);
			wdg.x = 12;
			wdg.y = y;
			sp.content.addChild(wdg);
			y += ROW_H;
		}
		sp.refreshContent(y + 8);

		modal.onClosed = function():Void {
			if (onClose != null)
				onClose();
			ClientPrefs.saveSettings();
			rebuildRows();
		};
		modal.open();
	}

	/** Opens the game-controls rebinder as an embedded modal (keyboard binds, two slots per action). **/
	function openControlsModal():Void {
		var mw:Float = 640;
		var mh:Float = 560;
		var modal:UIModal = new UIModal(Language.getPhrase('controls_menu', 'Controls'), mw, mh);

		var pane:UIScrollPane = new UIScrollPane(mw - 32, mh - UITheme.px(40) - 96);
		pane.x = 16;
		pane.y = 4;
		var innerW:Float = pane.w - 16;
		var rows:Array<ControlsBindRow> = [];
		var y:Float = 6;
		for (grp in controlGroups()) {
			var head:UILabel = new UILabel(grp.name.toUpperCase(), 10, 2);
			head.x = 4;
			head.y = y + 6;
			pane.content.addChild(head);
			y += UITheme.px(26);
			for (b in grp.binds) {
				var row:ControlsBindRow = new ControlsBindRow(b.id, b.label, innerW);
				row.x = 4;
				row.y = y;
				pane.content.addChild(row);
				rows.push(row);
				y += row.h + UITheme.px(4);
			}
			y += UITheme.px(6);
		}
		pane.refreshContent(y + 8);
		modal.body.addChild(pane);

		var afterPane:Float = pane.y + pane.h + 10;
		var hint:UILabel = new UILabel('Click Key 1 / Key 2, then press a key.  Backspace clears, Esc cancels.', 10, 2);
		hint.x = 16;
		hint.y = afterPane;
		modal.body.addChild(hint);

		var reset:UIButton = new UIButton(Language.getPhrase('controls_reset', 'Reset to Default'), 160, 28, function():Void {
			ClientPrefs.resetKeys(false);
			ClientPrefs.reloadVolumeKeys();
			for (r in rows)
				r.invalidate();
		});
		reset.x = 16;
		reset.y = afterPane + 22;
		modal.body.addChild(reset);

		var ok:UIButton = new UIButton('Close', 120, 28, modal.close, true);
		ok.x = mw - 136;
		ok.y = afterPane + 22;
		modal.body.addChild(ok);

		modal.onClosed = function():Void {
			ClientPrefs.reloadVolumeKeys();
			ClientPrefs.saveSettings();
		};
		modal.open();
	}

	/** The rebindable game-control groups shown in the controls modal (standard binds + per-keycount notes). **/
	function controlGroups():Array<{name:String, binds:Array<{id:String, label:String}>}> {
		var groups:Array<{name:String, binds:Array<{id:String, label:String}>}> = [
			{name: 'Notes', binds: [{id: 'note_left', label: 'Left'}, {id: 'note_down', label: 'Down'}, {id: 'note_up', label: 'Up'}, {id: 'note_right', label: 'Right'}]},
			{name: 'UI', binds: [{id: 'ui_left', label: 'Left'}, {id: 'ui_down', label: 'Down'}, {id: 'ui_up', label: 'Up'}, {id: 'ui_right', label: 'Right'}]},
			{name: 'General', binds: [{id: 'reset', label: 'Reset'}, {id: 'accept', label: 'Accept'}, {id: 'back', label: 'Back'}, {id: 'pause', label: 'Pause'}]},
			{name: 'Volume', binds: [{id: 'volume_mute', label: 'Mute'}, {id: 'volume_up', label: 'Up'}, {id: 'volume_down', label: 'Down'}]},
			{name: 'Debug', binds: [{id: 'debug_1', label: 'Debug Key #1'}, {id: 'debug_2', label: 'Debug Key #2'}]}
		];
		for (count in Mania.MIN...Mania.MAX + 1) {
			if (count == Mania.DEFAULT)
				continue;
			var binds:Array<{id:String, label:String}> = [];
			for (col in 0...count)
				binds.push({id: Mania.bindName(count, col), label: 'Key ${col + 1}'});
			groups.push({name: '${count}K Notes', binds: binds});
		}
		return groups;
	}

	/** Hides the UI root while a substate is open - substates render in the flixel layer beneath it. **/
	override public function openSubState(SubState:flixel.FlxSubState):Void {
		if (uiRoot != null)
			uiRoot.visible = false;
		super.openSubState(SubState);
	}

	/** Restores the UI root, saves, and rebuilds the rows since a substate may have changed values. **/
	override public function closeSubState():Void {
		super.closeSubState();
		if (uiRoot != null)
			uiRoot.visible = true;
		ClientPrefs.saveSettings();
		persistentUpdate = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;
		rebuildRows();
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
	}

	/** Saves settings and returns to gameplay (when opened from a song) or the main menu. **/
	function exitState():Void {
		FlxG.sound.play(Paths.sound('cancelMenu'));
		ClientPrefs.saveSettings();
		if (onPlayState) {
			StageData.loadDirectory(PlayState.SONG);
			LoadingState.loadAndSwitchState(new PlayState());
			if (FlxG.sound.music != null)
				FlxG.sound.music.volume = 0;
		} else
			MusicBeatState.switchState(new MainMenuState());
	}

	/** Fades the menu music back in and handles ESC/back when no widget or overlay owns the key. **/
	override function update(elapsed:Float):Void {
		if (needsRebuild && subState == null) {
			needsRebuild = false;
			rebuildRows();
		}

		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		if (subState == null && !UIRoot.overlayOpen && UIFocus.focused == null)
			handleKeyboard(elapsed);

		if (nextAccept > 0)
			nextAccept--;

		super.update(elapsed);
	}

	/** Tears down the hosted UI root and reloads prefs from disk on the way out. **/
	override function destroy():Void {
		FlxG.signals.gameResized.remove(onGameResized);
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		UITooltip.reset();
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		if (changedMusic && !onPlayState && FlxG.sound.music != null)
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 1, true);
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}

/** A rendered, keyboard-focusable row: a setting (with its option + widget), an action, or a section header. **/
private typedef RowEntry = {
	var kind:Int; // 0 = setting, 1 = action, 2 = section header
	var y:Float;
	var h:Float;
	var ?option:Option;
	var ?widget:UIComponent;
	var ?which:String;
	var ?secTitle:String;
}

/**
	A rebind row in the controls modal: a label plus two clickable key slots. Click a slot, then press
	a key to bind it (Backspace/Delete clears, Escape cancels). Binds are written straight into
	`ClientPrefs.keyBinds`, matching the legacy Controls menu's keyboard model.
**/
private final class ControlsBindRow extends UIComponent implements IUIFocusable {
	static inline var SLOT_W:Float = 150;
	static inline var SLOT_GAP:Float = 8;

	final action:String;
	final rowLabel:String;
	final labelTf:TextField;
	final slotTf:Array<TextField>;
	var capturing:Bool = false;
	var captureSlot:Int = 0;

	/**
		@param action the `ClientPrefs.keyBinds` id this row edits
		@param rowLabel the display label
		@param width the row width
	**/
	public function new(action:String, rowLabel:String, width:Float) {
		super(true, true);
		this.action = action;
		this.rowLabel = rowLabel;
		labelTf = UIFonts.make(UITheme.fs(11), UITheme.text2);
		addChild(labelTf);
		slotTf = [
			UIFonts.make(UITheme.fs(11), UITheme.text, openfl.text.TextFormatAlign.CENTER),
			UIFonts.make(UITheme.fs(11), UITheme.text, openfl.text.TextFormatAlign.CENTER)
		];
		for (tf in slotTf) {
			tf.autoSize = openfl.text.TextFieldAutoSize.NONE;
			addChild(tf);
		}
		resize(width, UITheme.px(26));
		render();
	}

	inline function slotX(i:Int):Float
		return (i == 0) ? w - 2 * SLOT_W - SLOT_GAP : w - SLOT_W;

	/** Which slot (0/1) a local x falls in, or -1 for the label area. **/
	function slotAt(localX:Float):Int {
		if (localX >= w - SLOT_W)
			return 1;
		if (localX >= w - 2 * SLOT_W - SLOT_GAP)
			return 0;
		return -1;
	}

	override function onPress(localX:Float, localY:Float):Void {
		var slot:Int = slotAt(localX);
		if (slot < 0)
			return;
		captureSlot = slot;
		capturing = true;
		UIFocus.set(this);
		invalidate();
	}

	public function capturesKeyboard():Bool
		return capturing;

	public function onFocusGained():Void {
		capturing = true;
		invalidate();
	}

	public function onFocusLost():Void {
		capturing = false;
		invalidate();
	}

	public function onKeyDown(keyCode:Int, charCode:Int, ctrl:Bool, shift:Bool, alt:Bool):Bool {
		if (keyCode == 27) { // Escape cancels
			UIFocus.clear();
			return true;
		}
		if (keyCode == 8 || keyCode == 46) { // Backspace / Delete clears the slot
			setSlot(FlxKey.NONE);
			UIFocus.clear();
			return true;
		}
		setSlot(keyCode);
		UIFocus.clear();
		return true;
	}

	/** Writes `key` into the captured slot, de-duplicating against the other slot. **/
	function setSlot(key:Int):Void {
		var keys:Array<FlxKey> = ClientPrefs.keyBinds.get(action);
		if (keys == null) {
			keys = [FlxKey.NONE, FlxKey.NONE];
			ClientPrefs.keyBinds.set(action, keys);
		}
		while (keys.length < 2)
			keys.push(FlxKey.NONE);
		var other:Int = 1 - captureSlot;
		if (key != FlxKey.NONE && keys[other] == key)
			keys[other] = FlxKey.NONE;
		keys[captureSlot] = key;
		ClientPrefs.clearInvalidKeys(action);
		invalidate();
	}

	override public function render():Void {
		var g = graphics;
		g.clear();
		if (hovered) {
			g.beginFill(UIColor.rgb(UITheme.panel2));
			g.drawRoundRect(0, 0, w, h, UITheme.px(6), UITheme.px(6));
			g.endFill();
		} else {
			g.beginFill(0, 0);
			g.drawRect(0, 0, w, h);
			g.endFill();
		}

		UIFonts.restyle(labelTf, UITheme.fs(11), UITheme.text2);
		if (labelTf.text != rowLabel)
			labelTf.text = rowLabel;
		labelTf.x = UITheme.px(8);
		labelTf.y = (h - labelTf.height) / 2;

		var keys:Array<FlxKey> = ClientPrefs.keyBinds.get(action);
		for (i in 0...2) {
			var bx:Float = slotX(i);
			var active:Bool = capturing && captureSlot == i;
			g.beginFill(UIColor.rgb(active ? UITheme.panel3 : UITheme.inputBg));
			g.drawRoundRect(bx, 1, SLOT_W, h - 2, UITheme.px(6), UITheme.px(6));
			g.endFill();
			g.lineStyle(1, UIColor.rgb(active ? UITheme.accent : UITheme.border));
			g.drawRoundRect(bx + 0.5, 1.5, SLOT_W - 1, h - 3, UITheme.px(6), UITheme.px(6));
			g.lineStyle();

			var tf:TextField = slotTf[i];
			UIFonts.restyle(tf, UITheme.fs(11), active ? UITheme.highlight : UITheme.text, openfl.text.TextFormatAlign.CENTER);
			var label:String;
			if (active)
				label = 'press a key...';
			else {
				var k:FlxKey = (keys != null && i < keys.length) ? keys[i] : FlxKey.NONE;
				label = InputFormatter.getKeyName(k);
				if (label == null || label == '')
					label = '---';
			}
			if (tf.text != label)
				tf.text = label;
			tf.width = SLOT_W;
			tf.height = tf.textHeight + 4;
			tf.x = bx;
			tf.y = (h - tf.height) / 2;
		}
	}
}
