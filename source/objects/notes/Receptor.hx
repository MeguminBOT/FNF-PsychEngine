package objects.notes;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import backend.animation.PsychAnimationController;
import backend.noteskin.NoteSkinService;
import backend.noteskin.NoteVisual;
import objects.notes.NoteDefaults;
import shaders.RGBPalette;
import shaders.RGBPalette.RGBShaderReference;

/**
	A receptor (the "strum"). Clean rewrite of `StrumNote`: it holds no skin-building logic -- it asks
	`NoteSkinService` to build its static/pressed/confirm look and only keeps positioning and the played
	animation. One per column per side.
**/
final class Receptor extends FlxSprite {
	public var column:Int = 0;
	public var keyCount:Int = 4;
	public var player:Int = 0;

	public var direction:Float = 90;
	public var downScroll:Bool = false;
	public var sustainReduce:Bool = true;
	public var rotateNotes:Bool = false;

	/**
		Cached scroll-axis unit vector and the matching sprite angle (`axisDeg - 90`). Recomputed by
		`refreshAxis` only when the effective axis angle changes, so the per-note `follow` reads these
		instead of paying `cos`/`sin` every frame. `axisDeg` defaults to 90 (vertical scroll): straight up.
	**/
	public var axisX(default, null):Float = 0;

	public var axisY(default, null):Float = 1;
	public var axisAngle(default, null):Float = 0;

	var _axisDeg:Float = Math.NaN;

	public var resetAnim:Float = 0;

	public var skinOffsetX:Float = 0;
	public var skinOffsetY:Float = 0;

	public var rgbShader:RGBShaderReference;
	public var useRGBShader:Bool = true;

	/** When set, the palette shader toggles per played anim; otherwise it's "colored unless static". **/
	public var colorPerAnim:Bool = false;

	/** When set, each anim frame is re-centered on the fixed lane width (folder skins). **/
	public var laneCenter:Bool = false;

	public var staticColorable:Bool = false;
	public var pressedColorable:Bool = true;
	public var confirmColorable:Bool = true;

	/**
		@param x screen x of the receptor
		@param y screen y of the receptor
		@param column the 0-based lane this receptor serves
		@param player `0` for the opponent side, `1` for the player side
		@param keyCount the active column count; defaults to `Mania.current`
	**/
	public function new(x:Float, y:Float, column:Int, player:Int, ?keyCount:Int) {
		super(x, y);
		animation = new PsychAnimationController(this);

		this.column = column;
		this.player = player;
		this.keyCount = (keyCount != null) ? keyCount : Mania.current;
		this.ID = column;

		rgbShader = new RGBShaderReference(this, NoteDefaults.initializeGlobalRGBShader(column));
		rgbShader.enabled = false;
		if (PlayState.SONG != null && PlayState.SONG.disableNoteRGB)
			useRGBShader = false;

		var arr:Array<FlxColor>;
		if (Mania.current != Mania.DEFAULT)
			arr = Mania.getColors(Mania.current)[column];
		else {
			arr = ClientPrefs.data.arrowRGB[column];
			if (PlayState.isPixelStage)
				arr = ClientPrefs.data.arrowRGBPixel[column];
		}
		if (arr != null && arr.length >= 3) {
			@:bypassAccessor {
				rgbShader.r = arr[0];
				rgbShader.g = arr[1];
				rgbShader.b = arr[2];
			}
		}

		scrollFactor.set();
		build();
		playAnim('static');
	}

	/** (Re)builds the receptor's static/pressed/confirm look from the active skin. **/
	public function build():Void {
		var lastAnim:String = (animation.curAnim != null) ? animation.curAnim.name : null;
		laneCenter = false;
		colorPerAnim = false;

		// Pin asset resolution to the active skin's owner so a folder skin in any mod (or a forced skin)
		// builds its strums from its own images -- matches NoteSprite/SustainSprite.apply.
		var prevPin:Null<String> = Paths.pinModRoot;
		var pin:Null<String> = backend.NoteSkinConfig.activeSkinPinRoot();
		if (pin != null)
			Paths.pinModRoot = pin;
		var v:NoteVisual = NoteSkinService.current().applyReceptor(this, rgbShader, column, keyCount, lastAnim);
		Paths.pinModRoot = prevPin;
		laneCenter = v.laneCenter;
		colorPerAnim = v.colorPerAnim;
		staticColorable = v.staticColorable;
		pressedColorable = v.pressedColorable;
		confirmColorable = v.confirmColorable;
		skinOffsetX = v.offsetX;
		skinOffsetY = v.offsetY;
	}

