package mobile.backend;

import openfl.utils.Assets;

/**
 * Android-safe file access. On Android the base game assets are bundled INSIDE the APK
 * (served by OpenFL Assets), not on the real filesystem -- only mods/saves/crash live on
 * external storage. So every read must try the real file first (mods + desktop on-disk
 * assets), then fall back to OpenFL Assets.
 *
 * `macros.FileAccessMacro` rewrites File.getContent/File.getBytes/FileSystem.exists calls
 * throughout the game's source to these methods on Android, so callers don't change.
 * Behaviour on desktop is identical to the original calls (the FS branch always wins).
 */
class AssetUtil
{
	/** Like File.getContent, but falls back to the APK asset. Throws if truly missing (matches File.getContent). */
	public static function getText(path:String):String
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getContent(path);
		#end
		// No AssetType filter: a .json may be registered as BINARY (not TEXT), yet
		// Assets.getText reads it fine. Filtering by type wrongly reported it missing.
		if (Assets.exists(path))
			return Assets.getText(path);
		#if sys
		return sys.io.File.getContent(path); // let it throw the usual "file not found"
		#else
		return Assets.getText(path);
		#end
	}

	/** Like File.getBytes, but falls back to the APK asset. */
	public static function getBytes(path:String):haxe.io.Bytes
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getBytes(path);
		#end
		if (Assets.exists(path))
			return Assets.getBytes(path);
		#if sys
		return sys.io.File.getBytes(path);
		#else
		return Assets.getBytes(path);
		#end
	}

	/** Real file first (mods + desktop on-disk), then the APK asset. Null if missing. */
	public static function getSound(path:String):openfl.media.Sound
	{
		#if sys
		if (sys.FileSystem.exists(path))
		{
			// Sound.fromFile (AudioBuffer.fromFile) returns null for external-storage
			// files on Android; decoding the bytes works.
			final buffer = lime.media.AudioBuffer.fromBytes(sys.io.File.getBytes(path));
			return buffer != null ? openfl.media.Sound.fromAudioBuffer(buffer) : null;
		}
		#end
		return Assets.exists(path) ? Assets.getSound(path) : null;
	}

	/** Real file first (mods + desktop on-disk), then the APK asset. Null if missing. */
	public static function getBitmap(path:String):openfl.display.BitmapData
	{
		#if sys
		if (sys.FileSystem.exists(path))
			// BitmapData.fromFile (Image.fromFile) returns null for external-storage
			// files on Android; decoding the bytes works.
			return openfl.display.BitmapData.fromBytes(sys.io.File.getBytes(path));
		#end
		return Assets.exists(path) ? Assets.getBitmapData(path) : null;
	}

	/** Like FileSystem.exists, but also true for APK-bundled assets. */
	public static function exists(path:String):Bool
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return true;
		#end
		return Assets.exists(path);
	}
}
