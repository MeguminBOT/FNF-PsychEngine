package states.converters;

#if CONVERTERS_ALLOWED
import flixel.FlxSprite;
import backend.tools.chartconvert.ChartConvertJob;
import backend.tools.chartconvert.ChartConvertJob.ModScan;
import backend.tools.chartconvert.ChartConvertJob.FolderJob;
import backend.tools.chartconvert.ChartConvertJob.ChartEntry;
import backend.tools.chartconvert.ChartConvertJob.ConvertSummary;
import ui.UIRoot;
import ui.UITheme;
import ui.UIFonts;
import ui.UILocale;
import ui.UIComponent;
import ui.input.UIFocus;
import ui.widgets.UIPanel;
import ui.widgets.UIScrollPane;
import ui.widgets.UILabel;
import ui.widgets.UIButton;
import ui.widgets.UICheckbox;
import ui.widgets.UIToast;
import ui.widgets.UITooltip;

/**
	The Chart Converter screen, built on the in-engine UI framework (`source/ui/`): a left rail that
	scopes the run (every mod, or one at a time) and a `UIScrollPane` of the charts it found. It
	migrates legacy / psych_v1 charts to the native **psych_v2** format and folds each song's standalone
	`events.json` into every difficulty so the result is self-contained. Convert overwrites the originals
	in place; the "Back up originals" checkbox mirrors each touched file into `<exe>/chartConvertERBackup`
	(folder layout preserved) first, so the user can restore by copying back.
**/
class ChartConverterState extends MusicBeatState {
	static inline var RAIL_X:Int = 24;
	static inline var RAIL_W:Int = 250;
	static inline var CONTENT_X:Int = 290;
	static inline var CONTENT_W:Int = 966;
	static inline var PANEL_Y:Int = 118;
	static inline var PANEL_H:Int = 548;
	static inline var PANEL_PAD:Int = 16;
	static inline var RAIL_FONT:Int = 16;
	static inline var RAIL_BTN_H:Int = 44;
	static inline var RAIL_BTN_GAP:Int = 6;
	static inline var MAX_ROWS:Int = 800;

	// Fixed header band inside the content panel (each element on its own row).
	static inline var HEADER_Y:Int = PANEL_Y + 12;
	static inline var SUMMARY_Y:Int = PANEL_Y + 44;
	static inline var DISCLAIMER_Y:Int = PANEL_Y + 70;
	static inline var PANE_TOP:Int = PANEL_Y + 128;

	static inline var DISCLAIMER:String = "Converts to the psych_v2 format, which reads and loads faster - at the cost of no longer working on pre-1.3.0 Psych releases nor other engines.";

	var uiRoot:UIRoot;

	/** Rail scopes: index 0 = "All mods", 1.. = each mod folder. **/
	var scopes:Array<String> = [];

	var modFolders:Array<String> = [];
	var curScope:Int = 0;

	var railPane:UIScrollPane;
	var railButtons:Array<UIButton> = [];
	var pane:UIScrollPane;
	var headerLabel:UILabel;
	var summaryLabel:UILabel;
	var disclaimerLabel:UILabel;
	var hintLabel:UILabel;

	var scanBtn:UIButton;
	var convertBtn:UIButton;
	var backupCheck:UICheckbox;

	var backupOriginals:Bool = true;

	/** The most recent scan, or null before the first scan. **/
	var lastScans:Array<ModScan> = null;

	override function create():Void {
		backend.Mods.allowCurrentModAssets = true;
		persistentUpdate = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		modFolders = backend.Mods.getModDirectories();
		scopes = ['All mods'];
		for (m in modFolders)
			scopes.push(m);

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
		if (modFolders.length > 0)
			selectScope(0);
		else {
			headerLabel.text = 'No mod folders found.';
			summaryLabel.text = 'Install a mod under the mods/ folder, then reopen this screen.';
		}
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end
	}

