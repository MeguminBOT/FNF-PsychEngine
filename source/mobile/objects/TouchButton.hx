package mobile.objects;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.util.FlxColor;

/**
 * A single on-screen touch button. Tracks press state across multitouch (and the
 * mouse, so the controls can be exercised on desktop while testing). Lives on an
 * overlay camera so its hitbox is in screen space, unaffected by game-camera zoom.
 *
 * `tag` identifies which virtual action this button maps to (see TouchPad / Hitbox).
 */
class TouchButton extends FlxSprite
{
	public var tag:String;

	public var justPressed:Bool = false;
	public var pressed:Bool = false;
	public var justReleased:Bool = false;

	/** Highlight alpha applied while held. */
	public var pressedAlpha:Float = 1.0;
	public var idleAlpha:Float = 0.6;

	public function new(x:Float = 0, y:Float = 0, ?tag:String)
	{
		super(x, y);
		this.tag = tag;
		alpha = idleAlpha;
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		final wasPressed:Bool = pressed;
		final nowPressed:Bool = checkPressed();

		justPressed = nowPressed && !wasPressed;
		justReleased = !nowPressed && wasPressed;
		pressed = nowPressed;

		alpha = pressed ? pressedAlpha : idleAlpha;
	}

	function checkPressed():Bool
	{
		final cam = (cameras != null && cameras.length > 0) ? cameras[0] : camera;

		#if FLX_TOUCH
		for (touch in FlxG.touches.list)
			if (touch.pressed && touch.overlaps(this, cam))
				return true;
		#end
		#if FLX_MOUSE
		if (FlxG.mouse.pressed && FlxG.mouse.overlaps(this, cam))
			return true;
		#end

		return false;
	}
}
