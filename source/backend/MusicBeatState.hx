package backend;

import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import backend.PsychCamera;
#if mobile
import flixel.FlxCamera;
import mobile.input.TouchPad;
import mobile.input.Hitbox;
#end

class MusicBeatState extends FlxState {
	#if mobile
	// On-screen controls for this state. `touchPad` drives menu navigation (read by
	// backend.Controls); `hitbox` drives gameplay lanes (polled by PlayState). Both
	// render on a dedicated overlay camera so they ignore game-camera zoom/scroll.
	public var touchPad:TouchPad;
	public var hitbox:Hitbox;
	public var mobileControlsCamera:FlxCamera;

	// Scripted states use plain controls.ACCEPT/BACK/UI_* with no android-specific
	// calls, so give them a default pad once (after their create runs) if they never
	// added their own pad or hitbox. Set true once attempted, so we don't re-add.
	var defaultTouchPadTried:Bool = false;
	#end

	private var curSection:Int = 0;
	private var stepsToDo:Int = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;

	private var curDecStep:Float = 0;
	private var curDecBeat:Float = 0;

	// Time-signature beat tracking. A "beat" is `stepsPerBeatCur` 16th-note steps
	// (= 16/denominator), and the beat phase resets at each section boundary so a
	// meter change (e.g. 4/4 -> 6/8) doesn't drift the beat. For all-4/4 charts
	// these reduce to curStep/4 and curStep % 4 (today's behaviour) exactly.
	private var sectionStartStep:Int = 0;
	private var beatsBeforeSection:Int = 0;
	private var stepsPerBeatCur:Int = 4;

	public var controls(get, never):Controls;

	private function get_controls() {
		return Controls.instance;
	}

	var _psychCameraInitialized:Bool = false;

	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();

	public static function getVariables()
		return getState().variables;

	// The mod folder a scripted state was loaded from (null for built-in states).
	// Set by scripting.ScriptedStates; used to auto-scope asset/script lookups
	// (see the preStateCreate hook in Main) so scripts never touch Mods.* manually.
	public var scriptOwnerMod:String = null;

	#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
	// On-screen script-error/debug overlay, available to EVERY state (not just
	// PlayState) so scripted menus surface errors instead of silently going black.
	// Lazily created and always re-raised to the front so it works regardless of
	// whether a scripted create() called super.create().
	var luaDebugGroup:FlxTypedGroup<psychlua.DebugLuaText>;

	public function addTextToDebug(text:String, color:FlxColor) {
		if (luaDebugGroup == null)
			luaDebugGroup = new FlxTypedGroup<psychlua.DebugLuaText>();
		// Keep the overlay frontmost even if the state added sprites after it.
		if (members.contains(luaDebugGroup))
			remove(luaDebugGroup, true);
		add(luaDebugGroup);

		var newText:psychlua.DebugLuaText = luaDebugGroup.recycle(psychlua.DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:psychlua.DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);

		Sys.println(text);
	}
	#end

	override function create() {
		var skip:Bool = FlxTransitionableState.skipNextTransOut;
		#if MODS_ALLOWED Mods.updatedOnState = false; #end

		if (!_psychCameraInitialized)
			initPsychCamera();

		super.create();

		if (!skip) {
			openSubState(new CustomFadeTransition(0.5, true));
		}
		FlxTransitionableState.skipNextTransOut = false;
		timePassedOnState = 0;
	}

	public function initPsychCamera():PsychCamera {
		var camera = new PsychCamera();
		FlxG.cameras.reset(camera);
		FlxG.cameras.setDefaultDrawTarget(camera, true);
		_psychCameraInitialized = true;
		// trace('initialized psych camera ' + Sys.cpuTime());
		return camera;
	}

	#if mobile
	function initMobileControlsCamera():Void {
		if (mobileControlsCamera != null)
			return;
		mobileControlsCamera = new FlxCamera();
		mobileControlsCamera.bgColor.alpha = 0;
		FlxG.cameras.add(mobileControlsCamera, false);
	}

