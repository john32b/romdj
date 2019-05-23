package;
import com.DatFile;
import com.SevenZip;
import com.Worker;
import djNode.BaseApp;
import djNode.task.CJob;
import djNode.task.CTask;
import djNode.task.CTestTask;
import djNode.tools.FileTool;
import djNode.tools.LOG;
import djNode.utils.Print2;
import haxe.Timer;
import js.Error;
import js.node.Fs;
import js.node.Path;


enum EngineAction {
	BUILD;
	VERIFY;
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
	
	// TRUE: Condense/Prioritize the Countries. Uses vars in (COUNTRY_AR)
	public static var FLAG_FIX_COUNTRY:Bool;
	
	// TRUE: Remove Language Strings when Building
	public static var FLAG_REMOVE_LANG:Bool;

	// TRUE: Will delete source files only after they have been built to Target Folder
	public static var FLAG_DEL_SOURCE:Bool;	
	
	// TRUE: Will overwrite files on the Target Folder
	public static var FLAG_OVERWRITE:Bool = false;
	
	// TRUE: Will produce log at target dir
	public static var FLAG_LOG:Bool;
	
	//====================================================;
	
	
	// Log file path, if -log is set
	static var log_file:String;
	
	static var info_scanExt = '';
	
	// Dat object
	static var DAT:DatFile = null;
	
	// The rom files on the source folder
	static var files:Array<String>;
	
	// Current operation statistics
	static var filesTotal:Int;
	static var filesMatched:Int;
	static var filesUnmatched:Array<String> = null;
	
	// Custom Priority Countries Array | Default [EUROPE,USA]
	// Set with pset_country_fix()
	static var COUNTRY_AR:Array<String> = null;
	
	// Compiled Compression Array
	static var COMPRESSION:Array<String> = null;
	// Helper
	static var isInited:Bool = false;
	
	// For every game that was verified/built, keep its CRC
	static var prCRC:Map<String,Bool>;
	
	// List of DUPLICATE ROMS, ( just info text , not proper filenames )
	static var arDups:Array<String>;
	
	// List of roms that were BUILT/CREATED in target (src filenames)
	static var arDone:Array<String>;
	
	// List of roms that had error when reading (archives mostly)
	static var arFailRead:Array<String>;
	
