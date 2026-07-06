package objects.notes;

import flixel.FlxSprite;
import flixel.math.FlxRect;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.notes.NoteDefaults;
import shaders.RGBPalette.RGBShaderReference;

/**
	A sustain (hold) rendered as ONE drawable: a vertically-scaled `body` plus a `tail` end-cap,
	replacing the legacy model of one `Note` per sustain step. Pooled (no-arg ctor + `apply`).

	Geometry -- length (`scale.y`), screen position, and progressive clipping as it's held -- is set by
	the `NoteField` each frame; this class only carries the visual and the clip helper.
**/
final class SustainSprite extends FlxSprite {
	public var data:NoteData;
	public var column:Int = 0;
	public var keyCount:Int = 4;

	/** Per-skin override of `headOverlap` (from `skin.tcfg`); `null` uses the static default. **/
	public var skinHeadOverlap:Null<Float> = null;

	/** `false` when the active skin ships no hold-end (tail) frame; the body then fills the tail's span. **/
	public var hasTail:Bool = true;

	public var tail:FlxSprite;

	public var rgbShader:RGBShaderReference;
	public var tailRGB:RGBShaderReference;

	/**
		Per-note hold graphic override (a sparrow/pixel sheet name). Assigning re-skins this hold's body +
		tail immediately, so a custom note can carry its own trail graphic. `null`/empty leaves the skin.
	**/
	public var texture(default, set):String = null;

	/** Toggles this hold's RGB palette shader (body + tail together). **/
	public var rgbEnabled(get, set):Bool;

	inline function get_rgbEnabled():Bool
		return rgbShader != null && rgbShader.enabled;

	inline function set_rgbEnabled(value:Bool):Bool {
		if (rgbShader != null)
			rgbShader.enabled = value;
		if (tailRGB != null)
			tailRGB.enabled = value;
		return value;
	}

	function set_texture(value:String):String {
		texture = value;
		if (value != null && value.length > 0) {
			NoteSkinService.classic().applySustainTexture(this, tail, column, keyCount, value);
			centerOnStrum = true;
		}
		return value;
	}

	/**
		How far a hold's visual end is pulled back toward its head, as a fraction of the note half-width
		(`Mania.swagWidth / 2`), so the tail cap tucks in short of the next note instead of reaching its
		centre. `0` restores the exact end-time tip; `1` stops the cap at the next note's leading edge.
		Clamped per hold so the cap always fits (the body never goes negative).
	**/
	public static var endTrimRatio:Float = 1.0;

	/**
		Extra pull of a held hold's clip toward the receptor, as a fraction of the note width, so the
		trail overlaps the receptor slightly instead of leaving a visible gap above it. `0` cuts exactly
		at the head; larger values tuck the trail further down over the receptor.
	**/
	public static var holdClipNudge:Float = 0.5;

	/**
		Extends an un-held hold's head-side edge up under the note head by this fraction of the note width,
		closing the seam between the head and the trail while it scrolls. `0` starts the body exactly at the
		head. Once the hold is hit, the held clip (`holdClipNudge`) governs the receptor-side edge instead,
		so this only affects the un-held (approaching / opponent-side) trail.
	**/
	public static var headOverlap:Float = 0.5;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;
	public var centerOnStrum:Bool = true;
	public var multAlpha:Float = 0.6;
	public var multSpeed:Float = 1;
	public var copyX:Bool = true;
	public var copyY:Bool = true;
	public var copyAngle:Bool = true;
	public var copyAlpha:Bool = true;
	public var pixel:Bool = false;

	/** LEGACY-API name: convenience pass-through to `data.time` (the v2 field) for old scripts. **/
	public var strumTime(get, never):Float;

	/** LEGACY-API name: convenience pass-through to `data.column` (the v2 field) for old scripts. **/
	public var noteData(get, never):Int;

	/** Always `true`; this drawable is the hold trail. **/
	public var isSustainNote(get, never):Bool;

	inline function get_strumTime():Float
		return data != null ? data.time : 0;

	inline function get_noteData():Int
		return data != null ? data.column : 0;

	inline function get_isSustainNote():Bool
		return true;

	public function new() {
		super();
		animation = new PsychAnimationController(this);
		scrollFactor.set();
		tail = new FlxSprite();
		tail.animation = new PsychAnimationController(tail);
		tail.scrollFactor.set();
	}

