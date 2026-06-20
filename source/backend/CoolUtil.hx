package backend;

import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;

class CoolUtil {
	public static function checkForUpdates(url:String = null):String {
		if (url == null || url.length == 0)
			url = "https://raw.githubusercontent.com/MeguminBOT/FNF-PsychEngine/master/gitVersion.txt";
		var version:String = states.MainMenuState.psychEngineVersion.trim();
		if (ClientPrefs.data.checkForUpdates) {
			trace('checking for updates...');
			var http = new haxe.Http(url);
			http.onData = function(data:String) {
				var newVersion:String = data.split('\n')[0].trim();
				trace('version online: $newVersion, your version: $version');
				if (newVersion != version) {
					trace('versions arent matching! please update');
					version = newVersion;
					http.onData = null;
					http.onError = null;
					http = null;
				}
			}
			http.onError = function(error) {
				trace('error: $error');
			}
			http.request();
		}
		return version;
	}

	inline public static function quantize(f:Float, snap:Float) {
		// changed so this actually works lol
		var m:Float = Math.fround(f * snap);
		// trace(snap);
		return (m / snap);
	}

	inline public static function capitalize(text:String)
		return text.charAt(0).toUpperCase() + text.substr(1).toLowerCase();

	inline public static function coolTextFile(path:String):Array<String> {
		var daList:String = null;
		#if (sys && MODS_ALLOWED)
		if (FileSystem.exists(path))
			daList = File.getContent(path);
		#else
		if (Assets.exists(path))
			daList = Assets.getText(path);
		#end
		return daList != null ? listFromString(daList) : [];
	}

	// Hoisted -- recompiling this regex on every call is wasteful;
	// colorFromString is hit a lot from Lua mod scripts.
	static final _hideCharsRegex:EReg = ~/[\t\n\r]/;

	inline public static function colorFromString(color:String):FlxColor {
		var color:String = _hideCharsRegex.split(color).join('').trim();
		if (color.startsWith('0x'))
			color = color.substring(color.length - 6);

		var colorNum:Null<FlxColor> = FlxColor.fromString(color);
		if (colorNum == null)
			colorNum = FlxColor.fromString('#$color');
		return colorNum != null ? colorNum : FlxColor.WHITE;
	}

	inline public static function listFromString(string:String):Array<String> {
		var daList:Array<String> = [];
		daList = string.trim().split('\n');

		for (i in 0...daList.length)
			daList[i] = daList[i].trim();

		return daList;
	}

	public static function floorDecimal(value:Float, decimals:Int):Float {
		if (decimals < 1)
			return Math.floor(value);

		return Math.floor(value * Math.pow(10, decimals)) / Math.pow(10, decimals);
	}

	inline public static function dominantColor(sprite:flixel.FlxSprite):Int {
		var countByColor:Map<Int, Int> = [];
		final pixels = sprite.pixels;
		final w:Int = sprite.frameWidth;
		final h:Int = sprite.frameHeight;
		for (col in 0...w) {
			for (row in 0...h) {
				var colorOfThisPixel:FlxColor = pixels.getPixel32(col, row);
				if (colorOfThisPixel.alphaFloat > 0.05) {
					colorOfThisPixel = FlxColor.fromRGB(colorOfThisPixel.red, colorOfThisPixel.green, colorOfThisPixel.blue, 255);
					// Single map lookup instead of exists()+get pair.
					final prev = countByColor.get(colorOfThisPixel);
					countByColor.set(colorOfThisPixel, prev == null ? 1 : prev + 1);
				}
			}
		}

		var maxCount = 0;
		var maxKey:Int = 0; // after the loop this will store the max color
		countByColor[FlxColor.BLACK] = 0;
		for (key => count in countByColor) {
			if (count >= maxCount) {
				maxCount = count;
				maxKey = key;
			}
		}
		countByColor = [];
		return maxKey;
	}

	inline public static function numberArray(max:Int, ?min = 0):Array<Int> {
		var dumbArray:Array<Int> = [];
		for (i in min...max)
			dumbArray.push(i);

		return dumbArray;
	}

	inline public static function browserLoad(site:String) {
		#if linux
		Sys.command('/usr/bin/xdg-open', [site]);
		#else
		FlxG.openURL(site);
		#end
	}

	inline public static function openFolder(folder:String, absolute:Bool = false) {
		#if sys
		if (!absolute)
			folder = Sys.getCwd() + '$folder';

		folder = folder.replace('/', '\\');
		// substr() is non-mutating -- the original assignment was missing,
		// so the trailing slash was never actually trimmed. Fixed.
		if (folder.endsWith('\\'))
			folder = folder.substr(0, folder.length - 1);

		#if linux
		var command:String = '/usr/bin/xdg-open';
		#else
		var command:String = 'explorer.exe';
		#end
		Sys.command(command, [folder]);
		trace('$command $folder');
		#else
		FlxG.error("Platform is not supported for CoolUtil.openFolder");
		#end
	}

	/**
		Helper Function to Fix Save Files for Flixel 5

		-- EDIT: [November 29, 2023] --

		this function is used to get the save path, period.
		since newer flixel versions are being enforced anyways.
		@crowplexus
	**/
	@:access(flixel.util.FlxSave.validate)
	inline public static function getSavePath():String {
		final company:String = FlxG.stage.application.meta.get('company');
		// #if (flixel < "5.0.0") return company; #else
		#if mobile
		// Keep saves in the public, browsable folder (cwd is already set to it in Main),
		// so they survive reinstalls and can be backed up by the user.
		return 'saves/${flixel.util.FlxSave.validate(FlxG.stage.application.meta.get('file'))}';
		#else
		return '${company}/${flixel.util.FlxSave.validate(FlxG.stage.application.meta.get('file'))}';
		#end
		// #end
	}

	public static function setTextBorderFromString(text:FlxText, border:String) {
		switch (border.toLowerCase().trim()) {
			case 'shadow':
				text.borderStyle = SHADOW;
			case 'outline':
				text.borderStyle = OUTLINE;
			case 'outline_fast', 'outlinefast':
				text.borderStyle = OUTLINE_FAST;
			default:
				text.borderStyle = NONE;
		}
	}
}
