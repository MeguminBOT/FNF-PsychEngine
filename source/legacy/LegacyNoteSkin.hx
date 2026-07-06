package legacy;

import legacy.LegacyNote;
import legacy.LegacyStrumNote;

using StringTools;

/**
 * **LEGACY (pre-v2) classic note-skin loader — deprecated.** Fallback texture loader for the legacy
 * `LegacyNote`/`LegacyStrumNote` runtime only; the v2 path resolves looks through
 * `backend.noteskin.*` (`NoteSkinService` -> `ClassicNoteSkin`/`FolderNoteSkin`). Methods are `@:deprecated`.
 *
 * The classic, pre-NoteSkinConfig note-skin system: sparrow-sheet arrows, multikey atlas merging,
 * and pixel UI sheets. Quarantined here out of LegacyNote/LegacyStrumNote so the modern folder-skin
 * (NoteSkinConfig / .tcfg) path stays clean. Still wired as the fallback: LegacyNote.reloadNote /
 * LegacyStrumNote.reloadNote call into this when there's no active folder skin, so pixel stages, vanilla
 * weeks, and charts with a custom `arrowSkin` keep rendering exactly as before.
 */
@:access(legacy.LegacyNote)
@:access(legacy.LegacyStrumNote)
class LegacyNoteSkin {
	/**
		Classic receptor build (formerly `LegacyStrumNote.reloadNote`'s non-folder branch): loads the
		strum's sparrow/pixel sheet, adds the `static`/`pressed`/`confirm` animations and sizes/centers it.
		@param strum the receptor to (re)build
		@param lastAnim the animation to restore afterwards (may be `null`)
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public static function reloadStrum(strum:LegacyStrumNote, lastAnim:String):Void {
		var texture:String = strum.texture;
		var noteData:Int = strum.noteData;

		if (PlayState.isPixelStage) {
			final pixelGraphic = Paths.image('pixelUI/' + texture);
			if (pixelGraphic == null) {
				FlxG.log.error('LegacyStrumNote: pixel skin missing -- could not load "images/pixelUI/$texture.png"');
				return;
			}
			strum.loadGraphic(pixelGraphic);
			strum.width = strum.width / 4;
			strum.height = strum.height / 5;
			strum.loadGraphic(pixelGraphic, true, Math.floor(strum.width), Math.floor(strum.height));

			strum.antialiasing = false;
			strum.setGraphicSize(Std.int(strum.width * PlayState.daPixelZoom));

			strum.animation.add('green', [6]);
			strum.animation.add('red', [7]);
			strum.animation.add('blue', [5]);
			strum.animation.add('purple', [4]);
			switch (Math.abs(noteData) % 4) {
				case 0:
					strum.animation.add('static', [0]);
					strum.animation.add('pressed', [4, 8], 12, false);
					strum.animation.add('confirm', [12, 16], 24, false);
				case 1:
					strum.animation.add('static', [1]);
					strum.animation.add('pressed', [5, 9], 12, false);
					strum.animation.add('confirm', [13, 17], 24, false);
				case 2:
					strum.animation.add('static', [2]);
					strum.animation.add('pressed', [6, 10], 12, false);
					strum.animation.add('confirm', [14, 18], 12, false);
				case 3:
					strum.animation.add('static', [3]);
					strum.animation.add('pressed', [7, 11], 12, false);
					strum.animation.add('confirm', [15, 19], 24, false);
			}
		} else if (Mania.current != Mania.DEFAULT) {
			// Multikey: keep the 4 arrows from the note skin and merge in the square atlas
			// (centre "square" note + arrowSQUARE); per-column anim name from the Mania table.
			var atlas:flixel.graphics.frames.FlxAtlasFrames = Paths.getSparrowAtlas(texture);
			if (atlas == null) {
				FlxG.log.error('LegacyStrumNote: skin "$texture" has no sparrow atlas (folder skin or missing?); classic strum render skipped');
				return;
			}
			atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			strum.frames = atlas;
			strum.antialiasing = ClientPrefs.data.antialiasing;

			var anim:String = Mania.noteAnimations[Mania.current - 1][Std.int(Math.abs(noteData)) % Mania.current];
			strum.animation.addByPrefix('static', 'arrow' + anim.toUpperCase(), 24, false);
			strum.animation.addByPrefix('pressed', anim + ' press', 24, false);
			strum.animation.addByPrefix('confirm', anim + ' confirm', 24, false);

			strum.setGraphicSize(Std.int(strum.width * Mania.noteSizes[Mania.current - 1]));
		} else {
			var atlas:flixel.graphics.frames.FlxAtlasFrames = Paths.getSparrowAtlas(texture);
			if (atlas == null) {
				FlxG.log.error('LegacyStrumNote: skin "$texture" has no sparrow atlas (folder skin or missing?); classic strum render skipped');
				return;
			}
			strum.frames = atlas;
			strum.animation.addByPrefix('green', 'arrowUP');
			strum.animation.addByPrefix('blue', 'arrowDOWN');
			strum.animation.addByPrefix('purple', 'arrowLEFT');
			strum.animation.addByPrefix('red', 'arrowRIGHT');

			strum.antialiasing = ClientPrefs.data.antialiasing;
			strum.setGraphicSize(Std.int(strum.width * 0.7));

			switch (Math.abs(noteData) % 4) {
				case 0:
					strum.animation.addByPrefix('static', 'arrowLEFT');
					strum.animation.addByPrefix('pressed', 'left press', 24, false);
					strum.animation.addByPrefix('confirm', 'left confirm', 24, false);
				case 1:
					strum.animation.addByPrefix('static', 'arrowDOWN');
					strum.animation.addByPrefix('pressed', 'down press', 24, false);
					strum.animation.addByPrefix('confirm', 'down confirm', 24, false);
				case 2:
					strum.animation.addByPrefix('static', 'arrowUP');
					strum.animation.addByPrefix('pressed', 'up press', 24, false);
					strum.animation.addByPrefix('confirm', 'up confirm', 24, false);
				case 3:
					strum.animation.addByPrefix('static', 'arrowRIGHT');
					strum.animation.addByPrefix('pressed', 'right press', 24, false);
					strum.animation.addByPrefix('confirm', 'right confirm', 24, false);
			}
		}
		strum.updateHitbox();

		if (lastAnim != null)
			strum.playAnim(lastAnim, true);
	}

	/**
		Classic note build (formerly `LegacyNote.reloadNote`'s non-folder branch): loads the note's
		sparrow/pixel/multikey sheet, adds its head or hold/end animations and sizes/centers it.
		@param note the note to (re)build
		@param skin the resolved base skin image name
		@param texture the explicit per-note texture override, or `''`/`null` for the base skin
		@param animName the animation to restore afterwards (may be `null`)
	**/
	@:deprecated("Legacy pre-v2 note runtime; kept for compatibilityMode only. The v2 path lives in objects.notes.*")
	public static function reloadNote(note:LegacyNote, skin:String, texture:String, animName:String):Void {
		var skinPixel:String = skin;
		var lastScaleY:Float = note.scale.y;
		var skinPostfix:String = LegacyNote.getNoteSkinPostfix();
		var customSkin:String = skin + skinPostfix;
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';
		if (customSkin == LegacyNote._lastValidChecked || Paths.fileExists('images/' + path + customSkin + '.png', IMAGE)) {
			skin = customSkin;
			LegacyNote._lastValidChecked = customSkin;
		} else
			skinPostfix = '';

		if (PlayState.isPixelStage) {
			if (note.isSustainNote) {
				var graphic = Paths.image('pixelUI/' + skinPixel + 'ENDS' + skinPostfix);
				if (graphic == null) {
					FlxG.log.error('LegacyNote: missing pixel sustain skin "images/pixelUI/${skinPixel}ENDS${skinPostfix}.png"');
					return;
				}
				note.loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 2));
				note.originalHeight = graphic.height / 2;
			} else {
				var graphic = Paths.image('pixelUI/' + skinPixel + skinPostfix);
				if (graphic == null) {
					FlxG.log.error('LegacyNote: missing pixel skin "images/pixelUI/${skinPixel}${skinPostfix}.png"');
					return;
				}
				note.loadGraphic(graphic, true, Math.floor(graphic.width / 4), Math.floor(graphic.height / 5));
			}
			note.setGraphicSize(Std.int(note.width * PlayState.daPixelZoom));
			note.loadPixelNoteAnims();
			note.antialiasing = false;

