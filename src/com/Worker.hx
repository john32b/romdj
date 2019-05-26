package com;
import djNode.tools.ArrayExecSync;
import djNode.tools.FileTool;
import djNode.utils.ISendingProgress;
import com.DatFile.DatEntry;
import js.Error;
import js.node.Fs;
import js.node.ChildProcess;
import js.node.Path;
import js.node.stream.Readable;

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
	
	var shortname:String; 				// Short SRC Name, no path (e.g. "Batman (e).rom" ) Used in Reports
	var src:String;						// Original file to be processed, could be archive or raw
	var subFiles:Array<String> = null;	// If <archive>, hold all the files inside the ARC
	
	var romsTotal:Int;					// How many roms SRC contains
	var romsMatched:Int;				// How many of those roms were matched to the DAT
	
	var no:Int;							// # of src item in list
	
	var action_match:(DatEntry, ?String, Void->Void)->Void;
	
	public static var COUNTER:Int = 0;
	
	// --
	public function new(Source:String) 
	{
		COUNTER++;
		
		src = Source; no = COUNTER;
		
		if (Engine.P_ACTION == EngineAction.BUILD) {
			action_match = action_build;
		}else{
			action_match = action_scan;
		}
		
		romsMatched = 0;
		//shortname = Path.basename(src);
		shortname = Path.relative(Engine.P_SOURCE, src);
	}//---------------------------------------------------;
	
	
	/**
	   Operations are SYNC
	   - Searches for valid roms (raw and inside archives)
	   - Calls action function on every entry found
	**/
	public function start()
	{
		log('${padL0} ($no/${Engine.info_total_files}) , Processing : "${shortname}"');
		
		// Operation Complete : Called when all files are processed
		var opComplete = ()->
		{
			// No roms were matched from a zip or raw
			if (romsMatched == 0) {
				Engine.arUnmatch.push(src);
				return onComplete();
			}
			
			// 'source file' processed OK
			if (Engine.FLAG_DEL_SOURCE && (romsMatched == romsTotal)){
				log('${padL1}Deleting "$src"');
				try Fs.unlinkSync(src) catch (e:Error) {
					Engine.arCannotDelete.push(src);
					log('${padL1}ERROR : Cannot Delete : "$src"');
				}
			}
			onComplete();
		};
		

		// --
		// When working with zip files, store the current path of inner files, I need it
		var last_subFile:String;
		// getStream() is a generator and everytime it is called it returns
		// the next file to process in a stream
		var getStream:Void->IReadable;
		if (Engine.fileIsArchive(src))
		{
			var S = new SevenZip();
				S.onFail = onFail;
				
			subFiles = S.getFileList(src);
			// The Archive is corrupted / Could not Read it
			if (subFiles == null) { 
				Engine.arFailRead.push(src);
				log('${padL1} [READ FAIL], skipping');
				return onComplete();
			}
			romsTotal = subFiles.length;
			getStream = ()-> {
				var f = subFiles.pop();
				last_subFile = f;
				if (f == null) return null;
				return S.extractToPipe(src, f);
			};
		}else{
			romsTotal = 1;
			var _c = false;
			getStream = ()->{
				if (_c) return null;
				_c = true;
				return Fs.createReadStream(src);
			};
		}
		
		// --
		// Process the next file by reading the generator, and getting an entry
		var doNext:Void->Void;
		doNext = ()-> 
		{
			var rs = getStream();
			if (rs == null) return opComplete(); // No more files to process
			var S = new SevenZip();
				S.onFail = onFail;
			// Dev: I don't care where or how, as long as it is a stream I need to process it
			var ws = S.getHashPipe("CRC32", (hash)->{
				var entry = Engine.DAT.DB.get(hash);
				if (entry != null) {					
					romsMatched++;
					action_match(entry, last_subFile, doNext);
				}else{
					log('${padL1} [NO MATCH]');
					doNext();
				}
			});
			rs.pipe(ws);
			return;
		}
		
		doNext();
	}//---------------------------------------------------;
	
	
	
	
	
	/**
	   Process [raw file] or [file inside archive] for BUILD operation
	   - If a file cannot be created, then the whole JOB will FAIL
	   
	**/
	function action_build(e:DatEntry, ?arcPath:String, end:Void->Void)
	{
		log_match(e, arcPath);
		
		if (checkDup(e, arcPath)) {
			return end();
		}
		
		var name_fixed = Engine.apply_NameFilters(e.name);
		var romFilename = name_fixed + Engine.DAT.EXT;
		var targetFile = '${Engine.P_TARGET}/${name_fixed}'; // NO EXT YET
		
		var endOK = function(){
			Engine.arProc.push(e.name);
			end();
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
		targetFile += Engine.getCompressionExt();
		
		if (Fs.existsSync(targetFile) && !Engine.FLAG_OVERWRITE) {
			log('${padL1}Skipping. Already exists on Target Folder');
			return end();
			// TODO : ?
			// FUTURE: check for file size or crc?
		}
		
		log('Creating "$targetFile"');
					
		var S = new SevenZip();
			S.onFail = fail;
			
		if (Engine.COMPRESSION == null)
		{
			if (arcPath == null) {
				// <From Raw File>
				FileTool.copyFile(src, targetFile, (err)->{
					if(err!=null)
						fail('Could not copy "$src" --> "$targetFile');
					else
						endOK();
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
					endOK();
				});
				
				pipeout.pipe(ws);
			}
		}
		else
		{
			var ws = S.compressFromPipe(targetFile, romFilename, '-mx${Engine.COMPRESSION[1]}');
			S.onComplete = endOK;
				
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
	   Process [raw file] or [file inside archive] for SCAN operation
	   DEV: Scan cannot fail
	**/
	function action_scan(e:DatEntry, ?arcPath:String, end:Void->Void)
	{
		log_match(e, arcPath);
		
		if (checkDup(e, arcPath)) {
			return end();
		}
		
		if(arcPath==null){
			Engine.arProc.push('${e.name}\t >>>>> \t"$shortname"');
		}else{
			Engine.arProc.push('${e.name}\t >>>>> \t"$shortname" > `$arcPath`');
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
				Engine.arDups.push('${e.name}\t >>>>> \t"$shortname"');
			}else{
				Engine.arDups.push('${e.name}\t >>>>> \t"$shortname" > `$arcPath`');
			}
			return true;
		}else{
			Engine.prCRC.set(e.crc, true);
			return false;
		}
	}//---------------------------------------------------;

	
	
}// --