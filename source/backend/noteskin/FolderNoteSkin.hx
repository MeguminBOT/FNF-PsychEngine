package backend.noteskin;

import flixel.FlxSprite;
import flixel.util.FlxColor;
import shaders.RGBPalette.RGBShaderReference;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;

/**
	Modern folder note skin (`.tcfg`/`.json` via `NoteSkinConfig`). Ports the per-lane resolution that
	used to live inline in `Note.reloadFolderNote` / `StrumNote.reloadFolderStrum`, retargeted onto bare
	sprites. Anything a folder skin can't resolve (missing element/keycount) falls back to the
	`ClassicNoteSkin` so partial skins still render. See `INoteSkin` for the method contracts.
**/
class FolderNoteSkin implements INoteSkin {
	final skinName:String;
	final fallback:ClassicNoteSkin;

	/**
		@param skinName the active folder skin (e.g. `noteSkins/Default`)
		@param fallback the classic provider used for elements this skin can't resolve
	**/
	public function new(skinName:String, fallback:ClassicNoteSkin) {
		this.skinName = skinName;
		this.fallback = fallback;
	}

	public function isPixel():Bool {
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return PlayState.isPixelStage;
		return (cfg.pixel == true) || (cfg.pixelVariant == true && PlayState.isPixelStage);
	}

	/** Updates the global `NoteSkinConfig.pixelMode` for this skin (unless an editor override is set). **/
	inline function syncPixelMode(cfg:NoteSkinData):Void {
		if (NoteSkinConfig.editorOverride == null)
			NoteSkinConfig.pixelMode = (cfg.pixel == true) || (cfg.pixelVariant == true && PlayState.isPixelStage);
	}

	/** Builds the note head; falls back to the classic skin if the lane/element can't be resolved. **/
	public function applyNote(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, animName:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return fallback.applyNote(spr, rgb, column, keyCount, animName);
		syncPixelMode(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var col:Int = column;
		var kc:Int = Mania.clamp(keyCount);
		var scaleBase:Float = NoteSkinConfig.scaleForColumn(cfg, col) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, col);

		var note = NoteSkinConfig.resolveColumn(cfg, cfg.notes, col);
		if (note == null)
			return fallback.applyNote(spr, rgb, column, keyCount, animName);
		var noteFrames:Array<String> = NoteSkinConfig.resolveFrames(base + note.key);
		if (noteFrames == null)
			return fallback.applyNote(spr, rgb, column, keyCount, animName);
		noteFrames = NoteSkinConfig.staticFrame(noteFrames, NoteSkinConfig.animatedFor(cfg, 'notes'));

		var factor:Float = NoteSkinConfig.applyAnims(spr, [
			{name: 'note', keys: noteFrames, fps: laneFps, loop: false, angle: note.angle, square: true}
		]);

		var colorable:Bool = NoteSkinConfig.colorableFor(cfg, 'notes');
		if (!colorable && rgb != null)
			rgb.enabled = false;
		v.colorable = colorable;
		// (Note splashes are built separately by NoteSkinConfig.applySplash / NoteSplash, not here.)

		spr.antialiasing = (cfg.pixel == true
			|| NoteSkinConfig.pixelMode) ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, col, ClientPrefs.data.antialiasing);
		spr.scale.set(scaleBase * factor, scaleBase * factor);
		spr.centerOffsets();
		spr.centerOrigin();
		spr.updateHitbox();

