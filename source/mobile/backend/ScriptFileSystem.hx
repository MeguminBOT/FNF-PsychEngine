package mobile.backend;

#if android
import sys.FileSystem as SysFS;

// sys.FileSystem stand-in for scripts: exists() also matches APK assets (via AssetUtil),
// everything else passes through to the real FileSystem. Injected as `FileSystem` in the
// HScript env so mod scripts checking for assets behave correctly on Android.
class ScriptFileSystem
{
	public static function exists(path:String):Bool
		return AssetUtil.exists(path);

	public static function readDirectory(path:String):Array<String>
		return SysFS.readDirectory(path);

	public static function isDirectory(path:String):Bool
		return SysFS.isDirectory(path);

	public static function createDirectory(path:String):Void
		SysFS.createDirectory(path);

	public static function deleteFile(path:String):Void
		SysFS.deleteFile(path);

	public static function deleteDirectory(path:String):Void
		SysFS.deleteDirectory(path);

	public static function rename(path:String, newPath:String):Void
		SysFS.rename(path, newPath);

	public static function stat(path:String)
		return SysFS.stat(path);

	public static function fullPath(relPath:String):String
		return SysFS.fullPath(relPath);

	public static function absolutePath(relPath:String):String
		return SysFS.absolutePath(relPath);
}
#end
