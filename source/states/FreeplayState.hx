package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import backend.SongMeta;
import backend.SongMeta.SongMetaInfo;
import objects.HealthIcon;
import objects.MusicPlayer;
import states.freeplay.FreeplayInfoFlyout;
import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import flixel.math.FlxMath;
import flixel.util.FlxDestroyUtil;
import openfl.utils.Assets;
import haxe.Json;

class FreeplayState extends MusicBeatState {
	var songs:Array<SongMetadata> = [];

	var selector:FlxText;

	private static var curSelected:Int = 0;

	var lerpSelected:Float = 0;
	var curDifficulty:Int = -1;

	private static var lastDifficultyName:String = Difficulty.getDefault();

	var scoreBG:FlxSprite;
	var scoreText:FlxText;
	var diffText:FlxText;
	var lerpScore:Int = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	private var grpSongs:FlxTypedGroup<Alphabet>;
	private var curPlaying:Bool = false;

	private var iconArray:Array<HealthIcon> = [];
	private var starArray:Array<FlxSprite> = [];

	var bg:FlxSprite;
	var intendedColor:Int;

	var missingTextBG:FlxSprite;
	var missingText:FlxText;

	var bottomString:String;
	var bottomText:FlxText;
	var bottomBG:FlxSprite;

	var player:MusicPlayer;
	var infoFlyout:FreeplayInfoFlyout; // right-edge metadata + difficulty-rating panel

	var allSongs:Array<SongMetadata> = []; // unfiltered master list; `songs` is the filtered view
	var initialized:Bool = false; // false until create() finishes building the song list
	var grpIcons:FlxTypedGroup<HealthIcon>;
	var grpStars:FlxTypedGroup<FlxSprite>; // star.png markers shown beside favorited songs

	static final SORTS:Array<String> = ['WEEK', 'A-Z', 'SCORE', 'FAVES'];

	var curSort:Int = 0;
	var groupOptions:Array<Int> = [-1]; // -1 = ALL, else a week index that actually has songs
	var curGroupIdx:Int = 0;
	var weekNames:Array<String> = [];

	var searching:Bool = false;
	var searchQuery:String = '';
	var favorites:Array<String> = [];

	var headerBar:FlxSprite;
	var searchTxt:FlxText;
	var sortTxt:FlxText;
	var groupTxt:FlxText;

