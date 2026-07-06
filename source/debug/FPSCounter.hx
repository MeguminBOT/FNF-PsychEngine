package debug;

import flixel.FlxG;
import flixel.math.FlxMath;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.Lib;
#if HARDWARE_ALLOWED
import hxhardware.CPU;
import hxhardware.GPU;
import hxhardware.Memory;
#end

/**
	A configurable performance overlay for an OpenFL/HaxeFlixel project.

	Everything the overlay shows (FPS, memory, peak memory, CPU, GPU, VRAM),
	where it sits on screen, its color, font size and refresh rate is driven by
	`DebugPrefs.data` (a separate, script-inaccessible save) and applied via
	`updateConfiguration()`. Call that after changing any of the `fps*` prefs so
	the change takes effect immediately.

	CPU/GPU/VRAM readouts (and process-accurate memory) require the `hxhardware`
	haxelib (HARDWARE_ALLOWED). Without it, memory falls back to the GC figure and
	the CPU/GPU toggles simply produce no lines.
**/
class FPSCounter extends TextField {
	/**
		The current frame rate, expressed using frames-per-second
	**/
	public var currentFPS(default, null):Int;

	/**
		Current GC memory (bytes). Kept for backwards-compat / hscript overrides;
		the visible "Memory" line uses the process figure when available.
	**/
	public var memoryMegas(get, never):Float;

	/**
		Highest memory value seen since launch (bytes). Drives the "Peak" line on
		builds without hxhardware (otherwise the native process peak is used).
	**/
	public var peakMemory(default, null):Float = 0;

	// Ordered named-color palette exposed to the options menu and resolved here.
	public static final COLOR_NAMES:Array<String> = [
		'White', 'Black', 'Red', 'Orange', 'Yellow', 'Lime', 'Green', 'Cyan', 'Blue', 'Purple', 'Pink'
	];
	public static final COLORS:Map<String, Int> = [
		'White' => 0xFFFFFFFF,
		'Black' => 0xFF000000,
		'Red' => 0xFFFF4B4B,
		'Orange' => 0xFFFF9933,
		'Yellow' => 0xFFFFE93B,
		'Lime' => 0xFF7CFF4F,
		'Green' => 0xFF35D35B,
		'Cyan' => 0xFF45D9FF,
		'Blue' => 0xFF5B9DFF,
		'Purple' => 0xFFB36BFF,
		'Pink' => 0xFFFF6BD6
	];
	static inline final WARN_COLOR:Int = 0xFFFF0000;
	static inline final BG_COLOR:Int = 0x000000; // panel fill (RGB; alpha is separate)
	static inline final BG_PAD:Float = 4; // padding around the text inside the panel

	// Ring buffer of frame timestamps. The old impl used Array.push +
	// Array.shift each frame, where shift() is O(n) and reallocates the
	// backing storage. With a fixed-size ring we get O(1) per frame and
	// zero allocations once warm.
	@:noCompletion private static inline var TIMES_CAPACITY:Int = 1024;
	@:noCompletion private static inline var MARGIN:Float = 10;

	@:noCompletion private var times:Array<Float>;
	@:noCompletion private var timesHead:Int = 0;
	@:noCompletion private var timesCount:Int = 0;

	// Cached config, refreshed by updateConfiguration() so we don't touch
	// ClientPrefs (a Reflect-backed struct) every single tick.
	@:noCompletion private var updateInterval:Float = 50;
	@:noCompletion private var position:String = 'Top Left';
	@:noCompletion private var fontSize:Int = 14;
	@:noCompletion private var baseColor:Int = 0xFFFFFFFF;
	@:noCompletion private var bgEnabled:Bool = false;
	@:noCompletion private var bgAlpha:Float = 0.5;
	// Sibling panel drawn directly behind the text (a TextField can't hold a
	// child, so the background lives next to us in the parent's display list).
	@:noCompletion private var bg:Shape;
	@:noCompletion private var showFPS:Bool = true;
	@:noCompletion private var showMemory:Bool = true;
	@:noCompletion private var showMemoryPeak:Bool = false;
	@:noCompletion private var showGCMemory:Bool = false;
	@:noCompletion private var showLuaMem:Bool = false;
	@:noCompletion private var showCPU:Bool = false;
	@:noCompletion private var showGPU:Bool = false;
	@:noCompletion private var showGPUMem:Bool = false;
	// Per-metric line numbers (column layout).
	@:noCompletion private var rowFPS:Int = 1;
	@:noCompletion private var rowMemory:Int = 2;
	@:noCompletion private var rowPeak:Int = 3;
	@:noCompletion private var rowGC:Int = 4;
	@:noCompletion private var rowLua:Int = 5;
	@:noCompletion private var rowCPU:Int = 6;
	@:noCompletion private var rowGPU:Int = 7;
	@:noCompletion private var rowVRAM:Int = 8;

