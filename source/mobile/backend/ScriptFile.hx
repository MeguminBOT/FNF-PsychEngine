package mobile.backend;

#if android
import sys.io.File as SysFile;

// sys.io.File stand-in for scripts: reads fall back to the APK asset (via AssetUtil),
// writes/streams pass through to the real File. Injected as `File` in the HScript env so
// mod scripts that read assets with File.getContent just work on Android.
class ScriptFile
{
	public static function getContent(path:String):String
		return AssetUtil.getText(path);

	public static function getBytes(path:String):haxe.io.Bytes
		return AssetUtil.getBytes(path);

	public static function saveContent(path:String, content:String):Void
		SysFile.saveContent(path, content);

	public static function saveBytes(path:String, bytes:haxe.io.Bytes):Void
		SysFile.saveBytes(path, bytes);

	public static function copy(srcPath:String, dstPath:String):Void
		SysFile.copy(srcPath, dstPath);

	public static function read(path:String, binary:Bool = true)
		return SysFile.read(path, binary);

	public static function write(path:String, binary:Bool = true)
		return SysFile.write(path, binary);

	public static function append(path:String, binary:Bool = true)
		return SysFile.append(path, binary);

	public static function update(path:String, binary:Bool = true)
		return SysFile.update(path, binary);
}
#end