	/** Applies the initial on-screen placement for this column/side (matches the legacy strum layout). **/
	public function playerPosition():Void {
		final kc:Int = Mania.current;
		if (kc == Mania.DEFAULT) {
			x += Mania.swagWidth * column;
			x += 50;
			x += ((FlxG.width / 2) * player);
			x += skinOffsetX;
			y += skinOffsetY;
			return;
		}

		final step:Float = Mania.swagWidth + Mania.STRUM_GAP;
		final center4K:Float = 160 * Mania.noteSizes[Mania.DEFAULT - 1] * (Mania.DEFAULT - 1) / 2;

		x += step * column;
		x += 50;
		x += ((FlxG.width / 2) * player);
		x -= (step * (kc - 1) / 2 - center4K);
		y += Mania.noteOffsetsY[kc - 1];
		x += skinOffsetX;
		y += skinOffsetY;
	}

	/**
		Recomputes the cached scroll-axis vector when the effective axis angle (`direction` plus the
		sprite `angle` when `rotateNotes`) changed. Cheap to call per frame: it only runs `cos`/`sin`
		on an actual angle change, so a script rotating the receptor stays correct. Call once per frame
		before the drawables read `axisX`/`axisY`/`axisAngle`.
	**/
	public inline function refreshAxis():Void {
		final deg:Float = direction + (rotateNotes ? angle : 0);
		if (deg != _axisDeg) {
			_axisDeg = deg;
			axisAngle = deg - 90;
			if (deg == 90) {
				axisX = 0;
				axisY = 1;
			} else {
				final rad:Float = deg * Math.PI / 180;
				axisX = Math.cos(rad);
				axisY = Math.sin(rad);
			}
		}
	}

	override function update(elapsed:Float) {
		if (resetAnim > 0) {
			resetAnim -= elapsed;
			if (resetAnim <= 0) {
				playAnim('static');
				resetAnim = 0;
			}
		}
		super.update(elapsed);
	}

	/**
		Plays a receptor animation and re-applies lane centering + per-anim colorability.
		@param anim one of `static` / `pressed` / `confirm`
		@param force restart the animation even if it's already playing
	**/
	public function playAnim(anim:String, ?force:Bool = false):Void {
		if (animation.curAnim != null && animation.curAnim.name == anim && animation.curAnim.numFrames <= 1)
			return;

		animation.play(anim, force);
		if (animation.curAnim != null) {
			centerOffsets();
			centerOrigin();
			if (laneCenter)
				offset.x = (frameWidth - Mania.swagWidth) / 2;
		}

		if (colorPerAnim) {
			var supported:Bool = false;
			if (useRGBShader && animation.curAnim != null) {
				supported = switch (animation.curAnim.name) {
					case 'static': staticColorable;
					case 'pressed': pressedColorable;
					case 'confirm': confirmColorable;
					default: false;
				}
			}
			rgbShader.enabled = supported;
			if (supported)
				tintAnim(animation.curAnim.name);
		} else if (useRGBShader)
			rgbShader.enabled = (animation.curAnim != null && animation.curAnim.name != 'static');
	}

	/**
		Tints the current receptor anim: the note colour when that element's "Link ..." option is on, or
		its own independent colour (per-keycount aware, falling back to the note colour) when off.
	**/
	function tintAnim(anim:String):Void {
		var element:String = switch (anim) {
			case 'static': 'strums';
			case 'pressed': 'pressed';
			case 'confirm': 'confirm';
			default: null;
		}
		if (element == null)
			return;
		var linked:Bool = switch (element) {
			case 'strums': ClientPrefs.data.linkStrumColor;
			case 'pressed': ClientPrefs.data.linkPressedColor;
			case 'confirm': ClientPrefs.data.linkConfirmColor;
			default: true;
		}
		var c:Array<FlxColor>;
		if (linked) {
			var np:RGBPalette = Note.initializeGlobalRGBShader(column);
			c = [np.r, np.g, np.b];
		} else {
			var all:Array<Array<FlxColor>> = Mania.getAssetColors(element, keyCount);
			if (column < 0 || column >= all.length)
				return;
			c = all[column];
		}
		if (c != null && c.length >= 3) {
			rgbShader.r = c[0];
			rgbShader.g = c[1];
			rgbShader.b = c[2];
		}
	}
}
