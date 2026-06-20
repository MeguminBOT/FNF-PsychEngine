package substates;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import flixel.util.FlxStringUtil;
import states.StoryMenuState;
import states.FreeplayState;
import options.OptionsState;
import options.ModSettingsSubState;
#if MODS_ALLOWED
import sys.io.File;
import sys.FileSystem;
#end

class PauseSubState extends MusicBeatSubstate {
	var grpMenuShit:FlxTypedGroup<Alphabet>;

	var menuItems:Array<String> = [];
	var menuItemsOG:Array<String> = ['Resume', 'Restart Song', 'Change Difficulty', 'Options', 'Exit to menu'];
	var difficultyChoices = [];
	var modOptionsChoices:Array<String> = [];
	var curSelected:Int = 0;

	// One entry per mod (current mod + any enabled global/script-pack mods) that has data/settings.json.
	// `label` is what's displayed in the submenu and is deduped against other entries.
	var modSettingsList:Array<{settings:Array<Dynamic>, folder:String, name:String, label:String}> = [];

	var pauseMusic:FlxSound;
	var practiceText:FlxText;
	var skipTimeText:FlxText;
	var skipTimeTracker:Alphabet;
	var curTime:Float = Math.max(0, Conductor.songPosition);

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	public static var songName:String = null;

