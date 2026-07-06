package states;

import flixel.util.FlxSpriteUtil;
import flixel.input.keyboard.FlxKey;
import flixel.graphics.FlxGraphic;
import openfl.display.BitmapData;
import backend.CreditsData;
import backend.CreditsData.CreditSection;
import backend.CreditsData.CreditPerson;

using StringTools;

/*
	WELCOME TO VARIABLE HELL
 */
class CreditsState extends MusicBeatState {
	static inline var PANEL_Y:Int = 104;
	static inline var PANEL_H:Int = 558;

	static inline var SIDEBAR_PX:Int = 24;
	static inline var SIDEBAR_PW:Int = 278;
	static inline var SIDEBAR_X:Int = 42;
	static inline var SIDEBAR_Y:Int = 118;
	static inline var SIDEBAR_W:Int = 250;
	static inline var SIDEBAR_ROW_H:Int = 72;
	static inline var SIDEBAR_ICON:Int = 54;
	static inline var SIDEBAR_ROWS:Int = 7;

	static inline var GRID_PX:Int = 314;
	static inline var GRID_PW:Int = 534;
	static inline var GRID_X:Int = 324;
	static inline var GRID_Y:Int = 124;
	static inline var GRID_COLS:Int = 5;
	static inline var GRID_ROWS:Int = 5;
	static inline var CELL:Int = 102;
	static inline var ICON:Int = 74;

	static inline var INFO_PX:Int = 862;
	static inline var INFO_PW:Int = 394;
	static inline var INFO_X:Int = 878;
	static inline var INFO_W:Int = 362;

	var sections:Array<CreditSection> = [];

	var viewPeople:Array<CreditPerson> = [];
	var viewOwner:Array<CreditSection> = [];
	var curSectionIdx:Int = 0;
	var curPerson:Int = 0;
	var gridScroll:Int = 0;
	var sidebarScroll:Int = 0;

	var searching:Bool = false;
	var query:String = '';

	var bgTint:FlxSprite;
	var bgImage:FlxSprite;
	var headerAlpha:Alphabet;
	var searchText:FlxText;
	var hintText:FlxText;

	var sidebarTexts:Array<FlxText> = [];
	var sidebarBgs:Array<FlxSprite> = [];
	var sidebarIcons:Array<FlxSprite> = [];
	var sidebarSlotSection:Array<Int> = [];
	var sidebarHint:FlxText;

	var sectionGraphics:Array<FlxGraphic> = [];
	var sectionAnimated:Array<Bool> = [];
	var gridGroup:FlxTypedGroup<FlxSprite>;
	var gridIcons:Array<FlxSprite> = [];
	var gridCursor:FlxSprite;
	var gridHint:FlxText;
	var emptyText:FlxText;

	var nameAlpha:Alphabet;
	var fromText:FlxText;
	var roleText:FlxText;
	var colorSwatch:FlxSprite;
	var linksLabel:FlxText;
	var linkTexts:Array<FlxText> = [];

	var intendedColor:FlxColor = 0xFF1A1A2E;
	var quitting:Bool = false;

