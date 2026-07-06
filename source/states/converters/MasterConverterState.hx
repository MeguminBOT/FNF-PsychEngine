package states.converters;

#if CONVERTERS_ALLOWED
import states.MainMenuState;
import states.FreeplayState;
import backend.tools.MediaConverter;

/**
 * A small "converters" menu (opened from the Main Menu with the debug_2 key) that
 * lists the engine's conversion tools. The osu! beatmap converter is the first entry.
 *
 * Shows whether the external tools (ffmpeg) are installed. Opening a converter when
 * they're missing pops up ConverterToolsSubState to download them first.
 */
class MasterConverterState extends MusicBeatState {
	var options:Array<String> = [
		'osu! Beatmap Converter',
		'Script Converter',
		'Chart Converter'
	];

	private var grpTexts:FlxTypedGroup<Alphabet>;
	private var curSelected:Int = 0;

	var statusTxt:FlxText;
	var ffmpegReady:Bool = false;
	var toolsChecked:Bool = false;

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.scrollFactor.set();
		bg.color = 0xFF353535;
		add(bg);

		grpTexts = new FlxTypedGroup<Alphabet>();
		add(grpTexts);

		for (i in 0...options.length) {
			var leText:Alphabet = new Alphabet(90, 320, options[i], true);
			leText.isMenuItem = true;
			leText.targetY = i;
			grpTexts.add(leText);
			leText.snapToPosition();
		}

		statusTxt = new FlxText(20, 18, FlxG.width - 40, '', 18);
		statusTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
		statusTxt.borderSize = 1.25;
		statusTxt.scrollFactor.set();
		add(statusTxt);

		var textBG:FlxSprite = new FlxSprite(0, FlxG.height - 42).makeGraphic(FlxG.width, 42, 0xFF000000);
		textBG.alpha = 0.6;
		add(textBG);

		var titleTxt:FlxText = new FlxText(textBG.x, textBG.y + 4, FlxG.width, 'CONVERTERS', 32);
		titleTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		titleTxt.scrollFactor.set();
		add(titleTxt);

		statusTxt.text = 'External tools (ffmpeg): checking...';
		statusTxt.color = 0xFFCCCCCC;

		changeSelection();
		FlxG.mouse.visible = false;
		super.create();
	}

	override function update(elapsed:Float) {
		// Defer the ffmpeg check to the first frame so the menu appears instantly.
		if (!toolsChecked) {
			toolsChecked = true;
			refreshToolStatus();
		}

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		if (controls.BACK)
			MusicBeatState.switchState(new MainMenuState());

		if (controls.ACCEPT)
			openConverter(options[curSelected]);

		for (num => item in grpTexts.members) {
			item.targetY = num - curSelected;
			item.alpha = (item.targetY == 0) ? 1 : 0.6;
		}
		super.update(elapsed);
	}

	function openConverter(name:String) {
		// The Script Converter only reads/writes local script files, so it needs no external tools.
		if (name == 'Script Converter') {
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
			FlxG.sound.music.volume = 0;
			FreeplayState.destroyFreeplayVocals();
			MusicBeatState.switchState(new ScriptConverterState());
			return;
		}

		// The Chart Converter only reads/writes local chart files, so it needs no external tools either.
		if (name == 'Chart Converter') {
			FlxG.sound.play(Paths.sound('confirmMenu'), 0.6);
			FlxG.sound.music.volume = 0;
			FreeplayState.destroyFreeplayVocals();
			MusicBeatState.switchState(new ChartConverterState());
			return;
		}

		// Gate on external tools: if ffmpeg isn't installed, prompt to download it
		// first, then retry opening the converter once it's ready.
		if (!ffmpegReady) {
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			openSubState(new ConverterToolsSubState(function() {
				ffmpegReady = true;
				openConverter(name);
			}));
			return;
		}

		FlxG.sound.music.volume = 0;
		FreeplayState.destroyFreeplayVocals();
		switch (name) {
			case 'osu! Beatmap Converter':
				MusicBeatState.switchState(new OsuConverterState());
		}
	}

	override function closeSubState() {
		super.closeSubState();
		refreshToolStatus();
	}

	function refreshToolStatus() {
		ffmpegReady = MediaConverter.hasFfmpeg();
		if (statusTxt == null)
			return;
		if (ffmpegReady) {
			statusTxt.text = 'External tools (ffmpeg): READY';
			statusTxt.color = 0xFF55CC55;
		} else {
			statusTxt.text = 'External tools (ffmpeg): NOT INSTALLED - opening a converter will offer to download it';
			statusTxt.color = 0xFFFFD24A;
		}
	}

	function changeSelection(change:Int = 0) {
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);
	}
}
#end