	/**
	 * Adds the menu virtual gamepad. `dpadMode` ∈ FULL/UP_DOWN/LEFT_RIGHT/UP_LEFT_RIGHT/NONE,
	 * `actionMode` ∈ A_B/A/NONE. Alpha follows ClientPrefs.data.controlsAlpha.
	 */
	public function addTouchPad(dpadMode:String = 'FULL', actionMode:String = 'A_B'):Void {
		removeTouchPad();
		initMobileControlsCamera();
		touchPad = new TouchPad(dpadMode, actionMode);
		touchPad.cameras = [mobileControlsCamera];
		for (btn in touchPad.buttons) btn.cameras = [mobileControlsCamera];
		applyControlsAlpha(touchPad);
		add(touchPad);
		TouchPad.current = touchPad;
	}

	public function removeTouchPad():Void {
		if (touchPad != null) {
			remove(touchPad, true);
			touchPad.destroy();
			touchPad = null;
		}
	}

	/** Adds the gameplay lane overlay for `keyCount` columns. */
	public function addHitbox(keyCount:Int):Void {
		removeHitbox();
		initMobileControlsCamera();
		hitbox = new Hitbox(keyCount);
		hitbox.cameras = [mobileControlsCamera];
		for (btn in hitbox.buttons) btn.cameras = [mobileControlsCamera];
		add(hitbox);
	}

	public function removeHitbox():Void {
		if (hitbox != null) {
			remove(hitbox, true);
			hitbox.destroy();
			hitbox = null;
		}
	}

	function applyControlsAlpha(pad:TouchPad):Void {
		final a:Float = ClientPrefs.data.controlsAlpha;
		for (btn in pad.buttons) btn.idleAlpha = a;
	}

	// Keep the on-screen controls above any HUD cameras a state adds after
	// addTouchPad/addHitbox, so callers can add the pad anywhere in create().
	// (see below for the reorder; the input helpers are declared outside #if mobile.)
	#end

	// Touch-pad query helpers usable WITHOUT #if guards at call sites (handy for
	// states that read FlxG.keys directly). Always present; return false off-mobile.
	public function touchPadJustPressed(tag:String):Bool {
		#if mobile return touchPad != null && touchPad.buttonJustPressed(tag); #else return false; #end
	}

	public function touchPadPressed(tag:String):Bool {
		#if mobile return touchPad != null && touchPad.buttonPressed(tag); #else return false; #end
	}

	// Index of the visible group item under a just-started click/tap, else -1.
	// (Touch drives FlxG.mouse on Android, so one path serves click and tap.)
	public function getTappedMenuItem<T:flixel.FlxBasic>(group:flixel.group.FlxTypedGroup<T>, ?cam:flixel.FlxCamera):Int {
		#if FLX_MOUSE
		if (group == null || !FlxG.mouse.justPressed)
			return -1;
		for (i in 0...group.length) {
			final m = group.members[i];
			if (m != null && m.exists && m.visible && FlxG.mouse.overlaps(m, cam))
				return i;
		}
		#end
		return -1;
	}

	// Extra on-screen action buttons (left column), for state-specific functions that
	// have no place on the d-pad (sort/group/favorite, etc). Returns false off-mobile.
	public function actionButtonJustPressed(tag:String):Bool {
		#if mobile return actionButtons != null && actionButtons.exists(tag) && actionButtons.get(tag).justPressed; #else return false; #end
	}

	#if mobile
	public var actionButtons:Map<String, mobile.objects.TouchButton>;

	// defs: each entry is [tag, label]. Stacked top-down on the left edge.
	public function addActionButtons(defs:Array<Array<String>>):Void {
		initMobileControlsCamera();
		if (actionButtons == null) actionButtons = new Map();
		final size:Int = 84;
		final pad:Int = 12;
		var ty:Float = pad;
		for (def in defs) {
			var btn = new mobile.objects.TouchButton(pad, ty, def[0]);
			btn.makeGraphic(size, size, 0xFF3B3B6B);
			btn.idleAlpha = ClientPrefs.data.controlsAlpha;
			btn.cameras = [mobileControlsCamera];
			add(btn);
			var lbl = new flixel.text.FlxText(pad, ty + size / 2 - 14, size, def[1], 24);
			lbl.setFormat(null, 24, flixel.util.FlxColor.WHITE, CENTER);
			lbl.scrollFactor.set();
			lbl.cameras = [mobileControlsCamera];
			add(lbl);
			actionButtons.set(def[0], btn);
			ty += size + pad;
		}
	}