	override function create() {
		if (Difficulty.list.length < 2)
			menuItemsOG.remove('Change Difficulty'); // No need to change difficulty if there is only one!
		if (PlayState.chartingMode) {
			menuItemsOG.insert(2, 'Leave Charting Mode');
			var num:Int = 0;
			if (!PlayState.instance.startingSong) {
				num = 1;
				menuItemsOG.insert(3, 'Skip Time');
			}
			menuItemsOG.insert(3 + num, 'End Song');
			menuItemsOG.insert(4 + num, 'Toggle Practice Mode');
			menuItemsOG.insert(5 + num, 'Toggle Botplay');
		} else if (PlayState.instance.practiceMode && !PlayState.instance.startingSong)
			menuItemsOG.insert(3, 'Skip Time');

		tryLoadModSettings();
		if (modSettingsList.length > 0) {
			var idx:Int = menuItemsOG.indexOf('Options');
			if (idx < 0) idx = menuItemsOG.length - 1;
			menuItemsOG.insert(idx + 1, 'Mod Options');

			for (entry in modSettingsList)
				modOptionsChoices.push(entry.label);
			modOptionsChoices.push('BACK');
		}

		menuItems = menuItemsOG;

		for (i in 0...Difficulty.list.length) {
			var diff:String = Difficulty.getString(i);
			difficultyChoices.push(diff);
		}
		difficultyChoices.push('BACK');

		pauseMusic = new FlxSound();
		try {
			var pauseSong:String = getPauseSong();
			if (pauseSong != null)
				pauseMusic.loadEmbedded(Paths.music(pauseSong), true, true);
		} catch (e:Dynamic) {}
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));

		FlxG.sound.list.add(pauseMusic);

		var bg:FlxSprite = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.scale.set(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0;
		bg.scrollFactor.set();
		add(bg);

		var levelInfo:FlxText = new FlxText(20, 15, 0, PlayState.SONG.song, 32);
		levelInfo.scrollFactor.set();
		levelInfo.setFormat(Paths.font("vcr.ttf"), 32);
		levelInfo.updateHitbox();
		add(levelInfo);

		var levelDifficulty:FlxText = new FlxText(20, 15 + 32, 0, Difficulty.getString().toUpperCase(), 32);
		levelDifficulty.scrollFactor.set();
		levelDifficulty.setFormat(Paths.font('vcr.ttf'), 32);
		levelDifficulty.updateHitbox();
		add(levelDifficulty);

		var blueballedTxt:FlxText = new FlxText(20, 15 + 64, 0, Language.getPhrase("blueballed", "Blueballed: {1}", [PlayState.deathCounter]), 32);
		blueballedTxt.scrollFactor.set();
		blueballedTxt.setFormat(Paths.font('vcr.ttf'), 32);
		blueballedTxt.updateHitbox();
		add(blueballedTxt);

		practiceText = new FlxText(20, 15 + 101, 0, Language.getPhrase("Practice Mode").toUpperCase(), 32);
		practiceText.scrollFactor.set();
		practiceText.setFormat(Paths.font('vcr.ttf'), 32);
		practiceText.x = FlxG.width - (practiceText.width + 20);
		practiceText.updateHitbox();
		practiceText.visible = PlayState.instance.practiceMode;
		add(practiceText);

		var chartingText:FlxText = new FlxText(20, 15 + 101, 0, Language.getPhrase("Charting Mode").toUpperCase(), 32);
		chartingText.scrollFactor.set();
		chartingText.setFormat(Paths.font('vcr.ttf'), 32);
		chartingText.x = FlxG.width - (chartingText.width + 20);
		chartingText.y = FlxG.height - (chartingText.height + 20);
		chartingText.updateHitbox();
		chartingText.visible = PlayState.chartingMode;
		add(chartingText);

		blueballedTxt.alpha = 0;
		levelDifficulty.alpha = 0;
		levelInfo.alpha = 0;

		levelInfo.x = FlxG.width - (levelInfo.width + 20);
		levelDifficulty.x = FlxG.width - (levelDifficulty.width + 20);
		blueballedTxt.x = FlxG.width - (blueballedTxt.width + 20);

		FlxTween.tween(bg, {alpha: 0.6}, 0.4, {ease: FlxEase.quartInOut});
		FlxTween.tween(levelInfo, {alpha: 1, y: 20}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.3});
		FlxTween.tween(levelDifficulty, {alpha: 1, y: levelDifficulty.y + 5}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.5});
		FlxTween.tween(blueballedTxt, {alpha: 1, y: blueballedTxt.y + 5}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.7});

		grpMenuShit = new FlxTypedGroup<Alphabet>();
		add(grpMenuShit);

		missingTextBG = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		missingTextBG.scale.set(FlxG.width, FlxG.height);
		missingTextBG.updateHitbox();
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		regenMenu();
		cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];

		super.create();

		#if mobile
		addTouchPad('UP_DOWN', 'A_B');
		#end
	}

	function tryLoadModSettings() {
		#if MODS_ALLOWED
		var seen:Map<String, Bool> = new Map();

		// Current mod first so it sorts to the top of the menu.
		var current:String = Mods.currentModDirectory;
		if (current != null && current.trim().length > 0)
			tryAppendModSettings(current, seen);

		// Then any enabled global mod (pack.json `runsGlobally: true` -- asset replacers, script packs, etc).
		for (mod in Mods.getGlobalMods())
			tryAppendModSettings(mod, seen);
		#end
	}

	#if MODS_ALLOWED
	function tryAppendModSettings(folder:String, seen:Map<String, Bool>) {
		if (folder == null || folder.trim().length == 0 || seen.exists(folder))
			return;
		seen.set(folder, true);

		var path:String = Paths.mods('$folder/data/settings.json');
		if (!FileSystem.exists(path))
			return;

		try {
			var parsed:Array<Dynamic> = tjson.TJSON.parse(File.getContent(path));
			if (parsed == null || parsed.length < 1)
				return;
			var pack:Dynamic = Mods.getPack(folder);
			var name:String = (pack != null && pack.name != null) ? pack.name : folder;

			// Dedupe display labels: if another entry already uses this name,
			// disambiguate both with their folder names.
			var label:String = name;
			for (existing in modSettingsList) {
				if (existing.label == label) {
					existing.label = '${existing.name} (${existing.folder})';
					label = '$name ($folder)';
					break;
				}
			}

			modSettingsList.push({settings: parsed, folder: folder, name: name, label: label});
		} catch (e:Dynamic) {
			trace('Failed to load mod settings for $folder: $e');
		}
	}
	#end

	// Opens a ModSettingsSubState as a nested substate while hiding the pause UI behind it.
	// Without this, the pause menu (items, dim bg, info text) keeps drawing on top of the
	// child substate, which makes it look like the settings opened "behind" the pause menu.
	function openModSettings(entry:{settings:Array<Dynamic>, folder:String, name:String, label:String}) {
		var sub = new options.ModSettingsSubState(entry.settings, entry.folder, entry.name);
		// PauseSubState uses its own dedicated camera (see create()), which is drawn last
		// in FlxG.cameras.list. If ModSettings used the default camera, the pause menu
		// would render on top of it. Reuse this substate's camera so draw order matches
		// the OptionsState -> BaseOptionsMenu pattern (parent's bg covered by child's bg).
		sub.cameras = cameras;
		openSubState(sub);
	}

	function getPauseSong() {
		var formattedSongName:String = (songName != null ? Paths.formatToSongPath(songName) : '');
		var formattedPauseMusic:String = Paths.formatToSongPath(ClientPrefs.data.pauseMusic);
		if (formattedSongName == 'none' || (formattedSongName != 'none' && formattedPauseMusic == 'none'))
			return null;

		return (formattedSongName != '') ? formattedSongName : formattedPauseMusic;
	}

	var holdTime:Float = 0;
	var cantUnpause:Float = 0.1;

	override function update(elapsed:Float) {
		cantUnpause -= elapsed;
		if (pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		super.update(elapsed);

		if (controls.BACK) {
			close();
			return;
		}

		if (FlxG.keys.justPressed.F5) {
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			PlayState.nextReloadAll = true;
			MusicBeatState.resetState();
		}

		updateSkipTextStuff();
		if (controls.UI_UP_P) {
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P) {
			changeSelection(1);
		}

		var daSelected:String = menuItems[curSelected];
		switch (daSelected) {
			case 'Skip Time':
				if (controls.UI_LEFT_P) {
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime -= 1000;
					holdTime = 0;
				}
				if (controls.UI_RIGHT_P) {
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
					curTime += 1000;
					holdTime = 0;
				}

				if (controls.UI_LEFT || controls.UI_RIGHT) {
					holdTime += elapsed;
					if (holdTime > 0.5) {
						curTime += 45000 * elapsed * (controls.UI_LEFT ? -1 : 1);
					}

					if (curTime >= FlxG.sound.music.length)
						curTime -= FlxG.sound.music.length;
					else if (curTime < 0)
						curTime += FlxG.sound.music.length;
					updateSkipTimeText();
				}
		}

		if (controls.ACCEPT && (cantUnpause <= 0 || !controls.controllerMode)) {
			if (menuItems == difficultyChoices) {
				var songLowercase:String = Paths.formatToSongPath(PlayState.SONG.song);
				var poop:String = Highscore.formatSong(songLowercase, curSelected);
				try {
					if (menuItems.length - 1 != curSelected && difficultyChoices.contains(daSelected)) {
						Song.loadFromJson(poop, songLowercase);
						PlayState.storyDifficulty = curSelected;
						MusicBeatState.resetState();
						FlxG.sound.music.volume = 0;
						PlayState.changedDifficulty = true;
						PlayState.chartingMode = false;
						return;
					}
				} catch (e:haxe.Exception) {
					trace('ERROR! ${e.message}');

					var errorStr:String = e.message;
					if (errorStr.startsWith('[lime.utils.Assets] ERROR:'))
						errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length - 1); // Missing chart
					else
						errorStr += '\n\n' + e.stack;

					missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
					missingText.screenCenter(Y);
					missingText.visible = true;
					missingTextBG.visible = true;
					FlxG.sound.play(Paths.sound('cancelMenu'));

					super.update(elapsed);
					return;
				}

				menuItems = menuItemsOG;
				regenMenu();
			}

			if (menuItems == modOptionsChoices) {
				if (daSelected == 'BACK') {
					menuItems = menuItemsOG;
					regenMenu();
					return;
				}
				for (entry in modSettingsList) {
					if (entry.label == daSelected) {
						openModSettings(entry);
						return;
					}
				}
				return;
			}

			switch (daSelected) {
				case "Resume":
					close();
				case 'Change Difficulty':
					menuItems = difficultyChoices;
					deleteSkipTimeText();
					regenMenu();
				case 'Mod Options':
					if (modSettingsList.length == 1) {
						openModSettings(modSettingsList[0]);
					} else if (modSettingsList.length > 1) {
						menuItems = modOptionsChoices;
						deleteSkipTimeText();
						regenMenu();
					}
				case 'Toggle Practice Mode':
					PlayState.instance.practiceMode = !PlayState.instance.practiceMode;
					PlayState.changedDifficulty = true;
					practiceText.visible = PlayState.instance.practiceMode;
				case "Restart Song":
					restartSong();
				case "Leave Charting Mode":
					restartSong();
					PlayState.chartingMode = false;
				case 'Skip Time':
					if (curTime < Conductor.songPosition) {
						PlayState.startOnTime = curTime;
						restartSong(true);
					} else {
						if (curTime != Conductor.songPosition) {
							PlayState.instance.clearNotesBefore(curTime);
							PlayState.instance.setSongTime(curTime);
						}
						close();
					}
				case 'End Song':
					close();
					PlayState.instance.notes.clear();
					PlayState.instance.unspawnNotes = [];
					PlayState.instance.finishSong(true);
				case 'Toggle Botplay':
					PlayState.instance.cpuControlled = !PlayState.instance.cpuControlled;
					PlayState.changedDifficulty = true;
					PlayState.instance.botplayTxt.visible = PlayState.instance.cpuControlled;
					PlayState.instance.botplayTxt.alpha = 1;
					PlayState.instance.botplaySine = 0;
				case 'Options':
					PlayState.instance.paused = true; // For lua
					PlayState.instance.vocals.volume = 0;
					PlayState.instance.canResync = false;
					MusicBeatState.switchState(new OptionsState());
					if (ClientPrefs.data.pauseMusic != 'None') {
						FlxG.sound.playMusic(Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic)), pauseMusic.volume);
						FlxTween.tween(FlxG.sound.music, {volume: 1}, 0.8);
						FlxG.sound.music.time = pauseMusic.time;
					}
					OptionsState.onPlayState = true;
				case "Exit to menu":
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
					PlayState.deathCounter = 0;
					PlayState.seenCutscene = false;

					PlayState.instance.canResync = false;
					if (PlayState.exitToScriptedStateIfNeeded()) {
						// returned to the launching mod's scripted state
					} else {
						Mods.loadTopMod();
						if (PlayState.isStoryMode)
							MusicBeatState.switchState(new StoryMenuState());
						else
							MusicBeatState.switchState(new FreeplayState());

						FlxG.sound.playMusic(Paths.music('freakyMenu'));
					}
					PlayState.changedDifficulty = false;
					PlayState.chartingMode = false;
					FlxG.camera.followLerp = 0;
			}
		}
	}

	function deleteSkipTimeText() {
		if (skipTimeText != null) {
			skipTimeText.kill();
			remove(skipTimeText);
			skipTimeText.destroy();
		}
		skipTimeText = null;
		skipTimeTracker = null;
	}

	public static function restartSong(noTrans:Bool = false) {
		PlayState.instance.paused = true; // For lua
		FlxG.sound.music.volume = 0;
		PlayState.instance.vocals.volume = 0;

		if (noTrans) {
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
		}
		MusicBeatState.resetState();
	}

	override function destroy() {
		pauseMusic.destroy();
		super.destroy();
	}

	function changeSelection(change:Int = 0):Void {
		curSelected = FlxMath.wrap(curSelected + change, 0, menuItems.length - 1);
		for (num => item in grpMenuShit.members) {
			item.targetY = num - curSelected;
			item.alpha = 0.6;
			if (item.targetY == 0) {
				item.alpha = 1;
				if (item == skipTimeTracker) {
					curTime = Math.max(0, Conductor.songPosition);
					updateSkipTimeText();
				}
			}
		}
		missingText.visible = false;
		missingTextBG.visible = false;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
	}

	function regenMenu():Void {
		for (i in 0...grpMenuShit.members.length) {
			var obj:Alphabet = grpMenuShit.members[0];
			obj.kill();
			grpMenuShit.remove(obj, true);
			obj.destroy();
		}

		for (num => str in menuItems) {
			var item = new Alphabet(90, 320, Language.getPhrase('pause_$str', str), true);
			item.isMenuItem = true;
			item.targetY = num;
			grpMenuShit.add(item);

			// Long labels (mod/pack names) would overflow the screen at full scale -- shrink to fit.
			var maxWidth:Float = FlxG.width - 180;
			if (item.width > maxWidth) {
				var s:Float = maxWidth / item.width;
				item.setScale(item.scale.x * s, item.scale.y * s);
			}

			if (str == 'Skip Time') {
				skipTimeText = new FlxText(0, 0, 0, '', 64);
				skipTimeText.setFormat(Paths.font("vcr.ttf"), 64, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				skipTimeText.scrollFactor.set();
				skipTimeText.borderSize = 2;
				skipTimeTracker = item;
				add(skipTimeText);

				updateSkipTextStuff();
				updateSkipTimeText();
			}
		}
		curSelected = 0;
		changeSelection();
	}

	function updateSkipTextStuff() {
		if (skipTimeText == null || skipTimeTracker == null)
			return;

		skipTimeText.x = skipTimeTracker.x + skipTimeTracker.width + 60;
		skipTimeText.y = skipTimeTracker.y;
		skipTimeText.visible = (skipTimeTracker.alpha >= 1);
	}

	function updateSkipTimeText()
		skipTimeText.text = FlxStringUtil.formatTime(Math.max(0, Math.floor(curTime / 1000)), false)
			+ ' / '
			+ FlxStringUtil.formatTime(Math.max(0, Math.floor(FlxG.sound.music.length / 1000)), false);
}