	/** Layers the UI root above the game view but below the FPS counter (mirrors ScriptConverterState). **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	function onGameResized(_:Int, _:Int):Void
		syncViewport();

	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	/** Builds the static chrome: title, action row, rail scroll-pane + buttons, and the results pane. **/
	function buildChrome():Void {
		var title:UILabel = new UILabel('CHART CONVERTER', 30, 0);
		title.x = RAIL_X;
		title.y = 18;
		uiRoot.content.addChild(title);

		var subtitle:UILabel = new UILabel('Migrate legacy / psych_v1 charts to psych_v2 and merge events.json into each chart.', 14, 2);
		subtitle.x = RAIL_X;
		subtitle.y = 56;
		uiRoot.content.addChild(subtitle);

		// Action row.
		scanBtn = new UIButton('Scan', 120, 34, runScan, true);
		scanBtn.fontSize = 15;
		scanBtn.tooltip = 'Scan the selected scope for convertible charts.';
		scanBtn.x = CONTENT_X;
		scanBtn.y = 74;
		uiRoot.content.addChild(scanBtn);

		convertBtn = new UIButton('Convert to psych_v2', 220, 34, runConvert);
		convertBtn.fontSize = 15;
		convertBtn.tooltip = 'Overwrite the found charts with psych_v2 versions.';
		convertBtn.x = CONTENT_X + 132;
		convertBtn.y = 74;
		convertBtn.visible = false;
		uiRoot.content.addChild(convertBtn);

		backupCheck = new UICheckbox('Back up originals', 240, backupOriginals, function(v:Bool):Void backupOriginals = v);
		backupCheck.fontSize = 14;
		backupCheck.tooltip = 'Copy each original into <exe>/' + ChartConvertJob.BACKUP_DIR + ' (folder layout kept) before overwriting.';
		backupCheck.x = CONTENT_X + CONTENT_W - 240;
		backupCheck.y = 80;
		uiRoot.content.addChild(backupCheck);

		// Rail panel + scrollable list of scopes.
		var railPanel:UIPanel = new UIPanel(RAIL_W, PANEL_H, UITheme.panel);
		railPanel.x = RAIL_X;
		railPanel.y = PANEL_Y;
		uiRoot.content.addChild(railPanel);

		railPane = new UIScrollPane(RAIL_W - 8, PANEL_H - 16);
		railPane.x = RAIL_X + 4;
		railPane.y = PANEL_Y + 8;
		uiRoot.content.addChild(railPane);

		// Content panel + fixed header band.
		var contentPanel:UIPanel = new UIPanel(CONTENT_W, PANEL_H, UITheme.panel);
		contentPanel.x = CONTENT_X;
		contentPanel.y = PANEL_Y;
		uiRoot.content.addChild(contentPanel);

		headerLabel = new UILabel('', 22, 0);
		headerLabel.x = CONTENT_X + PANEL_PAD;
		headerLabel.y = HEADER_Y;
		uiRoot.content.addChild(headerLabel);

		summaryLabel = new UILabel('', 14, 2);
		summaryLabel.x = CONTENT_X + PANEL_PAD;
		summaryLabel.y = SUMMARY_Y;
		uiRoot.content.addChild(summaryLabel);

		disclaimerLabel = new UILabel(DISCLAIMER, 13, 0);
		disclaimerLabel.colorOverride = 0xFFFFD24A;
		disclaimerLabel.wrapWidth = CONTENT_W - PANEL_PAD * 2;
		disclaimerLabel.x = CONTENT_X + PANEL_PAD;
		disclaimerLabel.y = DISCLAIMER_Y;
		uiRoot.content.addChild(disclaimerLabel);

		pane = new UIScrollPane(CONTENT_W - 16, PANEL_Y + PANEL_H - PANE_TOP - 12);
		pane.x = CONTENT_X + 8;
		pane.y = PANE_TOP;
		uiRoot.content.addChild(pane);

		hintLabel = new UILabel('Up/Down  Scope      Enter  Scan      Esc  Back', 14, 2);
		hintLabel.x = RAIL_X;
		hintLabel.y = FlxG.height - 28;
		uiRoot.content.addChild(hintLabel);

		buildRail();
	}

