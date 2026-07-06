package states.converters;

#if CONVERTERS_ALLOWED
import flixel.FlxSprite;
import backend.tools.scriptconvert.ScriptScanner;
import backend.tools.scriptconvert.ScriptScanner.FolderReport;
import backend.tools.scriptconvert.ScriptScanner.FileReport;
import backend.tools.scriptconvert.ScriptScanner.ScanIssue;
import backend.tools.scriptconvert.ScriptRule;
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
import ui.widgets.UIDropdown;
import ui.widgets.UIToast;
import ui.widgets.UITooltip;

/**
	The Script Converter screen, built on the in-engine UI framework (`source/ui/`): a scrollable
	left rail of installed mods and a `UIScrollPane` of scan results on the right. It *detects*
	outdated Lua/HScript idioms (see `backend.tools.scriptconvert.ScriptRules`) and never touches the
	modder's originals -- the only write paths are the explicit Export button (new `*.converted.*`
	copies + a report) and the "compatibilityMode" button (sets that flag in the pack's `pack.json`).

	Legacy support is removed in v2.0.0, so every legacy-only finding is framed as a choice: migrate
	the scripts now, or opt the pack onto the legacy layer for the time being.
**/
class ScriptConverterState extends MusicBeatState {
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
	static inline var MAX_ROWS:Int = 500;

	// Fixed header band inside the content panel (each element on its own row).
	static inline var HEADER_Y:Int = PANEL_Y + 12;
	static inline var SUMMARY_Y:Int = PANEL_Y + 44;
	static inline var BANNER_Y:Int = PANEL_Y + 68;
	static inline var FLAG_Y:Int = PANEL_Y + 112;
	static inline var PANE_TOP:Int = PANEL_Y + 152;

	var uiRoot:UIRoot;
	var modFolders:Array<String> = [];
	var curMod:Int = 0;

	var railPane:UIScrollPane;
	var railButtons:Array<UIButton> = [];
	var pane:UIScrollPane;
	var headerLabel:UILabel;
	var summaryLabel:UILabel;
	var bannerLabel:UILabel;
	var hintLabel:UILabel;

	var scanBtn:UIButton;
	var exportBtn:UIButton;
	var flagBtn:UIButton;
	var filterDrop:UIDropdown;

	/** 0 = all, 1 = warnings only, 2 = info only, 3 = compat-only. **/
	var filterMode:Int = 0;

	/** The most recent scan, or null before the first scan. **/
	var lastReport:FolderReport = null;

	override function create():Void {
		backend.Mods.allowCurrentModAssets = true;
		persistentUpdate = true;
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		modFolders = backend.Mods.getModDirectories();

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
			selectMod(0);
		else {
			headerLabel.text = 'No mod folders found.';
			summaryLabel.text = 'Install a mod under the mods/ folder, then reopen this screen.';
		}
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end
	}

	/** Layers the UI root above the game view but below the FPS counter (mirrors OptionsState). **/
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
		var title:UILabel = new UILabel('SCRIPT CONVERTER', 30, 0);
		title.x = RAIL_X;
		title.y = 18;
		uiRoot.content.addChild(title);

		var subtitle:UILabel = new UILabel('Scan a mod for outdated Lua / HScript. Legacy support is removed in v2.0.0.', 14, 2);
		subtitle.x = RAIL_X;
		subtitle.y = 56;
		uiRoot.content.addChild(subtitle);

		// Action row.
		scanBtn = new UIButton('Scan', 120, 34, runScan, true);
		scanBtn.fontSize = 15;
		scanBtn.tooltip = 'Scan the selected mod\'s scripts for outdated idioms.';
		scanBtn.x = CONTENT_X;
		scanBtn.y = 74;
		uiRoot.content.addChild(scanBtn);

		exportBtn = new UIButton('Export annotated copies', 250, 34, exportNow);
		exportBtn.fontSize = 15;
		exportBtn.tooltip = 'Write annotated *.converted copies + a report next to the scripts. Your originals are never modified.';
		exportBtn.x = CONTENT_X + 132;
		exportBtn.y = 74;
		exportBtn.visible = false;
		uiRoot.content.addChild(exportBtn);

		filterDrop = new UIDropdown('Show', 250, function(i:Int, _:String):Void {
			filterMode = i;
			rebuildResults();
		});
		filterDrop.fontSize = 14;
		filterDrop.tooltip = 'Filter which findings the list shows.';
		filterDrop.setItems(['All issues', 'Warnings only', 'Info only', 'Compat-only']);
		filterDrop.select(0);
		filterDrop.x = CONTENT_X + CONTENT_W - 250;
		filterDrop.y = 78;
		uiRoot.content.addChild(filterDrop);

		// Rail panel + scrollable list of mods.
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

