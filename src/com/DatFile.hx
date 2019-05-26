package com;
import haxe.zip.Entry;
import js.Error;
import js.node.Fs;
import haxe.xml.Access;
import js.node.Path;
import djNode.tools.LOG;


typedef DatEntry = {
	name:String,
	description:String,
	romname:String,
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
 *  - Handles `MD5` only, disregards other hashes
 * 
 */
class DatFile 
{
	/**
	   name,description,version,author,homepage,url 
	**/
	public var HEADER:Map<String,String>;
	
	/**
	   CRC32 => Entry
	   DEV: I am using CRC32 for lookups for quick lookup based on it **/
	public var DB:Map<String,DatEntry>;
	
	/** Number of entries */
	public var count:Int = 0;
	
	/** Guessed Romset Extension (lowercase) e.g `.sms` , `.gb` */
	public var EXT:String; 
	
	// The path of the DAT file loaded
	public var fileLoaded:String = "";
	
	// Object and Header info
	public var info:Array<String>;

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
		
		try{
			
		var ac = try new Access(Xml.parse(con).firstElement());

		var n_header = ac.node.resolve('header');
		ac.x.removeChild(n_header.x);
		
		info.push('== DatFile Object');
		info.push('> Loaded File : $file');
		info.push('> HEADER : ');
		
		for (i in n_header.elements) {
			HEADER[i.name] = i.innerData;
			info.push('\t${i.name} : ${i.innerData}');
		}
		
		//var t = 10;
		for (i in ac.elements) 
		{
			//if (--t == 0) break;
			count++;
			var _d = i.node.description;	// Alternative to `i.node.resolve('description');`
			var _r = i.node.rom;
			var f:DatEntry = {
				name:i.att.name,
				description:_d.innerData,
				romname:_r.att.name,
				md5:_r.att.md5,
				crc:_r.att.crc,
				size:Std.parseInt(_r.att.size),
				status:_r.x.exists('status')?_r.att.status:"-"
			};
			DB.set(f.crc, f);
		}
		
		if (count == 0)
		{
			throw 'DAT file `$file` found 0 entries';
		}
		
		// -
		for (i in DB) 
		{
			EXT = Path.extname(i.romname).toLowerCase();
			break;
		}
		
		info.push('> Found (${count}) Entries');
		info.push('> Rom Extension : $EXT');
		info.push('------');
		
		}catch (e:Dynamic) throw 'Cannot parse DAT file `$file`'; 
		
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
		count = 0;
		fileLoaded = "";
		EXT = "";
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