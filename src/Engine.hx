package;
import com.DatFile;
import com.SevenZip;
import com.Worker;
import djNode.BaseApp;
import djNode.Terminal;
import djNode.task.CJob;
import djNode.task.CTask;
import djNode.tools.FileTool;
import djNode.tools.LOG;
import djNode.utils.Print2;
import djNode.utils.ProgressBar;
import js.node.Fs;
import js.node.Os;
import js.node.Path;


enum EngineAction {
	BUILD;
	SCAN;
}

/**
 * RomUtil
 * Running parameters and engine
 * Singleton class
 */
@:allow(com.Worker)
class Engine 
{
	// Valid Archive Extensions that can be Read from the engine
	static final ARCHIVE_EXT:Array<String> = ['.zip', '.7z']; // (keep lowercase)
	
	// Default string for Priority Countries for the '-country' parameter
	static final DEF_COUNTRY = "EUROPE,USA";
	
	// Line length
	static final LINE = 45;
	
	// Pre String to all Terminal Prints
	static final p0 = " ";
	
	// Header for the report file
	static final rep_head = [
		'== ROM UTIL ',
		' - Emulation Rom Utilities',
		' - http://johndimi.github.com/romutil',
		' ------------------------------------'
	];
	
	// DON'T scan this files when gettinf files from an input dir
	static var ext_blacklist:Array<String> = [
		'.dll',
		'.exe',
		'.png',
		'.jpg',
		'.avi',
		'.mp4',
		'.mkv',
		'.txt',
		'.nfo',
		'.cfg',
		'.sav',
		'.srm',
		'.state'
	];
		
	//====================================================;
	
	// Temp folder for all operations. Set with setTempFolder()
	static var TEMP:String;
	
	// I need it, because some operations are done manually, outside the 7z class
	static var PATH_7Z:String = "";
	
	/// (P)arameters and Boolean (F)lags as they come from the user:
	
	// Source folder where the ROMS are
	public static var P_SOURCE:String;
	// Target folder for ROM BUILD
	
	public static var P_TARGET:String;
	
	// Global compression Settings for roms put to target folder (RAW,ZIP,7Z)
	public static var P_COMPRESSION:String;
	
	// Current active <Action>
	public static var P_ACTION(default, null):EngineAction;
	
	// Number of parallel workers
	// #SET DIRECTLY
	public static var P_PARALLEL:Int = 2;
	
	// TRUE: Condense/Prioritize the Countries. Uses vars in (COUNTRY_AR)
	public static var FLAG_FIX_COUNTRY:Bool;
	
	// TRUE: Remove Language Strings when Building
	public static var FLAG_REMOVE_LANG:Bool;

	// TRUE: Will delete source files only after they have been built to Target Folder
	public static var FLAG_DEL_SOURCE:Bool;	
	
	// TRUE: Will overwrite files on the Target Folder
	public static var FLAG_OVERWRITE:Bool = false;
	
	// TRUE: Will produce log at target dir
	public static var FLAG_REP:Bool;
	
	//====================================================;
	
	// <Compiled> Parameter Objects
	// Custom Priority Countries Array, Set in P_SET()
	static var COUNTRY_AR:Array<String> = null;
	
	// <Compiled> Compression Array, Set in P_SET()
	static var COMPRESSION:Array<String> = null;
	
	// Helper
	static var isInited:Bool = false;
	
	// Log file path, if -report is set
	static var report_file:String = null;
	
	// Actual report file data, this will be written onto the report file
	static var report:Array<String>;
	
	static var info_total_files:Int;
	
	// 
	static var info_verb:String;
	
	// The main DAT object holding the Dat Entries
	static var DAT:DatFile = null;
	
	// Terminal Printer
	public static var P:Print2;

	// For every game that was scanned/built, keep its CRC
	static var prCRC:Map<String,Bool>;
	
	// The rom files on the source folder
	static var arFiles:Array<String>;
	
	// Hold files that were unmatched
	static var arUnmatch:Array<String>;
	
	// List of DUPLICATE ROMS, ( just info text , not proper filenames )
	static var arDups:Array<String>;
	
