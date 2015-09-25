import haxe.io.BytesOutput;
import haxe.io.Eof;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
import thx.semver.Version;

using StringTools;
using haxe.io.Path;

class Main
{
	/*-------------------------------------*\
	 * Main
	\*-------------------------------------*/ 
	
	public static function main():Void
	{
		var args = Sys.args();
		
		if(args.length > 0 && args[0] == "setup")
		{
			var stencylPath = args[1];
			var polydesPath = args[2];
			
			File.saveContent
			(
				getConfigFilePath(),
				'stencylPath=$stencylPath\n' +
				'polydesPath=$polydesPath'
			);
			
			return;
		}
		
		var props = parsePropertiesFile(getConfigFilePath());
		
		cd(props.get("stencylPath"));
		if(gitConditionalPull())
			cmd("ant", ["dist-just-jar"]);
			// out: /home/justin/src/stencyl/dist/sw.jar
		
		cd(props.get("polydesPath"));
		cmd("git", ["pull"]);
		for(dir in loopFolders())
		{
			cd(dir);
			conditionalBuild();
			cd("..");
		}
	}
	
	/*-------------------------------------*\
	 * CMD interface
	\*-------------------------------------*/ 
	
	static var dir = "";
	
	static function cd(path:String)
	{
		if(path.isAbsolute())
			Sys.setCwd(dir = path);
		else
			Sys.setCwd(dir = '$dir/$path'.normalize());
	}
	
	static function cmd(command:String, ?args:Array<String>):Int
	{
		return Sys.command(command, args);
	}
	
	static function readCmd(command:String, ?args:Array<String>):String
	{
		var process:Process = null;
		try
		{
			process = new Process(command, args);
		}
		catch(e:Dynamic)
		{
			trace(e);
			return null;
		}
		
		var buffer = new BytesOutput();
		
		var waiting = true;
		while(waiting)
		{
			try
			{
				var current = process.stdout.readAll(1024);
				buffer.write(current);
				if (current.length == 0)
				{  
					waiting = false;
				}
			}
			catch (e:Eof)
			{
				waiting = false;
			}
		}
		
		process.close();
		
		var output = buffer.getBytes().toString();
		if (output == "")
		{
			var error = process.stderr.readAll().toString();
			if (error==null || error=="")
				error = 'error running $command ${args.join(" ")}';
			trace(error);
			
			return null;
		}
		
		return output;
	}
	
	static function loopFolders():Array<String>
	{
		return
			FileSystem.readDirectory(dir)
			.filter
			(
				function(path)
				{ return FileSystem.isDirectory(path); }
			);
	}
	
	static function exists(path:String):Bool
	{
		return FileSystem.exists('$dir/$path');
	}
	
	/*-------------------------------------*\
	 * Operations
	\*-------------------------------------*/ 
	
	static function conditionalBuild()
	{
		if(!exists("build.xml"))
			return;
		
		var buildVersion:Version = getBuildProp("version");
		var cachedVersion:Version = getVersionProp("semver");
		if(buildVersion > cachedVersion)
			rebuildExtension();
	}

	static function rebuildExtension()
	{
		var pkg=getBuildProp("pkg");
		var id=pkg.replace("/", ".");
		var hash = getVersionProp("hash");
		
		cmd("ant", ["-Djenkins=true"]);
		// out: /home/justin/src/polydes/dist/$id.jar
		
		var folderName = new Path(dir).file;
		var changes = hash != null ?
			readCmd("git", ["log", "--format=\"%s\"", '$hash...HEAD', "--", "\"folderName\""]) :
			"Initial Repository Version.";
		
		cmd("srm", ["add", 'dist/$id.jar', "-c", changes]);
		
		var semver = getBuildProp("version");
		var hash = readCmd("git", ["log", "-1", "--format=\"%H\""]);
		File.saveContent('$dir/.version', 'semver=$semver\nhash=$hash');
	}

	static function gitConditionalPull():Bool
	{
		cmd("git", ["remote", "update"]);
		
		var local = readCmd("git", ["rev-parse", "HEAD"]);
		var remote = readCmd("git", ["rev-parse", "master@{u}"]);
		var base = readCmd("git", ["merge-base", "HEAD", "master@{u}"]);
		
		if(local == remote)
		{
			trace("Up-to-date");
			return false;
		}
		else if(local == base)
		{
			trace("Need to pull");
			cmd("git", ["pull", "--rebase"]);
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
			cmd("git", ["pull", "--rebase"]);
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
				if(re.match(StringTools.trim(lines[i])))
					return re.matched(1);
		}
		return "";
	}
	
	static function getBuildProp(propertyName:String):String
	{
		return grep("build.xml", 'property name="$propertyName" value="(.*)"');
	}

	static function getVersionProp(propertyName:String):String
	{
		return grep(".version", '$propertyName=(.*)');
	}
	
	/*-------------------------------------*\
	 * Paths
	\*-------------------------------------*/ 
	
	static function getConfigFilePath():String
	{
		if(Sys.systemName() == "Windows")
			return Sys.getEnv("HOMEDRIVE") + Sys.getEnv("HOMEPATH") + "/.stencylbuilder";
		else
			return Sys.getEnv("HOME") + "/.stencylbuilder";
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
}
