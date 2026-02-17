=begin
#----------------------------------------------------------------------------------------------------------------
#****************************************************************************************************************
# Designed by Fredo6 - Copyright Fredo6 and Sketchucation - July 2016

# Permission to use this software for any purpose and without fee is hereby granted, subject to License
# Distribution of this software for commercial purpose is subject to:
#  - the expressed, written consent of the author
#  - the inclusion of the present copyright notice in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Name			:   SCFLicense.rb
# Original Date	:   21 Jul 2016
# Description	:   Test file to load SCF License (to be included in the loading process of Sketchucation plugin)
#-----------------------------------------------------------------------------------------------------------------
#*****************************************************************************************************************
=end

unless defined?(SCFLicenseTop)

#--------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------------------------------------
# SCFLicenseTop Module
#--------------------------------------------------------------------------------------------------------------			 
#--------------------------------------------------------------------------------------------------------------			 

module SCFLicenseTop

#Current directory where the current file is located. 
# Note: This code probably exists in Skecthucation plugin
file__ = __FILE__.dup
file__ = file__.force_encoding("UTF-8") if defined?(Encoding)
file__ = file__.gsub(/\\/, '/')
dir__ = File.dirname(file__)

#Directory path of the subfolder 'SCFLicense'
@dir_folder = File.join(dir__, "SCFLicense")

#Current top dir for SCFLIcense main file (called by the Ruby file) and Version
def SCFLicenseTop.subdir ; @subdir_name ; end
def SCFLicenseTop.version ; "6.4a - 27 Mar 24" ; end

#Load Process
def SCFLicenseTop.registration(dir_SCFLicense)
	#Storing the SCF License directory
	@subdir_name = dir_SCFLicense
	
	#Finding the right file to load: Reb and rbs have priority over rb
	rootname = "SCFLicenseRuby"
	rb_file = File.join(@subdir_name, "#{rootname}.rb")
	rbs_file = File.join(@subdir_name, "#{rootname}.rbs")
	rbe_file = File.join(@subdir_name, "#{rootname}.rbe")
	
	File.delete(rbs_file) if FileTest.exist?(rbs_file)
	
	if Sketchup.version.to_i < 16
		rbf = (FileTest.exist?(rbs_file)) ? rbs_file : rb_file
	else
		rbf = (FileTest.exist?(rbe_file)) ? rbe_file : rb_file
	end
	
	#Ruby file was not found
	unless rbf && FileTest.exist?(rbf)
		return "No Ruby File for SCF License"
	end	

	#Loading the SCFLicenseRuby file
	Sketchup.require rbf
	
	#Return success
	false
end

#LICFILE: get a directory from ENV
def SCFLicenseTop.get_dir_from_ENV(a)
	d = ENV[a]
	return nil unless d
	if defined?(Encoding) 
		if d.encoding.inspect =~ /Windows/i
			dir = (d+'').force_encoding('iso-8859-1').encode("UTF-8")
		elsif d.encoding.inspect !~ /UTF/i
			dir = d.dup.encode("UTF-8")
		else	
			dir = d + ""
		end
	else
		dir = d + ""
	end	
	dir = dir.gsub("\\", "/") if dir
	dir
end

def SCFLicenseTop.set_dialog_global(wdlg) ; @wdlg_glo = wdlg ; end
def SCFLicenseTop.get_dialog_global ; @wdlg_glo ; end

#WINDOWS: Load the path to local directory
unless RUBY_PLATFORM =~ /darwin/i
	def SCFLicenseTop.compute_appdata
		#Return the directory if already computed
		return @appdata_computed if @appdata_computed
		
		#include the gem
		require 'fiddle/import'
		
		# Extend this module to an importer
		extend Fiddle::Importer
		
		# Load 'shell32' dynamic library into this importer
		dlload 'shell32'
		
		# Set C aliases to this importer for further understanding of function signatures
		typealias 'HANDLE', 'void*'
		typealias 'HWND', 'HANDLE'
		typealias 'LPSTR', 'char*'
		typealias 'LPWSTR', 'wchar_t*'
		typealias 'UINT', 'unsigned int'
		typealias 'DWORD', 'unsigned long'
		typealias 'HRESULT', 'long'
		
		# Import C functions from loaded libraries and set them as module functions
		extern 'HRESULT SHGetFolderPathA(HWND, int, HANDLE, DWORD, LPSTR)'
		extern 'HRESULT SHGetFolderPathW(HWND, int, HANDLE, DWORD, LPWSTR)'
		
		#Computing the APPDATA directory
		buf = "\0" * 2048
		SCFLicenseTop.SHGetFolderPathW(0, 0x001c | 0x8000, 0, 0, buf)
		path = buf.unpack('S*').pack('U*').strip
		if path && !path.empty?
			@appdata_computed = path.gsub("\\", '/')
		else
			@appdata_computed = SCFLicenseTop.get_dir_from_ENV('LOCALAPPDATA')
		end
		@appdata_computed
	end
end

#TEXTS: Load a language file
def SCFLicenseTop.load_custom
	#File name
	basename = "SCFLicense__custom.txt"
	file_custom = File.join(File.dirname(File.dirname(@dir_folder)), basename)
	file_custom = File.join(File.dirname(@dir_folder), basename) unless File.exist?(file_custom)
	file_custom = File.join(@dir_folder, basename) unless File.exist?(file_custom)
	
	#Reading the custom file
	@hsh_custom = {}
	
	if File.exist?(file_custom)
		lines = IO.readlines file_custom
		lines.each do |line|
			next if line =~ /\A\s*#/ || line !~ /(.+?)\s*\=(.+)/
			key = $1
			val = $2.strip
			@hsh_custom[key.gsub(' ', '').intern] = val
		end
	end	
end

def SCFLicenseTop.standard?
	@hsh_custom.empty?
end

def SCFLicenseTop.get_custom(symb)
	@hsh_custom[symb]
end

def SCFLicenseTop.dir_folder ; @dir_folder ; end

#Reading the custom file
SCFLicenseTop.load_custom

end	#module SCFLicenseTop

# Telling SCFLicxense what is the path of its folder (due to a bug whereby __FILE__ is not defined when loading rbs in old versions of Sketchup)
UI.start_timer(0.025, false) { SCFLicenseTop.registration(SCFLicenseTop.dir_folder) }

#The following code if just for generating the RBE and RBS via the EWH certification
if false
	ext = SketchupExtension.new "SCFLicense", File.join(@dir_folder, "SCFLicenseTopLoader")
	ext.creator = "Sketchucation" 
	ext.description = "License Manager for Sketchucation Plugins" 
	ext.version = SCFLicenseTop.version 
	ext.copyright = "Copyright 2016-2024 © Sketchucation" 
	status = Sketchup.register_extension ext, true
end

end	#defined?(SCFLicenseTop)