package options;

import states.MainMenuState;
import backend.StageData;

class OptionsState extends MusicBeatState {
	var options:Array<String> = [
		'Note Colors',
		'Controls',
		'Adjust Delay and Combo',
		'Graphics',
		'Visuals',
		'Gameplay',
		'Misc'
		#if mobile, 'Mobile' #end
		#if TRANSLATIONS_ALLOWED, 'Language' #end
	];
	private var grpOptions:FlxTypedGroup<Alphabet>;

	private static var curSelected:Int = 0;
	public static var menuBG:FlxSprite;
	public static var onPlayState:Bool = false;

	function openSelectedSubstate(label:String) {
		switch (label) {
			case 'Note Colors':
				openSubState(new options.NotesColorSubState());
			case 'Controls':
				openSubState(new options.ControlsSubState());
			case 'Graphics':
				openSubState(new options.GraphicsSettingsSubState());
			case 'Visuals':
				openSubState(new options.VisualsSettingsSubState());
			case 'Gameplay':
				openSubState(new options.GameplaySettingsSubState());
			case 'Misc':
				openSubState(new options.MiscSettingsSubState());
			#if mobile
			case 'Mobile':
				openSubState(new mobile.options.MobileOptionsSubState());
			#end
			case 'Adjust Delay and Combo':
				MusicBeatState.switchState(new options.NoteOffsetState());
			case 'Language':
				openSubState(new options.LanguageSubState());
		}
	}

	var selectorLeft:Alphabet;
	var selectorRight:Alphabet;

	override function create() {
		backend.Mods.allowCurrentModAssets = false; // core menu: engine + global mods only
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = 0xFFea71fd;
		bg.updateHitbox();

		bg.screenCenter();
		add(bg);

		grpOptions = new FlxTypedGroup<Alphabet>();
		add(grpOptions);

		var scale:Float = 0.8;
		var spacing:Float = 92 * scale;
		for (num => option in options) {
			var optionText:Alphabet = new Alphabet(0, 0, Language.getPhrase('options_$option', option), true);
			optionText.setScale(scale);
			optionText.screenCenter();
			optionText.y += (spacing * (num - (options.length / 2))) + 45;
			grpOptions.add(optionText);
		}

		selectorLeft = new Alphabet(0, 0, '>', true);
		selectorLeft.setScale(scale);
		add(selectorLeft);
		selectorRight = new Alphabet(0, 0, '<', true);
		selectorRight.setScale(scale);
		add(selectorRight);

		changeSelection();
		ClientPrefs.saveSettings();

		super.create();

		#if mobile
		// Items are tappable (see update()); pad is just a Back button.
		addTouchPad('NONE', 'B');
		#end
	}

	override function closeSubState() {
		super.closeSubState();
		ClientPrefs.saveSettings();
		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Options Menu", null);
		#end
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (controls.UI_UP_P)
			changeSelection(-1);
		if (controls.UI_DOWN_P)
			changeSelection(1);

		#if mobile
		var tapped:Int = getTappedMenuItem(grpOptions);
		if (tapped >= 0) {
			curSelected = tapped;
			changeSelection();
			openSelectedSubstate(options[curSelected]);
			return;
		}
		#end

		if (controls.BACK) {
			FlxG.sound.play(Paths.sound('cancelMenu'));
			if (onPlayState) {
				StageData.loadDirectory(PlayState.SONG);
				LoadingState.loadAndSwitchState(new PlayState());
				if (FlxG.sound.music != null)
					FlxG.sound.music.volume = 0;
			} else
				MusicBeatState.switchState(new MainMenuState());
		} else if (controls.ACCEPT)
			openSelectedSubstate(options[curSelected]);
	}

	function changeSelection(change:Int = 0) {
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);

		for (num => item in grpOptions.members) {
			item.targetY = num - curSelected;
			item.alpha = 0.6;
			if (item.targetY == 0) {
				item.alpha = 1;
				selectorLeft.x = item.x - 63 * 0.8;
				selectorLeft.y = item.y;
				selectorRight.x = item.x + item.width + 15 * 0.8;
				selectorRight.y = item.y;
			}
		}
		FlxG.sound.play(Paths.sound('scrollMenu'));
	}

	override function destroy() {
		ClientPrefs.loadPrefs();
		super.destroy();
	}
}
