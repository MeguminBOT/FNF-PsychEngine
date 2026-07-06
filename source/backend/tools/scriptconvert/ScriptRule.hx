package backend.tools.scriptconvert;

/**
	How a flagged idiom relates to the current engine. Drives the reported severity and the
	advice the Script Converter shows (see `ScriptRules` for the catalog).
**/
enum abstract RuleKind(Int) from Int to Int {
	/** Pure old->new rename; always safe to update. Carries a `replace` for later auto-fix. **/
	var RENAMED;

	/** Superseded call that still works but should be replaced; the engine already warns at runtime. **/
	var DEPRECATED;

	/** Runs only when the modpack sets `compatibilityMode = true` (the `legacy/` layer); absent in native v2. **/
	var COMPAT_ONLY;

	/** No equivalent even under `compatibilityMode`; must be rewritten by hand. **/
	var REMOVED;

	/** A structural code pattern that is no longer supported. **/
	var PATTERN;

	/** `'warn'` for things that break or only survive on the legacy layer, `'info'` for pure renames. **/
	public function severity():String {
		return switch (cast this : RuleKind) {
			case RENAMED | DEPRECATED: 'info';
			default: 'warn';
		}
	}

	/** Short lowercase tag shown on the result chip. **/
	public function label():String {
		return switch (cast this : RuleKind) {
			case RENAMED: 'renamed';
			case DEPRECATED: 'deprecated';
			case COMPAT_ONLY: 'compat-only';
			case REMOVED: 'removed';
			case PATTERN: 'pattern';
		}
	}
}

/** Which script language a rule targets, or which language a scanned file is. **/
enum abstract ScriptKind(Int) from Int to Int {
	var LUA;
	var HSCRIPT;

	/** Rule-only: matches both Lua and HScript sources. **/
	var BOTH;
}

/**
	One detection rule: a regex to match against a source line, plus the guidance to report when
	it hits. `replace` is reserved for a future auto-rewrite pass (only meaningful for `RENAMED`
	rows) and is unused by v1 detection.
**/
typedef ScriptRule = {
	re:EReg,
	kind:RuleKind,
	appliesTo:ScriptKind,
	message:String,
	?suggestion:String,
	?replace:String
};