	// Cheap: only reorders on the frame(s) where it isn't already on top.
	function keepControlsCameraOnTop():Void {
		if (mobileControlsCamera == null)
			return;
		final list = FlxG.cameras.list;
		if (list.length == 0 || list[list.length - 1] == mobileControlsCamera)
			return;
		FlxG.cameras.remove(mobileControlsCamera, false);
		FlxG.cameras.add(mobileControlsCamera, false);
	}
	#end

	public static var timePassedOnState:Float = 0;
	private static var _lastSavedFullscreen:Bool = false;

	override function update(elapsed:Float) {
		#if (mobile && HSCRIPT_ALLOWED)
		if (!defaultTouchPadTried && touchPad == null && hitbox == null && (this is insanity.IScripted)) {
			defaultTouchPadTried = true;
			if (!Mods.isNativeMobile())
				addTouchPad('FULL', 'A_B');
		}
		#end

		#if mobile
		// The topmost updating state owns menu touch input; states without a pad
		// clear it so stale presses can't leak in (see TouchPad.current).
		TouchPad.current = touchPad;
		keepControlsCameraOnTop();
		#end

		// everyStep();
		var oldStep:Int = curStep;
		timePassedOnState += elapsed;

		updateCurStep();
		updateBeat();

		if (oldStep != curStep) {
			if (curStep > 0)
				stepHit();

			if (PlayState.SONG != null) {
				if (oldStep < curStep)
					updateSection();
				else
					rollbackSection();
			}
		}

		// Only persist the fullscreen flag when it actually changes;
		// the previous code wrote into FlxG.save.data every single frame.
		if (FlxG.save.data != null && _lastSavedFullscreen != FlxG.fullscreen) {
			FlxG.save.data.fullscreen = FlxG.fullscreen;
			_lastSavedFullscreen = FlxG.fullscreen;
		}

		// inline stagesFunc -- per-frame hot path; avoids closure capture of `elapsed`
		for (stage in stages) {
			if (stage == null || !stage.exists || !stage.active) continue;
			stage.update(elapsed);
		}

		super.update(elapsed);
	}

