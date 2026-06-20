package macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Expr;
using haxe.macro.ExprTools;

/**
 * ANDROID-ONLY build macro that makes every base-asset read fall back to the APK.
 *
 * On Android the bundled game assets live inside the APK (OpenFL Assets), not on the
 * real filesystem (only mods/saves/crash are on external storage). Rather than patch
 * every loader by hand, this rewrites, across the game's own packages:
 *
 *     File.getContent(x)      ->  mobile.backend.AssetUtil.getText(x)
 *     File.getBytes(x)        ->  mobile.backend.AssetUtil.getBytes(x)
 *     FileSystem.exists(x)    ->  mobile.backend.AssetUtil.exists(x)
 *     (and the sys.io.File / sys.FileSystem fully-qualified forms)
 *
 * Each AssetUtil method tries the real file first (mods + desktop on-disk assets) and
 * only then the APK asset, so behaviour is unchanged on desktop. Writes / directory ops
 * (File.saveContent, FileSystem.createDirectory/readDirectory/...) are left untouched.
 *
 * IMPORTANT: gating must use Context.defined('android'), NOT `#if android`. This code
 * runs in the macro context, where target defines like `android` are NOT set on the
 * conditional-compilation flags -- so `#if android` here is always false and the macro
 * would silently do nothing.
 *
 * Wired up in Project.xml: <haxeflag name="--macro" value="macros.FileAccessMacro.use()" if="android"/>
 */
class FileAccessMacro
{
	// Game packages that read assets. (Std lib / haxelibs are intentionally excluded.)
	static final PACKAGES:Array<String> = [
		'backend', 'objects', 'states', 'options', 'substates', 'cutscenes', 'psychlua', 'scripting'
	];

	public static function use():Void
	{
		if (!Context.defined('android'))
			return;
		for (pack in PACKAGES)
			Compiler.addGlobalMetadata(pack, '@:build(macros.FileAccessMacro.build())', true, true, false);
	}

	public static function build():Array<Field>
	{
		final fields = Context.getBuildFields();
		for (field in fields)
		{
			switch (field.kind)
			{
				case FFun(f) if (f.expr != null):
					f.expr = remap(f.expr);
				case FVar(t, e) if (e != null):
					field.kind = FVar(t, remap(e));
				case FProp(get, set, t, e) if (e != null):
					field.kind = FProp(get, set, t, remap(e));
				default:
			}
		}
		return fields;
	}

	static function remap(e:Expr):Expr
	{
		if (e == null)
			return e;

		switch (e.expr)
		{
			case ECall(callee, args) if (args.length >= 1):
				switch (dotPath(callee))
				{
					case 'File.getContent' | 'sys.io.File.getContent':
						return macro @:pos(e.pos) mobile.backend.AssetUtil.getText(${remap(args[0])});
					case 'File.getBytes' | 'sys.io.File.getBytes':
						return macro @:pos(e.pos) mobile.backend.AssetUtil.getBytes(${remap(args[0])});
					case 'FileSystem.exists' | 'sys.FileSystem.exists':
						return macro @:pos(e.pos) mobile.backend.AssetUtil.exists(${remap(args[0])});
					default:
				}
			default:
		}

		return e.map(remap);
	}

	// Reconstructs a dotted identifier path ("File.getContent", "sys.FileSystem.exists")
	// from an EField/EConst chain; null if it isn't a plain field access.
	static function dotPath(e:Expr):Null<String>
	{
		return switch (e.expr)
		{
			case EConst(CIdent(s)): s;
			case EField(sub, f):
				final s = dotPath(sub);
				s == null ? null : s + '.' + f;
			default: null;
		}
	}
}
#end