	@:noCompletion private var lastColor:Int = -1;

	public function new(x:Float = 10, y:Float = 10, color:Int = 0x000000) {
		super();

		this.x = x;
		this.y = y;

		currentFPS = 0;
		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat("_sans", 14, color);
		autoSize = LEFT;
		multiline = true;
		text = "FPS: ";

		times = [for (i in 0...TIMES_CAPACITY) 0];

		bg = new Shape(); // non-interactive, so it never steals input

		#if HARDWARE_ALLOWED
		// Primes CPU sampling so the first reading isn't garbage.
		try
			CPU.init()
		catch (e:Dynamic) {}
		#end

		updateConfiguration();
	}

	/**
		Re-reads every `fps*` preference and applies it (font size, color, update
		rate, visible metrics, anchor). Safe to call any time; cheap enough for
		option menus to call on every change.
	**/
	public function updateConfiguration():Void {
		position = DebugPrefs.data.fpsPosition;
		fontSize = Std.int(FlxMath.bound(DebugPrefs.data.fpsSize, 6, 72));
		updateInterval = Math.max(0, DebugPrefs.data.fpsUpdateMS);
		final namedColor:Null<Int> = COLORS.get(DebugPrefs.data.fpsColor);
		baseColor = (namedColor != null) ? namedColor : 0xFFFFFFFF;
		bgEnabled = DebugPrefs.data.fpsBackground;
		bgAlpha = FlxMath.bound(DebugPrefs.data.fpsBackgroundAlpha, 0, 1);
		showFPS = DebugPrefs.data.fpsShowFPS;
		showMemory = DebugPrefs.data.fpsShowMemory;
		showMemoryPeak = DebugPrefs.data.fpsShowMemoryPeak;
		showGCMemory = DebugPrefs.data.fpsShowGCMemory;
		showLuaMem = DebugPrefs.data.fpsShowLuaMem;
		showCPU = DebugPrefs.data.fpsShowCPU;
		showGPU = DebugPrefs.data.fpsShowGPU;
		showGPUMem = DebugPrefs.data.fpsShowGPUMem;
		rowFPS = DebugPrefs.data.fpsRowFPS;
		rowMemory = DebugPrefs.data.fpsRowMemory;
		rowPeak = DebugPrefs.data.fpsRowMemoryPeak;
		rowGC = DebugPrefs.data.fpsRowGCMemory;
		rowLua = DebugPrefs.data.fpsRowLuaMem;
		rowCPU = DebugPrefs.data.fpsRowCPU;
		rowGPU = DebugPrefs.data.fpsRowGPU;
		rowVRAM = DebugPrefs.data.fpsRowGPUMem;

		#if HARDWARE_ALLOWED
		// Tell the background sampler which GPU metrics to poll, and spin it up the
		// first time one is needed.
		sampleGPU = showGPU;
		sampleVRAM = showGPUMem;
		if (showGPU || showGPUMem)
			ensureSampler();
		#end

		// `defaultTextFormat`'s getter returns a CLONE, so mutating it does
		// nothing -- assign a fresh format (this is what actually resizes/recolors
		// the field) and apply it to any existing text.
		final fmt = new TextFormat("_sans", fontSize, baseColor);
		defaultTextFormat = fmt;
		if (text.length > 0)
			setTextFormat(fmt);
		lastColor = -1; // force textColor reapply next tick

		// Force a rebuild + reposition on the next refresh: blanking the field
		// makes the next buildText() differ, so the new size/metrics apply.
		text = '';
		deltaTimeout = updateInterval;
	}

	var deltaTimeout:Float = 0.0;

