package mobile.input;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import mobile.objects.TouchButton;

/**
 * Full-height gameplay lanes (one per note column). Each lane is a TouchButton; the
 * lane index is its tag. PlayState polls these each frame and feeds the existing
 * keyPressed()/keyReleased() path, so sustains/ghost-tapping behave exactly like the
 * keyboard. Lane count follows the chart's column count (4..9, via Mania).
 */
class Hitbox extends FlxSpriteGroup
{
	// Reasonable default palette; cycles if there are more lanes than colors.
	static final laneColors:Array<FlxColor> = [
		0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F, // 4K: purple/blue/green/red
		0xFFFFD700, 0xFFFF8C00, 0xFFFFFFFF, 0xFF9B59B6, 0xFF1ABC9C
	];

	public var buttons:Array<TouchButton> = [];

	public function new(keyCount:Int)
	{
		super();

		final laneWidth:Float = FlxG.width / keyCount;
		for (i in 0...keyCount)
		{
			final btn:TouchButton = new TouchButton(i * laneWidth, 0, Std.string(i));
			btn.makeGraphic(Std.int(laneWidth), FlxG.height, laneColors[i % laneColors.length]);
			btn.idleAlpha = 0.18;
			btn.pressedAlpha = 0.45;
			add(btn);
			buttons.push(btn);
		}

		scrollFactor.set();
		moves = false;
	}

	override public function destroy():Void
	{
		buttons = [];
		super.destroy();
	}
}
