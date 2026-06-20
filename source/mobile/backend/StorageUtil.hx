package mobile.backend;

#if android
import extension.androidtools.os.Build;
import extension.androidtools.os.Environment;
import extension.androidtools.widget.Toast;
import extension.androidtools.Permissions;
import extension.androidtools.Settings;
#end
import haxe.io.Path;
import sys.FileSystem;

/**
 * Resolves and prepares the engine's read/write storage location on mobile.
 *
 * The whole point of the Android port's storage strategy: mods/saves/crash logs
 * live in a public, top-level folder (`/storage/emulated/0/PsychEngine`) so users
 * can drop mods in with any file manager -- unlike `Android/data/<pkg>/files`, which
 * is hidden on non-rooted Android 11+. That public path requires All Files Access
 * (MANAGE_EXTERNAL_STORAGE) on Android 11+, which we request on launch.
 *
 * Bundled game assets stay inside the APK (served via openfl.Assets); only writable
 * content (mods/, saves, crash/) is placed on external storage.
 */
class StorageUtil
{
	/** Top-level folder name created under the device's shared storage root. */
	public static final ROOT_FOLDER:String = 'PsychEngine';

	/**
	 * Absolute path (with trailing slash) of the engine's external storage folder.
	 * On non-Android targets this returns the current working directory so callers
	 * can use it unconditionally.
	 */
	public static function getStorageDirectory():String
	{
		#if android
		return Path.addTrailingSlash(Path.join([Environment.getExternalStorageDirectory(), ROOT_FOLDER]));
		#elseif ios
		return Path.addTrailingSlash(lime.system.System.applicationStorageDirectory);
		#else
		return Path.addTrailingSlash(Sys.getCwd());
		#end
	}

	/**
	 * Requests the storage permissions needed to read/write the public folder.
	 * On Android 11+ this opens the All Files Access settings screen if not yet
	 * granted; on older versions it falls back to the legacy read/write prompt.
	 */
	public static function requestPermissions():Void
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.R)
		{
			if (!Environment.isExternalStorageManager())
			{
				Toast.makeText('Please grant "All Files Access" so mods and saves can be stored.', Toast.LENGTH_LONG);
				Settings.requestSetting('MANAGE_ALL_FILES_ACCESS_PERMISSION');
			}
		}
		else
		{
			Permissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
		}
		#end
	}

	/**
	 * Creates the writable subfolders the engine expects (mods/, saves/, crash/).
	 * Safe to call every launch -- existing folders are left untouched.
	 */
	public static function prepareDirectories():Void
	{
		#if (android || ios)
		final root:String = getStorageDirectory();
		for (folder in ['', 'mods', 'saves', 'crash'])
		{
			final dir:String = Path.join([root, folder]);
			if (!FileSystem.exists(dir))
			{
				try
				{
					FileSystem.createDirectory(dir);
				}
				catch (e:Dynamic)
				{
					trace('StorageUtil: failed to create "$dir": $e');
				}
			}
		}
		#end
	}
}