	// List of Fixed Rom Names that were PROCESSED (either Built or Scanned)
	static var arProc:Array<String>;
	
	// List of roms that had error when reading (log use mostly)
	static var arFailRead:Array<String>;
	
	static var arCannotDelete:Array<String>;
	
	static var T:Terminal;

	//====================================================;
	
	/**
	   Init engine and Check Input Parameters
	   @throws String Errors
	   @param	_datPath A Valid "DAT-O-MATIC" Dat File, Can be Null. For operations not requiring a DAT File
	   @param	_sourcePath Source folder for ROMS to check. Files can be RAW or inside a [zip,7z]
	   @param	_targetPath Can be Null. For operations not requiring a target path
	**/
	public static function init(_action:String, _datPath:String, _sourcePath:String = null, _targetPath:String = null):Void
	{
		if (isInited) return; isInited = true;
		
		CJob.FLAG_LOG_TASKS = false;
		T = BaseApp.TERMINAL;
		report = [];
		
		// #COLORS
		P = new Print2(BaseApp.TERMINAL);
		P.style(1, 'yellow');
		P.style(2, 'green');
		P.style(3, 'red');
		P.style(4, 'cyan');
		P.style(5, 'magenta');
		
		SevenZip.pathFromReg();
		PATH_7Z = Path.join(SevenZip.PATH, '7z.exe');

		P_SOURCE = _sourcePath;
		P_TARGET = _targetPath;
		
		P_ACTION = EngineAction.createByName(_action.toUpperCase());
		
		if (P_SOURCE != null)
		{
			if (!Fs.existsSync(P_SOURCE)) throw '[$P_SOURCE] does not exist';
		}
		
		if (P_TARGET != null){
			if (!Fs.existsSync(P_TARGET)) FileTool.createRecursiveDir(P_TARGET);
		}
		
		DAT = new DatFile(_datPath); // Throws
		
		// - Check params
		if (P_ACTION == BUILD)
		{
			info_verb = "Built";
			if (P_SOURCE == null) throw "You need to set a `source` directory";
			if (P_TARGET == null) throw "You need to set a `target` directory";
			
		}else
		{
			info_verb = "Scanned";
			// it is SCAN I don't have to check
			if (P_SOURCE == null) throw "You need to set a `source` directory";
		}
		
	}//---------------------------------------------------;
	
	
	/**
		Set and Check Optional Flags / Parameters
		- ! Call after init(); so target folder is set
		- Also sets defaults
		@throws String Error
		DEV: This could be part of the Engine.init() 
	**/
	public static function P_SET(delSrc:Bool, noLang:Bool, rep:Bool, country:String, compression:String)
	{
		FLAG_DEL_SOURCE = delSrc;
		FLAG_REMOVE_LANG = noLang;
		
		if ((FLAG_REP = rep) == true)
		{
			var dd = '_RomUtil Report ' + DateTools.format(Date.now(), "%Y-%m-%d (%H'%M'%S)") + '.txt';
			
			// Dev: Specify the report file but don't create yet.
			if (P_ACTION == BUILD)
			{
				report_file = Path.join(P_TARGET, dd);
			}else{
				report_file = Path.join(P_SOURCE, dd);	
			}
			
		}
		
		if ((P_COMPRESSION = compression) != null) 
		{
			P_COMPRESSION = parseCodecTuple(P_COMPRESSION , ['7Z', 'ZIP']);
			if (P_COMPRESSION == null)
			{
				throw 'Invalid Compression String `$compression`';
			}
			
			COMPRESSION = P_COMPRESSION.split(':');
		}
		
		if (country == null){
			FLAG_FIX_COUNTRY = false;
		}else{
			FLAG_FIX_COUNTRY = true;
			if (country.charAt(0) == "-") throw "Expecting Valid Country String or `=` for default";
			if (country == '=') country = DEF_COUNTRY;
			COUNTRY_AR = country.toUpperCase().split(',');
		}
		
	}//---------------------------------------------------;
	
	
	
