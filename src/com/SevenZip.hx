/****
 * 7ZIP 
 * Interface for the CLI app
 * -------
 * johndimi, johndimi@outlook.com
 * -------
 * @requires: [7za.exe]
 * @supports: nodeJS
 * @platform: windows
 * 
 * @DEVNOTES
 * 	- 7za.exe is the standalone version of 7zip
 *  - Guide: https://sevenzip.osdn.jp/chm/cmdline/index.htm
 * 
 * @NOTES
 * 	- SOLID : (-ms=on),  (-ms=off)
 * 
 * @callbacks
 * 
 * 	- onProgress (progress (0-100))
 *  - onComplete ();
 *  - onFail(Error);
 * 
 * ---------------------------------------*/

/// NOTE : Borrowed from `cdcrush.nodejs`

package com;
import djNode.tools.HTool;
import djNode.tools.LOG;
import djNode.utils.Registry;
import js.Error;
import js.node.ChildProcess;
import js.node.Fs;
import js.node.Path;
import js.node.stream.Readable.IReadable;
import js.node.stream.Writable.IWritable;

@:dce
class SevenZip extends Archiver
{
	
	static var S01 = ">update";	// Inner Helper special string ID to use on update/compress
	
	static var WIN32_EXE:String = "7za.exe"; // Standalone exe version.
	
	// Folder where the exe is in
	public static var PATH:String = "";
	//---------------------------------------------------;
	
	/**
	   Check if 7zip is installed and if so get its path
	**/
	public static function pathFromReg()
	{
		PATH = Registry.getValue("HKEY_CURRENT_USER\\Software\\7-Zip", "Path");
		if (PATH != null) {
			WIN32_EXE = '7z.exe';
			LOG.log("7Zip path read from registry [OK] : " + PATH);
		}
	}//---------------------------------------------------;
	
	public function new()
	{
		super(Path.join(PATH, WIN32_EXE));
		
		app.LOG_STDERR = true;
		
		app.onClose = (s)->{
			
			if (!s) // ERROR
			{
				ERROR = app.ERROR;
				return onFail(ERROR);
			}
			
			if (operation == "compress")
			{
				// Since stdout gives me the compressed size,
				// capture in case I need it later
				// - STDOUT Example :
				// - .......Files read from disk: 1\nArchive size: 544561 bytes (532 KiB)\nEverything is Ok
				var r = ~/Archive size: (\d+)/;
				if (r.match(app.stdErrLog)) /// was STDOUT
				{
					COMPRESSED_SIZE = Std.parseFloat(r.matched(1));
					LOG.log('$ARCHIVE_PATH Compressed size = $COMPRESSED_SIZE');
				}
			}
			onComplete();
		};
		
		// - Progress capture is the same on all operations ::
		// - STDOUT :
		// - 24% 13 + Devil Dice (USA).cue
		var expr = ~/(\d+)%/;		
		app.onStdErr = (data)->{
			if (expr.match(data)) {
				progress = Std.parseInt(expr.matched(1)); // Triggers setter and sends to user
			}	
		};
		
	}//---------------------------------------------------;
	
	
	/**
	   Compress a bunch of files into an archive
	   
	   # DEVNOTES
			- WARNING: If archive exists, it will APPEND files.
			- If a file in files[] does not exist, it will NOT ERROR
			- The files are going to be put in the ROOT of the archive.
			  even if input files are from multiple directories
			  
	   @param	files Files to add
	   @param	archive Final archive filename
	   @param	cs (Compression String) a Valid Compression String for FreeArc. | e.g. "-m4x"
	**/
	override public function compress(files:Array<String>, archive:String, cs:String = null):Bool
	{
		ARCHIVE_PATH = archive;
		operation = "compress";
		progress = 0;
		LOG.log('Compressing "$files" to "$archive" ... Compression:$cs' );
		
		// 7Zip does not have a command to replace the archive
		// so I delete it manually if it exists
		if (cs == S01)
		{
			cs = null;
			operation = "update";
		}else
		{
			if (Fs.existsSync(archive)) {
				Fs.unlinkSync(archive);
			}
		}
		
		var p:Array<String> = [
			'a', 						// Add
			'-bsp2', 					// Redirect PROGRESS outout to STDERR
			'-mmt' 						// Multithreaded
		];
		if (cs != null) p = p.concat(cs.split(' '));
		p.push(archive);
		p = p.concat(files);
		app.start(p);
		return true;
	}//---------------------------------------------------;
	
	
	/**
	   Extract file(s) from an archive. Overwrites output
	   ! NOTE: USES (e) parameter in 7zip. Does not restore folder structure
	   @param	archive To Extract
	   @param	output Path (will be created)
	   @param	files Optional, if set will extract those files only
	**/
	override public function extract(archive:String, output:String, files:Array<String> = null):Bool 
	{
		ARCHIVE_PATH = archive;
		operation = "extract";
		progress = 0;
		var p:Array<String> = [
			'e',			// Extract
			archive,
			'-bsp2',		// Progress in stderr
			'-mmt',			// Multithread
			'-aoa',			// Overwrite
			'-o$output'		// Target folder. DEV: Does not need "" works with spaces just fine
		];
		var _inf = "";
		if (files == null) {
			_inf = 'all files';
		}else {
			_inf = files.join(',');
			p = p.concat(files);
		}
		LOG.log('Extracting [$_inf] from "$archive" to "$output"' );
		app.start(p);
		return true;
	}//---------------------------------------------------;
	
	
	/**
	   Append files in an archive
	   - It uses the SAME compression as the archive
	   - Best use this on NON-SOLID archives (default solid = off in this class)
	   @param	archive
	   @param	files
	   @return
	**/
	override public function append(archive:String, files:Array<String>):Bool 
	{
		compress(files, archive, S01);
		return true;
	}//---------------------------------------------------;
	
	
	