		bannerLabel = new UILabel('', 14, 0);
		bannerLabel.colorOverride = 0xFFFFD24A;
		bannerLabel.wrapWidth = CONTENT_W - PANEL_PAD * 2;
		bannerLabel.x = CONTENT_X + PANEL_PAD;
		bannerLabel.y = BANNER_Y;
		uiRoot.content.addChild(bannerLabel);

		flagBtn = new UIButton('Add compatibilityMode to pack.json', 320, 30, addCompatFlag);
		flagBtn.fontSize = 13;
		flagBtn.tooltip = 'Sets "compatibilityMode": true in this pack\'s pack.json, keeping it on the legacy layer until v2.0.0.';
		flagBtn.x = CONTENT_X + PANEL_PAD;
		flagBtn.y = FLAG_Y;
		flagBtn.visible = false;
		uiRoot.content.addChild(flagBtn);

		pane = new UIScrollPane(CONTENT_W - 16, PANEL_Y + PANEL_H - PANE_TOP - 12);
		pane.x = CONTENT_X + 8;
		pane.y = PANE_TOP;
		uiRoot.content.addChild(pane);

		hintLabel = new UILabel('Up/Down  Mod      Enter  Scan      Esc  Back', 14, 2);
		hintLabel.x = RAIL_X;
		hintLabel.y = FlxG.height - 28;
		uiRoot.content.addChild(hintLabel);