	/**
	   After setting running parameters,
	   starts an action (BUILD,SCAN)
	**/
	public static function start()
	{
		// Extensions to search for Files
		var exts = ARCHIVE_EXT.copy(); exts.push(DAT.EXT);
		arFiles = filterBlacklist( FileTool.getFileListFromDirR(P_SOURCE) );
		
		info_total_files = arFiles.length;
		
		// Init statistics info
		prCRC = [];
		arDups = [];
		arProc = [];
		arFailRead = [];
		arUnmatch = [];
		arCannotDelete = [];
		
		if (FLAG_REP)
		{
			rep(Engine.rep_head);
			rep(DAT.info);
		}
		
		// --
		var j = new CJob("Process Roms : " + P_ACTION);
		
		Worker.COUNTER = 0;
		
		if (P_PARALLEL < 1) P_PARALLEL = 1;
		j.MAX_CONCURRENT = P_PARALLEL; 
	
		if (j.MAX_CONCURRENT > Os.cpus().length)
		{
			j.MAX_CONCURRENT = Os.cpus().length;
		}
		
		j.addTaskGen(()->{
			var f = arFiles.shift();
			if (f == null) return null;
			return new CTask(Path.basename(f), (t)->{
				var w = new Worker(f);
					t.syncWith(w);
					w.start();
			});
		});
		
		// --
		var progress:Int = 0;
		var _r = 1 / arFiles.length;
		var c:Int = 0; // All file counter
		
		ProgressBar.SYMBOLS = ['█', '░'];
		j.events.on('taskStatus', (a, t)->
		{
			if (a == CTaskStatus.complete){
				c++;
				progress = Math.round((c * _r) * 100);
				T.restorePos(); T.clearLine();
				restoreAndClear(2);
				print('>> |1|Processing| : (|4|$c / ${info_total_files}|) :');
				T.print(p0); ProgressBar.print(40, progress);
				P.print1('${p0}${info_verb} ({2}) , No Match ({3}) , Duplicates ({1})   ', [Std.string(arProc.length), Std.string(arUnmatch.length), Std.string(arDups.length)]);
			}
		});

		j.onComplete = ()->
		{
			restoreAndClear(3);
			T.up();
			print('|5|== [Operation Complete] |',true);
			print_post();
			repSave();
			return; // needed for some reason, else wont compile
		};
		
		j.onFail = (err)-> 
		{
			restoreAndClear(3);
			print('|3|== [Operation Fail]|', true);
			print('|1|  ${j.ERROR}|', true);
			repSave();
			return;
		};
		
		// -- Start Printing to Terminal
		print_pre();
		T.pageDown(4); // for savepos to work on windows CMD it needs space
		T.savePos();
		// --
		
		j.start();
	}//---------------------------------------------------;
	
	static function restoreAndClear(lines:Int = 1)
	{
		T.restorePos();
		while (--lines >= 0){
			T.clearLine().endl();
		}
		T.restorePos();
	}//---------------------------------------------------;
			
	/**
	   Prints the running parameters to the terminal
	   e.g.
	   
	   	- Building SET from (datfile)
		Source: 'c:\\temp\\'
		Destination: 'c:\\games\roms\\sms'
		Flags : RemoveLanguages | CondenseCountries | DeleteSource
		
	**/
	static function print_pre()
	{
		if (P_ACTION == BUILD) {
			print('= OPERATION : |5| BUILD |', true);
		}else{
			print('= OPERATION : |5| SCAN |', true);
		}
		
		if (DAT != null)
		{
			print('Dat File : |2|${DAT.fileLoaded}|', true);
			print('  contains : |4|${DAT.count}| Entries', true);
		}
		
		if (P_SOURCE != null)
		{
			print('Source : |2|$P_SOURCE|', true);
			print('  contains |2|$info_total_files| scannable files', true);
		}
			
		if (P_TARGET != null)
			print('Destination : |2|$P_TARGET|', true);
		
			
		if (P_COMPRESSION != null)
			print('Compression : |1|$P_COMPRESSION|', true);
		
		var fl = "";
		if (FLAG_DEL_SOURCE) fl += "|1|Delete Source| | ";
		if (FLAG_REP) fl += "|1|Report| | ";
		if (FLAG_REMOVE_LANG) fl += "|1|Remove Languages| | ";
		if (FLAG_FIX_COUNTRY) fl += "|1|Country Priority| : |4|" + COUNTRY_AR.toString() + "| | ";
		
		if (fl.length > 0)
		{
			fl = fl.substr(0, -3);
			print('Flags : $fl', true);
		}
		
		print('--');
	}//---------------------------------------------------;
	
	
	
