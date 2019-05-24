package com;
import djNode.tools.ArrayExecSync;
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
	
	var padL0 = " >> ";			// Logging helpers
	var padL1 = "  . ";			// --
	
	var shortname:String; 				// Short SRC Name, no path (e.g. "Batman (e).rom" )
	var src:String;						// Original file to be processed, could be archive or raw
	var subFiles:Array<String> = null;	// If <archive>, hold all the files inside the ARC
	
	var romsTotal:Int;					// How many roms SRC contains
	var romsMatched:Int;				// How many of those roms were matched to the DAT
	
	var no:Int;							// # of src item in list
	var S:SevenZip;						// General purpose 7zip obj
	
	var action_match:(DatEntry, ?String, Void->Void)->Void;

	// ----
	
	public function new(Source:String,No:Int) 
	{
		src = Source; no = No;
		
		if (Engine.P_ACTION == EngineAction.BUILD) {
			action_match = action_build;
		}else{
			action_match = action_verify;
		}
		
		S = new SevenZip();
		romsMatched = 0;
		shortname = Path.basename(src);
	}//---------------------------------------------------;
	
	
	/**
	   Operations are SYNC
	   - Searches for valid roms (raw and inside archives)
	   - Calls action function on every entry found
	**/
	public function start()
	{
		log('${padL0} ($no/${Engine.arFiles.length}) , Processing : "${shortname}"');
		
		// Operation Complete : Called when all files are processed
		var opComplete = ()->{
			
			if (romsMatched == 0) 
			{
				Engine.arUnmatch.push(src);
				return onComplete();
			}
			
			// 'source file' processed OK
			if (Engine.FLAG_DEL_SOURCE && (romsMatched == romsTotal))
			{
				log('${padL1}Deleting "$src"');
				try Fs.unlinkSync(src) catch (e:Error) {
					log('${padL1}ERROR : Cannot Delete : "$src"');
				}
			}
			
			onComplete();
		};
		
		if (Engine.fileIsArchive(src))
		{
			subFiles = S.getFileList(src);
			// The Archive is corrupted / Could not Read it
			if (subFiles == null) { 
				Engine.arFailRead.push(src);
				log('${padL1} [READ FAIL], skipping');
				return onComplete();
			}
	
			romsTotal = subFiles.length;
			
			var AX = new ArrayExecSync(subFiles);
			AX.queue_complete = opComplete;
			AX.queue_action = (f)->{
				var entry = Engine.DAT.DB.get(S.getHash(src, f));
				if (entry != null) {					
					romsMatched++;
					action_match(entry, f, AX.next);
				}else{
					log('${padL1} [NO MATCH]');
					AX.next();
				}
			};
			AX.start();
		}else // RAW file -->
		{
			romsTotal = 1;
			var entry = Engine.DAT.DB.get(S.getFileHash(src));
			if (entry != null) {
				romsMatched++;
				action_match(entry, null, opComplete); // There is no queue, so just call the complete function
			}else{
				log('${padL1} [NO MATCH]');
				opComplete();
			}
		}
	}//---------------------------------------------------;
	
	
	
	
	
	/**
	   Process [raw file] or [file inside archive] for BUILD operation
	   - If a file cannot be created, then the whole JOB will FAIL
	   
	**/
	function action_build(e:DatEntry, ?arcPath:String, _end:Void->Void)
	{
		log_match(e, arcPath);
		
		if (checkDup(e, arcPath)) {
			return _end();
		}
		
		var name_fixed = Engine.apply_NameFilters(e.name);
		var romFilename = name_fixed + Engine.DAT.EXT;
		var targetFile = '${Engine.P_TARGET}/${name_fixed}'; // NO EXT YET
		
		var end = function(){
			Engine.arBuilt.push(targetFile);
			_end();
		};
		
		var fail = function(e:String) {
			log('CRITICAL ERROR : $e');
			try{
				// I am deleting the target file as it may be incomplete
				Fs.unlinkSync(targetFile);
				log('Deleted $targetFile');
			}catch (e:Error){ }
			onFail(e);
		};
		
		
		// - Get target file and check if it exists
		if (Engine.COMPRESSION == null) {
			targetFile += Engine.DAT.EXT;
		}else {
			targetFile += switch(Engine.COMPRESSION[0]) {
				case "ZIP": '.zip';
				case "7Z":  '.7z';
				default: "";
			}
		}
		
		// -
		if (Fs.existsSync(targetFile) && !Engine.FLAG_OVERWRITE) {
			log('${padL1}Skipping. Already exists on Target Folder');
			return end();
			// FUTURE: check for file size or crc?
		}
		
		log('Creating "$targetFile"');
					
		if (Engine.COMPRESSION == null)
		{
			if (arcPath == null) {
				// <From Raw File>
				FileTool.copyFile(src, targetFile, (err)->{
					if(err!=null)
						fail('Could not copy "$src" --> "$targetFile');
					else
						end();
				});
				
			} else {
				// <From inside an archive>
				var pipeout = S.extractToPipe(src, arcPath);
				var ws = Fs.createWriteStream(targetFile);
				ws.once('error', (e:Error)->{
					ws.removeAllListeners();
					pipeout.unpipe();
					fail('Cannot create "$targetFile"');
				});
				ws.once('close', ()->{
					ws.removeAllListeners();
					end();
				});
				
				pipeout.pipe(ws);
			}
		}
		else
		{
			var ws = S.compressFromPipe(targetFile, romFilename, '-mx${Engine.COMPRESSION[1]}');
				S.onComplete = end;
				S.onFail = fail;
					
			if (arcPath == null) {
				// <From Raw File>
				var rs = Fs.createReadStream(src);
				rs.pipe(ws);
				
			}else{	
				// <From inside an archive>
				var S2 = new SevenZip();
				var rs = S2.extractToPipe(src, arcPath);
				rs.pipe(ws);
			}
		}
		
	}//---------------------------------------------------;
	
	

	/**
	   Process [raw file] or [file inside archive] for VERIFY operation
	   DEV: Verify cannot fail
	**/
	function action_verify(e:DatEntry, ?arcPath:String, end:Void->Void)
	{
		log_match(e, arcPath);
		
		if (checkDup(e, arcPath)) {
			return end();
		}
		
		end();
	}//---------------------------------------------------;
	
	
	
	function log_match(e:DatEntry, ?ap:String)
	{
		if (ap != null) {
			log('${padL1} (archive) (${romsMatched}/$romsTotal) [MATCH] = ${e.name}');
		}else {
			log('${padL1} [MATCH] = ${e.name}');
		}
	}//---------------------------------------------------;
	
	
	
	/**
	   Check if file was already processed in current run
	   @param	e
	   @param	arcPath
	   @return
	**/
	function checkDup(e:DatEntry, ?arcPath:String):Bool
	{
		if (Engine.prCRC.exists(e.crc))
		{
			log('${padL1}Duplicate Entry "${e.name}" skipping.');
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