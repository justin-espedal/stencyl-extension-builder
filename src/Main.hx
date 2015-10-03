import cmd.Cmd;
import cmd.Cmd.*;
import haxe.crypto.Crc32;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.io.Eof;
import haxe.io.Path;
import haxe.zip.Entry;
import haxe.zip.Reader;
import haxe.zip.Writer;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import thx.semver.Version;

using StringTools;
using haxe.io.Path;

class Main
{
	/*-------------------------------------*\
	 * CMD Binding
	\*-------------------------------------*/ 
	
	static var ant:Dynamic = bindCmd("ant");
	static var git:Dynamic = bindCmd("git");
	static var srm:Dynamic = bindCmd("srm", true);
	
	/*-------------------------------------*\
	 * Main
	\*-------------------------------------*/ 
	
	public static function main():Void
	{
		var args = Sys.args();
		
		if(args.length > 0 && args[0] == "setup")
		{
			args.shift();
			
			File.saveContent
			(
				getConfigFilePath(),
				"paths:\n" + args.join("\n")
			);
			
			return;
		}
		
		var lines = File.getContent(getConfigFilePath()).split("\n");
		var paths = [];
		for(line in lines)
		{
			var arr:Array<String> = null;
			
			switch(line)
			{
				case "paths:":
					arr = paths;
				case _:
					arr.push(line);
			}
		}
		
		var notEmpty = function(s) {return s.length > 0;};
		
		for(path in paths)
		{
			cd(path);
			if(exists(".seb"))
			{
				var script = File.getContent('$dir/.seb');
				runSeb(script);
			}
		}
	}
	
	static function runSeb(script:String)
	{
		var parser = new hscript.Parser();
		var program = parser.parseString(script);
		var interp = new hscript.Interp();
		
		interp.variables.set("File",File);
		interp.variables.set("Path",Path);
		interp.variables.set("asVersion",Version.stringToVersion);
		
		interp.variables.set("dir",dir);
		interp.variables.set("cd",cd);
		interp.variables.set("git",git);
		interp.variables.set("ant",ant);
		interp.variables.set("srm",srm);
		
		interp.variables.set("grep",grep);
		interp.variables.set("zipFile",zipFile);
		interp.variables.set("zipFolder",zipFolder);
		interp.variables.set("gitConditionalPull",gitConditionalPull);
		
		interp.execute(program);
	}
	
	/*-------------------------------------*\
	 * Operations
	\*-------------------------------------*/ 

	static function gitConditionalPull():Bool
	{
		git("remote", "update");
		
		var local = git("rev-parse", "HEAD").output;
		var remote = git("rev-parse", "master@{u}").output;
		var base = git("merge-base", "HEAD", "master@{u}").output;
		
		if(local == remote)
		{
			trace("Up-to-date");
			return false;
		}
		else if(local == base)
		{
			trace("Need to pull");
			git("pull", "--rebase");
			return true;
		}
		else if(remote == base)
		{
			trace("Need to push");
			return false;
		}
		else
		{
			trace("Diverged");
			git("pull", "--rebase");
			return true;
		}
	}
	
	/*-------------------------------------*\
	 * Helpers
	\*-------------------------------------*/ 
	
	static function grep(filename:String, pattern:String):String
	{
		if(exists(filename))
		{
			var content = File.getContent('$dir/$filename');
			var lines = content.split("\n");
			var result = "";
			var re = new EReg(pattern, "");
			
			for(i in 0...lines.length)
			{
				if(re.match(StringTools.trim(lines[i])))
					return re.matched(1);
			}
			trace("no matches");
		}
		trace(filename + " doesn't exist");
		return "";
	}
	
	/*-------------------------------------*\
	 * Paths
	\*-------------------------------------*/ 
	
	static function getConfigFilePath():String
	{
		var sebConf = Sys.getEnv("STENCYL_EXTENSION_BUILDER_CONFIG");
		if(sebConf != null)
			return sebConf;
		
		if(Sys.systemName() == "Windows")
			return Sys.getEnv("HOMEDRIVE") + Sys.getEnv("HOMEPATH") + "/.seb_config";
		else
			return Sys.getEnv("HOME") + "/.seb_config";
	}
	
	/*-------------------------------------*\
	 * Properties Files
	\*-------------------------------------*/ 
	
	static function parsePropertiesFile(path:String):Map<String, String>
	{
		return parseProperties(File.getContent(path));
	}
	
	// https://gist.github.com/YellowAfterlife/9643940
	static function parseProperties(text:String):Map<String, String>
	{
		var map:Map<String, String> = new Map(),
			ofs:Int = 0,
			len:Int = text.length,
			i:Int, j:Int,
			endl:Int;
		while (ofs < len)
		{
			// find line end offset:
			endl = text.indexOf("\n", ofs);
			if (endl < 0) endl = len; // last line
			// do not process comment lines:
			i = text.charCodeAt(ofs);
			if (i != "#".code && i != "!".code)
			{
				// find key-value delimiter:
				i = text.indexOf("=", ofs);
				j = text.indexOf(":", ofs);
				if (j != -1 && (i == -1 || j < i)) i = j;
				//
				if (i >= ofs && i < endl)
				{
					// key-value pair "key: value\n"
					map.set(StringTools.trim(text.substring(ofs, i)),
					StringTools.trim(text.substring(i + 1, endl)));
				}
				else
				{
					// value-less declaration "key\n"
					map.set(StringTools.trim(text.substring(ofs, endl)), "");
				}
			}
			// move on to next line:
			ofs = endl + 1;
		}
		return map;
	}
	
	/*-------------------------------------*\
	 * Zip Files
	\*-------------------------------------*/ 
	
	static function zipFolder(path:String, out:String):Void
	{
		var zipdata = new List<Entry>();
		for(filename in FileSystem.readDirectory(path))
			addEntries('$path/$filename', "", zipdata);
		
		var output = File.write(out);
		var zipWriter = new Writer(output);
		zipWriter.write(zipdata);
		output.close();
	}
	
	static function zipFile(path:String, out:String):Void
	{
		var zipdata = new List<Entry>();
		addEntries(path, "", zipdata);
		
		var output = File.write(out);
		var zipWriter = new Writer(output);
		zipWriter.write(zipdata);
		output.close();
	}
	
	static function addEntries(path:String, prefix:String, entries:List<Entry>):Void
	{
		var fpath = new Path(path);
		var filename = fpath.file;
		if(fpath.ext != null)
			filename += '.${fpath.ext}';
		
		if(FileSystem.isDirectory(path))
		{
			entries.add({
				fileName : prefix + filename,
				fileSize : 0, 
				fileTime : Date.now(), 
				compressed : false, 
				dataSize : 0,
				data : null,
				crc32 : 0,
				extraFields : new List()
			});
			
			for(file in FileSystem.readDirectory(path))
				addEntries(file, '$prefix/filename', entries);
		}
		else
		{
			var data = File.getBytes(path);
			
			var entry = {
				fileName : prefix + filename,
				fileSize : data.length, 
				fileTime : Date.now(), 
				compressed : false, 
				dataSize : data.length,
				data : data,
				crc32 : Crc32.make(data),
				extraFields : new List()
			};
			
			haxe.zip.Tools.compress(entry, 4);
			
			entries.add(entry);
		}
	}
}