	/**
	   Print info after all files processed
	**/
	static function print_post()
	{
		print(StringTools.lpad("", '-', LINE), true);
		
		rep('');
		
		var s:String = '';
		
		s = print('Files processed (|1|${info_total_files}|)');
		rep('>>>>$s\n');
		
		s = print('$info_verb (|2|${arProc.length}|) unique roms');
		rep('>>>>$s');
		rep(arProc,true);
		rep('');
		
		if (arDups.length > 0)
		{
			s = print('Duplicates in Input Folder (|3|${arDups.length}|)');
			rep('>>>>$s');
			rep(arDups,true);
			rep('');
		}
		
		if (arUnmatch.length > 0)
		{
			s = print('Input Files with No Match (|3|${arUnmatch.length}|)');
			rep('>>>>$s');
			rep(arUnmatch,true);
			rep('');
		}
		
		if (arFailRead.length > 0)
		{
			s = print('Files that failed to read (|3|${arFailRead.length}|)');
			rep('>>>>$s');
			rep(arFailRead,true);
			rep('');
		}
		
		if (arCannotDelete.length > 0)
		{
			s = print('Files that could not Delete (|3|${arCannotDelete.length}|)');
			rep('>>>>$s');
			rep(arCannotDelete,true);
			rep('');
		}
		
		if (FLAG_REP)
		{
			print('Created a report file with more info: |4|$report_file|');
		}else{
			print('Use |4|-report| to produce a detailed report file');
		}
		
		print(StringTools.lpad("", '-', LINE));
		
	}//---------------------------------------------------;
		
	
	
	/**
	   Print something to the Terminal using Print2() method
	   styles are predefined in init();
	   @param	str  |n|string| format
	   @param	log If true will also log to the global LOG 
	**/
	public static function print(str:String, r:Bool = false):String
	{
		var s = P.print2(p0 + str);
		if (r) {
			report.push(s);
		}
		return s;
	}//---------------------------------------------------;
	

	/**
	   Push to report
	**/
	static function rep(?s:String, ?ar:Array<String>,number:Bool = false)
	{
		if (ar == null)
		{
			report.push(p0 + s);
		}else{
			if (number)
			{
				var c = 1;
				for (i in ar){
					report.push(p0 +'\t${c}.\t$i');
					c++;
				}
				
			}else{
				for (i in ar){
					report.push(p0 + i);
				}
			}
		}
	}//---------------------------------------------------;
		
	
	/**
	   Save the Report Data to the File ( if the file was set )
	**/
	static function repSave()
	{
		if (report_file != null)
		{
			Fs.writeFileSync(report_file, report.join('\n'), {encoding:'utf8'});
		}
	}//---------------------------------------------------;

	
	// --
	public static function fileIsArchive(f:String):Bool
	{
		// Dev: Returns lower case and ARCHIVE is lower cases.
		var s = FileTool.getFileExt(f);
		return (ARCHIVE_EXT.indexOf(s) >= 0);
	}//---------------------------------------------------;
	
	
	
	
	/**
	   Apply activated Name Filters to a string
	   @return New String
	**/
	public static function apply_NameFilters(s:String):String
	{
		// Create new name based on filters (if any)
		if(FLAG_FIX_COUNTRY)
			s = str_prioritizeCountry(s, COUNTRY_AR);
		if (FLAG_REMOVE_LANG){
			s = str_noLanguage(s);
		}
		// Just in case, remove trailing spaces
		s = StringTools.rtrim(s);
		return s;
	}//---------------------------------------------------;
		
	
	