	override function create() {
		// Paths.clearStoredMemory();
		// Paths.clearUnusedMemory();

		persistentUpdate = true;
		PlayState.isStoryMode = false;
		WeekData.reloadWeekFiles(false);

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menus", null);
		#end

		for (i in 0...WeekData.weeksList.length) {
			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			// keep a label per week index (even locked ones) so song.week stays aligned
			weekNames[i] = (leWeek.storyName != null && leWeek.storyName.length > 0) ? leWeek.storyName : WeekData.weeksList[i];

			if (weekIsLocked(WeekData.weeksList[i]))
				continue;

			var leSongs:Array<String> = [];
			var leChars:Array<String> = [];

			for (j in 0...leWeek.songs.length) {
				leSongs.push(leWeek.songs[j][0]);
				leChars.push(leWeek.songs[j][1]);
			}

			var weekDiffs:Array<String> = (leWeek.difficulties != null && leWeek.difficulties.length > 0) ? leWeek.difficulties.split(',') : null;

			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs) {
				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3) {
					colors = [146, 113, 253];
				}
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]), Difficulty.getDifficultiesForSong(song[0], weekDiffs));
			}
		}

		// Freeplay no longer needs a week file: also list any song with charts on disk
		// (data/<song>/<song>.json) that no week declared. Weeks remain for Story mode
		// and for setting a custom icon/order without a metadata.json.
		discoverFreeplaySongs(WeekData.weeksList.length);

		if (allSongs.length < 1) {
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO SONGS FOUND FOR FREEPLAY\n\nAdd a song (data/<song>/<song>.json) to an enabled mod,\nor make a week.\n\nPress ACCEPT for the Week Editor.\nPress BACK to return to Main Menu.",
				function() MusicBeatState.switchState(new editors.WeekEditorState()),
				function() MusicBeatState.switchState(new states.MainMenuState())));
			return;
		}
		Mods.loadTopMod();

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		bg.screenCenter();

		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);
		grpIcons = new FlxTypedGroup<HealthIcon>();
		add(grpIcons);
		grpStars = new FlxTypedGroup<FlxSprite>();
		add(grpStars);

		if (FlxG.save.data.freeplayFavorites != null)
			favorites = FlxG.save.data.freeplayFavorites;

		// Group filter only offers weeks that actually contain songs (+ ALL).
		groupOptions = [-1];
		for (meta in allSongs)
			if (groupOptions.indexOf(meta.week) < 0)
				groupOptions.push(meta.week);

		applyFilters();
		rebuildSongList();

		scoreText = new FlxText(FlxG.width * 0.7, 39, 0, "", 32);
		scoreText.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);

		scoreBG = new FlxSprite(scoreText.x - 6, 34).makeGraphic(1, 66, 0xFF000000);
		scoreBG.alpha = 0.6;
		add(scoreBG);

		diffText = new FlxText(scoreText.x, scoreText.y + 36, 0, "", 24);
		diffText.font = scoreText.font;
		add(diffText);

		add(scoreText);

		headerBar = new FlxSprite(0, 0).makeGraphic(FlxG.width, 34, 0xFF000000);
		headerBar.alpha = 0.6;
		add(headerBar);

		sortTxt = makeHeaderLabel(0);
		groupTxt = makeHeaderLabel(1);
		searchTxt = makeHeaderLabel(2);

		missingTextBG = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		missingTextBG.alpha = 0.6;
		missingTextBG.visible = false;
		add(missingTextBG);

		missingText = new FlxText(50, 0, FlxG.width - 100, '', 24);
		missingText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingText.scrollFactor.set();
		missingText.visible = false;
		add(missingText);

		if (curSelected >= songs.length)
			curSelected = 0;
		if (songs.length > 0) {
			bg.color = songs[curSelected].color;
			intendedColor = bg.color;
		}
		lerpSelected = curSelected;

		curDifficulty = Math.round(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		bottomBG = new FlxSprite(0, FlxG.height - 26).makeGraphic(FlxG.width, 26, 0xFF000000);
		bottomBG.alpha = 0.6;
		add(bottomBG);

		var leText:String = Language.getPhrase("freeplay_tip2", "TAB Search  Q/E Group  T Sort  F Favorite  I Info  SPACE Listen  CTRL Changers  RESET Score");
		bottomString = leText;
		var size:Int = 16;
		bottomText = new FlxText(bottomBG.x, bottomBG.y + 4, FlxG.width, leText, size);
		bottomText.setFormat(Paths.font("vcr.ttf"), size, FlxColor.WHITE, CENTER);
		bottomText.scrollFactor.set();
		add(bottomText);

		player = new MusicPlayer(this);
		add(player);

		infoFlyout = new FreeplayInfoFlyout();
		infoFlyout.onChangeDiff = function(dir:Int) {
			changeDiff(dir);
			_updateSongLastDifficulty();
		};
		add(infoFlyout);

		updateHeader();
		changeSelection();
		updateTexts();
		initialized = true;
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		addActionButtons([['SEARCH', 'SRCH'], ['SORT', 'SORT'], ['GROUPL', 'GRP-'], ['GROUPR', 'GRP+'], ['FAV', 'FAV'], ['INFO', 'INFO'], ['CHANGERS', 'CHNG']]);
		#end
	}

	override function closeSubState() {
		changeSelection(0, false);
		persistentUpdate = true;
		super.closeSubState();
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String, color:Int, ?difficulties:Array<String>) {
		// An optional data/<song>/metadata.json can override the icon, color and the
		// difficulty order, and carry info (charter/source). It applies to any song.
		var info:SongMetaInfo = SongMeta.load(Paths.formatToSongPath(songName));
		var icon:String = songCharacter;
		var col:Int = color;
		var diffs:Array<String> = difficulties;
		if (info != null) {
			if (info.icon != null && info.icon.length > 0)
				icon = info.icon;
			if (info.color != null && info.color.length >= 3)
				col = FlxColor.fromRGB(info.color[0], info.color[1], info.color[2]);
			if (info.difficulties != null && info.difficulties.length > 0)
				diffs = Difficulty.getDifficultiesForSong(songName, info.difficulties);
		}

		var meta:SongMetadata = new SongMetadata(songName, weekNum, icon, col);
		meta.origIndex = allSongs.length;
		if (diffs != null && diffs.length > 0)
			meta.difficulties = diffs;
		if (info != null) {
			meta.charter = info.charter;
			meta.source = (info.source != null && info.source.length > 0) ? info.source : info.mod; // `source` canonical, `mod` alias
			meta.artist = info.artist;
			if (info.beatmapId != null)
				meta.beatmapId = info.beatmapId;
			meta.info = info.info;
			meta.tags = info.tags;
			if (info.displayBpm != null)
				meta.displayBpm = info.displayBpm;
			meta.displayTimeSignature = info.displayTimeSignature;
			meta.charters = info.charters;
		}
		allSongs.push(meta);
	}

	// Lists songs that have charts on disk (data/<song>/<song>.json) in any enabled
	// mod but aren't declared by a week, so Freeplay works without week files. Each
	// gets a synthetic group `freeplayWeek`. Deduped against already-added songs.
	function discoverFreeplaySongs(freeplayWeek:Int) {
		#if (sys && MODS_ALLOWED)
		var seen:Map<String, Bool> = new Map();
		for (meta in allSongs)
			seen.set(meta.folder + '|' + Paths.formatToSongPath(meta.songName), true);

		var roots:Array<Array<String>> = []; // [modFolder, dataDir]
		for (mod in Mods.parseList().enabled)
			roots.push([mod, Paths.mods('$mod/data')]);
		roots.push(['', Paths.mods('data')]);

		var added:Bool = false;
		for (root in roots) {
			var modFolder:String = root[0];
			var dataDir:String = root[1];
			if (!FileSystem.exists(dataDir) || !FileSystem.isDirectory(dataDir))
				continue;

			for (entry in FileSystem.readDirectory(dataDir)) {
				var songDir:String = '$dataDir/$entry';
				if (!FileSystem.isDirectory(songDir))
					continue;
				var key:String = Paths.formatToSongPath(entry);
				if (seen.exists('$modFolder|$key'))
					continue;
				var chart:String = representativeChart(songDir, key);
				if (chart == null)
					continue;
				seen.set('$modFolder|$key', true);

				Mods.currentModDirectory = modFolder;
				var display:String = chartSongName(chart, entry);
				if (Paths.formatToSongPath(display) != key)
					display = entry; // keep it loadable (folder name must format to the key)
				addSong(display, freeplayWeek, 'face', FlxColor.fromRGB(146, 113, 253), Difficulty.getDifficultiesForSong(display, null));
				added = true;
			}
		}
		if (added)
			weekNames[freeplayWeek] = 'Other Songs';
		backend.difficulty.ChartScanCache.commit(); // persist any newly-scanned names in one write
		#end
	}

	#if sys
	function representativeChart(songDir:String, key:String):String {
		var bare:String = '$songDir/$key.json';
		if (FileSystem.exists(bare))
			return bare;
		for (file in FileSystem.readDirectory(songDir))
			if (file.startsWith('$key-') && file.endsWith('.json'))
				return '$songDir/$file';
		return null;
	}

	function chartSongName(chartPath:String, fallback:String):String {
		// cache-first by file signature: an unchanged chart skips the whole-file parse below
		return backend.difficulty.ChartScanCache.songName(chartPath, function():String {
			try {
				var data:Dynamic = tjson.TJSON.parse(File.getContent(chartPath));
				var sub:Dynamic = Reflect.field(data, 'song');
				if (sub != null) {
					if (Std.isOfType(sub, String))
						return sub;
					var inner:Dynamic = Reflect.field(sub, 'song');
					if (inner != null)
						return Std.string(inner);
				}
			} catch (error:Dynamic) {}
			return fallback;
		});
	}
	#end

	function weekIsLocked(name:String):Bool {
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	var instPlaying:Int = -1;

	public static var vocals:FlxSound = null;
	public static var opponentVocals:FlxSound = null;

	var holdTime:Float = 0;

	var stopMusicPlay:Bool = false;

	override function update(elapsed:Float) {
		if (!initialized)
			return;

		if (FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		lerpScore = Math.floor(FlxMath.lerp(intendedScore, lerpScore, Math.exp(-elapsed * 24)));
		lerpRating = FlxMath.lerp(intendedRating, lerpRating, Math.exp(-elapsed * 12));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.01)
			lerpRating = intendedRating;

		var ratingSplit:Array<String> = Std.string(CoolUtil.floorDecimal(lerpRating * 100, 2)).split('.');
		if (ratingSplit.length < 2) // No decimals, add an empty space
			ratingSplit.push('');

		while (ratingSplit[1].length < 2) // Less than 2 decimals in it, add decimals then
			ratingSplit[1] += '0';

		var shiftMult:Int = 1;
		if (FlxG.keys.pressed.SHIFT)
			shiftMult = 3;

		// While typing a search, swallow all other input. Only the arrow keys still
		// move the selection (WASD would clash with the letters being typed).
		if (searching) {
			handleSearchInput();
			#if android
			if (controls.BACK) {
				endSearch();
				super.update(elapsed);
				return;
			}
			#end
			if (songs.length > 0) {
				if (FlxG.keys.justPressed.DOWN)
					changeSelection(1);
				else if (FlxG.keys.justPressed.UP)
					changeSelection(-1);
			}
			updateTexts(elapsed);
			super.update(elapsed);
			return;
		}

		// Info flyout is a focused sub-mode: while open it captures navigation so the
		// song list stays put, and it handles its own scroll / collapse / diff-switch.
		if (infoFlyout != null && infoFlyout.open) {
			infoFlyout.updateInput(elapsed);
			if (FlxG.keys.justPressed.I || controls.BACK) {
				infoFlyout.close();
				FlxG.sound.play(Paths.sound('cancelMenu'));
			}
			updateTexts(elapsed);
			super.update(elapsed);
			return;
		}

		if (!player.playingMusic) {
			scoreText.text = Language.getPhrase('personal_best', 'PERSONAL BEST: {1} ({2}%)', [lerpScore, ratingSplit.join('.')]);
			positionHighscore();

			if (songs.length > 1) {
				if (FlxG.keys.justPressed.HOME) {
					curSelected = 0;
					changeSelection();
					holdTime = 0;
				} else if (FlxG.keys.justPressed.END) {
					curSelected = songs.length - 1;
					changeSelection();
					holdTime = 0;
				}
				if (controls.UI_UP_P) {
					changeSelection(-shiftMult);
					holdTime = 0;
				}
				if (controls.UI_DOWN_P) {
					changeSelection(shiftMult);
					holdTime = 0;
				}

				if (controls.UI_DOWN || controls.UI_UP) {
					var checkLastHold:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var checkNewHold:Int = Math.floor((holdTime - 0.5) * 10);

					if (holdTime > 0.5 && checkNewHold - checkLastHold > 0)
						changeSelection((checkNewHold - checkLastHold) * (controls.UI_UP ? -shiftMult : shiftMult));
				}

				if (FlxG.mouse.wheel != 0) {
					FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
					changeSelection(-shiftMult * FlxG.mouse.wheel, false);
				}
			}

			if (controls.UI_LEFT_P) {
				changeDiff(-1);
				_updateSongLastDifficulty();
			} else if (controls.UI_RIGHT_P) {
				changeDiff(1);
				_updateSongLastDifficulty();
			}

			if (FlxG.keys.justPressed.TAB || actionButtonJustPressed('SEARCH'))
				beginSearch();
			else if (FlxG.keys.justPressed.T || actionButtonJustPressed('SORT'))
				cycleSort();
			else if (FlxG.keys.justPressed.Q || actionButtonJustPressed('GROUPL'))
				cycleGroup(-1);
			else if (FlxG.keys.justPressed.E || actionButtonJustPressed('GROUPR'))
				cycleGroup(1);
			else if (FlxG.keys.justPressed.F || actionButtonJustPressed('FAV'))
				toggleFavorite();
			else if ((FlxG.keys.justPressed.I || actionButtonJustPressed('INFO')) && songs.length > 0 && ClientPrefs.data.difficultyFlyout) {
				infoFlyout.setSong(songs[curSelected], curDifficulty);
				infoFlyout.openFlyout();
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			}
		}

		if (controls.BACK) {
			if (player.playingMusic) {
				FlxG.sound.music.stop();
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				instPlaying = -1;

				player.playingMusic = false;
				player.switchPlayMusic();

				FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
				FlxTween.tween(FlxG.sound.music, {volume: 1}, 1);
			} else if (searchQuery.length > 0 || curGroupIdx != 0 || curSort != 0) {
				// First BACK clears any active search/sort/group, second leaves.
				var sel:SongMetadata = songs.length > 0 ? songs[curSelected] : null;
				searchQuery = '';
				curGroupIdx = 0;
				curSort = 0;
				searching = false;
				applyFilters();
				rebuildSongList();
				restoreSelection(sel);
				updateHeader();
				FlxG.sound.play(Paths.sound('cancelMenu'));
			} else {
				persistentUpdate = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
		}

		if ((FlxG.keys.justPressed.CONTROL || actionButtonJustPressed('CHANGERS')) && !player.playingMusic) {
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
		} else if (FlxG.keys.justPressed.SPACE && songs.length > 0) {
			if (instPlaying != curSelected && !player.playingMusic) {
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;

				Mods.currentModDirectory = songs[curSelected].folder;
				var poop:String = Highscore.formatSong(songs[curSelected].songName.toLowerCase(), curDifficulty);
				Song.loadFromJson(poop, songs[curSelected].songName.toLowerCase());
				if (PlayState.SONG.needsVoices) {
					vocals = new FlxSound();
					try {
						var playerVocals:String = getVocalFromCharacter(PlayState.SONG.player1);
						var loadedVocals = Paths.voices(PlayState.SONG.song, (playerVocals != null && playerVocals.length > 0) ? playerVocals : 'Player');
						if (loadedVocals == null)
							loadedVocals = Paths.voices(PlayState.SONG.song);

						if (loadedVocals != null && loadedVocals.length > 0) {
							vocals.loadEmbedded(loadedVocals);
							FlxG.sound.list.add(vocals);
							vocals.persist = vocals.looped = true;
							vocals.volume = 0.8;
							vocals.play();
							vocals.pause();
						} else
							vocals = FlxDestroyUtil.destroy(vocals);
					} catch (e:Dynamic) {
						vocals = FlxDestroyUtil.destroy(vocals);
					}

					opponentVocals = new FlxSound();
					try {
						// trace('please work...');
						var oppVocals:String = getVocalFromCharacter(PlayState.SONG.player2);
						var loadedVocals = Paths.voices(PlayState.SONG.song, (oppVocals != null && oppVocals.length > 0) ? oppVocals : 'Opponent');

						if (loadedVocals != null && loadedVocals.length > 0) {
							opponentVocals.loadEmbedded(loadedVocals);
							FlxG.sound.list.add(opponentVocals);
							opponentVocals.persist = opponentVocals.looped = true;
							opponentVocals.volume = 0.8;
							opponentVocals.play();
							opponentVocals.pause();
							// trace('yaaay!!');
						} else
							opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
					} catch (e:Dynamic) {
						// trace('FUUUCK');
						opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
					}
				}

				FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 0.8);
				FlxG.sound.music.pause();
				instPlaying = curSelected;

				player.playingMusic = true;
				player.curTime = 0;
				player.switchPlayMusic();
				player.pauseOrResume(true);
			} else if (instPlaying == curSelected && player.playingMusic) {
				player.pauseOrResume(!player.playing);
			}
		} else if (controls.ACCEPT && !player.playingMusic && songs.length > 0) {
			persistentUpdate = false;
			var songLowercase:String = Paths.formatToSongPath(songs[curSelected].songName);
			var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

			try {
				Song.loadFromJson(poop, songLowercase);
				PlayState.isStoryMode = false;
				PlayState.storyDifficulty = curDifficulty;

				trace('CURRENT WEEK: ' + WeekData.getWeekFileName());
			} catch (e:haxe.Exception) {
				trace('ERROR! ${e.message}');

				var errorStr:String = e.message;
				if (errorStr.contains('There is no TEXT asset with an ID of'))
					errorStr = 'Missing file: ' + errorStr.substring(errorStr.indexOf(songLowercase), errorStr.length - 1); // Missing chart
				else
					errorStr += '\n\n' + e.stack;

				missingText.text = 'ERROR WHILE LOADING CHART:\n$errorStr';
				missingText.screenCenter(Y);
				missingText.visible = true;
				missingTextBG.visible = true;
				FlxG.sound.play(Paths.sound('cancelMenu'));

				updateTexts(elapsed);
				super.update(elapsed);
				return;
			}
			@:privateAccess
			if (PlayState._lastLoadedModDirectory != Mods.currentModDirectory) {
				trace('CHANGED MOD DIRECTORY, RELOADING STUFF');
				Paths.freeGraphicsFromMemory();
			}
			LoadingState.prepareToSong();
			LoadingState.loadAndSwitchState(new PlayState());
			#if !SHOW_LOADING_SCREEN FlxG.sound.music.stop(); #end
			stopMusicPlay = true;

			destroyFreeplayVocals();
			#if (MODS_ALLOWED && DISCORD_ALLOWED)
			DiscordClient.loadModRPC();
			#end
		} else if (controls.RESET && !player.playingMusic && songs.length > 0) {
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(songs[curSelected].songName, curDifficulty, songs[curSelected].songCharacter));
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}

		updateTexts(elapsed);
		super.update(elapsed);
	}

	function getVocalFromCharacter(char:String) {
		try {
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end
			return character.vocals_file;
		} catch (e:Dynamic) {}
		return null;
	}

	public static function destroyFreeplayVocals() {
		if (vocals != null)
			vocals.stop();
		vocals = FlxDestroyUtil.destroy(vocals);

		if (opponentVocals != null)
			opponentVocals.stop();
		opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
	}

	function changeDiff(change:Int = 0) {
		if (player.playingMusic || songs.length < 1)
			return;

		curDifficulty = FlxMath.wrap(curDifficulty + change, 0, Difficulty.list.length - 1);
		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].songName, curDifficulty);
		intendedRating = Highscore.getRating(songs[curSelected].songName, curDifficulty);
		#end

		lastDifficultyName = Difficulty.getString(curDifficulty, false);
		var displayDiff:String = Difficulty.getString(curDifficulty);
		if (Difficulty.list.length > 1)
			diffText.text = '< ' + displayDiff.toUpperCase() + ' >';
		else
			diffText.text = displayDiff.toUpperCase();

		positionHighscore();
		missingText.visible = false;
		missingTextBG.visible = false;
	}

	function changeSelection(change:Int = 0, playSound:Bool = true) {
		if (player.playingMusic || songs.length < 1)
			return;

		curSelected = FlxMath.wrap(curSelected + change, 0, songs.length - 1);
		_updateSongLastDifficulty();
		if (playSound)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var newColor:Int = songs[curSelected].color;
		if (newColor != intendedColor) {
			intendedColor = newColor;
			FlxTween.cancelTweensOf(bg);
			FlxTween.color(bg, 1, bg.color, intendedColor);
		}

		for (num => item in grpSongs.members) {
			var icon:HealthIcon = iconArray[num];
			item.alpha = 0.6;
			icon.alpha = 0.6;
			if (item.targetY == curSelected) {
				item.alpha = 1;
				icon.alpha = 1;
			}
		}

		Mods.currentModDirectory = songs[curSelected].folder;
		PlayState.storyWeek = songs[curSelected].week;
		// Per-song difficulties (derived from charts on disk), not the whole week's list.
		Difficulty.copyFrom(songs[curSelected].difficulties);

		var savedDiff:String = songs[curSelected].lastDifficulty;
		var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
		if (savedDiff != null && Difficulty.list.contains(savedDiff))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(savedDiff)));
		else if (lastDiff > -1)
			curDifficulty = lastDiff;
		else if (Difficulty.list.contains(Difficulty.getDefault()))
			curDifficulty = Math.round(Math.max(0, Difficulty.list.indexOf(Difficulty.getDefault())));
		else
			curDifficulty = 0;

		changeDiff();
		_updateSongLastDifficulty();
	}

	inline private function _updateSongLastDifficulty() {
		if (songs.length > 0)
			songs[curSelected].lastDifficulty = Difficulty.getString(curDifficulty, false);
	}

	private function positionHighscore() {
		scoreText.x = FlxG.width - scoreText.width - 6;
		scoreBG.scale.x = FlxG.width - scoreText.x + 6;
		scoreBG.x = FlxG.width - (scoreBG.scale.x / 2);
		diffText.x = Std.int(scoreBG.x + (scoreBG.width / 2));
		diffText.x -= diffText.width / 2;
	}

	// Three equal columns, each text centered in its column -- keeps the labels clear
	// of the top-left FPS/debug counter.
	inline function makeHeaderLabel(col:Int):FlxText {
		var colW:Float = FlxG.width / 3;
		var t:FlxText = new FlxText(col * colW, 6, colW, "", 18);
		t.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1;
		add(t);
		return t;
	}

	function updateHeader() {
		sortTxt.text = 'SORT: ' + SORTS[curSort];
		var g:Int = groupOptions[curGroupIdx];
		groupTxt.text = 'GROUP: ' + (g < 0 ? 'ALL' : weekNames[g]);
		if (searching)
			searchTxt.text = 'SEARCH: ' + searchQuery + '_';
		else
			searchTxt.text = searchQuery.length > 0 ? 'SEARCH: ' + searchQuery : 'SEARCH';
	}

	inline function favKey(s:SongMetadata):String
		return '${s.folder}|${s.songName}';

	inline function isFavorite(s:SongMetadata):Bool
		return favorites.indexOf(favKey(s)) >= 0;

	// Best score for a song at its currently-relevant difficulty, without mutating
	// the global Difficulty.list (used by the SCORE sort across heterogeneous songs).
	function bestScoreFor(s:SongMetadata):Int {
		var diffName:String = (s.difficulties.indexOf(lastDifficultyName) >= 0) ? lastDifficultyName : s.difficulties[0];
		var key:String = Difficulty.scoreKey(s.songName, diffName);
		return Highscore.songScores.exists(key) ? Highscore.songScores.get(key) : 0;
	}

	// Search matches the song title, artist, source/mod and any metadata tags.
	function matchesQuery(s:SongMetadata, q:String):Bool {
		if (s.songName.toLowerCase().indexOf(q) >= 0)
			return true;
		if (s.artist != null && s.artist.toLowerCase().indexOf(q) >= 0)
			return true;
		if (s.source != null && s.source.toLowerCase().indexOf(q) >= 0)
			return true;
		if (s.tags != null)
			for (tag in s.tags)
				if (tag != null && tag.toLowerCase().indexOf(q) >= 0)
					return true;
		return false;
	}

	function applyFilters() {
		var g:Int = groupOptions[curGroupIdx];
		var q:String = searchQuery.toLowerCase();
		var filtered:Array<SongMetadata> = [];
		for (s in allSongs) {
			if (g >= 0 && s.week != g)
				continue;
			if (q.length > 0 && !matchesQuery(s, q))
				continue;
			filtered.push(s);
		}

		switch (curSort) {
			case 1: // A-Z
				filtered.sort(function(a, b) {
					var an = a.songName.toLowerCase(),
						bn = b.songName.toLowerCase();
					return an < bn ? -1 : (an > bn ? 1 : 0);
				});
			case 2: // SCORE (desc)
				filtered.sort((a, b) -> bestScoreFor(b) - bestScoreFor(a));
			case 3: // FAVES first, then week order
				filtered.sort(function(a, b) {
					var fa = isFavorite(a) ? 0 : 1, fb = isFavorite(b) ? 0 : 1;
					return fa != fb ? fa - fb : a.origIndex - b.origIndex;
				});
			default: // WEEK
				filtered.sort((a, b) -> a.origIndex - b.origIndex);
		}
		songs = filtered;
	}

	// Recreates the Alphabet rows + icons for the current `songs` view. Visuals are
	// identical to the original create() loop; only the source list differs.
	function rebuildSongList() {
		for (icon in iconArray)
			if (icon != null) {
				grpIcons.remove(icon, true);
				icon.destroy();
			}
		for (star in starArray)
			if (star != null) {
				grpStars.remove(star, true);
				star.destroy();
			}
		iconArray = [];
		starArray = [];
		grpSongs.clear();
		_lastVisibles = [];

		for (i in 0...songs.length) {
			var songText:Alphabet = new Alphabet(LIST_X, LIST_Y, songs[i].songName, true);
			songText.targetY = i;
			// x: 0 removes the left-stagger; y: compact row step
			songText.distancePerItem.set(0, LIST_STEP);
			grpSongs.add(songText);

			songText.setScale(Math.min(LIST_SCALE, 900 / songText.width));
			songText.snapToPosition();

			Mods.currentModDirectory = songs[i].folder;
			var icon:HealthIcon = new HealthIcon(songs[i].songCharacter);
			// Positioned manually in updateTexts and shrunk to the row height.
			// autoAdjustOffset off so the scaled-down hitbox keeps x/y as top-left.
			icon.autoAdjustOffset = false;
			icon.setGraphicSize(LIST_ICON, LIST_ICON);
			icon.updateHitbox();

			// too laggy with a lot of songs, so i had to recode the logic for it
			songText.visible = songText.active = songText.isMenuItem = false;
			icon.visible = icon.active = false;

			iconArray.push(icon);
			grpIcons.add(icon);

			// Star marker overlapping the title's left edge on favorited songs
			// (positioned in updateTexts). Animated unless Low Quality is on -- only
			// favorited, on-screen stars are active, so the animation cost is bounded.
			var star:FlxSprite = new FlxSprite();
			if (!ClientPrefs.data.lowQuality) {
				star.frames = Paths.getSparrowAtlas('starMarkerAnimated');
				star.animation.addByPrefix('active', 'active', 24, true);
				star.animation.play('active');
			} else
				star.loadGraphic(Paths.image('starMarker'));
			star.antialiasing = ClientPrefs.data.antialiasing;
			star.setGraphicSize(LIST_STAR, LIST_STAR);
			star.updateHitbox();
			star.visible = star.active = false;
			starArray.push(star);
			grpStars.add(star);
		}
		WeekData.setDirectoryFromWeek();

		if (curSelected >= songs.length)
			curSelected = Std.int(Math.max(0, songs.length - 1));

		// Empty result (e.g. a search that matches nothing) gets a friendly notice.
		// (missingText may not exist yet on the very first build during create().)
		if (missingText != null) {
			if (songs.length < 1) {
				missingText.text = 'No songs match your search.';
				missingText.screenCenter(Y);
				missingText.visible = true;
				missingTextBG.visible = true;
			} else if (missingText.text == 'No songs match your search.') {
				missingText.visible = false;
				missingTextBG.visible = false;
			}
		}
	}

	// Re-point the selection at `keep` after a rebuild (or clamp to 0).
	function restoreSelection(keep:SongMetadata) {
		var idx:Int = keep != null ? songs.indexOf(keep) : -1;
		curSelected = idx >= 0 ? idx : 0;
		if (curSelected >= songs.length)
			curSelected = Std.int(Math.max(0, songs.length - 1));
		lerpSelected = curSelected;
		if (songs.length > 0) {
			bg.color = songs[curSelected].color;
			intendedColor = bg.color;
		}
		changeSelection(0, false);
	}

	function cycleSort() {
		var sel:SongMetadata = songs.length > 0 ? songs[curSelected] : null;
		curSort = (curSort + 1) % SORTS.length;
		applyFilters();
		rebuildSongList();
		restoreSelection(sel);
		updateHeader();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function cycleGroup(dir:Int) {
		var sel:SongMetadata = songs.length > 0 ? songs[curSelected] : null;
		curGroupIdx = FlxMath.wrap(curGroupIdx + dir, 0, groupOptions.length - 1);
		applyFilters();
		rebuildSongList();
		restoreSelection(sel);
		updateHeader();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function toggleFavorite() {
		if (songs.length < 1)
			return;
		var sel:SongMetadata = songs[curSelected];
		var k:String = favKey(sel);
		if (favorites.indexOf(k) >= 0)
			favorites.remove(k);
		else
			favorites.push(k);
		FlxG.save.data.freeplayFavorites = favorites;
		FlxG.save.flush();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);

		if (curSort == 3) { // FAVES sort: order changes, so rebuild
			applyFilters();
			rebuildSongList();
			restoreSelection(sel);
		}
		// star markers refresh every frame in updateTexts via isFavorite()
	}

	function beginSearch() {
		searching = true;
		updateHeader();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		#if android
		mobile.backend.SoftKeyboard.open(searchType, searchBackspace, endSearch);
		#end
	}

	function endSearch() {
		searching = false;
		updateHeader();
		#if android mobile.backend.SoftKeyboard.close(); #end
	}

	#if android
	function searchType(input:String) {
		searchQuery += input.toLowerCase();
		applySearchChange();
	}

	function searchBackspace() {
		if (searchQuery.length > 0) {
			searchQuery = searchQuery.substr(0, searchQuery.length - 1);
			applySearchChange();
		}
	}

	function applySearchChange() {
		var sel:SongMetadata = songs.length > 0 ? songs[curSelected] : null;
		applyFilters();
		rebuildSongList();
		restoreSelection(sel);
		updateHeader();
	}
	#end

	function handleSearchInput() {
		var k:Int = FlxG.keys.firstJustPressed();
		if (k <= 0)
			return;
		if (k == 13 || k == 27 || k == 9) { // enter / escape / tab -> finish typing
			endSearch();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			return;
		}

		var changed:Bool = false;
		if (k == 8) { // backspace
			if (searchQuery.length > 0) {
				searchQuery = searchQuery.substr(0, searchQuery.length - 1);
				changed = true;
			}
		} else if (k == 32) { // space
			searchQuery += ' ';
			changed = true;
		} else if ((k >= 65 && k <= 90) || (k >= 48 && k <= 57)) {
			searchQuery += String.fromCharCode(k).toLowerCase();
			changed = true;
		}

		if (!changed) {
			updateHeader();
			return;
		}

		var sel:SongMetadata = songs.length > 0 ? songs[curSelected] : null;
		applyFilters();
		rebuildSongList();
		restoreSelection(sel);
		updateHeader();
	}

	// Compact list layout: left margin, selected-row baseline, per-row step
	// (multiplied by 1.3 in the position formula -> ~78px rows), text scale and
	// icon size. Halving the old sizes roughly doubles how many songs fit.
	static final LIST_X:Float = 90;
	static final LIST_Y:Float = 320;
	static final LIST_STEP:Float = 90;
	static final LIST_SCALE:Float = 0.75;
	static final LIST_ICON:Int = 90;
	static final LIST_STAR:Int = 46; // favorite-marker star, overlaps the title's left edge

	var _drawDistance:Int = 7;
	var _lastVisibles:Array<Int> = [];

	public function updateTexts(elapsed:Float = 0.0) {
		lerpSelected = FlxMath.lerp(curSelected, lerpSelected, Math.exp(-elapsed * 9.6));
		for (i in _lastVisibles) {
			grpSongs.members[i].visible = grpSongs.members[i].active = false;
			iconArray[i].visible = iconArray[i].active = false;
			starArray[i].visible = starArray[i].active = false;
		}
		_lastVisibles = [];

		var min:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected - _drawDistance)));
		var max:Int = Math.round(Math.max(0, Math.min(songs.length, lerpSelected + _drawDistance)));
		for (i in min...max) {
			var item:Alphabet = grpSongs.members[i];
			item.visible = item.active = true;
			item.x = ((item.targetY - lerpSelected) * item.distancePerItem.x) + item.startPosition.x;
			item.y = ((item.targetY - lerpSelected) * 1.3 * item.distancePerItem.y) + item.startPosition.y;

			var icon:HealthIcon = iconArray[i];
			icon.visible = icon.active = true;
			icon.x = item.x + item.width + 10;
			icon.y = item.y + (item.height - icon.height) * 0.5;

			// Star overlaps the title's top-left corner, only for favorited songs.
			var star:FlxSprite = starArray[i];
			star.visible = star.active = isFavorite(songs[i]);
			star.x = item.x - star.width * 0.7;
			star.y = item.y - star.height * 0.4;
			star.alpha = item.alpha;
			_lastVisibles.push(i);
		}
	}

	override function destroy():Void {
		super.destroy();

		FlxG.autoPause = ClientPrefs.data.autoPause;
		if (!FlxG.sound.music.playing && !stopMusicPlay)
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}
}

class SongMetadata {
	public var songName:String = "";
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var color:Int = -7179779;
	public var folder:String = "";
	public var lastDifficulty:String = null;
	public var difficulties:Array<String> = Difficulty.defaultList.copy(); // per-song, derived from charts on disk
	public var origIndex:Int = 0; // position in the unfiltered list (stable WEEK-order sort)
	public var charter:String = null; // optional, from metadata.json
	public var source:String = null; // optional, from metadata.json (e.g. "osu!")
	public var artist:String = null; // optional, from metadata.json
	public var beatmapId:Int = 0; // optional, from metadata.json (osu! converts)
	public var info:Array<{label:String, value:String}> = null; // optional free-form rows, from metadata.json
	public var tags:Array<String> = null; // optional, from metadata.json (also matched by search)
	public var displayBpm:Float = 0; // optional BPM override for the info flyout (0 == use chart bpm)
	public var displayTimeSignature:Array<Int> = null; // optional time-signature override for the info flyout
	public var charters:haxe.DynamicAccess<String> = null; // optional per-difficulty charter overrides

	public function new(song:String, week:Int, songCharacter:String, color:Int) {
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;
		this.folder = Mods.currentModDirectory;
		if (this.folder == null)
			this.folder = '';
	}
}