	override function create() {
		Mods.allowCurrentModAssets = false;
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus", null);
		#end
		persistentUpdate = true;

		sections = CreditsData.build();

		bgImage = new FlxSprite();
		bgImage.scrollFactor.set();
		bgImage.alpha = 0;
		add(bgImage);

		bgTint = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bgTint.color = intendedColor;
		bgTint.scrollFactor.set();
		bgTint.screenCenter();
		add(bgTint);

		makePanel(SIDEBAR_PX, PANEL_Y, SIDEBAR_PW, PANEL_H);
		makePanel(GRID_PX, PANEL_Y, GRID_PW, PANEL_H);
		makePanel(INFO_PX, PANEL_Y, INFO_PW, PANEL_H);

		headerAlpha = new Alphabet(SIDEBAR_X, 30, '', true);
		headerAlpha.scrollFactor.set();
		add(headerAlpha);

		searchText = mkText(FlxG.width - 470, 44, 450, 'SEARCH ( / )', 22, RIGHT);
		add(searchText);

		preloadSectionIcons();

		for (i in 0...SIDEBAR_ROWS) {
			var rowY:Int = SIDEBAR_Y + i * SIDEBAR_ROW_H;

			var bgRow:FlxSprite = new FlxSprite(SIDEBAR_PX + 4, rowY).makeGraphic(1, 1, FlxColor.WHITE);
			bgRow.scale.set(SIDEBAR_PW - 8, SIDEBAR_ROW_H - 4);
			bgRow.updateHitbox();
			bgRow.alpha = 0;
			bgRow.scrollFactor.set();
			add(bgRow);
			sidebarBgs.push(bgRow);

			var icon:FlxSprite = new FlxSprite(SIDEBAR_PX + 12, rowY + (SIDEBAR_ROW_H - SIDEBAR_ICON) / 2);
			icon.scrollFactor.set();
			icon.visible = false;
			add(icon);
			sidebarIcons.push(icon);

			var t:FlxText = mkText(SIDEBAR_PX + 12 + SIDEBAR_ICON + 10, rowY, SIDEBAR_PW - SIDEBAR_ICON - 34, '', 18, LEFT);
			sidebarTexts.push(t);
			add(t);

			sidebarSlotSection.push(-1);
		}
		sidebarHint = mkText(SIDEBAR_PX, PANEL_Y + PANEL_H - 26, SIDEBAR_PW - 12, '', 14, RIGHT);
		sidebarHint.alpha = 0.7;
		add(sidebarHint);

		gridGroup = new FlxTypedGroup<FlxSprite>();
		add(gridGroup);

		gridCursor = new FlxSprite();
		gridCursor.makeGraphic(CELL, CELL, FlxColor.TRANSPARENT, true);
		FlxSpriteUtil.drawRect(gridCursor, 0, 0, CELL - 1, CELL - 1, FlxColor.TRANSPARENT, {thickness: 4, color: 0xFFFFFF00});
		gridCursor.scrollFactor.set();
		gridCursor.visible = false;
		add(gridCursor);

		gridHint = mkText(GRID_PX, PANEL_Y + PANEL_H - 26, GRID_PW - 12, '', 14, RIGHT);
		gridHint.alpha = 0.7;
		add(gridHint);

		emptyText = mkText(GRID_X, GRID_Y + 160, GRID_COLS * CELL, 'No results.', 28, CENTER);
		emptyText.visible = false;
		add(emptyText);

		nameAlpha = new Alphabet(INFO_X, GRID_Y + 4, '', true);
		nameAlpha.scrollFactor.set();
		add(nameAlpha);

		fromText = mkText(INFO_X, GRID_Y + 62, INFO_W, '', 16, LEFT);
		fromText.alpha = 0.7;
		add(fromText);

		colorSwatch = new FlxSprite(INFO_X, GRID_Y + 90).makeGraphic(INFO_W, 6, FlxColor.WHITE);
		colorSwatch.scrollFactor.set();
		add(colorSwatch);

		roleText = mkText(INFO_X, GRID_Y + 108, INFO_W, '', 20, LEFT);
		add(roleText);

		linksLabel = mkText(INFO_X, GRID_Y + 320, INFO_W, '', 18, LEFT);
		linksLabel.alpha = 0.7;
		add(linksLabel);

		hintText = mkText(0, FlxG.height - 32, FlxG.width, 'ARROWS Navigate   Q/E Section   ENTER Open link   / Search   ESC Back', 16, CENTER);
		add(hintText);

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end

		selectSection(0, false);
		super.create();
	}

