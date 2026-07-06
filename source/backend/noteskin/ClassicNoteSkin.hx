package backend.noteskin;

import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import shaders.RGBPalette.RGBShaderReference;
import objects.notes.NoteDefaults;

using StringTools;

/**
	The classic (pre-folder) note skin: NOTE_assets sparrow sheets, `pixelUI/` pixel sheets, and the
	multikey square-atlas merge. A faithful port of the old `Note`/`StrumNote` building (and
	`legacy.LegacyNoteSkin`) retargeted onto bare `FlxSprite`s with standardized anim names
	(`note`/`hold`/`end` and `static`/`pressed`/`confirm`). Used by the new drawables when no folder
	skin is active, and as `FolderNoteSkin`'s fallback for elements a folder skin can't resolve. See
	`INoteSkin` for the method contracts.
**/
class ClassicNoteSkin implements INoteSkin {
	public function new() {}

	public function isPixel():Bool
		return PlayState.isPixelStage;

	/**
		Resolves the base classic skin image name: the chart's `arrowSkin` (else the default) plus the
		user's noteSkin postfix when that variant exists.
		@return the resolved skin image base name
	**/
	function resolveSkin():String {
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';
		var skin:String;
		if (!ClientPrefs.data.forceNoteSkin
			&& PlayState.SONG != null
			&& PlayState.SONG.arrowSkin != null
			&& PlayState.SONG.arrowSkin.length > 1) {
			skin = PlayState.SONG.arrowSkin;
		} else {
			// Default classic base, location-flexible: prefer noteSkins/NOTE_assets, fall back to the
			// images/-root NOTE_assets that some mods ship instead.
			skin = NoteDefaults.defaultNoteSkin;
			if (!Paths.fileExists('images/' + path + skin + '.png', IMAGE) && Paths.fileExists('images/' + path + 'NOTE_assets.png', IMAGE))
				skin = 'NOTE_assets';
		}
		var custom:String = skin + NoteDefaults.getNoteSkinPostfix();
		if (Paths.fileExists('images/' + path + custom + '.png', IMAGE))
			skin = custom;
		return skin;
	}

	/** Builds the note head from the classic sparrow sheet, or the `pixelUI/` sheet on a pixel stage. **/
	public function applyNote(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, animName:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var skin:String = resolveSkin();
		var nd:Int = column % Mania.colArray.length;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			var graphic = Paths.image('pixelUI/' + skin);
			if (graphic == null)
				return v;
			spr.loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			spr.animation.add('note', [nd + 4], 24, false);
			spr.setGraphicSize(Std.int(spr.width * PlayState.daPixelZoom));
			spr.antialiasing = false;
			v.pixel = true;
		} else {
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			if (Mania.current != Mania.DEFAULT)
				atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			spr.frames = atlas;
			spr.antialiasing = ClientPrefs.data.antialiasing;
			spr.animation.addByPrefix('note', Mania.colArray[nd] + '0');
			spr.setGraphicSize(Std.int(spr.width * Mania.noteSizes[kc - 1]));
		}