		buildRail();
	}

	/** Fills the rail scroll-pane with one ellipsized, tooltipped button per installed mod. **/
	function buildRail():Void {
		railButtons = [];
		var btnW:Float = railPane.w - PANEL_PAD;
		var y:Float = 4;
		for (i in 0...modFolders.length) {
			var idx:Int = i;
			var full:String = modFolders[i];
			var btn:UIButton = new UIButton(ellipsize(full, btnW, RAIL_FONT), btnW, RAIL_BTN_H, function() selectMod(idx));
			btn.fontSize = RAIL_FONT;
			btn.tooltip = full;
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

	/** Selects a mod in the rail (does not scan; the results clear until the next Scan). **/
	function selectMod(i:Int):Void {
		curMod = i;
		for (n in 0...railButtons.length)
			railButtons[n].accent = (n == curMod);
		scrollRailTo(i);
		lastReport = null;
		exportBtn.visible = false;
		flagBtn.visible = false;
		bannerLabel.text = '';
		headerLabel.text = modFolders[curMod];
		summaryLabel.text = 'Press Scan to check this mod\'s scripts.';
		clearPane(pane);
		pane.refreshContent(8);
	}

	/** Scrolls the rail so the selected mod button is fully visible (mirrors OptionsState.scrollToRow). **/
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

	/** Runs a full folder scan of the selected mod and renders the results. **/
	function runScan():Void {
		if (modFolders.length == 0)
			return;
		FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
		#if sys
		var folder:String = modFolders[curMod];
		lastReport = ScriptScanner.scanFolder(Paths.mods(folder));
		rebuildResults();
		#else
		UIToast.show('Script scanning is only available on desktop.');
		#end
	}

	/** Clears and rebuilds the results pane from `lastReport`, honouring the active filter. **/
	function rebuildResults():Void {
		clearPane(pane);
		if (lastReport == null) {
			pane.refreshContent(8);
			return;
		}

		var leftPad:Float = 12;
		var issueIndent:Float = 24;
		var scrollbarGutter:Float = UITheme.px(4) + 12;
		var rowW:Float = pane.w - scrollbarGutter;

		var shown:Int = 0;
		var y:Float = 8;
		var truncated:Bool = false;

		for (file in lastReport.files) {
			var fileIssues:Array<ScanIssue> = filtered(file.report.issues);
			if (fileIssues.length == 0)
				continue;

			var head:UILabel = new UILabel(ellipsize(file.relPath, rowW - leftPad, 15) + '   (' + fileIssues.length + ')', 15, 0);
			head.tooltip = file.relPath;
			head.x = leftPad;
			head.y = y;
			pane.content.addChild(head);
			y += 26;

			for (issue in fileIssues) {
				if (shown >= MAX_ROWS) {
					truncated = true;
					break;
				}
				var line:UILabel = new UILabel('', 13, 1);
				line.colorOverride = colorForKind(issue.kind);
				line.wrapWidth = rowW - issueIndent;
				line.text = issueText(issue);
				line.x = issueIndent;
				line.y = y;
				pane.content.addChild(line);
				y += line.measure() + 6;
				shown++;
			}
			y += 8;
			if (truncated)
				break;
		}

		if (truncated) {
			var more:UILabel = new UILabel('... more issues hidden. Export the report to see them all.', 13, 2);
			more.x = issueIndent;
			more.y = y;
			pane.content.addChild(more);
			y += 22;
		}

		pane.refreshContent(y + 8);
		updateSummary();
	}

	/** Updates the header/summary/banner and the export + compat-flag affordances after a scan. **/
	function updateSummary():Void {
		headerLabel.text = modFolders[curMod];
		if (lastReport.total == 0) {
			summaryLabel.text = 'No outdated idioms found. This mod looks clean.';
			bannerLabel.text = '';
			exportBtn.visible = false;
			flagBtn.visible = false;
			return;
		}

		summaryLabel.text = lastReport.total + ' issue(s) across ' + lastReport.files.length + ' file(s).';
		exportBtn.visible = true;

		if (hasLegacyOnly()) {
			#if (MODS_ALLOWED && sys)
			if (backend.Mods.noteCompatibilityMode(modFolders[curMod])) {
				bannerLabel.text = 'This pack already runs on the legacy layer (compatibilityMode), which v2.0.0 removes. Migrate the scripts before then.';
				flagBtn.visible = false;
			} else {
				bannerLabel.text = 'Some findings only run through the legacy layer, which v2.0.0 removes. Migrate the scripts now, or opt this pack onto the legacy layer for now:';
				flagBtn.visible = true;
			}
			#else
			bannerLabel.text = 'Some findings only run through the legacy layer, which v2.0.0 removes.';
			flagBtn.visible = false;
			#end
		} else {
			bannerLabel.text = '';
			flagBtn.visible = false;
		}
	}

	/** Whether the current report has any compat-only or removed finding (the legacy-sunset cases). **/
	function hasLegacyOnly():Bool {
		for (file in lastReport.files)
			for (issue in file.report.issues)
				if (issue.kind == COMPAT_ONLY || issue.kind == REMOVED)
					return true;
		return false;
	}

	/** The issues in `source` that pass the active filter. **/
	function filtered(source:Array<ScanIssue>):Array<ScanIssue> {
		if (filterMode == 0)
			return source;
		var out:Array<ScanIssue> = [];
		for (issue in source) {
			var keep:Bool = switch (filterMode) {
				case 1: issue.severity == 'warn';
				case 2: issue.severity == 'info';
				case 3: issue.kind == COMPAT_ONLY;
				default: true;
			}
			if (keep)
				out.push(issue);
		}
		return out;
	}

	/** The single-line result text for one issue (wrapped by the label). **/
	inline function issueText(issue:ScanIssue):String {
		var advice:String = (issue.suggestion != null && issue.suggestion.length > 0) ? issue.message + ' ' + issue.suggestion : issue.message;
		return 'L' + issue.line + '  [' + issue.kind.label() + ']  ' + issue.match + '  -  ' + advice;
	}

	/** The result-row colour for a rule kind (red = removed, amber = compat-only, muted = renames). **/
	inline function colorForKind(kind:RuleKind):Int {
		return switch (kind) {
			case REMOVED | PATTERN: 0xFFFF6B6B;
			case COMPAT_ONLY: 0xFFFFD24A;
			default: 0xFFB9C0D0;
		}
	}

	/** Writes the annotated copies + report for the current scan (never touches originals). **/
	function exportNow():Void {
		if (lastReport == null || lastReport.total == 0)
			return;
		#if sys
		var written:Int = ScriptScanner.exportFolder(lastReport);
		UIToast.show('Wrote ' + written + ' annotated copy(ies) + report to ' + modFolders[curMod] + '.');
		#else
		UIToast.show('Exporting is only available on desktop.');
		#end
	}

	/** Sets `"compatibilityMode": true` in the selected pack's pack.json (opt onto the legacy layer). **/
	function addCompatFlag():Void {
		#if (MODS_ALLOWED && sys)
		var folder:String = modFolders[curMod];
		var data:Dynamic = backend.Mods.getPack(folder);
		if (data == null)
			data = {};
		Reflect.setField(data, 'compatibilityMode', true);
		if (backend.Mods.savePack(folder, data)) {
			UIToast.show('Set compatibilityMode = true in ' + folder + '/pack.json.');
			flagBtn.visible = false;
			bannerLabel.text = 'This pack now runs on the legacy layer (compatibilityMode), which v2.0.0 removes. Migrate the scripts before then.';
		} else {
			UIToast.show('Could not write pack.json for ' + folder + '.');
		}
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

	/** Keyboard / controller navigation: Up/Down move the mod rail, Enter scans, Esc exits. **/
	function handleKeyboard():Void {
		if (modFolders.length > 0) {
			if (controls.UI_UP_P)
				cycleMod(-1);
			if (controls.UI_DOWN_P)
				cycleMod(1);
			if (controls.ACCEPT)
				runScan();
		}
		if (controls.BACK)
			exitState();
	}

	function cycleMod(dir:Int):Void {
		selectMod(FlxMath.wrap(curMod + dir, 0, modFolders.length - 1));
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