			if (note.isSustainNote) {
				note.offsetX += note._lastNoteOffX;
				note._lastNoteOffX = (note.width - 7) * (PlayState.daPixelZoom / 2);
				note.offsetX -= note._lastNoteOffX;
			}
		} else {
			var atlas:flixel.graphics.frames.FlxAtlasFrames = Paths.getSparrowAtlas(skin);
			if (atlas == null) {
				// Folder skins (skin.tcfg + individual images) have no sparrow atlas, and the legacy
				// note renderer only speaks sparrow. Bail instead of NPEing on null frames in
				// loadNoteAnims -> findByPrefix (folder skins render via the v2 objects.notes path).
				FlxG.log.error('LegacyNote: skin "$skin" has no sparrow atlas (folder skin?); legacy render skipped');
				return;
			}
			// Multikey: notes on the default skin merge in the square atlas (centre "square" note).
			// Custom per-note textures are left alone.
			if (Mania.current != Mania.DEFAULT && (texture == null || texture.length < 1))
				atlas.addAtlas(Paths.getSparrowAtlas(Mania.ATLAS));
			note.frames = atlas;
			note.loadNoteAnims();
			if (!note.isSustainNote) {
				note.centerOffsets();
				note.centerOrigin();
			}
		}

		if (note.isSustainNote)
			note.scale.y = lastScaleY;
		note.updateHitbox();

		if (animName != null)
			note.animation.play(animName, true);
	}
}