	/**
		Binds this pooled hold to a note and (re)builds its body + tail from the active skin.
		@param data the sustain this drawable represents
		@param keyCount the active column count (for per-keycount skin resolution)
	**/
	public function apply(data:NoteData, keyCount:Int):Void {
		this.data = data;
		this.column = data.column;
		this.keyCount = keyCount;
		skinHeadOverlap = backend.NoteSkinConfig.headOverlap();

		exists = visible = active = true;
		tail.exists = tail.visible = true;
		copyX = copyY = copyAngle = copyAlpha = true;
		clipRect = null;
		tail.clipRect = null;

		var rgbOff:Bool = data.disableRGB || (PlayState.SONG != null && PlayState.SONG.disableNoteRGB);
		if (rgbShader == null)
			rgbShader = new RGBShaderReference(this, NoteDefaults.initializeGlobalRGBShader(column));
		else
			rgbShader.reset(this, NoteDefaults.initializeGlobalRGBShader(column));
		if (tailRGB == null)
			tailRGB = new RGBShaderReference(tail, NoteDefaults.initializeGlobalRGBShader(column));
		else
			tailRGB.reset(tail, NoteDefaults.initializeGlobalRGBShader(column));

		// Force Selected Skin blocks a PLAIN note's hold-texture override; a custom-type note keeps it.
		var forceSkip:Bool = ClientPrefs.data.forceNoteSkin && (data.type == null || data.type == '');
		if (!forceSkip && data.texture != null && data.texture.length > 0) {
			// Per-note custom hold graphic (matches the head's data.texture); route through the setter.
			@:bypassAccessor texture = null;
			texture = data.texture;
			offsetX = 0;
			offsetY = 0;
			pixel = PlayState.isPixelStage;
		} else {
			@:bypassAccessor texture = null;
			// Force Selected Skin: pin the active skin's asset resolution to its owner (mods can't shadow it).
			var prevPin:Null<String> = Paths.pinModRoot;
			var pin:Null<String> = backend.NoteSkinConfig.activeSkinPinRoot();
			if (pin != null)
				Paths.pinModRoot = pin;
			var v:NoteVisual = NoteSkinService.current().applySustain(this, rgbShader, tail, tailRGB, column, keyCount);
			Paths.pinModRoot = prevPin;
			offsetX = v.offsetX;
			offsetY = v.offsetY;
			centerOnStrum = v.centerOnStrum;
			pixel = v.pixel;
		}
		if (rgbOff) {
			rgbShader.enabled = false;
			tailRGB.enabled = false;
		}

		// No hold-end frame in the skin -> the body extends over the tail's span instead of stopping short.
		var endAnim = tail.animation.getByName('end');
		hasTail = (endAnim != null && endAnim.numFrames > 0);
		tail.visible = hasTail;

		alpha = multAlpha = 0.6;
		tail.alpha = alpha;
	}

	/** Returns this hold (body + tail) to the pool. **/
	public function release():Void {
		exists = visible = active = false;
		tail.exists = tail.visible = false;
		data = null;
		clipRect = null;
		tail.clipRect = null;
	}