	override function update(elapsed:Float) {
		if (FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		if (quitting) {
			super.update(elapsed);
			return;
		}

		if (searching) {
			handleSearchInput();
			super.update(elapsed);
			return;
		}

		handleKeyboard();
		handleMouse();
		super.update(elapsed);
	}

	function handleKeyboard():Void {
		if (FlxG.keys.justPressed.SLASH) {
			beginSearch();
			return;
		}

		if (FlxG.keys.justPressed.E || FlxG.keys.justPressed.TAB)
			cycleSection(1);
		else if (FlxG.keys.justPressed.Q)
			cycleSection(-1);

		if (viewPeople.length > 0) {
			if (controls.UI_LEFT_P)
				moveGrid(-1, 0);
			if (controls.UI_RIGHT_P)
				moveGrid(1, 0);
			if (controls.UI_UP_P)
				moveGrid(0, -1);
			if (controls.UI_DOWN_P)
				moveGrid(0, 1);

			if (controls.ACCEPT)
				openLink(0);

			var numKeys:Array<FlxKey> = [ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE];
			for (i in 0...numKeys.length)
				if (FlxG.keys.anyJustPressed([numKeys[i]]))
					openLink(i);
		}

		if (controls.BACK)
			exitState();
	}

	function handleMouse():Void {
		if (FlxG.mouse.wheel != 0 && viewPeople.length > 0)
			moveGrid(0, -FlxG.mouse.wheel > 0 ? 1 : -1);

		var moved:Bool = (FlxG.mouse.deltaScreenX != 0 || FlxG.mouse.deltaScreenY != 0);
		if (!moved && !FlxG.mouse.justPressed)
			return;

		for (i in 0...sidebarBgs.length) {
			var sectionIdx:Int = sidebarSlotSection[i];
			if (sectionIdx < 0 || !FlxG.mouse.overlaps(sidebarBgs[i]))
				continue;
			if (FlxG.mouse.justPressed && sectionIdx != curSectionIdx)
				selectSection(sectionIdx, true);
		}

		for (vi in 0...gridIcons.length) {
			var spr:FlxSprite = gridIcons[vi];
			if (!spr.visible || !FlxG.mouse.overlaps(spr))
				continue;

			if (FlxG.mouse.justPressed) {
				if (vi == curPerson)
					openLink(0);
				else
					selectPerson(vi);
			}
		}

		for (i in 0...linkTexts.length) {
			if (FlxG.mouse.overlaps(linkTexts[i]) && FlxG.mouse.justPressed)
				openLink(i);
		}
	}

	function cycleSection(dir:Int):Void {
		if (sections.length == 0)
			return;
		selectSection(FlxMath.wrap(curSectionIdx + dir, 0, sections.length - 1), true);
	}

	function selectSection(idx:Int, sound:Bool):Void {
		if (sections.length == 0)
			return;

		curSectionIdx = FlxMath.wrap(idx, 0, sections.length - 1);
		query = '';
		searchText.text = 'SEARCH ( / )';
		setHeader(sections[curSectionIdx].name);

		viewPeople = sections[curSectionIdx].people.copy();
		viewOwner = [for (_ in viewPeople) sections[curSectionIdx]];
		curPerson = 0;
		gridScroll = 0;

		if (sound)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);

		refreshSidebar();
		buildGrid();
		selectPerson(0);
	}