	/**
	   Get a generic compression string
		- Not recommended. Read the 7ZIP docs and produce custom compression 
	     strings for use in encode();
	   @param	level 1 is the lowest, 9 is the highest
	**/
	public static function getCompressionString(l:Int = 4)
	{
		HTool.inRange(l, 1, 9);
		return '-mx${l}';
	}//---------------------------------------------------;
	
	
	
	/// NEW:
	/**
	   
	   @param	a The Archive Path
	   @param	getSize If TRUE will prepend uncompressed filesize on the return array
						["566267|File.txt", "2300|folder\file.dat"]
						Just use split('|') to separate and parseint to get size
	   @return NULL for error, Empty Array for no Files.
	**/
	public function getFileList(a:String, getSize:Bool = false):Array<String>
	{
		//LOG.log('Getting file list from `$a`');
		var stdo:String = try ChildProcess.execSync('"${app.exePath}" l "$a"', {stdio:['ignore', 'pipe', 'ignore']}) catch (e:Error) return null;
		var ar:Array<String> = stdo.toString().split('\n');	// NOTE: toString() is needed, else error
		
		var l = 0;
		while (l < ar.length) {
			if (ar[l++].indexOf('---------') == 0) break; // A line before the file list
			// l is now where the entries start
		}
		// Line example
		// 2019-05-12 01:04:09 ....A         5049               Folder\filename.cfg
		// 2019-05-10 21:16:55 ....A        10423       692492  file.txt
		var files:Array<String> = [];
		
		while (l < ar.length) {
			if (ar[l].indexOf('---------') == 0) break; // Entries End
			// Skip Folders
			if (ar[l].charAt(20) == "D") { l++;  continue; }	
			
			// Trim the first 25 characters to reach the filesize
			var size:Int = Std.parseInt(ar[l].substr(26, 13));
			var name = StringTools.rtrim(ar[l].substr(53));
			if (getSize){
				files.push('$size|$name'); 
			}else{
				files.push(name);
			}
			l++;
		}
		return files;
	}//---------------------------------------------------;
	
	/**
		Get the Hash of a file inside the archive.
	   
	   @param	arc The archive
	   @param	file full path of the file inside the archive e.g. "folder/file.dat"
	   @param	type (CRC32|CRC64|SHA1|SHA256)
	   @return  Hash, Warning make sure the file exists in the archive, else random string will be returned
	**/
	public function getHash(arc:String, file:String, type:String = "CRC32"):String
	{
		var stdo:String = ChildProcess.execSync('"${app.exePath}" e "$arc" "$file" -so | "${app.exePath}" h -si -scrc${type}');
		
		// DEV Note:
		// + This way ^ works OK.
		// + If I do this this way, it will buffer overflow in large files.
			// var stdo:String = ChildProcess.execSync('"${app.exePath}" h -si -scrc${type}', {
			// input:ChildProcess.execSync('"${app.exePath}" e "$arc" "$file" -so') });
		// + I could do it ASYNC, but this way is just more convenient
		
		return hashParse(stdo.toString());	// Note: To String is needed, else it errors.
	}//---------------------------------------------------;
	
	
	/**
	   Get a file Hash
	   @param	file The path of the file to get the hash
	   @param	type (CRC32|CRC64|SHA1|SHA256)
	   @return
	**/
	public function getFileHash(file:String, type:String = "CRC32"):String
	{
		var stdo:String = ChildProcess.execSync('"${app.exePath}" h "$file" -scrc${type}');
		return hashParse(stdo.toString());
	}//---------------------------------------------------;
	
	
	// From a (h) call, get the HASH value
	function hashParse(stdout:String):String
	{
		var ar:Array<String> = stdout.split('\n');
		var l = 0;
		while (l < ar.length) {
			if (ar[l++].indexOf('--------') == 0) break; // A line before the file list
			// l is now where the entries start
		}
		var r = ~/^(\S+)/i;
		if (r.match(ar[l])) {
			return r.matched(1);
		}
		return null;
	}//---------------------------------------------------;
	
	
	/**
	   Extract to STDOUT Stream.
	   @param	arc Archive to Extract
	   @param	files If set, will extract these files from within the archive
	**/
	public function extractToPipe(arc:String, files:Array<String> = null):IReadable
	{
		app.LOG_STDOUT = false;
		var p:Array<String> = [
			'e', '-mmt', arc
		];
		var _inf = "";
		if (files == null) {
			_inf = 'all files';
		}else {
			_inf = files.join(',');
			p = p.concat(files);
		}
		LOG.log('Extracting [$_inf] from "$arc" to PIPE');
		p.push('-so');
		app.start(p);
		return app.proc.stdout;
	}//---------------------------------------------------;
	
	/**
	   Compresses from STDIN stream.
	   Updates Archive, It will APPEND files, so be careful
	   @param	arc Archive Path to create
	   @param	fname name of the file to be created inside the archive
	   @param	cs Valid Compression String
	   @return
	**/
	public function compressFromPipe(arc:String, fname:String, cs:String = null):IWritable
	{
		app.LOG_STDOUT = false;
		var p:Array<String> = [
			'a', arc, '-mmt'
		];
		if (cs != null) p = p.concat(cs.split(' '));
		p.push('-si${fname}');
		LOG.log('Compressing from PIPE to "$arc" ... Compression:$cs' );
		app.start(p);
		return app.proc.stdin;
	}//---------------------------------------------------;
	
}// --