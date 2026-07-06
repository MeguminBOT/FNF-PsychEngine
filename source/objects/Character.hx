package objects;

import backend.animation.PsychAnimationController;
import flixel.util.FlxSort;
import flixel.util.FlxDestroyUtil;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import haxe.Json;
import backend.Song;
import states.stages.objects.TankmenBG;

typedef CharacterFile = {
	var animations:Array<AnimArray>;
	var image:String;
	var scale:Float;
	var sing_duration:Float;
	var healthicon:String;

	var position:Array<Float>;
	var camera_position:Array<Float>;

	var flip_x:Bool;
	var no_antialiasing:Bool;
	var healthbar_colors:Array<Int>;
	var vocals_file:String;
	@:optional var loop_sing_on_hold:Null<Bool>;
	@:optional var _editor_isPlayer:Null<Bool>;
}

typedef AnimArray = {
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

class Character extends FlxSprite {
	/**
	 * In case a character is missing, it will use this on its place
	**/
	public static final DEFAULT_CHARACTER:String = 'bf';

	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;
	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var animationNotes:Array<Dynamic> = [];
	public var stunned:Bool = false;
	public var singDuration:Float = 4; // Multiplier of how long a character holds the sing pose

	/** When true, the sing animation is replayed (looped) for the duration of a held sustain instead of
		freezing on its last frame. Opt-in per character via the `loop_sing_on_hold` json field. **/
	public var loopSingOnHold:Bool = false;

	/** Set true each frame by `PlayState` while this character is actively holding a sustain; drives the
		`loopSingOnHold` re-trigger. Self-clears in `update` so it falls back to false once the hold ends. **/
	public var singHold:Bool = false;
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false; // Character use "danceLeft" and "danceRight" instead of "idle"
	public var skipDance:Bool = false;

	public var healthIcon:String = 'face';
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var missingCharacter:Bool = false;
	public var missingText:FlxText;
	public var hasMissAnimations:Bool = false;
	public var vocalsFile:String = '';

	// Used on Character Editor
	public var imageFile:String = '';
	public var jsonScale:Float = 1;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var editorIsPlayer:Null<Bool> = null;

	public var correctFlippedOffsets:Bool = true;
	public var scalableOffsets:Bool = true;

	public var baseFlipX:Bool = false;
	public var baseFlipY:Bool = false;

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false) {
		super(x, y);

		animation = new PsychAnimationController(this);

		animOffsets = new Map<String, Array<Dynamic>>();
		this.isPlayer = isPlayer;
		changeCharacter(character);

		switch (curCharacter) {
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
			case 'pico-blazin', 'darnell-blazin':
				skipDance = true;
		}
	}

	public function changeCharacter(character:String) {
		animationsArray = [];
		animOffsets = [];
		curCharacter = character;
		var characterPath:String = 'characters/$character.json';

		var path:String = Paths.getPath(characterPath, TEXT);
		#if MODS_ALLOWED
		if (!FileSystem.exists(path))
		#else
		if (!Assets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER +
				'.json'); // If a character couldn't be found, change him to BF just to prevent a crash
			missingCharacter = true;
			missingText = new FlxText(0, 0, 300, 'ERROR:\n$character.json', 16);
			missingText.alignment = CENTER;
		}

		try {
			#if MODS_ALLOWED
			loadCharacterFile(Json.parse(File.getContent(path)));
			#else
			loadCharacterFile(Json.parse(Assets.getText(path)));
			#end
		} catch (e:Dynamic) {
			trace('Error loading character file of "$character": $e');
		}

		skipDance = false;
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
		recalculateDanceIdle();
		dance();
	}

	public function loadCharacterFile(json:Dynamic) {
		isAnimateAtlas = false;
		swfMode = (json.swfMode == true);

		#if flixel_animate
		var animToFind:String = Paths.getPath('images/' + json.image + '/Animation.json', TEXT);
		if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
			isAnimateAtlas = true;
		#end

		scale.set(1, 1);
		updateHitbox();

		if (!isAnimateAtlas) {
			frames = Paths.getMultiAtlas(json.image.split(','));
		}
		#if flixel_animate
		else {
			atlas = new FlxAnimate();
			try {
				Paths.loadAnimateAtlas(atlas, json.image, null, null, swfMode);
			} catch (e:haxe.Exception) {
				FlxG.log.warn('Could not load atlas ${json.image}: $e');
				trace(e.stack);
			}
		}
		#end

		imageFile = json.image;
		jsonScale = json.scale;
		if (json.scale != 1) {
			scale.set(jsonScale, jsonScale);
			updateHitbox();
		}

		// positioning
		positionArray = json.position;
		cameraPosition = json.camera_position;

		// data
		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		loopSingOnHold = (json.loop_sing_on_hold == true);
		flipX = (json.flip_x != isPlayer);
		baseFlipX = flipX;
		baseFlipY = flipY;
		healthColorArray = (json.healthbar_colors != null && json.healthbar_colors.length > 2) ? json.healthbar_colors : [161, 161, 161];
		vocalsFile = json.vocals_file != null ? json.vocals_file : '';
		originalFlipX = (json.flip_x == true);
		editorIsPlayer = json._editor_isPlayer;

		// antialiasing
		noAntialiasing = (json.no_antialiasing == true);
		antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

		// offset auto-correction opt-outs
		if (json.correctFlippedOffsets != null)
			correctFlippedOffsets = (json.correctFlippedOffsets == true);
		if (json.scalableOffsets != null)
			scalableOffsets = (json.scalableOffsets == true);

		// animations
		animationsArray = json.animations;
		if (animationsArray != null && animationsArray.length > 0) {
			for (anim in animationsArray) {
				var animAnim:String = '' + anim.anim;
				var animName:String = '' + anim.name;
				var animFps:Int = anim.fps;
				var animLoop:Bool = !!anim.loop; // Bruh
				var animIndices:Array<Int> = anim.indices;

				if (!isAnimateAtlas) {
					if (animIndices != null && animIndices.length > 0)
						animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop);
					else
						animation.addByPrefix(animAnim, animName, animFps, animLoop);
				}
				#if flixel_animate
				else {
					// flixel-animate's addBySymbol*/addBySymbolIndices use `frameRate ??= getDefaultFramerate()`,
					// so only `null` falls back to the symbol's framerate; `0` would leave the animation frozen.
					// Many character JSONs (e.g. darnell-blazin) ship `"fps": 0` meaning "use default".
					var atlasFps:Null<Float> = (animFps > 0) ? cast animFps : null;
					if (animIndices != null && animIndices.length > 0)
						atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, atlasFps, animLoop);
					else
						atlas.anim.addBySymbol(animAnim, animName, atlasFps, animLoop);
				}
				#end

				if (anim.offsets != null && anim.offsets.length > 1)
					addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
				else
					addOffset(anim.anim, 0, 0);
			}
		}
		#if flixel_animate
		if (isAnimateAtlas)
			copyAtlasValues();
		#end
		// trace('Loaded file to character ' + curCharacter);
	}

	override function update(elapsed:Float) {
		if (isAnimateAtlas)
			atlas.update(elapsed);

		if (debugMode || (!isAnimateAtlas && animation.curAnim == null) || (isAnimateAtlas && !atlas.isAnimate)) {
			super.update(elapsed);
			return;
		}

		if (heyTimer > 0) {
			var rate:Float = (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
			heyTimer -= elapsed * rate;
			if (heyTimer <= 0) {
				var anim:String = getAnimationName();
				if (specialAnim && (anim == 'hey' || anim == 'cheer')) {
					specialAnim = false;
					dance();
				}
				heyTimer = 0;
			}
		} else if (specialAnim && isAnimationFinished()) {
			specialAnim = false;
			dance();
		} else if (getAnimationName().endsWith('miss') && isAnimationFinished()) {
			dance();
			finishAnimation();
		}

		switch (curCharacter) {
			case 'pico-speaker':
				if (animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0]) {
					var noteData:Int = 1;
					if (animationNotes[0][1] > 2)
						noteData = 3;

					noteData += FlxG.random.int(0, 1);
					playAnim('shoot' + noteData, true);
					animationNotes.shift();
				}
				if (isAnimationFinished())
					playAnim(getAnimationName(), false, false, animation.curAnim.frames.length - 3);
		}

		if (getAnimationName().startsWith('sing'))
			holdTimer += elapsed;
		else if (isPlayer)
			holdTimer = 0;

		if (!isPlayer
			&& holdTimer >= Conductor.stepCrochet * (0.0011 #if FLX_PITCH / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1) #end) * singDuration) {
			dance();
			holdTimer = 0;
		}

		var name:String = getAnimationName();
		if (isAnimationFinished() && hasAnimation('$name-loop'))
			playAnim('$name-loop');
		else if (loopSingOnHold
			&& singHold
			&& name != null
			&& name.startsWith('sing')
			&& name.indexOf('miss') < 0
			&& name.indexOf('-loop') < 0
			&& !hasAnimation('$name-loop')
			&& isAnimationFinished())
			playAnim(name, true); // replay the sing pose for the length of the held sustain

		// PlayState re-asserts this every frame the sustain is held; clearing it here lets it lapse to
		// false one frame after the hold ends (Character.update runs before PlayState's hold loop).
		singHold = false;

		super.update(elapsed);
	}

	inline public function isAnimationNull():Bool {
		return !isAnimateAtlas ? (animation.curAnim == null) : !atlas.isAnimate;
	}

	var _lastPlayedAnimation:String;

	inline public function getAnimationName():String {
		return _lastPlayedAnimation;
	}

	public function isAnimationFinished():Bool {
		if (isAnimationNull())
			return false;
		return !isAnimateAtlas ? animation.curAnim.finished : atlas.anim.finished;
	}

	public function finishAnimation():Void {
		if (isAnimationNull())
			return;

		if (!isAnimateAtlas)
			animation.curAnim.finish();
		else if (atlas.anim.curAnim != null)
			atlas.anim.curAnim.curFrame = atlas.anim.curAnim.numFrames - 1;
	}

	public function hasAnimation(anim:String):Bool {
		return animOffsets.exists(anim);
	}

	public var animPaused(get, set):Bool;

	private function get_animPaused():Bool {
		if (isAnimationNull())
			return false;
		return !isAnimateAtlas ? animation.curAnim.paused : atlas.anim.paused;
	}

	private function set_animPaused(value:Bool):Bool {
		if (isAnimationNull())
			return value;
		if (!isAnimateAtlas)
			animation.curAnim.paused = value;
		else {
			if (value)
				atlas.anim.pause();
			else
				atlas.anim.resume();
		}

		return value;
	}

	public var danced:Bool = false;

	/**
	 * FOR GF DANCING SHIT
	 */
	public function dance() {
		if (!debugMode && !skipDance && !specialAnim) {
			if (danceIdle) {
				danced = !danced;

				if (danced)
					playAnim('danceRight' + idleSuffix);
				else
					playAnim('danceLeft' + idleSuffix);
			} else if (hasAnimation('idle' + idleSuffix))
				playAnim('idle' + idleSuffix);
		}
	}

	public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void {
		specialAnim = false;
		if (!isAnimateAtlas) {
			animation.play(AnimName, Force, Reversed, Frame);
		} else {
			atlas.anim.play(AnimName, Force, Reversed, Frame);
			atlas.update(0);
		}
		_lastPlayedAnimation = AnimName;

		if (hasAnimation(AnimName)) {
			var daOffset = animOffsets.get(AnimName);
			applyAnimOffset(daOffset[0], daOffset[1]);
		}
		// else offset.set(0, 0);

		if (curCharacter.startsWith('gf-') || curCharacter == 'gf') {
			if (AnimName == 'singLEFT')
				danced = true;
			else if (AnimName == 'singRIGHT')
				danced = false;

			if (AnimName == 'singUP' || AnimName == 'singDOWN')
				danced = !danced;
		}
	}

	function loadMappedAnims():Void {
		try {
			var songData:SwagSong = Song.getChart('picospeaker', Paths.formatToSongPath(Song.loadedSongName));
			if (songData != null)
				for (section in songData.notes)
					for (songNotes in section.sectionNotes)
						animationNotes.push(songNotes);

			TankmenBG.animationNotes = animationNotes;
			animationNotes.sort(sortAnims);
		} catch (e:Dynamic) {}
	}

	function sortAnims(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int {
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	public var danceEveryNumBeats:Int = 2;

	private var settingCharacterUp:Bool = true;

	public function recalculateDanceIdle() {
		var lastDanceIdle:Bool = danceIdle;
		danceIdle = (hasAnimation('danceLeft' + idleSuffix) && hasAnimation('danceRight' + idleSuffix));

		if (settingCharacterUp) {
			danceEveryNumBeats = (danceIdle ? 1 : 2);
		} else if (lastDanceIdle != danceIdle) {
			var calc:Float = danceEveryNumBeats;
			if (danceIdle)
				calc /= 2;
			else
				calc *= 2;

			danceEveryNumBeats = Math.round(Math.max(calc, 1));
		}
		settingCharacterUp = false;
	}

	public function addOffset(name:String, x:Float = 0, y:Float = 0) {
		animOffsets[name] = [x, y];
	}

	/**
	 * Applies a stored (authored) animation offset to the live `offset`, scaling
	 * it by the ratio to the authored `jsonScale` and mirroring it only when the
	 * live flip differs from the load-time flip (baseFlipX/Y). Offsets stay as
	 * authored for a normally-loaded character (flipped-by-design ones like Pico
	 * included); the mirror only applies once flipX/flipY is changed after load,
	 * so a flipped duplicate or a setProperty('flipX', ...) reuses the same JSON
	 * without re-tuning. Atlas characters position through copyAtlasValues, so
	 * flip mirroring (frameWidth/width based) is skipped.
	 */
	public function applyAnimOffset(rawX:Float, rawY:Float) {
		var ox:Float = rawX;
		var oy:Float = rawY;

		if (scalableOffsets) {
			var base:Float = (jsonScale > 0) ? jsonScale : 1;
			ox *= scale.x / base;
			oy *= scale.y / base;
		}

		if (correctFlippedOffsets && !isAnimateAtlas) {
			if (flipX != baseFlipX)
				ox = (frameWidth * scale.x - width) - ox;
			if (flipY != baseFlipY)
				oy = (frameHeight * scale.y - height) - oy;
		}

		offset.set(ox, oy);
	}

	/**
	 * Inverse of `applyAnimOffset`: converts the current live `offset` (e.g. one
	 * dragged in the character editor while flipped/scaled) back into the
	 * authored value that belongs in the JSON. Returns `[x, y]`.
	 */
	public function getAuthoredOffset():Array<Float> {
		var ox:Float = offset.x;
		var oy:Float = offset.y;

		if (correctFlippedOffsets && !isAnimateAtlas) {
			if (flipX != baseFlipX)
				ox = (frameWidth * scale.x - width) - ox;
			if (flipY != baseFlipY)
				oy = (frameHeight * scale.y - height) - oy;
		}

		if (scalableOffsets) {
			var base:Float = (jsonScale > 0) ? jsonScale : 1;
			ox /= scale.x / base;
			oy /= scale.y / base;
		}

		return [ox, oy];
	}

	public function quickAnimAdd(name:String, anim:String) {
		animation.addByPrefix(name, anim, 24, false);
	}

	// Atlas support
	// special thanks ne_eo for the references, you're the goat!!
	/**
	 * SWF-style rendering for Animate atlases: nested movieclips advance their own
	 * timelines and bake every frame (like a real SWF player) instead of rendering
	 * statically. Load-time setting; toggling it requires reloading the atlas.
	 * Persisted in the character JSON as `swfMode`.
	 */
	public var swfMode:Bool = false;

	@:allow(editors.CharacterEditorState)
	public var isAnimateAtlas(default, null):Bool = false;
	#if flixel_animate
	public var atlas:FlxAnimate;

	public override function draw() {
		var lastAlpha:Float = alpha;
		var lastColor:FlxColor = color;
		if (missingCharacter) {
			alpha *= 0.6;
			color = FlxColor.BLACK;
		}

		if (isAnimateAtlas) {
			if (atlas.isAnimate) {
				copyAtlasValues();
				atlas.draw();
				if (missingCharacter && visible) {
					alpha = lastAlpha;
					color = lastColor;
					missingText.x = getMidpoint().x - 150;
					missingText.y = getMidpoint().y - 10;
					missingText.draw();
				}
			}
			// Always restore alpha/color before returning -- previously the
			// `!isAnimate` branch skipped the restore, so each frame
			// re-multiplied alpha by 0.6 until the sprite faded to black.
			alpha = lastAlpha;
			color = lastColor;
			return;
		}
		super.draw();
		if (missingCharacter && visible) {
			alpha = lastAlpha;
			color = lastColor;
			missingText.x = getMidpoint().x - 150;
			missingText.y = getMidpoint().y - 10;
			missingText.draw();
		} else if (missingCharacter) {
			alpha = lastAlpha;
			color = lastColor;
		}
	}

	public function copyAtlasValues() {
		@:privateAccess
		{
			atlas.cameras = cameras;
			// IMPORTANT: copy FlxPoint *values* -- never assign the references
			// (`atlas.scale = scale`). Aliasing the character's points onto the
			// atlas means destroying the atlas (e.g. the editor's
			// reloadCharacterImage()) returns the character's live points to the
			// FlxPoint pool, which then get recycled and corrupted -- that was the
			// editor "scale shrinks every reload" bug. Gameplay never hit it
			// because the atlas isn't destroyed/recreated mid-life there.
			atlas.scrollFactor.set(scrollFactor.x, scrollFactor.y);
			atlas.scale.set(scale.x, scale.y);
			// flixel-animate (MaybeMaru) subtracts `timeline._bounds` from the
			// render matrix before scaling; the legacy flxanimate did not. Add the
			// inverse to offset so the visible art lands where the legacy library
			// placed it. Offset is subtracted in prepareDrawMatrix
			// (`_point.x -= offset.x`), so `+(-bounds*scale)` cancels the
			// `-bounds*scale` baked into the matrix.
			//
			// This is read LIVE every draw (instead of cached at load) so the
			// compensation is always correct no matter how/when the atlas was
			// (re)built -- e.g. the character editor's reloadCharacterImage()
			// rebuilds the atlas without going through loadCharacterFile(). A
			// stale/missing snapshot was making editor offsets differ from
			// in-game offsets on reload.
			var boundsX:Float = 0;
			var boundsY:Float = 0;
			if (atlas.timeline != null && atlas.timeline._bounds != null) {
				boundsX = atlas.timeline._bounds.x;
				boundsY = atlas.timeline._bounds.y;
			}
			if (boundsX != 0 || boundsY != 0)
				atlas.offset.set(offset.x - boundsX * scale.x, offset.y - boundsY * scale.y);
			else
				atlas.offset.set(offset.x, offset.y);
			atlas.origin.set(origin.x, origin.y);
			atlas.x = x;
			atlas.y = y;
			atlas.angle = angle;
			atlas.alpha = alpha;
			atlas.visible = visible;
			atlas.flipX = flipX;
			atlas.flipY = flipY;
			atlas.shader = shader;
			atlas.antialiasing = antialiasing;
			atlas.colorTransform = colorTransform;
			atlas.color = color;
		}
	}
	#end

	public override function destroy() {
		#if flixel_animate
		atlas = FlxDestroyUtil.destroy(atlas);
		#end
		missingText = FlxDestroyUtil.destroy(missingText);
		super.destroy();
	}
}
