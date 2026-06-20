package mobile.input;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import mobile.objects.TouchButton;

/**
 * On-screen virtual gamepad for menu navigation. A d-pad (bottom-left) and action
 * buttons (bottom-right) whose press state is OR-ed into `backend.Controls` so that
 * every existing `controls.UI_UP` / `ACCEPT` / `BACK` check keeps working untouched.
 *
 * Only one pad is "active" at a time: each MusicBeatState/Substate re-asserts
 * `TouchPad.current` at the top of its update(), so the topmost updating state owns
 * input and states without a pad clear it (current = null).
 */
class TouchPad extends FlxSpriteGroup
{
	/** The pad belonging to the state/substate currently updating (null if none). */
	public static var current:TouchPad = null;

	/**
	 * Maps an engine control name (see backend/Controls keyboardBinds) to a button
	 * tag. ui and note directions share the d-pad; accept/back use the action pads.
	 */
	public static final controlToTag:Map<String, String> = [
		'ui_up' => 'UP', 'ui_down' => 'DOWN', 'ui_left' => 'LEFT', 'ui_right' => 'RIGHT',
		'note_up' => 'UP', 'note_down' => 'DOWN', 'note_left' => 'LEFT', 'note_right' => 'RIGHT',
		'accept' => 'A', 'back' => 'B', 'pause' => 'B', 'reset' => 'C'
	];

	public var buttons:Map<String, TouchButton> = new Map();

	final btnSize:Float = 130;

	public function new(dpadMode:String = 'FULL', actionMode:String = 'A_B')
	{
		super();

		buildDpad(dpadMode);
		buildActions(actionMode);

		scrollFactor.set();
		moves = false;
	}

	function buildDpad(mode:String):Void
	{
		final pad:Float = 20;
		final baseX:Float = pad;
		final baseY:Float = FlxG.height - pad - btnSize * 2;

		switch (mode.toUpperCase())
		{
			case 'UP_DOWN':
				makeButton('UP', baseX, baseY, FlxColor.CYAN, '^');
				makeButton('DOWN', baseX, baseY + btnSize, FlxColor.PURPLE, 'v');
			case 'LEFT_RIGHT':
				makeButton('LEFT', baseX, baseY + btnSize, FlxColor.MAGENTA, '<');
				makeButton('RIGHT', baseX + btnSize, baseY + btnSize, FlxColor.RED, '>');
			case 'UP_LEFT_RIGHT':
				makeButton('UP', baseX + btnSize, baseY, FlxColor.CYAN, '^');
				makeButton('LEFT', baseX, baseY + btnSize, FlxColor.MAGENTA, '<');
				makeButton('RIGHT', baseX + btnSize * 2, baseY + btnSize, FlxColor.RED, '>');
			case 'NONE':
			// no d-pad
			default: // FULL diamond
				makeButton('UP', baseX + btnSize, baseY, FlxColor.CYAN, '^');
				makeButton('LEFT', baseX, baseY + btnSize, FlxColor.MAGENTA, '<');
				makeButton('RIGHT', baseX + btnSize * 2, baseY + btnSize, FlxColor.RED, '>');
				makeButton('DOWN', baseX + btnSize, baseY + btnSize, FlxColor.PURPLE, 'v');
		}
	}

	function buildActions(mode:String):Void
	{
		final pad:Float = 20;
		final aX:Float = FlxG.width - pad - btnSize;
		final baseY:Float = FlxG.height - pad - btnSize;

		switch (mode.toUpperCase())
		{
			case 'NONE':
			case 'A':
				makeButton('A', aX, baseY, FlxColor.LIME, 'A');
			case 'B': // single button, used as pause in gameplay -- top-right, clear of the lanes
				makeButton('B', aX, pad, FlxColor.ORANGE, 'II');
			case 'A_B_C': // adds a third button for the 'reset' control
				makeButton('A', aX, baseY, FlxColor.LIME, 'A');
				makeButton('B', aX - (btnSize + pad), baseY, FlxColor.ORANGE, 'B');
				makeButton('C', aX - 2 * (btnSize + pad), baseY, FlxColor.CYAN, 'C');
			default: // A_B
				makeButton('A', aX, baseY, FlxColor.LIME, 'A');
				makeButton('B', aX - btnSize - pad, baseY, FlxColor.ORANGE, 'B');
		}
	}

	function makeButton(tag:String, x:Float, y:Float, color:FlxColor, label:String):TouchButton
	{
		final btn:TouchButton = new TouchButton(x, y, tag);
		btn.makeGraphic(Std.int(btnSize), Std.int(btnSize), color);
		add(btn);
		buttons.set(tag, btn);

		final txt:FlxText = new FlxText(x, y + btnSize / 2 - 20, btnSize, label, 40);
		txt.setFormat(null, 40, FlxColor.WHITE, CENTER);
		txt.scrollFactor.set();
		add(txt);

		return btn;
	}

	public inline function buttonPressed(tag:String):Bool
		return buttons.exists(tag) && buttons.get(tag).pressed;

	public inline function buttonJustPressed(tag:String):Bool
		return buttons.exists(tag) && buttons.get(tag).justPressed;

	public inline function buttonJustReleased(tag:String):Bool
		return buttons.exists(tag) && buttons.get(tag).justReleased;

	override public function destroy():Void
	{
		if (current == this)
			current = null;
		buttons.clear();
		super.destroy();
	}
}
