# encoding: UTF-8
=begin
(c) SketchUcation [SCF] / TIG 2020-2024
###
All rights reserved.
THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES; 
INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
FITNESS FOR A PARTICULAR PURPOSE.
###
SketchUcation.rb
Sets up SCF_loader in SketchUcation subfolder.
=end
###
#require('sketchup.rb')
#require('extensions.rb')
###
module SCF
	###
	if defined?(Encoding) ### v2014 lashup # always used because now >=v2017
		PLUGINS=File.dirname(__FILE__.dup).force_encoding("ASCII-8BIT").force_encoding("UTF-8")
		LNAME = File.basename(__FILE__.dup.force_encoding("ASCII-8BIT").force_encoding("UTF-8"), ".*")
	else
		PLUGINS=File.dirname(__FILE__.dup)
		LNAME = File.basename(__FILE__.dup, ".*")
	end
  CONTAINER=File.dirname(PLUGINS) ###
	FOLDER = File.join(PLUGINS, LNAME)
	### set Constants
	SCFURL = "https://plugin.sketchucation.com/pluginstore_6.php"
	VERSION = "4.4.1"
	NAME = "SCF"
	### set up other folders
 	STRINGS=File.join(FOLDER, "Strings") ### Translations
	IMAGES=File.join(FOLDER, "Images") ### Icons
  DATA=File.join(FOLDER, "Data") ### HTML etc
	###
	IS_WIN=(RUBY_PLATFORM.downcase =~ /mswin|mingw/) != nil
	IS_MAC=(RUBY_PLATFORM.downcase =~ /darwin/) != nil
	IS_LINUX=(RUBY_PLATFORM.downcase =~ /linux/) != nil
	###
	HOME=File.expand_path( (begin;ENV['HOME'].dup.force_encoding("ASCII-8BIT").force_encoding('UTF-8');rescue;ENV['HOME'];end) || (begin;ENV['HOMEPATH'].dup.force_encoding("ASCII-8BIT").force_encoding('UTF-8');rescue;ENV['HOMEPATH'];end) || (begin;ENV['HOMEDRIVE'].dup.force_encoding('UTF-8');rescue;ENV['HOMEDRIVE'];end) )
	if IS_MAC
		DESKTOP=File.join(HOME, "Desktop") ### TBC
	else
		DESKTOP=File.join(HOME, "Desktop") ### PC
	end
	### ALWAYS going to be temp_dir as >=v2017 ???
	[(begin;Sketchup.temp_dir;rescue;'??';end),
	(begin;Sketchup.temp_dir.force_encoding("ASCII-8BIT").force_encoding('UTF-8');rescue;'?';end),
	(begin;ENV['TEMP'].dup.force_encoding("ASCII-8BIT").force_encoding('UTF-8');rescue;ENV['TEMP'];end), 
	(begin;ENV['TMP'].dup.force_encoding("ASCII-8BIT").force_encoding('UTF-8');rescue;ENV['TMP'];end), 
	(begin;ENV['TMPDIR'].force_encoding("ASCII-8BIT").dup.force_encoding('UTF-8');rescue;ENV['TMPDIR'];end), 
	(begin;ENV['USERPROFILE'].force_encoding("ASCII-8BIT").dup.force_encoding('UTF-8');rescue;ENV['USERPROFILE'];end),  
	FOLDER, 
	PLUGINS, 
	CONTAINER, 
	HOME, 
	DESKTOP, 
	'C:/Temp', 
	'/tmp'#,
	#Dir.pwd
	].each{|d|
		if d && File.directory?(d) #&& File.writable?(d)
			TEMP = File.expand_path(d)
			break ### it's usually Sketchup.temp_dir in all newer SketchUp versions
		end
  }
	###
	TEMPDIR	= File.join(TEMP, NAME)
	@tempdir=TEMPDIR
	begin ### allows for false File.exist? failure with non-ASCII
		Dir.mkdir(TEMPDIR)
	rescue
		###
	end
	### NOUPS scripts never covered by update/installed checks
	NOUPS=[
	"deBabelizer.rb", 
	"ArcCurveTests.rb", 
	"toggleWindows.rb", 
	"delauney3.rb", 
	"inputbox.rb"
	]
	### NONOS == $LOAD_PATH folders BUT NOT custom-plugins - uses // regex
	#home = Regexp.new('^'+Regexp.escape(HOME)+'$')
	#if ENV["GEM_HOME"]
		#gems = Regexp.new('^'+Regexp.escape(ENV["GEM_HOME"].dup.force_encoding("ASCII-8BIT").force_encoding('UTF-8'))+'$')
	#else
		#gems = nil
	#end
	# avoid non-ASCII user name mess with home and gems.
	###
	nonos=[]#home, #/^C[:]\/Users\/Антон\/AppData/,
	[ 
	/\/[Gg][Ee][Mm][Ss]64$/, #WIN
	/\/[Gg][Ee][Mm][Ss]32$/, #WIN
	/\/[Gg][Ee][Mm][Ss]$/, #MAC
	/\/RubyStdLib/, 
	/\/lib\/ruby\//, 
	/\/[Tt]est[Uu]p\//, 
	/\/[Tt]ools$/, 
	/\/TT_Lib/, 
	/\/SketchyPhysics/, 
	/\/SketchThis/, 
	/\/i[.]materialise/, 
	/\/[Ww]in_[Uu]tils\//, 
	/\/wxSU\//, 
	/\/ASGVIS/, 
	/\/skindigo/
	].compact.each{|x|
		y=x.to_s
		y.force_encoding("ASCII-8BIT").force_encoding('UTF-8') if defined?(Encoding)
		z=Regexp.new(y)
		nonos << z
	}
	NONOS=nonos.dup
	###
	SUCPLUGINS = '' #HOME+'/sketchUcloud/plugins' #Now Disabled
	### 'Helpers' which other scripts might 'require'...
	HELPERS=['progressbar.rb', 
	'offset.rb', 
	'arraysum.rb', 
	'array_to.rb', 
	'getMaterials.rb', 
	'EntsGetAtt.rb', 
	'select.rb', 
	'smustard-app-observer.rb', 
	'deBabelizer.rb', 
	'parametric.rb', 
	'mesh_additions.rb', 
	'su_dynamiccomponents.rb', 
	'add_funcs.rb', 
	'resizing_material.rb', 
	'delauney2.rb', 
	'delauney3.rb', 
	'ftools.rb', 
	'inputbox.rb', 
	'LibFredo6.rb', 
	'LibTraductor.rb', 
	'toggleWindows.rb', 
	'vector.flat_angle.rb', 
	'wxSU.rb', 
	'image_code.rb', 
	'easings.rb', 
	'su2pov34.rbs', 
	'windowizer4stylemanager.rb', 
	'weld.rb', 
	'TIG-weld.rb', 
	'pp.rb',
	'!AdditionalPluginFolders.rb'
	].sort
	###
	CREATOR="#{LNAME}"
	COPYRIGHT="#{LNAME} © #{Time.now.year}"
	###
	### set up translated Constants ### File.exist? should always work as all ASCII in path
	file=File.join(STRINGS, "#{NAME}-#{Sketchup.get_locale.upcase}.strings")
	if File.exist?(file)
		lines=IO.readlines(file)
	else
		file=File.join(STRINGS, "#{NAME}-EN-US.strings")
		if File.exist?(file)
			lines=IO.readlines(file)
		else
			lines=[]
		end
	end
	lines.each{|line|
		line.chomp!
		next if line.empty? || line=~/^[#]/
		next unless line=~/[=]/
		eval(line) ### set CONSTANT=value
	}
	###
	EXT=SketchupExtension.new(NAME, File.join(FOLDER, "SCF_loader"))
	EXT.name = LNAME
	EXT.description = "#{LNAME} #{TOOLSS}: #{DESC}, #{MDESC} #{AND} #{XDESC}"
	EXT.version = VERSION
	EXT.creator = CREATOR
	EXT.copyright = COPYRIGHT
	ext=Sketchup.register_extension(EXT, true) # show on 1st install
	###
end#module
