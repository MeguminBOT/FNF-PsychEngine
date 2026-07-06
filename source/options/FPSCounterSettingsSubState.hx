package options;

/**
 * Customization for the on-screen performance counter (debug.FPSCounter).
 * Position, font size, refresh rate and which metrics are shown all live in
 * `DebugPrefs.data` (a separate save, so mod scripts can't tamper with them)
 * and are applied live by calling `Main.fpsVar.updateConfiguration()` on every
 * change. Options are rebound to DebugPrefs via `bindDebugOption`.
 *
 * The option list is exposed via the static `buildOptions`, shared by this
 * legacy substate and the embedded modal opened from `OptionsState`.
 */
class FPSCounterSettingsSubState extends BaseOptionsMenu {
	public function new() {
		title = Language.getPhrase('fps_counter_menu', 'FPS Counter Settings');
		rpcTitle = 'FPS Counter Settings';
		for (o in buildOptions())
			addOption(o);
		super();
	}

	/**
	 * The FPS-counter options, all rebound to `DebugPrefs`. Shared by this substate and the
	 * embedded modal so the two stay in sync.
	 * @return the option list, in display order
	 */
	public static function buildOptions():Array<Option> {
		var opts:Array<Option> = [];
		function add(option:Option):Void {
			bindDebugOption(option);
			opts.push(option);
		}
		// Each metric gets a Show toggle plus a "Line" number; metrics that share
		// a line number are printed on the same line, joined with " | ".
		function metric(name:String, desc:String, showVar:String, rowVar:String):Void {
			var show:Option = new Option('Show $name', desc, showVar, BOOL);
			show.onChange = applyConfig;
			add(show);

			var row:Option = new Option('$name Line',
				'Which line "$name" appears on (lower numbers are higher up).\nMetrics sharing a line number are joined with " | ".', rowVar, INT);
			row.minValue = 1;
			row.maxValue = 8;
			row.changeValue = 1;
			row.scrollSpeed = 8;
			row.onChange = applyConfig;
			add(row);
		}

		var option:Option = new Option('Position:', "Which corner of the screen the counter is anchored to.", 'fpsPosition', STRING,
			['Top Left', 'Top Right', 'Bottom Left', 'Bottom Right']);
		option.onChange = applyConfig;
		add(option);

		option = new Option('Color:', "Text color of the counter.", 'fpsColor', STRING, debug.FPSCounter.COLOR_NAMES.copy());
		option.onChange = applyConfig;
		add(option);

		option = new Option('Background', "Draw a dark panel behind the counter so it's easier to read over bright stages.", 'fpsBackground', BOOL);
		option.onChange = applyConfig;
		add(option);

		option = new Option('Background Opacity', "How opaque the background panel is (only matters when Background is on).", 'fpsBackgroundAlpha', PERCENT);
		option.minValue = 0;
		option.maxValue = 1;
		option.changeValue = 0.05;
		option.scrollSpeed = 0.5;
		option.decimals = 2;
		option.onChange = applyConfig;
		add(option);

		option = new Option('Font Size', "Text size of the counter, in points.", 'fpsSize', INT);
		option.minValue = 6;
		option.maxValue = 72;
		option.changeValue = 1;
		option.scrollSpeed = 30;
		option.onChange = applyConfig;
		add(option);

		option = new Option('Update Rate (ms)',
			"Minimum time between text refreshes.\nHigher = steadier numbers and slightly less overhead.\n0 refreshes every frame.", 'fpsUpdateMS', INT);
		option.minValue = 0;
		option.maxValue = 1000;
		option.changeValue = 10;
		option.scrollSpeed = 250;
		option.onChange = applyConfig;
		add(option);

		metric('FPS', "Show the frames-per-second line.", 'fpsShowFPS', 'fpsRowFPS');
		metric('Memory', "Show current process memory usage (real working set).\nFalls back to GC memory on builds without hxhardware.", 'fpsShowMemory',
			'fpsRowMemory');
		metric('Peak Memory', "Show the highest memory usage seen since launch.", 'fpsShowMemoryPeak', 'fpsRowMemoryPeak');
		metric('GC Memory', "Show the Haxe/hxcpp garbage-collector heap only.\nThis does NOT include LuaJIT memory.", 'fpsShowGCMemory', 'fpsRowGCMemory');
		#if LUA_ALLOWED
		metric('Lua Memory', "Show LuaJIT GC memory, totalled across all running scripts.\nLuaJIT keeps its own heap, separate from the GC Memory line.",
			'fpsShowLuaMem', 'fpsRowLuaMem');
		#end
		#if HARDWARE_ALLOWED
		metric('CPU Usage', "Show this process's CPU usage as a percentage.", 'fpsShowCPU', 'fpsRowCPU');
		metric('GPU Usage', "Show total system GPU usage as a percentage.\n(Windows only; reads 0% elsewhere.)", 'fpsShowGPU', 'fpsRowGPU');
		metric('GPU Memory (VRAM)', "Show dedicated video memory in use.\n(Windows only, via DXGI; hidden elsewhere.)", 'fpsShowGPUMem', 'fpsRowGPUMem');
		#end

		return opts;
	}

	/** Applies the current counter configuration to the live FPS counter. **/
	public static function applyConfig():Void {
		if (Main.fpsVar != null)
			Main.fpsVar.updateConfiguration();
	}

	/**
	 * Points an Option's value get/set (and default) at `DebugPrefs.data` instead
	 * of the `ClientPrefs.data` the Option class assumes. Reusable from any menu
	 * that exposes a counter setting (e.g. the master toggle in Performance).
	 * @param option the option to rebind to DebugPrefs
	 */
	public static function bindDebugOption(option:Option):Void {
		final v:String = option.variable;
		option.defaultValue = Reflect.getProperty(DebugPrefs.defaultData, v);
		option.getValue = function():Dynamic return Reflect.getProperty(DebugPrefs.data, v);
		option.setValue = function(val:Dynamic):Dynamic {
			Reflect.setProperty(DebugPrefs.data, v, val);
			return val;
		};
		// Re-sync the STRING selector index now that getValue points at DebugPrefs.
		if (option.type == STRING && option.options != null) {
			final idx:Int = option.options.indexOf(option.getValue());
			if (idx > -1)
				option.curOption = idx;
		}
	}

	override function destroy():Void {
		ClientPrefs.saveSettings();
		super.destroy();
	}
}