	/**
		Positions the stretched body and its tail cap relative to the receptor for the current song
		time. One body spans the whole hold; `scale.y` = (span length - tail height) / frame height so
		the tail cap occupies the final segment instead of adding to it. The sustain is `flipY`'d for
		downscroll (matching the legacy per-piece flip) and uses the same `0.45 * (songPos - t) * rate`
		scroll multiplier as the head (negated for upscroll).

		This is the most behaviourally sensitive piece of the rewrite; offsets/clip want a runtime pass.
		@param strum the receptor for this hold's column
		@param songSpeed the active scroll speed (already divided by playback rate)
		@param scrollNow the SV-mapped position of the current song time (`== songPos` when SV is off)
	**/
	public function follow(strum:Receptor, songSpeed:Float, scrollNow:Float):Void {
		if (data == null)
			return;
		flipY = strum.downScroll;
		tail.flipY = strum.downScroll;

		var sign:Float = strum.downScroll ? 1 : -1;
		var rate:Float = songSpeed * multSpeed;

		var uX:Float = strum.axisX;
		var uY:Float = strum.axisY;

		if (copyAngle)
			angle = strum.axisAngle;
		if (copyAlpha) {
			alpha = strum.alpha * multAlpha;
			tail.alpha = alpha;
		}

		var headDist:Float = sign * (0.45 * (scrollNow - data.scrollPos) * rate);
		var endDist:Float = sign * (0.45 * (scrollNow - data.endScrollPos) * rate);

		// Missing hold-end: no tail length is reserved, so the body reaches where the tail would have ended.
		var tailLen:Float = hasTail ? tail.height : 0;
		var totalLen:Float = Math.abs(headDist - endDist);

		var trim:Float = Mania.swagWidth * 0.5 * endTrimRatio;
		var maxTrim:Float = totalLen - tailLen;
		if (maxTrim < 0)
			maxTrim = 0;
		if (trim > maxTrim)
			trim = maxTrim;
		endDist += sign * trim;
		totalLen -= trim;

		var nearA:Float = offsetY + headDist;
		var farA:Float = offsetY + endDist;
		var bodyLen:Float = totalLen - tailLen;
		if (bodyLen < 0)
			bodyLen = 0;

		// Un-held trail: push the head-side edge up under the note head to close the seam. The far (tail)
		// edge stays put. Skipped once hit -- the held clip owns the receptor-side edge from then on.
		var ho:Float = (skinHeadOverlap != null) ? skinHeadOverlap : headOverlap;
		if (data != null && !data.hit && ho != 0) {
			var headOver:Float = Mania.swagWidth * ho;
			nearA += sign * headOver;
			bodyLen += headOver;
		}
		// bodyLen is constant while scrolling (headDist - endDist reduces to 0.45*rate*(endScrollPos -
		// scrollPos), independent of scrollNow), so scale.y only really moves on spawn/speed change and
		// while a held note clips. Only pay updateHitbox when it actually changed (legacy's 0.1px gate);
		// width/height stay valid on the skipped frames since scale.x/frameWidth don't change.
		if (frameHeight > 0) {
			var newScaleY:Float = bodyLen / frameHeight;
			if (Math.abs((newScaleY - scale.y) * frameHeight) > 0.1) {
				scale.y = newScaleY;
				updateHitbox();
			}
		}

		var perp:Float = offsetX + (centerOnStrum ? Mania.swagWidth / 2 : width / 2);
		var bodyA:Float = (nearA + farA + sign * tailLen) / 2;
		var bcx:Float = strum.x + uX * bodyA + uY * perp;
		var bcy:Float = strum.y + uY * bodyA - uX * perp;
		if (copyX)
			x = bcx - width / 2;
		if (copyY)
			y = bcy - (frameHeight * scale.y) / 2;

		var tperp:Float = offsetX + (centerOnStrum ? Mania.swagWidth / 2 : tail.width / 2);
		var tailA:Float = farA + sign * (tailLen / 2);
		var tcx:Float = strum.x + uX * tailA + uY * tperp;
		var tcy:Float = strum.y + uY * tailA - uX * tperp;
		tail.angle = copyAngle ? strum.axisAngle : tail.angle;
		tail.x = tcx - tail.width / 2;
		tail.y = tcy - tail.height / 2;

		clip(sign * headDist - Mania.swagWidth * holdClipNudge, bodyLen);
	}

	/**
		Clips away the consumed portion of the body once the head has been hit, anchored to the receptor
		so the cut edge stays put instead of drifting past it as the hold shrinks. The hidden fraction is
		measured against the ACTUAL body sprite (`consumed / bodyLen`), NOT the full hold span -- the span
		includes the tail cap and the end-trim, so dividing by it under-clips and the near edge creeps past
		the receptor. Because the body is `flipY`'d for downscroll, hiding the first `frac` of the frame
		removes the receptor-side region in both scroll directions.
		@param consumed how far the head has scrolled past the receptor, in screen px (negative = not yet)
		@param bodyLen the body's on-screen length, in screen px
	**/
	public function clip(consumed:Float, bodyLen:Float):Void {
		if (data == null || !data.hit || data.length <= 0 || bodyLen <= 0 || consumed <= 0) {
			clipRect = null;
			return;
		}
		var frac:Float = consumed / bodyLen;
		if (frac > 1)
			frac = 1;

		var r:FlxRect = (clipRect != null) ? clipRect : new FlxRect();
		r.x = 0;
		r.width = frameWidth;
		r.y = frameHeight * frac;
		r.height = frameHeight * (1 - frac);
		clipRect = r;
	}

	override function draw():Void {
		super.draw();
		if (tail != null && tail.exists && tail.visible) {
			tail.cameras = cameras;
			tail.draw();
		}
	}

	override function update(elapsed:Float):Void {
		super.update(elapsed);
		if (tail != null && tail.exists)
			tail.update(elapsed);
	}

	@:noCompletion override function set_clipRect(rect:FlxRect):FlxRect {
		@:bypassAccessor clipRect = rect;
		if (frames != null && animation.frameIndex >= 0 && animation.frameIndex < frames.frames.length)
			frame = frames.frames[animation.frameIndex];
		return rect;
	}
}