	/**
	   Prioritize Country Codes
	   Changes a string to only include country codes of your choosing.
	   ! Only if there are multiple country codes
	   ! Single country codes or if no prioritized country codes, No change.
	   ! Don't forget UPPERCASE Custom Countries
	   
	   e.g. (with the keeping [USA,EUROPE])
	    (USA, Europe, Brazil) => (USA, Europe)
		(USA, Europe) => (USA, Europe)
		(USA) => (USA)
		(Brazil, Korea) => (Brazil, Korea)
		(Brazil, Korea, Europe) => (Europe)	     
	   
	   @param	s String to apply to, Usually ROM name
	   @param	COUNT Countries to Prioritize, !UPPERCASE! Default = [USA,EUROPE]
	   @return  Formatted String
	**/
	public static function str_prioritizeCountry(s:String, COUNT:Array<String>):String
	{
		var strb = COUNT.join('|');
		var r = new EReg('\\([^\\)]*($strb).*?\\)', 'i');
		if (r.match(s)) {
			var c = r.matched(0);
				c = c.substr(1, c.length - 2); // Remove ( and )
			var C = c.split(',');
			if (C.length == 0) return s; // No Two Countries there
			var i = C.length - 1;
			while (i >= 0) {
				C[i] = StringTools.trim(C[i]);
				// traverse backwards, so i can delete elements
				if (COUNT.indexOf(C[i].toUpperCase()) < 0) C.splice(i, 1);
				i--;
			}
			
			var b = C.join(', ');
			s = r.replace(s, '($b)');
		}
		
		return s;
	}//---------------------------------------------------;
	
	
	/**
	   Removes Language Codes from a String
	   e.g.
	   Winter Olympics (Europe) (En,Fr,De,Es,It,Pt,Sv,No) => Winter Olympics (Europe)
	   
	   @param	s String to apply to
	   @return Fixed String
	**/
	public static function str_noLanguage(s:String):String
	{
		var r = ~/\((En|Fr|De|Es|It|Nl|Pt|Sv).*?\)/;
		if (r.match(s))
		{
			return r.replace(s, "");
		}
		
		return s;
	}//---------------------------------------------------;

	
	/**
	   -- Fetched from CDCRUSH project
	**/
	static function parseCodecTuple(S:String, M:Array<String>):String
	{
        var DEF:Int = 4;
        var MAX:Int = 9;
        
		var a = S.split(':');
		if (a.length > 0){
			var ret = "";
			var p1 = a[0].toUpperCase();
			if (M.indexOf(p1)>-1){
				ret = p1 + ':';
				if (a[1] != null) {
					var t = Std.parseInt(a[1]);
					if (t != null){
						if (t < 0) t = 0; else if (t>MAX) t=MAX;
						return ret + t;
					}
				}
				return ret + '$DEF';
			}
		}
		return null;
	}//---------------------------------------------------;

	
	// No arguments to use system OS default
	// : Dev, I might not need this, as most operations are using pipes
	public static function setTempFolder(p:String = null)
	{
		if (p == null) p = js.node.Os.tmpdir();
		TEMP = Path.join(p, 'romutil_temp_3890ff18');	// Random String
		if (!Fs.existsSync(TEMP)) Fs.mkdirSync(TEMP);
	}//---------------------------------------------------;
	
	
	// Process the <COMPRESSION> parameter and return according extension
	public static function getCompressionExt():String
	{
		if (COMPRESSION == null) return DAT.EXT;
		return switch(Engine.COMPRESSION[0]) {
			case "ZIP": '.zip';
			case "7Z":  '.7z';
			default: throw "Invalid Compression String";
		};
	}//---------------------------------------------------;
	
	static function filterBlacklist(f:Array<String>):Array<String>
	{
		var R:Array<String> = [];
		for (i in f) {
			var ext = Path.extname(i);
			if (ext_blacklist.indexOf(ext.toLowerCase()) < 0) {
				R.push(i);
			}
		}
		return R;
	}//---------------------------------------------------;
	
	
}// --