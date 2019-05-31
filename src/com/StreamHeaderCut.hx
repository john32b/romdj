package com;

import haxe.extern.EitherType;
import js.Error;
import js.node.Buffer;
import js.node.readline.Interface.InterfaceEvent;
import js.node.stream.Transform;


/**
   Transform stream to skip the first X bytes of a Stream
   - works for small amount of bytes
   - totally untested and does not error check for anything, like short streams, more bytes to skip than stream has, etc.
   
   e.g.
	
   var cutter = new StreamHeaderCut(32); // cut 32 bytes
		originalStream.pipe(cutter);
		cutter.pipe(destinationStream);
   
**/
class StreamHeaderCut<T:Transform<T>> extends js.node.stream.Transform<T>
{
	var len:Int; // Number of bytes to cut from the beginning
	var skipped:Int = 0;
	var done:Bool = false;
	public function new(i:Int) 
	{
		len = i;
		super(null);
	}//---------------------------------------------------;
	
	override function _transform(chunk:Buffer, encoding:String, callback:js.Error->EitherType<String, Buffer>->Void):Void 
	{
		if (!done)
		{
			if (chunk.byteLength > (len - skipped))
			{
				// The chunk needs to be cut (start, buffer end, defaults to total len)
				var newCh = chunk.slice(len - skipped);
				push(newCh);
				done = true;
			}else
			{
				// Don't push anything, Discard the chunk.
				skipped += chunk.byteLength;
			}
		}else
		{
			// Bytes already skipped, pipe data normally
			push(chunk);
		}
		
		callback(null,null);
	}//---------------------------------------------------;
}// --