		v.centerOnStrum = true;
		var off:Array<Float> = NoteSkinConfig.offsetFor(cfg.noteOffsets, col);
		v.offsetX = off[0];
		v.offsetY = off[1];
		v.scaleFactor = scaleBase * factor;
		v.pixel = (cfg.pixel == true || NoteSkinConfig.pixelMode);
		spr.animation.play('note', true);
		v.ok = true;
		return v;
	}

	/** Builds the hold body + tail; falls back to the classic skin if the lane/element can't be resolved. **/
	public function applySustain(body:FlxSprite, bodyRGB:RGBShaderReference, tail:FlxSprite, tailRGB:RGBShaderReference, column:Int,
			keyCount:Int):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return fallback.applySustain(body, bodyRGB, tail, tailRGB, column, keyCount);
		syncPixelMode(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var col:Int = column;
		var kc:Int = Mania.clamp(keyCount);
		var scaleBase:Float = NoteSkinConfig.scaleForColumn(cfg, col) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, col);

		var holdKey:String = NoteSkinConfig.columnKey(cfg.holds, col);
		var endKey:String = NoteSkinConfig.columnKey(cfg.ends, col);
		if (holdKey == null || endKey == null)
			return fallback.applySustain(body, bodyRGB, tail, tailRGB, column, keyCount);
		var holdFrames:Array<String> = NoteSkinConfig.resolveFrames(base + holdKey);
		var endFrames:Array<String> = NoteSkinConfig.resolveFrames(base + endKey);
		if (holdFrames == null || endFrames == null)
			return fallback.applySustain(body, bodyRGB, tail, tailRGB, column, keyCount);
		holdFrames = NoteSkinConfig.staticFrame(holdFrames, NoteSkinConfig.animatedFor(cfg, 'holds'));
		endFrames = NoteSkinConfig.staticFrame(endFrames, NoteSkinConfig.animatedFor(cfg, 'ends'));

		var fBody:Float = NoteSkinConfig.applyAnims(body, [{name: 'hold', keys: holdFrames, fps: laneFps, loop: true}]);
		var fTail:Float = NoteSkinConfig.applyAnims(tail, [{name: 'end', keys: endFrames, fps: laneFps, loop: true}]);

		var holdsSupported:Bool = NoteSkinConfig.colorableFor(cfg, 'holds');
		var endsSupported:Bool = NoteSkinConfig.colorableFor(cfg, 'ends');
		var linked:Bool = ClientPrefs.data.linkSustainColor;
		tintElement(bodyRGB, 'holds', holdsSupported, linked, col, kc);
		tintElement(tailRGB, 'holds', endsSupported, linked, col, kc);

		var aa:Bool = (cfg.pixel == true
			|| NoteSkinConfig.pixelMode) ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, col, ClientPrefs.data.antialiasing);
		if (cfg.holdAntialiasing != null)
			aa = cfg.holdAntialiasing;
		body.antialiasing = tail.antialiasing = aa;
		body.scale.set(scaleBase * fBody, scaleBase * fBody);
		tail.scale.set(scaleBase * fTail, scaleBase * fTail);
		body.updateHitbox();
		tail.updateHitbox();

		v.centerOnStrum = true;
		var off:Array<Float> = NoteSkinConfig.offsetFor(cfg.holdOffsets, col);
		v.offsetX = off[0];
		v.offsetY = off[1];
		v.scaleFactor = scaleBase * fBody;
		v.pixel = (cfg.pixel == true || NoteSkinConfig.pixelMode);
		v.colorable = holdsSupported;
		v.ok = true;
		return v;
	}

	/**
		Enables/tints an element's RGB shader: disabled when the skin can't colour it; otherwise the note
		colour when its link is ON, or the asset's own independent colour (per-keycount aware) when OFF.
	**/
	inline function tintElement(ref:RGBShaderReference, element:String, supported:Bool, linked:Bool, column:Int, keyCount:Int):Void {
		if (ref == null)
			return;
		if (!supported) {
			ref.enabled = false;
			return;
		}
		ref.enabled = true;
		if (linked)
			return;
		var cols:Array<FlxColor> = tintFor(element, column, keyCount);
		if (cols != null) {
			ref.r = cols[0];
			ref.g = cols[1];
			ref.b = cols[2];
		}
	}

	/** The [r,g,b] triple an asset resolves to at a lane, or null when out of range. **/
	inline function tintFor(element:String, column:Int, keyCount:Int):Array<FlxColor> {
		var all:Array<Array<FlxColor>> = Mania.getAssetColors(element, keyCount);
		return (column >= 0 && column < all.length && all[column] != null && all[column].length >= 3) ? all[column] : null;
	}

	/** Builds the receptor static/pressed/confirm look; falls back to the classic skin if unresolved. **/
	public function applyReceptor(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, lastAnim:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var cfg:NoteSkinData = NoteSkinConfig.forCurrentKeys(skinName);
		if (cfg == null)
			return fallback.applyReceptor(spr, rgb, column, keyCount, lastAnim);
		syncPixelMode(cfg);

		var base:String = NoteSkinConfig.folder(skinName);
		var c:Int = column;
		var kc:Int = Mania.clamp(keyCount);

		var st = NoteSkinConfig.resolveColumn(cfg, cfg.strums, c);
		if (st == null)
			return fallback.applyReceptor(spr, rgb, column, keyCount, lastAnim);
		var staticF:Array<String> = NoteSkinConfig.resolveFrames(base + st.key);
		if (staticF == null)
			return fallback.applyReceptor(spr, rgb, column, keyCount, lastAnim);
		staticF = NoteSkinConfig.staticFrame(staticF, NoteSkinConfig.animatedFor(cfg, 'strums'));
		var staticA:Float = st.angle;

		var pr = NoteSkinConfig.resolveColumn(cfg, cfg.pressed, c);
		var pressedF:Array<String> = pr == null ? null : NoteSkinConfig.resolveFrames(base + pr.key);
		var pressedA:Float = pr == null ? staticA : pr.angle;
		if (pressedF == null) {
			pressedF = staticF;
			pressedA = staticA;
		} else
			pressedF = NoteSkinConfig.staticFrame(pressedF, NoteSkinConfig.animatedFor(cfg, 'pressed'));

		var cf = NoteSkinConfig.resolveColumn(cfg, cfg.confirm, c);
		var confirmF:Array<String> = cf == null ? null : NoteSkinConfig.resolveFrames(base + cf.key);
		var confirmA:Float = cf == null ? pressedA : cf.angle;
		if (confirmF == null) {
			confirmF = pressedF;
			confirmA = pressedA;
		} else
			confirmF = NoteSkinConfig.staticFrame(confirmF, NoteSkinConfig.animatedFor(cfg, 'confirm'));

		var laneFps:Int = NoteSkinConfig.fpsForColumn(cfg, c);
		var factor:Float = NoteSkinConfig.applyAnims(spr, [
			{name: 'static', keys: staticF, fps: laneFps, loop: false, angle: staticA, square: true},
			{name: 'pressed', keys: pressedF, fps: laneFps, loop: false, angle: pressedA, square: true},
			{name: 'confirm', keys: confirmF, fps: confirmF.length > 1 ? laneFps : 24, loop: false, angle: confirmA, square: true}
		]);

		v.colorPerAnim = true;
		// Skin support only; the per-anim link/custom colour is resolved in Receptor.playAnim.
		v.staticColorable = NoteSkinConfig.colorableFor(cfg, 'strums');
		v.pressedColorable = NoteSkinConfig.colorableFor(cfg, 'pressed');
		v.confirmColorable = NoteSkinConfig.colorableFor(cfg, 'confirm');
		spr.antialiasing = (cfg.pixel == true
			|| NoteSkinConfig.pixelMode) ? false : NoteSkinConfig.boolForColumn(cfg.antialiasing, c, ClientPrefs.data.antialiasing);

		var soff:Array<Float> = NoteSkinConfig.offsetFor(cfg.strumOffsets, c);
		v.offsetX = soff[0];
		v.offsetY = soff[1];
		v.laneCenter = true;

		var scaleBase:Float = NoteSkinConfig.scaleForColumn(cfg, c) * Mania.noteSizes[kc - 1] / Mania.noteSizes[Mania.DEFAULT - 1];
		spr.scale.set(scaleBase * factor, scaleBase * factor);
		spr.updateHitbox();
		v.scaleFactor = scaleBase * factor;
		v.pixel = (cfg.pixel == true || NoteSkinConfig.pixelMode);

		if (lastAnim != null && spr.animation.getByName(lastAnim) != null)
			spr.animation.play(lastAnim, true);
		else
			spr.animation.play('static', true);
		v.ok = true;
		return v;
	}
}
