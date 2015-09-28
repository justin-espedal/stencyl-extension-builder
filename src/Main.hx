import cmd.Cmd;
import cmd.Cmd.*;
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
	 * CMD Binding
	\*-------------------------------------*/ 
	
	static var ant:Dynamic = bindCmd("ant");
	static var git:Dynamic = bindCmd("git");
	static var srm:Dynamic = bindCmd("srm");
	
	static var gitRead:Dynamic = bindReadCmd("git");
	
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
			ant("dist-just-jar");
			// out: /home/justin/src/stencyl/dist/sw.jar
		
		cd(props.get("polydesPath"));
		git("pull");
		
		//Make sure common is built first.
		cd("Common");
		conditionalBuild();
		cd("..");
		
		for(dir in loopFolders())
		{
			cd(dir);
			if(!exists("seb-skip"))
				conditionalBuild();
			cd("..");
		}
	}
	
	/*-------------------------------------*\
	 * Operations
	\*-------------------------------------*/ 
	
	static function conditionalBuild()
	{
		if(!exists("build.xml"))
			return;
		
		var buildVersion:Version = getBuildProp("version");
		var cvString = getVersionProp("semver");
		var cachedVersion:Version = cvString != "" ? cvString : "0.0.0";
		if(buildVersion > cachedVersion)
			rebuildExtension();
	}

	static function rebuildExtension()
	{
		var pkg=getBuildProp("pkg");
		var id=pkg.replace("/", ".");
		var hash = getVersionProp("hash");
		
		ant();
		// out: /home/justin/src/polydes/dist/$id.jar
		
		var folderName = new Path(dir).file;
		
		if(hash != "")
			git("log", "--format=%s", '$hash...HEAD', "--", ".", ">", "changes");
		else
			File.saveContent('$dir/changes', "Initial Repository Version.");
		
		srm("add", '$dir/../dist/$id.jar'.normalize(), '$dir/changes');
		
		var semver = getBuildProp("version");
		var hash = gitRead("log", "-1", "--format=%H");
		File.saveContent('$dir/.version', 'semver=$semver\nhash=$hash');
	}

	static function gitConditionalPull():Bool
	{
		git("remote", "update");
		
		var local = gitRead("rev-parse", "HEAD");
		var remote = gitRead("rev-parse", "master@{u}");
		var base = gitRead("merge-base", "HEAD", "master@{u}");
		
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
		var sebConf = Sys.getEnv("STENCYL_EXTENSION_BUILDER_CONFIG");
		if(sebConf != null)
			return sebConf;
		
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
