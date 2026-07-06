package ui;

import openfl.display.Sprite;
import openfl.events.MouseEvent;
import openfl.ui.MouseCursor;
import ui.input.UIPointer;

/**
	Base class for every widget: a retained `openfl.display.Sprite` that repaints ONLY when
	invalidated (no per-frame update). Subclasses override `render()` and read `UITheme` /
	`UILocale` there, so theme and locale swaps re-skin the whole tree via `UIRoot.invalidateAll`.

	Pointer correctness is built in: `pressed` is only set by a press that starts on this widget,
	and `click()` fires only when the matching release also lands on it (see `UIPointer`). Drags
	use `beginCapture()` to receive exclusive `onDragMove`/`onDragEnd` callbacks.

	Construction flavors:
	- `interactive = true` — hover/press/click handling (leaf widgets)
	- `interactive = false, blocking = true` — a passive surface that still swallows pointer hits
	  (panels, backdrops); children stay interactive
	- `interactive = false, blocking = false` — pure layout group, pointer-transparent
**/
class UIComponent extends Sprite {
	/** Layout width in UI units (independent of DisplayObject's content-derived `width`). **/
	public var w(default, null):Float = 0;

	/** Layout height in UI units. **/
	public var h(default, null):Float = 0;

	/** Disabled widgets ignore the pointer and typically render dimmed. **/
	public var enabled(default, set):Bool = true;

	/** Fired on a completed click (press + release on this widget). **/
	public var onClick:Void->Void = null;

	/** Fired on a right mouse press over this widget (context menus). **/
	public var onRightClick:Void->Void = null;

	/** Fired when the cursor first enters this widget (hover-driven descriptions/previews). **/
	public var onHover:Void->Void = null;

	/** Optional tooltip text (already-localized or a fixed string). **/
	public var tooltip:String = null;

	/** Optional right-aligned shortcut hint rendered in the tooltip. **/
	public var tooltipShortcut:String = null;

	/** Native cursor while hovering (interactive widgets; `null` keeps the arrow). **/
	public var hoverCursor:MouseCursor = MouseCursor.BUTTON;

	/** `true` while the cursor is over this widget. **/
	public var hovered(default, null):Bool = false;

	/** `true` while a press that started here is held. **/
	public var pressed(default, null):Bool = false;

	@:allow(ui.UIRoot)
	var __dirty:Bool = false;

	final _interactive:Bool;

	public function new(interactive:Bool = true, blocking:Bool = true) {
		super();
		_interactive = interactive;
		if (interactive) {
			mouseChildren = false;
			mouseEnabled = true;
			addEventListener(MouseEvent.ROLL_OVER, __onRollOver);
			addEventListener(MouseEvent.ROLL_OUT, __onRollOut);
			addEventListener(MouseEvent.MOUSE_DOWN, __onMouseDown);
			addEventListener(MouseEvent.RIGHT_MOUSE_DOWN, __onRightMouseDown);
		} else {
			mouseChildren = true;
			mouseEnabled = blocking;
		}
	}

	/**
		Sets the layout size and repaints when it changed.
		@param width the new layout width in UI units
		@param height the new layout height in UI units
	**/
	public function resize(width:Float, height:Float):Void {
		if (w == width && h == height)
			return;
		w = width;
		h = height;
		invalidate();
	}

	/** Schedules a repaint for the next frame (cheap; deduplicated). **/
	override public function invalidate():Void {
		UIRoot.schedule(this);
	}

	/** Repaints immediately. Subclasses draw their full visual state here. **/
	public function render():Void {}

	/** Routes exclusive pointer moves to this widget until release (`onDragMove`/`onDragEnd`). **/
	function beginCapture():Void {
		UIPointer.capture(this);
	}

	/**
		Pointer moved while this widget holds capture. Subclass hook.
		@param stageX pointer x in stage coordinates
		@param stageY pointer y in stage coordinates
	**/
	@:allow(ui.UIRoot)
	function onDragMove(stageX:Float, stageY:Float):Void {}

	/** Capture ended (pointer released). **/
	@:allow(ui.UIRoot)
	function onDragEnd():Void {}

	/** Hover/press state changed; default schedules a repaint. **/
	function onStateChanged():Void {
		invalidate();
	}

	/** A completed click; default fires `onClick`. **/
	function click():Void {
		if (onClick != null)
			onClick();
	}

	@:allow(ui.UIRoot)
	function releasePress(inside:Bool):Void {
		if (!pressed)
			return;
		pressed = false;
		onStateChanged();
		if (inside && enabled)
			click();
	}

	function __onRollOver(_:MouseEvent):Void {
		if (hovered)
			return;
		hovered = true;
		onStateChanged();
		UIRoot.tooltipEnter(this);
		if (onHover != null)
			onHover();
	}

	function __onRollOut(_:MouseEvent):Void {
		if (!hovered)
			return;
		hovered = false;
		onStateChanged();
		UIRoot.tooltipLeave(this);
	}

	function __onMouseDown(e:MouseEvent):Void {
		if (!enabled)
			return;
		pressed = true;
		@:privateAccess UIPointer.beginPress(this);
		onStateChanged();
		onPress(e.localX, e.localY);
	}

	/**
		Press started on this widget. Subclass hook.
		@param localX press x in this widget's coordinates
		@param localY press y in this widget's coordinates
	**/
	function onPress(localX:Float, localY:Float):Void {}

	function __onRightMouseDown(e:MouseEvent):Void {
		if (!enabled)
			return;
		onRightPress(e.localX, e.localY);
		if (onRightClick != null)
			onRightClick();
	}

	/**
		Right mouse press over this widget. Subclass hook (used for context menus).
		@param localX press x in this widget's coordinates
		@param localY press y in this widget's coordinates
	**/
	function onRightPress(localX:Float, localY:Float):Void {}

	/** Feeds `hoverCursor` into OpenFL's native per-move cursor management. **/
	@:noCompletion override function __getCursor():MouseCursor {
		return (_interactive && enabled) ? hoverCursor : null;
	}

	function set_enabled(value:Bool):Bool {
		if (enabled == value)
			return value;
		enabled = value;
		alpha = value ? 1.0 : 0.5;
		invalidate();
		return value;
	}

	/** Tears the widget down: listeners, pointer references, children, parent link. **/
	public function dispose():Void {
		if (_interactive) {
			removeEventListener(MouseEvent.ROLL_OVER, __onRollOver);
			removeEventListener(MouseEvent.ROLL_OUT, __onRollOut);
			removeEventListener(MouseEvent.MOUSE_DOWN, __onMouseDown);
			removeEventListener(MouseEvent.RIGHT_MOUSE_DOWN, __onRightMouseDown);
		}
		@:privateAccess UIPointer.forget(this);
		UIRoot.tooltipLeave(this);
		var i:Int = numChildren;
		while (--i >= 0) {
			var child = getChildAt(i);
			if (child is UIComponent)
				(cast child : UIComponent).dispose();
		}
		removeChildren();
		if (parent != null)
			parent.removeChild(this);
	}
}
