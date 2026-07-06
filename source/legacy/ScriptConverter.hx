package legacy;

import backend.tools.scriptconvert.ScriptScanner;
import backend.tools.scriptconvert.ScriptScanner.ScanReport;

/** One flagged spot in a script (legacy shape kept for older callers). **/
typedef ConvertIssue = {
	line:Int,
	severity:String,
	match:String,
	advice:String
};

/** Result of analysing one script source (legacy shape kept for older callers). **/
typedef ConvertReport = {
	issues:Array<ConvertIssue>,
	annotated:String
};

/**
	Thin backwards-compatible façade over `backend.tools.scriptconvert.ScriptScanner`, which is now
	the real engine (a superset of the original note-v2-only converter this class used to be). Kept
	so any code that still imports `legacy.ScriptConverter` keeps compiling; new code should call
	`ScriptScanner` directly.
**/
class ScriptConverter {
	/**
		Scans one script's source for outdated API and returns the legacy report shape.
		@param src the raw script text
		@param isLua `true` for Lua (`--` comments), `false` for HScript (`//` comments)
		@return the per-line issues plus an annotated copy of the source
	**/
	public static function analyze(src:String, isLua:Bool):ConvertReport {
		var report:ScanReport = ScriptScanner.analyze(src, isLua ? LUA : HSCRIPT);
		var issues:Array<ConvertIssue> = [];
		for (issue in report.issues) {
			var advice:String = (issue.suggestion != null && issue.suggestion.length > 0) ? issue.message + ' ' + issue.suggestion : issue.message;
			issues.push({line: issue.line, severity: issue.severity, match: issue.match, advice: advice});
		}
		return {issues: issues, annotated: report.annotated};
	}

	#if sys
	/**
		Scans a mod folder and writes annotated copies + a report (originals untouched).
		@param dir the mod folder to scan
		@return the total number of issues found
	**/
	public static function convertFolder(dir:String):Int {
		var report = ScriptScanner.scanFolder(dir);
		ScriptScanner.exportFolder(report);
		return report.total;
	}
	#end
}
