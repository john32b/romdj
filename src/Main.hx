package;

import com.SevenZip;
import djNode.BaseApp;
import djNode.task.CJob;
import djNode.tools.LOG;
import js.node.Fs;

class Main extends BaseApp
{
	static function main()  { new Main(); }
	
	override function init():Void 
	{
		LOG.FLAG_SHOW_MESSAGE_TYPE = false;
		LOG.FLAG_SHOW_POS = false;
		CJob.FLAG_LOG_TASKS = false;
		
		#if debug
			LOG.setLogFile("a:\\log_romdj.txt");
		#end 
		
		// Initialize Program Information here.
		PROGRAM_INFO = {
			executable:'romdj',
			name:"romdj - Emulation Romset Builder",
			info:"https://github.com/johndimi/romdj",
			version :Engine.VERSION
		};
		
		ARGS.requireAction = true;
		
		ARGS.inputRule = "yes";
		ARGS.outputRule = "opt";
		ARGS.helpInput = "A valid NO-INTRO (.dat) file.";
		ARGS.helpOutput = "Target directory to build roms ~darkgray~(<build> action)~!~";
		
		ARGS.Actions = [
			// DEVNOTE: ActionNames should match enum <Engine.EngineAction> (case insensitive)
			['build', 'Build RomSet to Output Folder', 'Scan a directory, check against DAT file and create rom files (raw or zipped)'],
			['scan', 'Scans a directory ', 'Will check a folder against a DAT file and report information']
		];
		
		ARGS.Options = [
			['i', 'Input Source Folder', 'A path with Rom files (Supported: 7z zip raw)','yes'],
			['c', 'If set will apply Compression to the roms when Building', 'Type = [ZIP,7Z], Compression Level = [0...9]\ne.g. "ZIP:9", "7z:4", "ZIP"', 'yes'],
			['delsrc','Delete Source Files after Building', 'In case of archives with multiple files, will delete it when all included files were built'],
			['nolang', 'Remove Language Strings from Filenames', 'e.g. (En,Fr,Es,De), etc will be removed from the rom names'],
			['regkeep', 'Prioritize Country Codes in Filenames', 'Removes unwanted redundant countries from the Filenames.\nCSV values, = for defaults (USA,EUROPE) e.g. -regkeep BRAZIL,USA\nCheck the readme for more details on how this works', 'yes'],
			['regdel', 'Remove these country codes from the filenames','CSV values, = for defaults (USA,EUROPE) e.g. -regdel USA\nCheck the readme for more details on how this works', 'yes'],
			
			['report', 'Produce detailed Report. on Build the file will be created on <target>', 'On <scan> the file will be created on <source>'],
			
			['header', 'Skip this many bytes from the beginning of the files when checking checksums', 'Useful in some romsets, like the NES which has a 16 byte header', 'yes'],
			['nods'  , 'No Deep Scan','Don\'t scan subfolders in the input folder'],
			['p', 'Set number of parallel tasks (default 2)', '', 'yes']
		];
		
		ARGS.helpText = 'e.g.\n romdj build c:\\dats\\sega_sms.dat -i c:\\roms\\sms_unfixed -o c:\\roms\\sms_fixed -delsrc -regkeep = -nolang -report -c 7Z:9\n' +
						' - Will build a romset from <c:\\roms\\sms_unfixed> to <c:\\roms\\sms_fixed>, Use 7Z Maximum compression (7Z:9) \n' +
						'   remove language strings (-nolang), prioritize country codes (EUROPE,USA) in filenames (-country =)\n' +
						'   Delete original files (-delsrc) and generate a report.txt file in <c:\\roms\\sms_fixed> (-report)';
		super.init();
	}//---------------------------------------------------;
	
	// This is the user code entry point :
	// --
	override function onStart() 
	{
		printBanner();
		
		try 
		{
			// Init engine with input,output, datfile
			Engine.init(argsAction, argsInput[0], argsOptions.i, argsOutput);
			
			// Set optional parameters
			Engine.P_SET(
				argsOptions.delsrc,
				argsOptions.nolang,
				argsOptions.report,
				argsOptions.regkeep,
				argsOptions.regdel,
				argsOptions.c,
				argsOptions.nods
			);
			
			if (argsOptions.p != null)
			{
				Engine.P_PARALLEL = Std.parseInt(argsOptions.p);
			}
			
			if (argsOptions.header != null)
			{
				Engine.P_HEADER_SKIP = Std.parseInt(argsOptions.header);
			}
			
		}
		catch (e:String) exitError(e);
		
		Engine.start();
	}//---------------------------------------------------;
	
}// --