	/** Fills the rail scroll-pane with one ellipsized, tooltipped button per scope. **/
	function buildRail():Void {
		railButtons = [];
		var btnW:Float = railPane.w - PANEL_PAD;
		var y:Float = 4;
		for (i in 0...scopes.length) {
			var idx:Int = i;
			var full:String = scopes[i];
			var btn:UIButton = new UIButton(ellipsize(full, btnW, RAIL_FONT), btnW, RAIL_BTN_H, function() selectScope(idx));
			btn.fontSize = RAIL_FONT;
			btn.tooltip = (i == 0) ? 'Scan / convert every installed mod.' : full;
			btn.x = 4;
			btn.y = y;
			railPane.content.addChild(btn);
			railButtons.push(btn);
			y += RAIL_BTN_H + RAIL_BTN_GAP;
		}
		railPane.refreshContent(y + 4);
	}

	/** Truncates `text` to fit `width` at `fontSize`, appending an ellipsis when it overflows. **/
	function ellipsize(text:String, width:Float, fontSize:Int):String {
		var budget:Int = Std.int((width - PANEL_PAD) / (fontSize * 0.52));
		if (budget < 4 || text.length <= budget)
			return text;
		return text.substr(0, budget - 1) + '...';
	}

	/** Selects a scope in the rail (does not scan; the results clear until the next Scan). **/
	function selectScope(i:Int):Void {
		curScope = i;
		for (n in 0...railButtons.length)
			railButtons[n].accent = (n == curScope);
		scrollRailTo(i);
		lastScans = null;
		convertBtn.visible = false;
		headerLabel.text = scopes[curScope];
		summaryLabel.text = 'Press Scan to look for convertible charts.';
		clearPane(pane);
		pane.refreshContent(8);
	}

	/** Scrolls the rail so the selected scope button is fully visible. **/
	function scrollRailTo(i:Int):Void {
		if (railPane == null)
			return;
		var top:Float = 4 + i * (RAIL_BTN_H + RAIL_BTN_GAP);
		var bottom:Float = top + RAIL_BTN_H;
		if (top < railPane.scrollY)
			railPane.setScroll(top - 4);
		else if (bottom > railPane.scrollY + railPane.h)
			railPane.setScroll(bottom - railPane.h + 4);
	}

	/** The mod folders in scope for the current selection (all, or the single selected mod). **/
	function scopedMods():Array<String> {
		if (curScope == 0)
			return modFolders;
		return [scopes[curScope]];
	}

	/** Runs a scan of the selected scope and renders the results. **/
	function runScan():Void {
		if (modFolders.length == 0)
			return;
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		#if sys
		lastScans = ChartConvertJob.scanMods(scopedMods());
		rebuildResults();
		#else
		UIToast.show('Chart conversion is only available on desktop.');
		#end
	}

	/** Clears and rebuilds the results pane from `lastScans`. **/
	function rebuildResults():Void {
		clearPane(pane);
		if (lastScans == null) {
			pane.refreshContent(8);
			return;
		}

		var leftPad:Float = 12;
		var indent:Float = 24;
		var scrollbarGutter:Float = UITheme.px(4) + 12;
		var rowW:Float = pane.w - scrollbarGutter;

		var shown:Int = 0;
		var y:Float = 8;
		var truncated:Bool = false;

		for (scan in lastScans) {
			var modHead:UILabel = new UILabel(ellipsize(scan.mod, rowW - leftPad, 15) + '   (' + scan.chartCount + ' chart(s))', 15, 0);
			modHead.tooltip = scan.mod;
			modHead.x = leftPad;
			modHead.y = y;
			pane.content.addChild(modHead);
			y += 26;

			for (folder in scan.folders) {
				var hasEvents:Bool = folder.eventsPath != null;
				for (entry in folder.charts) {
					if (shown >= MAX_ROWS) {
						truncated = true;
						break;
					}
					var line:UILabel = new UILabel('', 13, 1);
					line.colorOverride = ChartConvertJob.colorForKind(entry.kind, hasEvents);
					line.wrapWidth = rowW - indent;
					line.text = folder.songFolder + '/' + entry.fileName + '   -   ' + ChartConvertJob.actionText(entry.kind, hasEvents);
					line.x = indent;
					line.y = y;
					pane.content.addChild(line);
					y += line.measure() + 6;
					shown++;
				}
				if (truncated)
					break;
			}
			y += 8;
			if (truncated)
				break;
		}

		if (truncated) {
			var more:UILabel = new UILabel('... more charts hidden. Convert anyway to process them all.', 13, 2);
			more.x = indent;
			more.y = y;
			pane.content.addChild(more);
			y += 22;
		}

		pane.refreshContent(y + 8);
		updateSummary();
	}