	// Terminal Printer
	public static var P:Print2;
	
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
			if (P_SOURCE == null) throw "You need to set a `source` directory";
			if (P_TARGET == null) throw "You need to set a `target` directory";
			
		}else
		{
			// it is VERIFY I don't have to check
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
	public static function P_SET(delSrc:Bool, noLang:Bool, log:Bool, country:String, compression:String)
	{
		FLAG_DEL_SOURCE = delSrc;
		FLAG_REMOVE_LANG = noLang;
		
		if ((FLAG_LOG = log) == true)
		{
			var dd = '_RomUtil Log ' + DateTools.format(Date.now(), "%Y-%m-%d (%H'%M'%S)") + '.txt';
			
			if (P_ACTION == BUILD)
			{
				log_file = Path.join(P_TARGET, dd);
			}else{
				log_file = Path.join(P_SOURCE, dd);	
			}
			
			LOG.setLogFile(log_file);
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
	   starts an action (BUILD,VERIFY)
	**/
	public static function start()
	{
		// Extensions to search for Files
		var exts = ARCHIVE_EXT.copy(); exts.push(DAT.EXT);
		files = FileTool.getFileListFromDirR(P_SOURCE, exts);
		info_scanExt = exts.join(' ');
		
		// Init statistics info
		filesMatched = 0;
		filesTotal = files.length;
		filesUnmatched = [];
		prCRC = [];
		arDups = [];
		arDone = [];
		arFailRead = [];
		
		// Print infos
		print_pre();
		
		// --
		var j = new CJob("Process Roms : " + P_ACTION);
		
		j.MAX_CONCURRENT = 1; // Currently just one.
		j.FLAG_LOG_TASKS = false;
		
		var c = 0;// Counter
		
			j.addTaskGen(()->{
				#if debug
				//if (c == 15) return null;
				#end
				var f = files.pop();
				if (f == null) return null;
				return new CTask(Path.basename(f), (t)->{
					var w = new Worker(f,++c);
						t.syncWith(w);
						w.start();
				});
			});
			
		j.onComplete = ()->{	
			print_post();
			if (j.ERROR == null)
			{
				// SUCCESS
				print('|4|:: Operation Complete |',true);
			}else{
				// ERROR
				print('|4|:: Operation FAILED|', true);
				print('|4|${j.ERROR}',true);
			}
			return; // needed for some reason, else wont compile
		};
		
		j.start();
		
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
		print(' ==', true);
		if (P_ACTION == BUILD) {
			print(' == |5|[ BUILDING ]|', true);
		}else{
			print(' == |5|[ VERIFYING ]|', true);
		}
		print(' ==', true);
		
		if (DAT != null)
			print(' Dat File : |2|${DAT.fileLoaded}|', true);
		
		if (P_TARGET != null)
			print(' Destination : |2|$P_TARGET|', true);
		
		if (P_SOURCE != null)
			print(' Source : |2|$P_SOURCE|', true);
			
		if (P_COMPRESSION != null)
			print(' Compression : |1|$P_COMPRESSION|', true);
		
		var fl = "";
		if (FLAG_DEL_SOURCE) fl += "|1|Delete Source| | ";
		if (FLAG_LOG) fl += "|1|Log| | ";
		if (FLAG_REMOVE_LANG) fl += "|1|Remove Languages| | ";
		if (FLAG_FIX_COUNTRY) fl += "|1|Country Priority| : |4|" + COUNTRY_AR.toString() + "| | ";
		
		if (fl.length > 0)
		{
			fl = fl.substr(0, -3);
			print(' Flags : $fl', true);
		}
		
		print(' Scanning Extensions : [|1| $info_scanExt |]', true);
		
		print(StringTools.lpad("", '-', LINE), true);
	}//---------------------------------------------------;
	
	
	
	/**
	   Print info after all files processed
	**/
	static function print_post()
	{
		print(StringTools.lpad("", '-', LINE), true);
		print('Dat File Total Entries : |4|${DAT.count}|', true);
		print('Files found in Input Dir : |1|${filesTotal}|', true);
		print('Files matched to an entry : |2|${filesMatched}|', true);	/// DELETE?
		
		var v = switch(P_ACTION) {
			case BUILD:  "Built into Target";
			case VERIFY: "Verified";
			default:"";
		};
		
		print('$v : |4|${arDone.length}| unique files');
		
		if (arDups.length > 0)
		{
			print('Duplicates : |3|${arDups.length}|', true);
			for (i in arDups) {
				LOG.log('  $i');
			}
		}
		
		if (filesUnmatched.length > 0)
		{
			print('Files with No Match : |3|${filesUnmatched.length}|',true);
			for (f in filesUnmatched) {
				LOG.log('  $f');
			}		
		}
		
		if (arFailRead.length > 0)
		{
			print('Files that failed to read : |3|${arFailRead.length}|', true);
			for (f in arFailRead) {
				LOG.log('  $f');
			}		
		}
		
		if (FLAG_LOG)
		{
			print('Created logfile with more info: |4|$log_file|');
		}
		
		print(StringTools.lpad("", '-', LINE), true);
	}//---------------------------------------------------;
		
	
	
	/**
	   Print something to the Terminal using Print2() method
	   styles are predefined in init();
	   @param	str  |n|string| format
	   @param	log If true will also log to the global LOG 
	**/
	public static function print(str:String, log:Bool = false)
	{
		var s = P.print2(str);
		if (log) {
			LOG.log(s);
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
		var r = new EReg('\\(.*($strb).*?\\)', 'i');
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
	
}// --