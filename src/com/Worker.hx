package com;
import djNode.tools.FileTool;
import djNode.utils.ISendingProgress;
import com.DatFile.DatEntry;
import js.Error;
import js.node.Fs;
import js.node.ChildProcess;
import js.node.Path;

// Helper
import Engine.print as print;
import djNode.tools.LOG.log as log;
import Engine.EngineAction;

/**
 * Checks One ROM
 * - Runs from inside a Task
 */
class Worker implements ISendingProgress
{
  	public var onComplete:Void->Void;
	public var onProgress:Int->Void;
	public var onFail:String->Void;
	public var ERROR(default, null):String;
	
	var padL0 = " >> ";
	var padL1 = "  . ";
	
	var shortname:String; // Short SRC Name
	var src:String;	// Original file to be processed, could be archive or raw
	var isArc:Bool; // Is source file an Archive
	
	// IF src is archive, hold all the files inside the ARC
	var subFiles:Array<String>;
	
	// Either total roms from inside an ARC or 1 for RAW
	// Useful to know for when deciding to delete source
	var romsTotal:Int;
	var romsMatched:Int;
	
	var entryAction:(DatEntry, ?String)->Void;
	
	var no:Int;
	
	public function new(Source:String,No:Int) 
	{
		src = Source;
		no = No;
		isArc = Engine.fileIsArchive(src);
		entryAction = 
		if (Engine.P_ACTION == EngineAction.BUILD)
		{
			entryAction = action_build;
		}else
		{
			entryAction = action_verify;
		}
	}//---------------------------------------------------;
	
	/**
	   Operations are SYNC
	   - Searches for valid roms (raw and inside archives)
	   - Calls action function on every entry found
	**/
	public function start()
	{
		var S = new SevenZip();
		
		// Count roms processed and found in the DAT
		romsMatched = 0;
		
		shortname = Path.basename(src);
		print('${padL0} |1|($no/${Engine.filesTotal})| Processing : |1|${shortname}|', true);
		
		if (isArc)
		{
			subFiles = S.getFileList(src);
			if (subFiles == null)
			{
				Engine.arFailRead.push(src);
				print('|3|[READ FAIL]| , skipping', true);
				return onComplete();
			}
			
			romsTotal = subFiles.length;
			log('${padL1}Archive contains ($romsTotal) files.');
			
			for (f in subFiles)
			{
				var entry = Engine.DAT.DB.get(S.getHash(src, f));
				if (entry != null) {					
					romsMatched++;
					entryAction(entry, f);
				}
			}
			
			if (romsMatched == 0){
				action_unmatched(src);
			}else{
				Engine.filesMatched++;
			}

		}else // RAW file
		{
			romsTotal = 1;
			var entry = Engine.DAT.DB.get(S.getFileHash(src));
			if (entry != null) {
				romsMatched++;
				Engine.filesMatched ++;
				entryAction(entry, null);
			}else{
				action_unmatched(src);
			}
		}
			
		if (Engine.FLAG_DEL_SOURCE && (romsMatched == romsTotal))
		{
			log('${padL1}Deleting "$src"');
			try Fs.unlinkSync(src) catch (e:Error) {
				print('${padL1}|3|Cannot Delete :| $src', true);
			}
		}
			
		onComplete();
	}//---------------------------------------------------;
	

	/**
	   Process [raw file] or [file inside archive]
	   for BUILD operation
	**/
	function action_build(e:DatEntry, ?arcPath:String)
	{
		// Create new name based on filters (if any)
		var fixname = e.name;
		if(Engine.FLAG_FIX_COUNTRY)
			fixname = Engine.str_prioritizeCountry(fixname, Engine.COUNTRY_AR);
		if (Engine.FLAG_REMOVE_LANG){
			fixname = Engine.str_noLanguage(fixname);
		}
		// Just in case, remove trailing spaces
		fixname = StringTools.rtrim(fixname);
		
		var romFilename = fixname + Engine.DAT.EXT;
		var targetFile = '${Engine.P_TARGET}/${fixname}'; // NO EXT YET
		
		print_match(e, arcPath);
	
		if (checkDup(e, arcPath)) return;
		
		// - Get target file and check if it exists
		if (Engine.COMPRESSION == null)
		{
			targetFile +=  Engine.DAT.EXT;
		}else
		{
			targetFile += switch(Engine.COMPRESSION[0]) {
				case "ZIP": '.zip';
				case "7Z":  '.7z';
				default: "";
			};
		}
		// -
		if (Fs.existsSync(targetFile) && !Engine.FLAG_OVERWRITE) {
			print('${padL1}|5|Skipping|. Already exists on Target Folder', true);
			return;
		}
		
		
		if (Engine.COMPRESSION == null)
		{
			if (arcPath == null)
			{
				// <From Raw File>
				FileTool.copyFile(src, targetFile);
			} else 
			{
				// <From inside an archive>
				ChildProcess.execSync('"${Engine.PATH_7Z}" e "$src" "$arcPath" -so > "$targetFile"');
			}
		}
		else
		{
			var CSTR = '"${Engine.PATH_7Z}" a "$targetFile" -si"${romFilename}" -mx${Engine.COMPRESSION[1]} -aoa';
			
			if (arcPath == null) {
				// <From Raw File>
				ChildProcess.execSync('$CSTR < "$src"');
					
			}else{	
				// <From inside an archive>
				ChildProcess.execSync('"${Engine.PATH_7Z}" e "$src" "$arcPath" -so | $CSTR');
			}
		}
		
		Engine.arDone.push(targetFile);
		
		print('${padL1}|5|Created| : |1|$targetFile|', true);
		
	}//---------------------------------------------------;
	
	
	

		
	
	/**
	   Process [raw file] or [file inside archive]
	   for VERIFY operation
	**/
	function action_verify(e:DatEntry, ?arcPath:String)
	{
		print_match(e, arcPath);
		
		if (checkDup(e, arcPath)) return;
		
		Engine.arDone.push(e.name);
	}//---------------------------------------------------;
	
	
	
	function print_match(e:DatEntry, ?ap:String)
	{
		if (ap != null) {
			print('${padL1} (archive) (${romsMatched}/$romsTotal) |2|[MATCH]| = |4|${e.name}|', true);
		}else {
			print('${padL1}|2|[MATCH]| = |4|${e.name}|', true);
		}
	}//---------------------------------------------------;
	
	/**
	   A file was not found
	   - Raw file was not matched
	   - If Archive, no inner files were matched
	   @param	src
	**/
	function action_unmatched(src:String)
	{
		Engine.filesUnmatched.push(src);
		print('${padL1}|3|[NO MATCH]|', true);
	}//---------------------------------------------------;
	
	
	
	function checkDup(e:DatEntry, ?arcPath:String):Bool
	{
		if (Engine.prCRC.exists(e.crc))
		{
			print('${padL1}|5|Duplicate Entry| skipping.', true);
			if(arcPath==null){
				Engine.arDups.push(shortname);
			}else{
				Engine.arDups.push('$shortname >> $arcPath');
			}
			return true;
		}else{
			Engine.prCRC.set(e.crc, true);
			return false;
		}
	}//---------------------------------------------------;

	
}// --