	// Event Handlers
	private override function __enterFrame(deltaTime:Float):Void {
		final now:Float = haxe.Timer.stamp() * 1000;
		final cap:Int = TIMES_CAPACITY;

		// Push current timestamp; overwrite oldest if we'd overflow (only
		// happens at sustained >1000 FPS, but be defensive).
		if (timesCount < cap) {
			times[(timesHead + timesCount) % cap] = now;
			timesCount++;
		} else {
			times[timesHead] = now;
			timesHead = (timesHead + 1) % cap;
		}

		// Drop entries older than 1000ms.
		final cutoff:Float = now - 1000;
		while (timesCount > 0 && times[timesHead] < cutoff) {
			timesHead = (timesHead + 1) % cap;
			timesCount--;
		}

		// prevents the overlay from updating every frame, why would you need to anyways @crowplexus
		if (deltaTimeout < updateInterval) {
			deltaTimeout += deltaTime;
			return;
		}

		currentFPS = timesCount < FlxG.drawFramerate ? timesCount : FlxG.drawFramerate;
		updateText();
		deltaTimeout = 0.0;
	}

	public dynamic function updateText():Void { // so people can override it in hscript
		// Compare against the live field text so toggling every metric off
		// actually clears the overlay instead of leaving a stale line.
		final newText:String = buildText();
		if (newText != text) {
			text = newText;
			updatePosition();
		}

		final col:Int = (currentFPS < Math.min(FlxG.drawFramerate, FlxG.updateFramerate) * 0.5) ? WARN_COLOR : baseColor;
		if (lastColor != col && text.length > 0) {
			lastColor = col;
			textColor = col;
		}
	}

	// Buckets entries by their configured line number. Built fresh each refresh
	// (which is throttled), so the allocation here is not on a hot path.
	@:noCompletion var rowMap:Map<Int, Array<String>>;
	@:noCompletion var rowKeys:Array<Int>;

	@:noCompletion inline function add(row:Int, s:String):Void {
		var arr = rowMap.get(row);
		if (arr == null) {
			arr = [];
			rowMap.set(row, arr);
			rowKeys.push(row);
		}
		arr.push(s);
	}

	@:noCompletion function buildText():String {
		rowMap = new Map<Int, Array<String>>();
		rowKeys = [];

		if (showFPS)
			add(rowFPS, 'FPS: ${currentFPS}');

		if (showMemory || showMemoryPeak) {
			final cur:Float = currentMemory();
			if (cur > peakMemory)
				peakMemory = cur;
			if (showMemory)
				add(rowMemory, 'Memory: ${bytes(cur)}');
			if (showMemoryPeak)
				add(rowPeak, 'Peak: ${bytes(peakMemoryBytes())}');
		}

		if (showGCMemory)
			add(rowGC, 'GC: ${bytes(memoryMegas)}');

		#if LUA_ALLOWED
		if (showLuaMem)
			add(rowLua, 'Lua: ${bytes(psychlua.FunkinLua.totalLuaMemoryBytes())}');
		#end

		#if HARDWARE_ALLOWED
		// CPU is cheap (a couple of syscalls), so it's read inline. GPU/VRAM are
		// expensive native calls (PDH enumeration / DXGI factory creation), so a
		// background thread samples them ~2x/sec and we just read the cache here --
		// otherwise enabling them tanks the framerate.
		if (showCPU)
			add(rowCPU, 'CPU: ${percent(safeRead(CPU.getProcessCPUUsage))}');
		if (showGPU)
			add(rowGPU, 'GPU: ${percent(gpuUsage)}');
		if (showGPUMem && vramBytes > 0)
			add(rowVRAM, 'VRAM: ${bytes(vramBytes)}');
		#end

		if (rowKeys.length == 0)
			return '';

		// Lines ordered by row number; metrics on the same row joined with " | ".
		rowKeys.sort((a, b) -> a - b);
		var lines:Array<String> = [for (k in rowKeys) rowMap.get(k).join(' | ')];
		return lines.join('\n');
	}

	@:noCompletion inline function bytes(v:Float):String
		return flixel.util.FlxStringUtil.formatBytes(v);

	// Current process memory. Uses the real process working set when hxhardware
	// is available; otherwise falls back to the (smaller) GC figure.
	@:noCompletion inline function currentMemory():Float {
		#if HARDWARE_ALLOWED
		return safeMem(Memory.getProcessPhysicalMemoryUsage);
		#else
		return memoryMegas;
		#end
	}

