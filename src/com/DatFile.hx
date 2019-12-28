package com;
import js.lib.Error;
import js.node.Fs;
import haxe.xml.Access;
import js.node.Path;
import djNode.tools.LOG;


typedef DatEntry = {
	name:String,
	description:String,
	roms:Array<DatRom>
}

typedef DatRom = {
	filename:String,	// name XML
	md5:String,
	crc:String,
	size:Int,
	status:String
}


/**
 * Represents a DAT-O-MATIC Dat File
 * 
 *  - Get DATS from `https://datomatic.no-intro.org`
 * 	- Loads a DAT file and creates a DB
 * 
 */
class DatFile 
{
	/**
		XML header infos
		name,description,version,author,homepage,url,etc **/
	public var HEADER:Map<String,String>;
	
	/** Number of entries */
	public var count:Int = 0;
	
	/** Guessed Romset Extension
	    Not reliable, since it is the first element rom extension */
	public var EXT:String; 
	
	// The path of the DAT file loaded
	public var fileLoaded:String = "";
	
	// LOG/TEXT Object and Header infos
	public var info:Array<String>;

	/** Map rom CRC -> DB Index**/
	public var ROMHASH:Map<String,Int>;

	/** Store all entries serially**/
	public var DB:Array<DatEntry>;

	public var includesMultiRoms(default,null):Bool;

	//====================================================;
	
	public function new(?file:String) 
	{
		if (file != null) load(file);
	}//---------------------------------------------------;
	
	
	/**
	   Load a DAT file and fill DB
	   @throws String Errors
	**/
	public function load(file:String)
	{
		reset();
		fileLoaded = file;

		var con:String = try Fs.readFileSync(file, {encoding:'utf8'}) catch (e:Dynamic) throw 'Cannot read file `$file`';

		info.push('== DatFile Object');
		info.push('> Loaded File : $file');
		info.push('> HEADER : ');
		
		try{
			
		var ac = try new Access(Xml.parse(con).firstElement());
		
		var n_header = ac.node.resolve('header');
		ac.x.removeChild(n_header.x); // Remove it so I can traverse through the rest of the elements in a for loop

		// Parse the <header> first
		for (i in n_header.elements) {
			try{
				HEADER[i.name] = i.innerData;
				info.push('\t${i.name} : ${i.innerData}');
			}catch (e:Dynamic){ }
		}
		
		// Then the rest of the elements, which should all be <game> tags
		for (i in ac.elements) 
		{
			var e:DatEntry = {
				name:i.att.name,
				description:i.node.description.innerData,
				roms:[]
			};

			for(rom in i.nodes.rom)
			{
				var r:DatRom = {
					filename:rom.att.name,
					md5:rom.att.md5,
					crc:rom.att.crc,
					size:Std.parseInt(rom.att.size),
					status:rom.x.exists('status')?rom.att.status:"-"
				};

				e.roms.push(r);
				ROMHASH.set(r.crc,count); // hash -> DB index
			}

			if(e.roms.length==0)
			{
				LOG.log('WARNING: Entry "${e.name}" contains no roms.');
			}else
			if(e.roms.length>1)
			{
				includesMultiRoms = true;
			}
			
			DB.push(e);
			count++;
		}
		
		if (count == 0)
		{
			throw 'DAT file `$file` found 0 entries';
		}
		
		// -
		for (i in DB) 
		{
			// DEV: WARNING: Assumes first element has roms!
			EXT = Path.extname(i.roms[0].filename).toLowerCase();
			break;
		}
		
		info.push('> Found (${count}) Entries');
		info.push('> Rom Extension : $EXT');
		info.push('------');
		
		}catch (e:Error) {
			LOG.log(e.message);
			throw 'Cannot parse DAT file `$file`'; 
		}
		catch (e:String) {
			LOG.log(e);
			throw e;
		}

		for (i in info)
		{
			LOG.log(i);
		}
	}//---------------------------------------------------;
	
	function reset()
	{
		HEADER = [];
		info = [];
		DB = [];
		ROMHASH = [];
		count = 0;
		fileLoaded = "";
		EXT = "";
		includesMultiRoms = false;
	}//---------------------------------------------------;
	
}// --




/** Data Example::

<?xml version="1.0"?>
<!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
<datafile>
	<header>
		<name>Sega - Master System - Mark III</name>
		<description>Sega - Master System - Mark III</description>
		<version>20190402-062156</version>
		<author>BigFred, C. V. Reynolds, fuzzball, gigadeath, kazumi213, omonim2007, relax, Rifu, TeamEurope, xuom2</author>
		<homepage>No-Intro</homepage>
		<url>http://www.no-intro.org</url>
	</header>
	<game name="[BIOS] Alex Kidd in Miracle World (Korea)">
		<description>[BIOS] Alex Kidd in Miracle World (Korea)</description>
		<rom name="[BIOS] Alex Kidd in Miracle World (Korea).sms" size="131072" crc="9C5BAD91" md5="E49E63328C78FE3D24AE32BF903583E0" sha1="2FEAFD8F1C40FDF1BD5668F8C5C02E5560945B17" status="verified"/>
	</game>
	<game name="[BIOS] Alex Kidd in Miracle World (USA, Europe)">
		<description>[BIOS] Alex Kidd in Miracle World (USA, Europe)</description>
		<rom name="[BIOS] Alex Kidd in Miracle World (USA, Europe).sms" size="131072" crc="CF4A09EA" md5="E8B26871629B938887757A64798DF6DC" sha1="3AF7B66248D34EB26DA40C92BF2FA4C73A46A051" status="verified"/>
	</game>
	.
	.
	.
	
</datafile>


*/