	/** Updates the header/summary and the Convert affordance after a scan. **/
	function updateSummary():Void {
		headerLabel.text = scopes[curScope];
		var totalCharts:Int = 0;
		var totalV2:Int = 0;
		var totalEvents:Int = 0;
		for (scan in lastScans) {
			totalCharts += scan.chartCount;
			totalV2 += scan.v2Count;
			totalEvents += scan.eventFileCount;
		}

		if (totalCharts == 0) {
			summaryLabel.text = 'No charts found in this scope.';
			convertBtn.visible = false;
			return;
		}

		var pending:Int = totalCharts - totalV2;
		summaryLabel.text = totalCharts + ' chart(s) - ' + pending + ' to migrate, ' + totalV2 + ' already psych_v2, ' + totalEvents + ' events.json to merge.';
		convertBtn.visible = true;
	}

	/** Performs the conversion over the current scan (with backup if the checkbox is set). **/
	function runConvert():Void {
		if (lastScans == null)
			return;
		#if sys
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		var summary:ConvertSummary = {
			converted: 0,
			alreadyV2: 0,
			failed: 0,
			eventsMerged: 0,
			backedUp: 0,
			errors: []
		};
		ChartConvertJob.convert(lastScans, backupOriginals, summary);

		var msg:String = 'Converted ' + summary.converted + ' chart(s)';
		if (summary.eventsMerged > 0)
			msg += ', merged ' + summary.eventsMerged + ' events.json';
		if (summary.alreadyV2 > 0)
			msg += ', skipped ' + summary.alreadyV2 + ' already-v2';
		if (backupOriginals && summary.backedUp > 0)
			msg += ', backed up ' + summary.backedUp;
		if (summary.failed > 0)
			msg += ' - ' + summary.failed + ' FAILED (see log)';
		msg += '.';
		UIToast.show(msg);

		for (err in summary.errors)
			trace('[ChartConverter] ' + err);

		// Re-scan so the list reflects the now-converted files.
		runScan();
		#else
		UIToast.show('Chart conversion is only available on desktop.');
		#end
	}

	/** Disposes and removes every widget currently in `target`'s content. **/
	function clearPane(target:UIScrollPane):Void {
		var i:Int = target.content.numChildren;
		while (--i >= 0) {
			var c = target.content.getChildAt(i);
			if (c is UIComponent)
				(cast c : UIComponent).dispose();
		}
		target.content.removeChildren();
	}

	override function update(elapsed:Float):Void {
		if (subState == null && !UIRoot.overlayOpen && UIFocus.focused == null)
			handleKeyboard();
		super.update(elapsed);
	}

	/** Keyboard / controller navigation: Up/Down move the scope rail, Enter scans, Esc exits. **/
	function handleKeyboard():Void {
		if (scopes.length > 0) {
			if (controls.UI_UP_P)
				cycleScope(-1);
			if (controls.UI_DOWN_P)
				cycleScope(1);
			if (controls.ACCEPT)
				runScan();
		}
		if (controls.BACK)
			exitState();
	}

	function cycleScope(dir:Int):Void {
		selectScope(FlxMath.wrap(curScope + dir, 0, scopes.length - 1));
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function exitState():Void {
		FlxG.sound.play(Paths.sound('cancelMenu'));
		MusicBeatState.switchState(new MasterConverterState());
	}

	override function destroy():Void {
		FlxG.signals.gameResized.remove(onGameResized);
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;
		UITooltip.reset();
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
#end