	@:noCompletion inline function peakMemoryBytes():Float {
		#if HARDWARE_ALLOWED
		final native:Float = safeMem(Memory.getProcessPeakPhysicalMemoryUsage);
		return native > peakMemory ? native : peakMemory;
		#else
		return peakMemory;
		#end
	}

	#if HARDWARE_ALLOWED
	@:noCompletion inline function safeMem(fn:Void->cpp.SizeT):Float {
		var v:Float = 0;
		try
			v = (fn() : Float)
		catch (e:Dynamic)
			v = 0;
		return v < 0 ? 0 : v;
	}

	@:noCompletion inline function safeRead(fn:Void->Float):Float {
		var v:Float = 0;
		try
			v = fn()
		catch (e:Dynamic)
			v = 0;
		return (v < 0 || Math.isNaN(v)) ? 0 : v;
	}

	@:noCompletion inline function percent(v:Float):String
		return '${FlxMath.roundDecimal(v, 1)}%';

	// --- Background GPU sampling -------------------------------------------------
	// GPU.getSystemTotalGPUUsage() walks every "GPU Engine" PDH counter instance
	// (opening/closing a query per instance) and GPUMemory.getUsedBytes() spins up
	// a DXGI factory each call. Doing that at the overlay's refresh rate (~20x/sec)
	// stutters the game, so one daemon thread samples them on a slow clock and the
	// render thread only ever reads these cached Floats (tearing is harmless here).
	@:noCompletion static var gpuUsage:Float = 0;
	@:noCompletion static var vramBytes:Float = 0;
	@:noCompletion static var sampleGPU:Bool = false;
	@:noCompletion static var sampleVRAM:Bool = false;
	@:noCompletion static var samplerStarted:Bool = false;
	@:noCompletion static inline final GPU_SAMPLE_INTERVAL:Float = 0.5; // seconds

	// Starts the (single, app-lifetime) sampler the first time any GPU metric is
	// enabled. While both are off the thread just sleeps and does no native work.
	@:noCompletion static function ensureSampler():Void {
		if (samplerStarted)
			return;
		samplerStarted = true;
		sys.thread.Thread.create(function() {
			while (true) {
				if (sampleGPU) {
					try
						gpuUsage = GPU.getSystemTotalGPUUsage()
					catch (e:Dynamic) {}
				}
				if (sampleVRAM) {
					try
						vramBytes = GPUMemory.getUsedBytes()
					catch (e:Dynamic) {}
				}
				Sys.sleep(GPU_SAMPLE_INTERVAL);
			}
		});
	}
	#end

	// Anchors the field to the configured corner. Recomputed whenever the text
	// changes so right/bottom anchors track the (variable) field size and any
	// window resize.
	@:noCompletion function updatePosition():Void {
		final stage = Lib.current.stage;
		final sw:Float = stage.stageWidth;
		final sh:Float = stage.stageHeight;
		switch (position) {
			case 'Top Right':
				x = sw - width - MARGIN;
				y = MARGIN;
			case 'Bottom Left':
				x = MARGIN;
				y = sh - height - MARGIN;
			case 'Bottom Right':
				x = sw - width - MARGIN;
				y = sh - height - MARGIN;
			default: // Top Left
				x = MARGIN;
				y = MARGIN;
		}
		redrawBackground();
	}

	// Keeps the panel attached just behind the text and sized to the current
	// text bounds. Cheap: only runs when the text/position actually changed.
	@:noCompletion function redrawBackground():Void {
		// Lazily slot the panel into the parent's display list, directly below us.
		if (bg.parent != parent && parent != null)
			parent.addChildAt(bg, parent.getChildIndex(this));

		bg.graphics.clear();
		final draw:Bool = visible && bgEnabled && bgAlpha > 0 && text.length > 0;
		bg.visible = draw;
		if (!draw)
			return;

		bg.graphics.beginFill(BG_COLOR, bgAlpha);
		bg.graphics.drawRoundRect(x - BG_PAD, y - BG_PAD, width + BG_PAD * 2, height + BG_PAD * 2, BG_PAD * 2, BG_PAD * 2);
		bg.graphics.endFill();
	}

	// Keep the panel's visibility in lock-step with the counter's.
	@:noCompletion override private function set_visible(value:Bool):Bool {
		super.set_visible(value);
		if (bg != null)
			redrawBackground();
		return value;
	}

	inline function get_memoryMegas():Float
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
}