	function refreshSidebar():Void {
		if (curSectionIdx < sidebarScroll)
			sidebarScroll = curSectionIdx;
		else if (curSectionIdx >= sidebarScroll + SIDEBAR_ROWS)
			sidebarScroll = curSectionIdx - SIDEBAR_ROWS + 1;

		if (sidebarScroll > sections.length - SIDEBAR_ROWS)
			sidebarScroll = sections.length - SIDEBAR_ROWS;

		if (sidebarScroll < 0)
			sidebarScroll = 0;

		for (i in 0...SIDEBAR_ROWS) {
			var sectionIdx:Int = sidebarScroll + i;
			var t:FlxText = sidebarTexts[i];
			var bgRow:FlxSprite = sidebarBgs[i];
			var icon:FlxSprite = sidebarIcons[i];

			if (sectionIdx >= sections.length) {
				sidebarSlotSection[i] = -1;
				t.text = '';
				icon.visible = false;
				bgRow.alpha = 0;
				continue;
			}
			sidebarSlotSection[i] = sectionIdx;

			var sec:CreditSection = sections[sectionIdx];
			var selected:Bool = (sectionIdx == curSectionIdx && !searching);
			var rowY:Float = SIDEBAR_Y + i * SIDEBAR_ROW_H;

			icon.visible = true;
			var animated:Bool = sectionAnimated[sectionIdx];
			icon.loadGraphic(sectionGraphics[sectionIdx], animated, animated ? 150 : 0, animated ? 150 : 0);
			icon.antialiasing = ClientPrefs.data.antialiasing;
			icon.setGraphicSize(SIDEBAR_ICON, SIDEBAR_ICON);
			icon.updateHitbox();
			icon.setPosition(SIDEBAR_PX + 12, rowY + (SIDEBAR_ROW_H - SIDEBAR_ICON) / 2);

			bgRow.alpha = selected ? 0.85 : 0;

			t.text = sec.name;
			t.color = selected ? 0xFF20131F : FlxColor.WHITE;
			t.borderColor = selected ? FlxColor.WHITE : FlxColor.BLACK;
			t.alpha = selected ? 1 : 0.85;
			t.y = rowY + (SIDEBAR_ROW_H - t.height) / 2;
		}

		sidebarHint.text = (sections.length > SIDEBAR_ROWS) ? '${sidebarScroll + 1}-${Std.int(Math.min(sidebarScroll + SIDEBAR_ROWS, sections.length))} / ${sections.length}' : '';
	}

	function buildGrid():Void {
		gridGroup.clear();
		for (s in gridIcons)
			s.destroy();
		gridIcons = [];

		for (person in viewPeople) {
			var spr:FlxSprite = loadPersonIcon(person);
			gridGroup.add(spr);
			gridIcons.push(spr);
		}

		emptyText.visible = (viewPeople.length == 0);
		gridCursor.visible = (viewPeople.length > 0);
		layoutGrid();
	}

	function layoutGrid():Void {
		var rows:Int = GRID_ROWS;
		var curRow:Int = Std.int(curPerson / GRID_COLS);
		if (curRow < gridScroll)
			gridScroll = curRow;
		else if (curRow >= gridScroll + rows)
			gridScroll = curRow - rows + 1;

		if (gridScroll < 0)
			gridScroll = 0;

		for (vi in 0...gridIcons.length) {
			var spr:FlxSprite = gridIcons[vi];
			var col:Int = vi % GRID_COLS;
			var row:Int = Std.int(vi / GRID_COLS);
			var slot:Int = row - gridScroll;
			var onScreen:Bool = (slot >= 0 && slot < rows);

			spr.visible = onScreen;
			if (!onScreen)
				continue;

			var cellX:Float = GRID_X + col * CELL;
			var cellY:Float = GRID_Y + slot * CELL;

			spr.x = cellX + (CELL - spr.width) / 2;
			spr.y = cellY + (CELL - spr.height) / 2;
			spr.alpha = (vi == curPerson) ? 1 : 0.7;

			if (vi == curPerson) {
				gridCursor.x = cellX;
				gridCursor.y = cellY;
			}
		}
		gridCursor.visible = (gridIcons.length > 0 && curPerson < gridIcons.length);

		var perPage:Int = GRID_COLS * GRID_ROWS;
		if (gridIcons.length > perPage) {
			var first:Int = gridScroll * GRID_COLS + 1;
			var last:Int = Std.int(Math.min(gridIcons.length, (gridScroll + GRID_ROWS) * GRID_COLS));
			gridHint.text = '$first-$last / ${gridIcons.length}';
		} else
			gridHint.text = '';
	}