	private function updateSection():Void {
		if (stepsToDo < 1) {
			sectionStartStep = 0;
			beatsBeforeSection = 0;
			stepsPerBeatCur = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSection));
			stepsToDo = sectionStartStep + Math.round(getBeatsOnSection() * stepsPerBeatCur);
		}
		while (curStep >= stepsToDo) {
			// Tally the beats of the section we're leaving (ceil so a fractional
			// section still advances by the number of beat ticks it actually fired).
			beatsBeforeSection += (stepsPerBeatCur > 0) ? Math.ceil((stepsToDo - sectionStartStep) / stepsPerBeatCur) : 0;
			sectionStartStep = stepsToDo;
			curSection++;
			stepsPerBeatCur = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSection));
			stepsToDo += Math.round(getBeatsOnSection() * stepsPerBeatCur);
			sectionHit();
		}
	}

	private function rollbackSection():Void {
		if (curStep < 0)
			return;

		var lastSection:Int = curSection;
		curSection = 0;
		stepsToDo = 0;
		sectionStartStep = 0;
		beatsBeforeSection = 0;
		stepsPerBeatCur = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, 0));
		for (i in 0...PlayState.SONG.notes.length) {
			if (PlayState.SONG.notes[i] != null) {
				var spb:Int = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSection));
				var secSteps:Int = Math.round(getBeatsOnSection() * spb);
				if (stepsToDo + secSteps > curStep) {
					sectionStartStep = stepsToDo;
					stepsPerBeatCur = spb;
					stepsToDo += secSteps;
					break;
				}
				stepsToDo += secSteps;
				beatsBeforeSection += (spb > 0) ? Math.ceil(secSteps / spb) : 0;
				curSection++;
			}
		}

		// rollbackSection only runs when we went backwards, so curSection
		// can never be greater than the prior value here; the previous
		// `>` comparison meant sectionHit() never fired on rewinds (e.g.
		// chart editor scrubbing), leaving stages/scripts desynced.
		if (curSection != lastSection)
			sectionHit();
	}

	private function updateBeat():Void {
		var spb:Int = (stepsPerBeatCur > 0) ? stepsPerBeatCur : 4;
		curBeat = beatsBeforeSection + Math.floor((curStep - sectionStartStep) / spb);
		curDecBeat = beatsBeforeSection + (curDecStep - sectionStartStep) / spb;
	}

	private function updateCurStep():Void {
		var lastChange = Conductor.getBPMFromSeconds(Conductor.songPosition);

		var shit = ((Conductor.songPosition - ClientPrefs.data.noteOffset) - lastChange.songTime) / lastChange.stepCrochet;
		curDecStep = lastChange.stepTime + shit;
		curStep = lastChange.stepTime + Math.floor(shit);
	}

	public static function switchState(nextState:FlxState = null) {
		// Default every state to full mod-asset resolution; core-menu states opt
		// out in their create() so non-global mods can't override menu assets.
		Mods.allowCurrentModAssets = true;
		if (nextState == null)
			nextState = FlxG.state;
		#if HSCRIPT_ALLOWED
		else {
			// Let the active state-source (a launched mod / scriptpack) replace a
			// built-in core menu with its scripted override, if one exists.
			var scripted:MusicBeatState = scripting.ScriptedStates.coreOverride(nextState);
			if (scripted != null)
				nextState = scripted;
		}
		#end
		if (nextState == FlxG.state) {
			resetState();
			return;
		}

		if (FlxTransitionableState.skipNextTransIn)
			FlxG.switchState(nextState);
		else
			startTransition(nextState);
		FlxTransitionableState.skipNextTransIn = false;
	}

	public static function resetState() {
		if (FlxTransitionableState.skipNextTransIn)
			FlxG.resetState();
		else
			startTransition();
		FlxTransitionableState.skipNextTransIn = false;
	}

	// Custom made Trans in
	public static function startTransition(nextState:FlxState = null) {
		if (nextState == null)
			nextState = FlxG.state;

		FlxG.state.openSubState(new CustomFadeTransition(0.5, false));
		if (nextState == FlxG.state)
			CustomFadeTransition.finishCallback = function() FlxG.resetState();
		else
			CustomFadeTransition.finishCallback = function() FlxG.switchState(nextState);
	}

	public static function getState():MusicBeatState {
		return cast(FlxG.state, MusicBeatState);
	}

	public function stepHit():Void {
		// inline stagesFunc -- per-step hot path
		for (stage in stages) {
			if (stage == null || !stage.exists || !stage.active) continue;
			stage.curStep = curStep;
			stage.curDecStep = curDecStep;
			stage.stepHit();
		}

		if (stepsPerBeatCur > 0 && (curStep - sectionStartStep) % stepsPerBeatCur == 0)
			beatHit();
	}

	public var stages:Array<BaseStage> = [];

	public function beatHit():Void {
		// trace('Beat: ' + curBeat);
		// inline stagesFunc -- per-beat hot path
		for (stage in stages) {
			if (stage == null || !stage.exists || !stage.active) continue;
			stage.curBeat = curBeat;
			stage.curDecBeat = curDecBeat;
			stage.beatHit();
		}
	}

	public function sectionHit():Void {
		// trace('Section: ' + curSection + ', Beat: ' + curBeat + ', Step: ' + curStep);
		for (stage in stages) {
			if (stage == null || !stage.exists || !stage.active) continue;
			stage.curSection = curSection;
			stage.sectionHit();
		}
	}

	function stagesFunc(func:BaseStage->Void) {
		for (stage in stages)
			if (stage != null && stage.exists && stage.active)
				func(stage);
	}

	function getBeatsOnSection() {
		var fallback:Float = (PlayState.SONG != null) ? Conductor.getBaseTimeSignature(PlayState.SONG)[0] : 4;
		var val:Null<Float> = fallback;
		if (PlayState.SONG != null && PlayState.SONG.notes[curSection] != null)
			val = PlayState.SONG.notes[curSection].sectionBeats;
		return val == null ? fallback : val;
	}
}
