package;

import com.SevenZip;
import djNode.BaseApp;
import djNode.tools.LOG;
import js.node.Fs;

class Main extends BaseApp
{
	static function main()  { new Main(); }
	
	override function init():Void 
	{
		#if (!debug)
			LOG.FLAG_SHOW_MESSAGE_TYPE = false;
			LOG.FLAG_SHOW_POS = false;
			// Log file will be set later when it is set in the parameters
		#else
			LOG.setLogFile("a:\\log_romtool.txt");
		#end 
		
		// Initialize Program Information here.
		PROGRAM_INFO = {
			name:"RomUtil",
			version:"0.1",
			info:"Emulation Rom Utilities"
		};
		
		ARGS.requireAction = true;
		
		ARGS.inputRule = "yes";
		ARGS.outputRule = "opt";
		ARGS.helpInput = "A valid DAT-O-MATIC (.dat) file.";
		ARGS.helpOutput = "Target directory to build roms ~darkgray~(<build> action)~!~";
		
		ARGS.Actions = [
			// DEVNOTE: ActionNames should match enum <Engine.EngineAction> (case insensitive)
			['build', 'Build RomSet to Output Folder', 'Scan a directory, check against DAT file and create rom files (raw or zipped)'],
			['verify', 'Verifies a romset', 'Will check a folder against a DAT file and report information']
		];
		
		ARGS.Options = [
			['i', 'Input Source Folder', 'A path with Rom files (Supported: `7z,zip` or Raw)','yes'],
			['c', 'If set will apply Compression to the roms when Building', 'Type = [ZIP,7Z], Compression Level = [0...9]\ne.g. "ZIP:9", "7z:4", "ZIP"', 'yes'],
			['delsrc','Delete Source Files after Building', 'For each source file (Archive/Raw) processed, if it was matched, delete it'],
			['nolang', 'Remove Language Strings from Names', 'e.g. (En,Fr,Es,De) ,etc will be removed from the rom names'],
			['country', 'Prioritize Country Codes (CSV)', '= for Defaults (USA,EUROPE)', 'yes'],
			['log', 'Produce detailed Log on Source or Target dir'],
			['p','Set number of parallel tasks (default 2)','','yes']
			
		];
		
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
				argsOptions.log,
				argsOptions.country,
				argsOptions.c
			);
			
			if (argsOptions.p != null)
			{
				Engine.P_PARALLEL = Std.parseInt(argsOptions.p);
			}
			
		}
		catch (e:String) exitError(e);
		
		Engine.start();
	}//---------------------------------------------------;
	
	
}// --