	function moveGrid(dx:Int, dy:Int):Void {
		if (viewPeople.length == 0)
			return;
		var col:Int = curPerson % GRID_COLS;
		var row:Int = Std.int(curPerson / GRID_COLS);
		var maxRow:Int = Std.int((viewPeople.length - 1) / GRID_COLS);

		if (dx != 0)
			selectPerson(FlxMath.wrap(curPerson + dx, 0, viewPeople.length - 1));
		else if (dy != 0) {
			row = FlxMath.wrap(row + dy, 0, maxRow);
			var target:Int = row * GRID_COLS + col;
			if (target >= viewPeople.length)
				target = viewPeople.length - 1;
			selectPerson(target);
		}
	}

	function selectPerson(idx:Int):Void {
		if (viewPeople.length == 0) {
			updateInfoPanel(null, null);
			return;
		}

		curPerson = Std.int(FlxMath.bound(idx, 0, viewPeople.length - 1));
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.35);

		layoutGrid();
		updateInfoPanel(viewPeople[curPerson], viewOwner[curPerson]);
		updateBackground(viewPeople[curPerson], viewOwner[curPerson]);
	}

	function updateInfoPanel(person:CreditPerson, owner:CreditSection):Void {
		for (t in linkTexts)
			remove(t, true);
		linkTexts = [];

		if (person == null) {
			fitAlphabet(nameAlpha, '', INFO_W, 0.8);
			fromText.text = '';
			roleText.text = '';
			linksLabel.text = '';
			colorSwatch.visible = false;
			return;
		}

		fitAlphabet(nameAlpha, person.name != null ? person.name : '', INFO_W, 0.8);

		fromText.text = (owner != null) ? 'from ${owner.name}' : '';
		roleText.text = person.role != null ? person.role : '';

		colorSwatch.visible = true;
		colorSwatch.color = CoolUtil.colorFromString(personColor(person, owner));

		if (person.links != null && person.links.length > 0) {
			linksLabel.text = 'Links:';

			for (i in 0...person.links.length) {
				var prefix:String = person.links.length > 1 ? '${i + 1}. ' : '> ';
				var t:FlxText = mkText(INFO_X, GRID_Y + 346 + i * 30, INFO_W, prefix + person.links[i].label, 18, LEFT);
				t.color = 0xFF7EC8FF;
				linkTexts.push(t);
				add(t);
			}
		} else
			linksLabel.text = '';
	}

	function openLink(idx:Int):Void {
		if (viewPeople.length == 0)
			return;

		var person:CreditPerson = viewPeople[curPerson];
		if (person.links == null || idx < 0 || idx >= person.links.length)
			return;
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		CoolUtil.browserLoad(person.links[idx].url);
	}

	function updateBackground(person:CreditPerson, owner:CreditSection):Void {
		var bgAsset:String = person.background;
		var folder:String = person.modFolder;

		if (bgAsset == null && owner != null) {
			bgAsset = owner.background;
			folder = owner.modFolder;
		}

		var graphic:flixel.graphics.FlxGraphic = (bgAsset != null) ? resolveImage(bgAsset, folder) : null;
		if (graphic != null) {
			bgImage.loadGraphic(graphic);
			bgImage.setGraphicSize(FlxG.width, FlxG.height);
			bgImage.updateHitbox();
			bgImage.screenCenter();

			FlxTween.cancelTweensOf(bgImage);
			FlxTween.tween(bgImage, {alpha: 1}, 0.3);
			FlxTween.cancelTweensOf(bgTint);
			FlxTween.tween(bgTint, {alpha: 0}, 0.3);
		} else {
			FlxTween.cancelTweensOf(bgImage);
			FlxTween.tween(bgImage, {alpha: 0}, 0.3);

			bgTint.alpha = 1;

			var newColor:FlxColor = CoolUtil.colorFromString(personColor(person, owner));
			if (newColor != intendedColor) {
				intendedColor = newColor;
				FlxTween.cancelTweensOf(bgTint);
				FlxTween.color(bgTint, 0.5, bgTint.color, intendedColor);
			}
		}
	}

	inline function personColor(person:CreditPerson, owner:CreditSection):String {
		if (person != null && person.color != null && person.color.length > 0)
			return person.color;
		if (owner != null && owner.color != null && owner.color.length > 0)
			return owner.color;
		return '1A1A2E';
	}

	function beginSearch():Void {
		searching = true;
		searchText.text = 'SEARCH: ' + query + '_';

		FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
		applySearch();

		#if android
		mobile.backend.SoftKeyboard.open(searchType, searchBackspace, endSearch);
		#end
	}

	function endSearch():Void {
		searching = false;

		#if android
		mobile.backend.SoftKeyboard.close();
		#end

		if (query.length == 0)
			selectSection(curSectionIdx, false);
		else
			searchText.text = 'SEARCH: ' + query;
		refreshSidebar();
	}

	function handleSearchInput():Void {
		// FlxKey codes are ASCII for these: ENTER 13, ESC 27, BACKSPACE 8, SPACE 32, A-Z 65-90,
		// 0-9 48-57. Compared as plain ints (FlxKey doesn't coerce to Int for </>).

		var k:Int = FlxG.keys.firstJustPressed();
		if (k == 13 || k == 27) {
			endSearch();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			return;
		}

		if (k == 8)
			query = query.length > 0 ? query.substr(0, query.length - 1) : '';
		else if (k == 32)
			query += ' ';
		else if ((k >= 65 && k <= 90) || (k >= 48 && k <= 57))
			query += String.fromCharCode(k).toLowerCase();
		else {
			if (controls.UI_LEFT_P)
				moveGrid(-1, 0);
			if (controls.UI_RIGHT_P)
				moveGrid(1, 0);
			if (controls.UI_UP_P)
				moveGrid(0, -1);
			if (controls.UI_DOWN_P)
				moveGrid(0, 1);
			if (controls.ACCEPT)
				openLink(0);
			handleMouse();
			return;
		}

		searchText.text = 'SEARCH: ' + query + '_';
		applySearch();
	}

	#if android
	function searchType(input:String):Void {
		query += input.toLowerCase();
		searchText.text = 'SEARCH: ' + query + '_';
		applySearch();
	}

	function searchBackspace():Void {
		if (query.length > 0) {
			query = query.substr(0, query.length - 1);
			searchText.text = 'SEARCH: ' + query + '_';
			applySearch();
		}
	}
	#end

	function applySearch():Void {
		viewPeople = [];
		viewOwner = [];
		var q:String = query.toLowerCase().trim();

		setHeader((q.length == 0) ? sections[curSectionIdx].name : 'Search Results');
		if (q.length == 0) {
			viewPeople = sections[curSectionIdx].people.copy();
			viewOwner = [for (_ in viewPeople) sections[curSectionIdx]];
		} else {
			for (sec in sections) {
				var sectionMatches:Bool = sec.name.toLowerCase().indexOf(q) >= 0;
				for (p in sec.people) {
					var hit:Bool = sectionMatches
						|| (p.name != null && p.name.toLowerCase().indexOf(q) >= 0)
						|| (p.role != null && p.role.toLowerCase().indexOf(q) >= 0);
					if (hit) {
						viewPeople.push(p);
						viewOwner.push(sec);
					}
				}
			}
		}

		curPerson = 0;
		gridScroll = 0;

		for (i in 0...sidebarTexts.length)
			sidebarTexts[i].alpha = 0.35;
		buildGrid();

		if (viewPeople.length > 0)
			selectPerson(0);
		else
			updateInfoPanel(null, null);
	}

	function loadPersonIcon(person:CreditPerson):FlxSprite {
		var spr:FlxSprite = new FlxSprite();
		spr.scrollFactor.set();
		spr.loadGraphic(resolvePersonGraphic(person));
		spr.antialiasing = ClientPrefs.data.antialiasing;

		if (spr.width > spr.height)
			spr.setGraphicSize(ICON);
		else
			spr.setGraphicSize(0, ICON);

		spr.updateHitbox();
		return spr;
	}

	function resolvePersonGraphic(person:CreditPerson):FlxGraphic {
		var folder:String = person.modFolder;
		var prevDir:String = Mods.currentModDirectory;
		var prevAllow:Bool = Mods.allowCurrentModAssets;
		if (folder != null && folder.length > 0) {
			Mods.currentModDirectory = folder;
			// The credits screen runs with allowCurrentModAssets off (core menu); turn it on for this
			// resolution so the owning mod's own icon is found instead of falling back to the placeholder.
			Mods.allowCurrentModAssets = true;
		}

		var path:String = 'credits/missing_icon';
		if (person.icon != null && person.icon.length > 0 && Paths.fileExists('images/${person.icon}.png', IMAGE))
			path = person.icon;

		var graphic:FlxGraphic = Paths.image(path);
		Mods.currentModDirectory = prevDir;
		Mods.allowCurrentModAssets = prevAllow;
		return graphic;
	}

	function preloadSectionIcons():Void {
		for (sec in sections) {
			var graphic:FlxGraphic = null;
			var animated:Bool = false;

			#if MODS_ALLOWED
			if (sec.modFolder != null) {
				var file:String = Paths.mods(sec.modFolder + '/pack.png');
				if (FileSystem.exists(file)) {
					var bmp:BitmapData = #if mobile mobile.backend.AssetUtil.getBitmap(file) #else BitmapData.fromFile(file) #end;
					if (bmp != null) {
						graphic = FlxGraphic.fromBitmapData(bmp, false, 'creditsSection_' + sec.modFolder);
						animated = bmp.width > bmp.height;
					}
				}
			}
			#end

			if (graphic == null)
				graphic = (sec.people.length > 0) ? resolvePersonGraphic(sec.people[0]) : Paths.image('credits/missing_icon');

			sectionGraphics.push(graphic);
			sectionAnimated.push(animated);
		}
	}

	function resolveImage(asset:String, folder:String):flixel.graphics.FlxGraphic {
		var prevDir:String = Mods.currentModDirectory;
		var prevAllow:Bool = Mods.allowCurrentModAssets;
		if (folder != null && folder.length > 0) {
			Mods.currentModDirectory = folder;
			Mods.allowCurrentModAssets = true; // enable mod resolution in this core-menu screen (see resolvePersonGraphic)
		}

		var graphic:flixel.graphics.FlxGraphic = null;
		if (Paths.fileExists('images/$asset.png', IMAGE))
			graphic = Paths.image(asset);

		Mods.currentModDirectory = prevDir;
		Mods.allowCurrentModAssets = prevAllow;
		return graphic;
	}

	function exitState():Void {
		quitting = true;
		FlxG.sound.play(Paths.sound('cancelMenu'));
		MusicBeatState.switchState(new MainMenuState());
	}

	function mkText(x:Float, y:Float, w:Float, text:String, size:Int, align:flixel.text.FlxTextAlign):FlxText {
		var t:FlxText = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, align, OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.5;
		t.scrollFactor.set();
		return t;
	}

	function makePanel(x:Int, y:Int, w:Int, h:Int):Void {
		var border:FlxSprite = new FlxSprite(x - 2, y - 2).makeGraphic(1, 1, 0xFF3A3F58);
		border.scale.set(w + 4, h + 4);
		border.updateHitbox();
		border.alpha = 0.4;
		border.scrollFactor.set();
		add(border);

		var panel:FlxSprite = new FlxSprite(x, y).makeGraphic(1, 1, 0xFF12141F);
		panel.scale.set(w, h);
		panel.updateHitbox();
		panel.alpha = 0.55;
		panel.scrollFactor.set();
		add(panel);
	}

	inline function setHeader(text:String):Void {
		fitAlphabet(headerAlpha, text, 740, 0.9);
	}

	function fitAlphabet(a:Alphabet, text:String, maxW:Float, maxScale:Float):Void {
		a.text = text;
		a.setScale(1);

		var target:Float = (a.width > maxW) ? (maxW / a.width) : 1;
		if (target > maxScale)
			target = maxScale;
		a.setScale(target);
	}
}