		spr.updateHitbox();
		spr.centerOffsets();
		spr.centerOrigin();
		spr.animation.play('note', true);
		v.scaleFactor = spr.scale.x;
		v.colorable = true;
		v.ok = true;
		return v;
	}

	/**
		Overrides a note head's graphic with an explicit sheet (the v2 equivalent of the legacy
		`Note.reloadNote(texture)` / per-note-type texture). Same column-indexed anim build as `applyNote`,
		but the sheet name is given rather than resolved from the skin. Silently no-ops if the sheet is
		missing, leaving the note on its skin graphic.
		@param spr the note-head sprite to re-skin
		@param column the 0-based lane (selects the colour anim)
		@param keyCount the active column count (for note sizing)
		@param texture the sparrow/pixel sheet name (no extension)
	**/
	public function applyNoteTexture(spr:FlxSprite, column:Int, keyCount:Int, texture:String):Void {
		if (texture == null || texture.length < 1)
			return;
		var nd:Int = column % Mania.colArray.length;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			if (!Paths.fileExists('images/pixelUI/' + texture + '.png', IMAGE))
				return;
			var graphic = Paths.image('pixelUI/' + texture);
			if (graphic == null)
				return;
			spr.loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			spr.animation.add('note', [nd + 4], 24, false);
			spr.setGraphicSize(Std.int(spr.width * PlayState.daPixelZoom));
			spr.antialiasing = false;
		} else {
			if (!Paths.fileExists('images/' + texture + '.png', IMAGE))
				return;
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(texture);
			if (atlas == null)
				return;
			if (Mania.current != Mania.DEFAULT)
				atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			spr.frames = atlas;
			spr.antialiasing = ClientPrefs.data.antialiasing;
			spr.animation.addByPrefix('note', Mania.colArray[nd] + '0');
			spr.setGraphicSize(Std.int(spr.width * Mania.noteSizes[kc - 1]));
		}

		spr.updateHitbox();
		spr.centerOffsets();
		spr.centerOrigin();
		spr.animation.play('note', true);
	}

	/**
		Builds the hold body + tail. On a pixel stage both come from the `<skin>ENDS` sheet (4 columns x
		2 rows: top row = hold piece, bottom row = end cap, indexed by direction); otherwise from the
		classic sparrow `hold piece` / `hold end` prefixes.
	**/
	public function applySustain(body:FlxSprite, bodyRGB:RGBShaderReference, tail:FlxSprite, tailRGB:RGBShaderReference, column:Int,
			keyCount:Int):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var skin:String = resolveSkin();
		var nd:Int = column % Mania.colArray.length;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			var ends = Paths.image('pixelUI/' + skin + 'ENDS');
			if (ends == null)
				return v;
			body.loadGraphic(ends, true, Math.floor(ends.width / 4), Math.floor(ends.height / 2));
			tail.loadGraphic(ends, true, Math.floor(ends.width / 4), Math.floor(ends.height / 2));
			body.animation.add('hold', [nd], 24, true);
			tail.animation.add('end', [nd + 4], 24, true);
			var zoom:Float = PlayState.daPixelZoom;
			body.setGraphicSize(Std.int(body.width * zoom));
			tail.setGraphicSize(Std.int(tail.width * zoom));
			body.antialiasing = tail.antialiasing = false;
			v.pixel = true;
		} else {
			var bodyAtlas:FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			var tailAtlas:FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			if (Mania.current != Mania.DEFAULT) {
				bodyAtlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
				tailAtlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			}
			body.frames = bodyAtlas;
			tail.frames = tailAtlas;
			body.animation.addByPrefix('hold', Mania.colArray[nd] + ' hold piece', 24, true);
			tail.animation.addByPrefix('end', Mania.colArray[nd] + ' hold end', 24, true);
			body.antialiasing = tail.antialiasing = ClientPrefs.data.antialiasing;
			var sz:Float = Mania.noteSizes[kc - 1];
			body.setGraphicSize(Std.int(body.width * sz));
			tail.setGraphicSize(Std.int(tail.width * sz));
		}

		body.animation.play('hold', true);
		tail.animation.play('end', true);
		body.updateHitbox();
		tail.updateHitbox();
		v.scaleFactor = body.scale.x;
		v.colorable = true;
		// Lane-center the hold like the folder-skin and per-note-texture paths do, so a body/tail frame
		// narrower (or wider) than the note head still sits on the lane instead of drifting off the head.
		v.centerOnStrum = true;
		v.ok = true;
		return v;
	}

	/**
		Overrides a hold's body + tail graphics with an explicit sheet (the sustain counterpart of
		`applyNoteTexture`). Same column-indexed `hold piece` / `hold end` build as `applySustain`, but the
		sheet is given rather than resolved. Silently no-ops if the sheet is missing.
		@param body the hold-body sprite
		@param tail the hold-end sprite
		@param column the 0-based lane
		@param keyCount the active column count (for sizing)
		@param texture the sparrow/pixel sheet name (pixel uses `<texture>ENDS`)
	**/
	public function applySustainTexture(body:FlxSprite, tail:FlxSprite, column:Int, keyCount:Int, texture:String):Void {
		if (texture == null || texture.length < 1)
			return;
		var nd:Int = column % Mania.colArray.length;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			if (!Paths.fileExists('images/pixelUI/' + texture + 'ENDS.png', IMAGE))
				return;
			var ends = Paths.image('pixelUI/' + texture + 'ENDS');
			if (ends == null)
				return;
			body.loadGraphic(ends, true, Math.floor(ends.width / 4), Math.floor(ends.height / 2));
			tail.loadGraphic(ends, true, Math.floor(ends.width / 4), Math.floor(ends.height / 2));
			body.animation.add('hold', [nd], 24, true);
			tail.animation.add('end', [nd + 4], 24, true);
			var zoom:Float = PlayState.daPixelZoom;
			body.setGraphicSize(Std.int(body.width * zoom));
			tail.setGraphicSize(Std.int(tail.width * zoom));
			body.antialiasing = tail.antialiasing = false;
		} else {
			if (!Paths.fileExists('images/' + texture + '.png', IMAGE))
				return;
			var bodyAtlas:FlxAtlasFrames = Paths.getSparrowAtlas(texture);
			var tailAtlas:FlxAtlasFrames = Paths.getSparrowAtlas(texture);
			if (bodyAtlas == null || tailAtlas == null)
				return;
			if (Mania.current != Mania.DEFAULT) {
				bodyAtlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
				tailAtlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			}
			body.frames = bodyAtlas;
			tail.frames = tailAtlas;
			body.animation.addByPrefix('hold', Mania.colArray[nd] + ' hold piece', 24, true);
			tail.animation.addByPrefix('end', Mania.colArray[nd] + ' hold end', 24, true);
			body.antialiasing = tail.antialiasing = ClientPrefs.data.antialiasing;
			var sz:Float = Mania.noteSizes[kc - 1];
			body.setGraphicSize(Std.int(body.width * sz));
			tail.setGraphicSize(Std.int(tail.width * sz));
		}

		body.animation.play('hold', true);
		tail.animation.play('end', true);
		body.updateHitbox();
		tail.updateHitbox();
	}

	/**
		Skins ONE element sprite -- a note head, a hold body, or a hold-end tail -- from `source`: either a
		sparrow atlas (column-indexed frames, like the skin) or a single static image (loaded whole, one
		frame). This is the granular primitive behind the runtime note-skinning Lua callbacks, so a script
		can set each part independently and mix atlas + image parts (like a folder skin).
		@param spr the element sprite
		@param column the 0-based lane (selects the colour frames)
		@param keyCount the active column count (sizing)
		@param role `note` (head), `hold` (body), or `end` (tail) -- picks the frame prefix + anim name
		@param source the sheet/image name (no extension)
		@param asImage `true` to load a single static image; `false` for a sparrow atlas
	**/
	public function applyElement(spr:FlxSprite, column:Int, keyCount:Int, role:String, source:String, asImage:Bool):Void {
		if (spr == null || source == null || source.length < 1)
			return;
		var nd:Int = column % Mania.colArray.length;
		var kc:Int = Mania.clamp(keyCount);
		var anim:String = (role == 'hold') ? 'hold' : (role == 'end' ? 'end' : 'note');
		var loop:Bool = (role != 'note');

		if (asImage) {
			if (!Paths.fileExists('images/$source.png', IMAGE))
				return;
			var g = Paths.image(source);
			if (g == null)
				return;
			spr.loadGraphic(g);
			spr.animation.add(anim, [0], 24, loop);
		} else {
			if (!Paths.fileExists('images/$source.png', IMAGE))
				return;
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(source);
			if (atlas == null)
				return;
			if (Mania.current != Mania.DEFAULT)
				atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			spr.frames = atlas;
			var prefix:String = switch (role) {
				case 'hold': Mania.colArray[nd] + ' hold piece';
				case 'end': Mania.colArray[nd] + ' hold end';
				default: Mania.colArray[nd] + '0';
			};
			spr.animation.addByPrefix(anim, prefix, 24, loop);
		}

		spr.antialiasing = PlayState.isPixelStage ? false : ClientPrefs.data.antialiasing;
		var sz:Float = PlayState.isPixelStage ? PlayState.daPixelZoom : Mania.noteSizes[kc - 1];
		spr.setGraphicSize(Std.int(spr.width * sz));
		spr.updateHitbox();
		spr.centerOffsets();
		spr.centerOrigin();
		spr.animation.play(anim, true);
	}

	/** Builds the receptor static/pressed/confirm look (pixel, multikey, or classic 4K branch). **/
	public function applyReceptor(spr:FlxSprite, rgb:RGBShaderReference, column:Int, keyCount:Int, lastAnim:String):NoteVisual {
		var v:NoteVisual = new NoteVisual();
		var nd:Int = column;
		var kc:Int = Mania.clamp(keyCount);

		if (PlayState.isPixelStage) {
			var graphic = Paths.image('pixelUI/' + resolveSkin());
			if (graphic == null)
				return v;
			spr.loadGraphic(graphic);
			spr.width = spr.width / 4;
			spr.height = spr.height / 5;
			spr.loadGraphic(graphic, true, Math.floor(spr.width), Math.floor(spr.height));
			spr.antialiasing = false;
			spr.setGraphicSize(Std.int(spr.width * PlayState.daPixelZoom));
			switch (Std.int(Math.abs(nd)) % 4) {
				case 0:
					spr.animation.add('static', [0]);
					spr.animation.add('pressed', [4, 8], 12, false);
					spr.animation.add('confirm', [12, 16], 24, false);
				case 1:
					spr.animation.add('static', [1]);
					spr.animation.add('pressed', [5, 9], 12, false);
					spr.animation.add('confirm', [13, 17], 24, false);
				case 2:
					spr.animation.add('static', [2]);
					spr.animation.add('pressed', [6, 10], 12, false);
					spr.animation.add('confirm', [14, 18], 12, false);
				case 3:
					spr.animation.add('static', [3]);
					spr.animation.add('pressed', [7, 11], 12, false);
					spr.animation.add('confirm', [15, 19], 24, false);
			}
			v.pixel = true;
		} else if (Mania.current != Mania.DEFAULT) {
			var atlas:FlxAtlasFrames = Paths.getSparrowAtlas(NoteDefaults.defaultNoteSkin);
			atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			spr.frames = atlas;
			spr.antialiasing = ClientPrefs.data.antialiasing;
			var anim:String = Mania.noteAnimations[Mania.current - 1][Std.int(Math.abs(nd)) % Mania.current];
			spr.animation.addByPrefix('static', 'arrow' + anim.toUpperCase(), 24, false);
			spr.animation.addByPrefix('pressed', anim + ' press', 24, false);
			spr.animation.addByPrefix('confirm', anim + ' confirm', 24, false);
			spr.setGraphicSize(Std.int(spr.width * Mania.noteSizes[kc - 1]));
		} else {
			spr.frames = Paths.getSparrowAtlas(NoteDefaults.defaultNoteSkin);
			spr.antialiasing = ClientPrefs.data.antialiasing;
			spr.setGraphicSize(Std.int(spr.width * 0.7));
			switch (Std.int(Math.abs(nd)) % 4) {
				case 0:
					spr.animation.addByPrefix('static', 'arrowLEFT');
					spr.animation.addByPrefix('pressed', 'left press', 24, false);
					spr.animation.addByPrefix('confirm', 'left confirm', 24, false);
				case 1:
					spr.animation.addByPrefix('static', 'arrowDOWN');
					spr.animation.addByPrefix('pressed', 'down press', 24, false);
					spr.animation.addByPrefix('confirm', 'down confirm', 24, false);
				case 2:
					spr.animation.addByPrefix('static', 'arrowUP');
					spr.animation.addByPrefix('pressed', 'up press', 24, false);
					spr.animation.addByPrefix('confirm', 'up confirm', 24, false);
				case 3:
					spr.animation.addByPrefix('static', 'arrowRIGHT');
					spr.animation.addByPrefix('pressed', 'right press', 24, false);
					spr.animation.addByPrefix('confirm', 'right confirm', 24, false);
			}
		}

		spr.updateHitbox();
		if (lastAnim != null && spr.animation.getByName(lastAnim) != null)
			spr.animation.play(lastAnim, true);
		else
			spr.animation.play('static', true);
		v.colorable = true;
		v.ok = true;
		return v;
	}
}
