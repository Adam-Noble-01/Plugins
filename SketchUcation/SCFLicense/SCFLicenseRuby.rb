=begin
#----------------------------------------------------------------------------------------------------------------
#****************************************************************************************************************
# Designed by Sketchucation - Copyright July 2016

# Permission to use this software for any purpose and without fee is hereby granted, subject to License
# Distribution of this software for commercial purpose is subject to:
#  - the expressed, written consent of the author
#  - the inclusion of the present copyright notice in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Name			:   SCFLicense_ruby.rb
# Original Date	:   21 Jul 2016
# Description	:   Ruby section for SCF License
#-----------------------------------------------------------------------------------------------------------------
#*****************************************************************************************************************
=end

#-------------------------------------------------------------------------------------
#-------------------------------------------------------------------------------------
# SCFLicense Module
#-------------------------------------------------------------------------------------			 
#-------------------------------------------------------------------------------------			 

unless defined?(SCFLicense)

module SCFLicenseState

def SCFLicenseState.loaded? ; @already_loaded ; end
def SCFLicenseState.load_done ; @already_loaded = true ; end

end	#module SCFLicenseState

require "FileUtils" unless defined?(FileUtils)

module SCFLicense

Sketchup.write_default 'Vava', 'Vava', []

#=====================================================================================
#=====================================================================================
# PUBLIC METHODS OF SCFLicense module
#=====================================================================================
#=====================================================================================

#PUBLIC: DIALOG BOX FOR LICENSE HANDLING (to be called from a menu)
#ex: SCFLicense.license_dialog "Animator"
def self.license_dialog(plugin_name)
	return unless load_binary(true)
	LicenseManager.new(plugin_name, Time.now.to_f.round+13, :dialog) 	
end

#PUBLIC: DIALOG BOX FOR GLOBAL STATUS (to be called from a menu)
#ex: SCFLicense.license_dialog_global
def self.license_dialog_global
	wdlg_glo = SCFLicenseTop.get_dialog_global
	if wdlg_glo
		wdlg_glo.close
	end	
	return unless load_binary(true)
	LicenseManager.new("Souvenir", Time.now.to_f.round+13, :global) 	
end


#PUBLIC: Test if a plugin is licensed
#ex: SCFLicense.licensed? "Animator", "m8IH7iL3Uy3u4R646l"
def self.licensed?(plugin_name, author_secret_key)
	return nil unless load_binary && author_secret_key
	ls = [author_secret_key]
	LicenseManager.new(plugin_name, Time.now.to_f.round+13, :licensed, ls) 
	ls[0]	
end

#PUBLIC: Given an encrypted key and a number, return an encrypted key which is <key>_<number>
#ex: SCFLicense.dynamic_token "m8IH7iL3Uy3u4R646l", 333
def self.dynamic_token(encrypted_key, n)
	return nil unless load_binary
	ls = [encrypted_key, n]
	LicenseManager.new(Time.now.to_f.round-39, Time.now.to_f.round+13, :token, ls) 
	ls[0]	
end

def self.visual_version ; ::SCFLicenseTop.version.split[0] ; end

#=====================================================================================
#=====================================================================================
# PRIVATE SECTION OF SCFLicense module
#=====================================================================================
#=====================================================================================

private
 
#---------------------------------
# Load of the binary .so
#---------------------------------

#Load the binary file with possibly a message
def self.load_binary(msg=false)
	#Already loaded
	return true if SCFLicenseState.loaded?
	
	#Rootname for the binary library
	rootname = "SUEX_SCFLibrary"
	
	#Identifying the Platform and Ruby version
	if RUBY_PLATFORM =~ /darwin/i	#Mac OSX
		platform = 'Mac'
		ext = "bundle"
	elsif RUBY_PLATFORM =~ /386/	#32 bits
		platform = 'Win32'
		ext = "so"
	else							#Windows 64 bits
		platform = 'Win64'
		ext = "so"
	end
	ruby_version = RUBY_VERSION.split('.')[0..1].join
	bin_code = "#{platform}_#{ruby_version}"
	
	#Full path of the original binary file (from installation)
	subdir = SCFLicenseTop.subdir
	so_install = File.join(SCFLicenseTop.subdir, bin_code, "#{rootname}_#{bin_code}.#{ext}")

	#Inform the user if there is NO binary file and NO install file
	unless File.exist?(so_install)
		latest = "You may need to install the latest version of Sketchucation tools"
		UI.messagebox "SCFLicense not supported: missing Library file \n\n#{so_install}\n\n#{latest}" if msg
		return false
	end
		
	#Create the temporary folder for the runtime binary (target)
	tmpdir = File.join(Sketchup.temp_dir, "SCFLicense - SU20#{Sketchup.version.to_i}")
	Dir.mkdir(tmpdir) unless File.directory?(tmpdir)

	#Inform the user if there is NO binary file and NO install file
	unless File.directory?(tmpdir)
		UI.messagebox "Security Permissions does not allow to create directory\n\n#{tmpdir}" if msg
		return false
	end
			
	#Run time file path
	so_runtime = File.join(tmpdir, "#{rootname}.#{ext}")

	#Copy the install binary to the runtime temporary folder
	begin
		FileUtils.copy so_install, so_runtime
	rescue
		if !File.exist?(so_runtime) || File.size(so_runtime) != File.size(so_install)
			UI.messagebox "Security Permissions does not allow to create file\n\n#{so_runtime}" if msg
		end
	end
	
	#Load the binary in Ruby
	status = require so_runtime

	#Inform the user in case of error
	unless status
		UI.messagebox "Binary library of SCFLicense did not load properly\n\n#{so_runtime}" if msg
		return nil
	end	
			
	#Delete the old file
	so_old = File.join(SCFLicenseTop.subdir, bin_code, "#{rootname}.#{ext}")
	if File.exist?(so_old)
		begin
			File.delete so_old
		rescue
		end
	end	
	
	#Transfer the path to the binary
	::SCFLibrary.declare_path(SCFLicenseTop.subdir) if defined?(::SCFLibrary.declare_path)
	
	#Freeze the module
SCFLibrary.freeze
	
	#Loading was successful
	SCFLicenseState.load_done
	true
end
 
#---------------------------------
# Custom configuration file
#---------------------------------

@url_purchase = 'https://sketchucation.com/purchase.php?plugin=%1'
@url_mylicenses = 'https://sketchucation.com/webshop/my-licences.php'
@url_support = 'https://sketchucation.com/forums/viewtopic.php?f=323&t=73325'

def SCFLicense.get_url_purchase(plugin_name)
	url = SCFLicenseTop.get_custom(:url_purchase)
	lst_plugins = SCFLicenseTop.get_custom(:plugins)
	unless url && lst_plugins && lst_plugins.include?(plugin_name)
		url = @url_purchase
	end	
	url.sub('%1', plugin_name)
end
 
def SCFLicense.get_url_mylicenses_sketchucation
	@url_mylicenses
end
 
def SCFLicenseTop.standard?
	!SCFLicenseTop.get_custom(:url_purchase)
end
 
def SCFLicense.get_url_mylicenses
	SCFLicenseTop.get_custom(:url_mylicenses)
end
 
def SCFLicense.get_url_support
	url = SCFLicenseTop.get_custom(:url_support)
	url = @url_support unless url
	url
end
  
#------------------------------------------
# TEXTS: Texts and Message
#------------------------------------------

#TEXTS: Initialize the Plugin, essentially messages. This is executed only once
def SCFLicense.text_init(lang=nil)
	lang = SCFLicenseTop.get_custom(:force_language) unless lang
	lang = Sketchup.get_locale unless lang
	
	#Loading the English file if no text has been loaded yet
	file_eng = File.join SCFLicenseTop.subdir, "SCFLicense__en.lang"
	@hsh_texts = {}
	text_load_language_file(file_eng)
	
	#Identifying the main language file and the one with sub lang if any
	lang = lang.downcase
	fmain = fsub = nil
	Dir[File.join(SCFLicenseTop.subdir, "SCFLicense__*.lang")].each do |f|
		fname = File.basename f
		next if fname !~ /\ASCFLicense__(.+)\.lang\Z/
		lg = $1
		if lg.downcase == lang
			fsub = f
		elsif lg[0..1].downcase == lang
			fmain = f unless f == file_eng
		end					
	end	
	
	#Loading the file languages
	SCFLicense.text_load_language_file(fmain) if fmain
	SCFLicense.text_load_language_file(fsub) if fsub

	#Correction for list of months
	lst_months = ["xxx"]
	@hsh_texts[:lst_months].split('-').each do |m|
		lst_months.push m.strip
	end	
	@hsh_texts[:lst_months] = lst_months
	
	#Corrections for list of week days
	lst_week_days = []
	@hsh_texts[:lst_week_days].split('-').each do |m|
		lst_week_days.push m.strip
	end	
	@hsh_texts[:lst_week_days] = lst_week_days
	
end

#TEXTS: Load a language file
def SCFLicense.text_load_language_file(f)
	lines = IO.readlines f
	lines.each do |line|
		next if line =~ /\A\s*#/ || line !~ /(.+?)\s*\=(.+)/
		key = $1
		val = $2.strip
		@hsh_texts[key.gsub(' ', '').intern] = val
	end
end

def SCFLicense.get_text(symb)
	text = SCFLicenseTop.get_custom(symb)
	return text if text
	@hsh_texts.fetch(symb, symb.to_s)
end
  
#*************************************************************************************
#*************************************************************************************
# CLASS: LicenseManager - Manages the License mechanisms 
#
# Note: the class if frozen and all methods are private
#*************************************************************************************
#*************************************************************************************

class LicenseManager

private

#Initialize a class instance
def initialize(plugin_name, secret_key, *args)
	#Checking the secret key - raise an error. 
	#The secret key is just used to be sure the instance is created by the genuine SCFLicense
	if !secret_key || (Time.now.to_f.round+13 - secret_key).abs > 1
		e = Exception.exception("Invalid Attempt to create a LicenseManager")
		raise e
		return nil
	end
	action = args[0]
	
	#Initialize the dialog styles and colors
	init_style_color
	
	#Storing the Plugin Name
	@plugin_name = plugin_name
	@distributor_name = SCFLicenseTop.get_custom(:distributor_name)
	@distributor_type = SCFLicenseTop.get_custom(:distributor_type)
	@distributor_type = 'A' if @distributor_name
	
	#Dialog initialization
	dialog_dimension_init
	
	#Initializing the texts in the right language
	####text_init if action != :licensed && action != :token
	
	#Executing the action as requested
	case action
	when :dialog
		dialog_license_launch
	when :global
		dialog_global_launch
	when :licensed
		srand
		@magic_rand = rand(10000)
		args[1][0] = licensed?(args[1], @magic_rand)
	when :token
		return nil if plugin_name != Time.now.to_f.round-39
		srand
		@magic_rand = rand(10000)
		args[1][0] = dynamic_token(args[1], @magic_rand)
	end	
end

#-------------------------------------------------------------------------------------
# TEXTS: Texts and Message
#-------------------------------------------------------------------------------------

#TEXTS: Return a text, given a symbol, with possible replacement of parameter (convention %1, %2, ...)
def text_of(symb, *args)	
	text = SCFLicense.get_text(symb)
	args.each_with_index { |arg, i| text = text.sub("%#{i+1}", arg) }
	text
end	

#TEXTS: Return a text, given a symbol, with possible replacement of parameter (convention %1, %2, ...)
def text_of_nosc(symb, *args)	
	text_of(symb, *args).sub(/:/, '').strip
end	

#--------------------------------------------
# COLORS: Color and styles for the dialogs
#--------------------------------------------

def init_style_color
	@dlg_background_color = '#F0F0F0'
end

#-------------------------------------------------------------------------------------
# LICFILE: Management of the License directory and files: signature, local license, ....
#-------------------------------------------------------------------------------------

#LICFILE: Compute the license directory
def licfile_directory
	#Already defined
	return @licdir if @licdir
	
	#Checking the directories in order
	@licdir = licfile_writable_directory(licfile_app_data_directory)
	
	#Returning the license directory
	@licdir
end

#LICFILE: Determine the APP Data directory
def licfile_app_data_directory
	#Already determined
	return @dir_appdata if @dir_appdata
	
	#Check the Sketchup natural locations
	if RUBY_PLATFORM =~ /darwin/i
		@dir_appdata = File.expand_path("~/Library/Application Support")
	elsif Sketchup.version.to_i >= 17
		@dir_appdata = SCFLicenseTop.compute_appdata		
	else
		@dir_appdata = SCFLicenseTop.get_dir_from_ENV('LOCALAPPDATA') || SCFLicenseTop.get_dir_from_ENV('APPDATA')
		@dir_appdata = File.dirname(Sketchup.temp_dir) unless @dir_appdata && File.directory?(@dir_appdata)
		@dir_appdata = @dir_appdata.gsub("\\", '/')
	end
	@dir_appdata
end

#LICFILE: Check if a directory exists and is writable - If so, create a subfolder "SCF LIcenses" and return it
def licfile_writable_directory(dir_local)
	return nil unless dir_local
	dir_local = dir_local.gsub(/\\/, "/")
	return nil unless File.directory?(dir_local) && File.writable?(dir_local)
	
	#Checking if there is a subfolder SCF Licenses
	folder_license = "SCF Licenses"
	dlic = File.join(dir_local, folder_license)
	return dlic if File.directory?(dlic) && File.writable?(dlic)
	
	#Otherwise, create the License subfolder
	begin
		Dir.mkdir dlic
	rescue
	end
	
	#Returning the LIcense directory if it exists and is writable
	(File.directory?(dlic) && File.writable?(dlic)) ? dlic : nil
end

#LICFILE: Compute the license file path for a plugin
def licfile_local_license_path(plugin_name=nil)
	plugin_name = @plugin_name unless plugin_name
	licdir = licfile_directory
	return nil unless licdir	
	File.join(licdir, "SCFLicense_#{plugin_name}_this_computer.txt")
end

#LICFILE: Delete local license file for a given plugin	
def licfile_local_license_remove(plugin_name)	
	#Getting the local license file
	licfile = licfile_local_license_path(plugin_name)
	return false unless File.file?(licfile)
	
	#Removing the file
	begin
		File.delete licfile
	rescue
		return nil
	end	
	true
end

#-------------------------------------------------------------------------------------
# SIGNATURE: Manage a Unique identifier for the computer
#-------------------------------------------------------------------------------------

#SIGNATURE: Compute the path for the Signature file
def signature_path
	licdir = licfile_directory
	return nil unless licdir	
	File.join(licdir, "SCFLicenseSignature - DO NOT MODIFY OR DELETE.txt")
end

#SIGNATURE: Store the error symbol for signature
def signature_error(symb)
	@signature_error = "signature_error_#{symb}".intern
	nil
end

#SIGNATURE: Return the error message for signature
def signature_error_message
	#Event type
	case @signature_error.to_s
	when /signature_error_writing/i
		msg = "Signature file cannot be created"
	when /signature_error_modified/i
		msg = "Signature file has been modified"
	when /signature_error_invalid/i
		msg = "Signature file is invalid"
	else
		msg = "#{@signature_error}"
	end
	msg
end

#-------------------------------------------------------------------------------------
# LOG: Logging facility
#-------------------------------------------------------------------------------------

#LOG: Log an event to the log file
def log_build_message(event, *args)
	#Event type
	case event.to_s
	when /license_file_not_exist/
		msg = text_of(:msg_license_file_not_exist) + "\n\n" + args[0]
	when /\A(.+)_request_error/
		msg = text_of("msg_#{$1}_error".intern) + "\n\n" + text_of(:msg_request_SCF) + ": " + args[0]
	when /\A(.+)_response_error/
		msg = text_of("msg_#{$1}_error".intern) + "\n\n" + text_of(:msg_response_SCF) + ": " + args[0]
	when /validate_success/i
		msg = "Validation successful on Sketchucation -- "
		msg << " License: #{@hsh_license_cur[:lid]} (#{@hsh_license_cur[:type]})"
		msg << " SCF user: #{@hsh_license_cur[:username]}"
	when /release_success/i
		msg = "Release successful on Sketchucation -- "
		msg << " License: #{@hsh_license_cur[:lid]} (#{@hsh_license_cur[:type]})"
		msg << " SCF user: #{@hsh_license_cur[:username]}"
	when /purchase_request/
		msg = "Purchase request at #{url_purchase}"
	when /signature_created/i
		msg = "Signature file created for the computer as #{@hwid}"
	when /signature_critical_error/
		msg = "Problem with the License Signature file (#{signature_error_message})"
	when /signature_error_no_writable_directory/	
		msg = text_of(:msg_no_writable_directory)
	when /license_information/i
		msg = "Error reading Local License Information -- #{args[0]}"
	when /_SCF_/
		msg = "Sketchucation::#{args[0]}"
	else
		msg = event.to_s
	end
	
	#Return the message
	msg
end

#LOG: Log an event to the log file
def log(event, *args)
	#Getting the local Log file
	logpath = log_path
	return nil unless logpath

	#Fields of the log record
	plugin_name = @plugin_name
	plugin_name = "SCF License" if event.to_s =~ /signature/i
	
	#Event type
	msg = log_build_message(event, *args)
	
	#Building and Logging the record
	log_append(logpath, event, plugin_name, msg)
	
	#Return value is always nil
	nil
end

#LOG: Log an event with display of a messagebox
def log_box(event, *args)
	#puts "Log BOX event = #{event} args = #{args}"
	
	#Logging the event
	log event, *args
	
	msg = log_build_message(event, *args)
	
	#Building and Logging the record
	UI.messagebox msg
	
	#Return value is always nil
	nil
end

#LOG: Build the log record and append it to the log file
def log_append(logpath, event, plugin_name, msg)
	stime = Time.now.strftime "%d-%b-%y   %H:%M:%S"
	rec = "#{stime};;;#{plugin_name};;;#{event};;;#{msg}"
	rec = rec.gsub("\n", '-')
	begin
		File.open(logpath, "a") do |f|
			f.puts rec
		end	
	rescue
	end
end

#LOG: Getting the path for the local Log file
def log_path
	licdir = licfile_directory
	return nil unless licdir	
	File.join(licdir, "SCFLicenseLog.txt")
end

#-------------------------------------------------------------------------------------
# CHECK: Checking of the license
#-------------------------------------------------------------------------------------

def dynamic_token(ls, magic_rand)
	#Check if the method is called from within the class
	return nil if magic_rand != @magic_rand
	
	#Checking the arguments
	encrypted_key, n = ls
	return nil unless n.is_a?(Integer) && encrypted_key.class == String
	
	#Calling the binary method
	s = ::SCFLibrary.dynamic_token(encrypted_key, n.to_s)
	(s.class == String && s.length > encrypted_key.length) ? s : nil
end

#CHECK: Check the license
def licensed?(ls, magic_rand)
	t1 = Time.now
	
	#Check if the method is called from within the class
	return nil if magic_rand != @magic_rand
	
	#The encrypted key is the first element in the input list
	encrypted_key_author = ls[0]
	ls.clear
	
	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)
	return nil unless FileTest.exist?(local_license_file_path)
	
	#Checking the License
	t2 = Time.now
	status = ::SCFLibrary.plugin_licensed(@plugin_name, signature_file_path, local_license_file_path, encrypted_key_author)
	
	#Parsing the result
	return nil if status =~ /ERROR_/ || status !~ /;/
	
	#Checking online
	#puts "LS = #{ls}"
	lp = Sketchup.read_default 'Vava', 'Vava'
	UI.start_timer(0) { col_check(signature_file_path, local_license_file_path) }
	
	#The license was invalidated
	if lp && lp.include?(@plugin_name)
		puts "The License for #{@plugin_name} was invalidated"
		return nil
	end
	
	#License is OK. Returning the non-encrypted value of the proof key and the licence type
	type, dkey = status.split(";;")
	
	#Getting the license_information
	hsh_license_info = license_information
	return nil unless hsh_license_info
	
	#Checking if the license has expired
	texpire = license_expiration_date(hsh_license_info)
	return nil if texpire && (Time.now > texpire)
	
	#Returning the feature if defined
	type = hsh_license_info.fetch :feature, type
	
	#Returning the license information and decrypted author key
	#puts "Full Licensed?************* #{Time.now-t1} s"
	ls[0] = [type, dkey]
end

#CHECK: Periodic check of the license online
def col_check(signature_file_path, local_license_file_path)
	#Data to pass to the query
	encrypted_key = ::SCFLibrary.validate_posting_key(@plugin_name, signature_file_path, local_license_file_path, Sketchup.version)
	return false if !encrypted_key || encrypted_key =~ /ERROR_/i

	#Getting the date for the license file
	plugin_key = @plugin_name.gsub(/./) { |c| c.ord.to_s }
	torigin, tcheck, tdiff = Sketchup.read_default('TDGmjdfotf', plugin_key)
	
	#Initialization
	torigin0 = Time.gm(2021, 9, 30).to_f
	
	#If the time is not already stored, store it and return
	if !torigin || (tcheck - torigin)**1.1 != tdiff
		tcheck = torigin0
	end	
	#puts "plugin = #{@plugin_name} - TORIGIN = #{torigin} - TCHECK = #{tcheck} - TDIFF = #{tdiff}"
	
	#No need to check
	telapse = 86400 * 30
	return true if (Time.now.to_f - tcheck).abs < telapse
	
	#Sending the check query to Sketchucation
	num = rand(50)
	num = 7 if num <= 1
	#puts "\n******************CHECK ONLINE NUM = #{num}"
	uri = "https://s.sketchucation.com/plugin-license.php"
	vnum = (SCFLicense.visual_version.to_f * 10).round
	@hreq = Sketchup::Http::Request.new(uri, Sketchup::Http::POST)
	@hreq.body = "action=check&data=#{encrypted_key}&num=#{num}&ac=#{vnum}"
	begin
		status_send = @hreq.start do |req, response|
			code = response.body
			lp = Sketchup.read_default 'Vava', 'Vava'
			lp = [] unless lp.class == Array

			if code =~ /error/i
				lp |= [@plugin_name]
				license_notify_invalid(code)
				col_delete_license
				
			elsif code =~ /\A(\d+)\Z/ && $1.to_i == (num * num).modulo(7)
				#puts "YA CALCULATE"
				tcheck = Time.now.to_f
				Sketchup.write_default('TDGmjdfotf', plugin_key, [torigin0, tcheck, (tcheck - torigin0)**1.1])
				lp.delete @plugin_name
				#puts "\nREPONSE = #{code.inspect} with num = #{num}  -> #{(num * num).modulo(7)}"
			else
				lp |= [@plugin_name]
				license_notify_invalid(code)
				col_delete_license
				#puts "PAS BON"
			end
			#puts "VAVA LP = #{lp}"
			Sketchup.write_default 'Vava', 'Vava', lp
		end
	rescue
		#puts "Rescue Send periodic"
		return true
	end	
	
	#Case where it is not connected to Internet
	UI.start_timer(0.4) do
		force_check = (Time.now.to_f - tcheck).abs >  3 * telapse
		if force_check && !status_send
			lp = Sketchup.read_default 'Vava', 'Vava'
			lp = [] unless lp.class == Array
			lp |= [@plugin_name]
			Sketchup.write_default 'Vava', 'Vava', lp
			#puts "CHECK INTERNET --> INVALIDATE AFTER 4 trials"
			license_notify_internet
		end	
	end	
end

def col_delete_license
	begin
		File.delete licfile_local_license_path
	rescue
	end
end

def license_notify_invalid(code)
	return unless defined?(UI::Notification)
	msg = "The license for #{@plugin_name} is invalid: #{code}"
	noti = UI::Notification.new(SketchupExtension.new('toto', 'toto'), msg)
	noti.show
end

def license_notify_internet
	return unless defined?(UI::Notification)
	msg = "You need to connect to Internet to validate the license for #{@plugin_name}"
	noti = UI::Notification.new(SketchupExtension.new('toto', 'toto'), msg)
	noti.show
end

#CHECK: Check if the license has expired
def license_expired?(hsh_license_info=nil)
	texpire = license_expiration_date(hsh_license_info)
	return false unless texpire
	(Time.now > texpire)
end

#CHECK: Compute the license expiration date as a Time object
def license_expiration_date(hsh_license_info=nil)
	hsh_license_info = @hsh_license_cur unless hsh_license_info
	return nil unless hsh_license_info
	duration = hsh_license_info[:duration]
	return nil unless duration
	sdate = hsh_license_info[:date]
	tpurchase = Time.gm(sdate[0..3], sdate[4..5], sdate[6..7], sdate[8..9], sdate[10..11])
	tpurchase + duration.to_i * 86400	
end

#CHECK: Return the public information about a license
def license_information(plugin_name=nil)
	@error_license_information = nil
	plugin_name = @plugin_name unless plugin_name
	
	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless File.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(plugin_name)
	return nil unless FileTest.exist?(local_license_file_path)
	
	#Getting the information
	status = ::SCFLibrary.local_license_info(plugin_name, signature_file_path, local_license_file_path)

	#Status invalid
	if status =~ /ERROR_/ || status !~ /;/
		@error_license_information = status
		return nil
	end	
	
	#Parsing the information
	hsh = {}
	status.split(';;').each { |a| key, val = a.split('::') ; hsh[key.intern] = val }
	hsh
end

#-------------------------------------------------------------------------------------
# PURCHASE: Purchase Phase
#-------------------------------------------------------------------------------------

#PURCHASE: Purchase URL
def url_purchase
	SCFLicense.get_url_purchase(@plugin_name)
end

#PURCHASE: Purchasing of a license
#Invoke the URL page on Sketchucation to purchase a license
def license_purchase(plugin_name=nil)
	plugin_name = @plugin_name unless plugin_name

	#Redirect to URL of purchase page on SCF (to be done when URL syntax finalized)
	UI.openURL url_purchase
	log(:purchase_request)
end

#LICENSE INFO: Store or retrieve the current license directory path in the Sketchup registry (just for convenience)
def license_purchase_directory(plugin_name, path=nil)
	#Dictionary and attribute used in the registry
	dico = "SCF"
	###attr = "SCF_License_#{plugin_name}_directory"
	attr = "SCF_License_purchased_directory"
	
	#Saving the directory path
	if path
		path = path.gsub(/\\/, "/")
		Sketchup.write_default(dico, attr, path)
		
	#Retrieve the directory path and setup a default path
	else	
		path = Sketchup.read_default(dico, attr)
		unless path && File.directory?(path)
			appdata_dir = licfile_app_data_directory
			begin
				path = File.join appdata_dir, "SCF"
				Dir.mkdir path unless FileTest.directory?(path)
			rescue	
				path = appdata_dir
			end	
		end	
	end	
	
	path
end

#--------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------------------------------------
# DIALOG LicenseDialog: Display and manage the License Dialog box
#--------------------------------------------------------------------------------------------------------------			 
#--------------------------------------------------------------------------------------------------------------			 

#----------------------------------------------------
# DIALOG LICENSE INIT: Dialog box initialization
#----------------------------------------------------

#DIALOG LICENSE INIT: Launching the dialog for licensing
def dialog_license_launch(plugin_name=nil)
	@plugin_name = plugin_name if plugin_name
	
	if dialog_check_online
		dialog_license_launch_exec
	end	
end

#DIALOG LICENSE INIT: Check the license online before launching the dialog
def dialog_check_online
	#Signature and license
	signature_file_path = signature_path
	return true unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)
	return true unless FileTest.exist?(local_license_file_path)
	
	#Data to pass to the query
	encrypted_key = ::SCFLibrary.validate_posting_key(@plugin_name, signature_file_path, local_license_file_path, Sketchup.version)
	if !encrypted_key || encrypted_key =~ /ERROR_/i
		col_delete_license
		return true
	end	
	
	#Sending the check query to Sketchucation
	num = rand(50)
	num = 7 if num <= 1
	uri = "https://s.sketchucation.com/plugin-license.php"
	vnum = (SCFLicense.visual_version.to_f * 10).round
	@hreq = Sketchup::Http::Request.new(uri, Sketchup::Http::POST)
	@hreq.body = "action=check&data=#{encrypted_key}&num=#{num}&ac=#{vnum}"
	begin
		status_send = @hreq.start do |req, response|
			code = response.body
			if !code.empty? && (code !~ /\A(\d+)\Z/ || $1.to_i != (num * num).modulo(7))
				col_delete_license
			end
			dialog_license_launch_exec
		end
	rescue
		return true
	end	

	#Launching the dialog
	false
end

#DIALOG LICENSE INIT: Initialization
def dialog_license_launch_exec	
	#Checking the local license directory
	licfile_directory
	unless @licdir
		return log_box(:signature_error_no_writable_directory, text_of(:msg_no_writable_directory))
	end	
	
	#Initialization
	title = encode_to_ruby(text_of(:title, @plugin_name))
	dlgkey = "SCFLicense Web Dialog"	#Unique key for dialog box

	#Getting the local license information
	@hsh_license_cur = license_information
	
	#Initial position and size
	xpos = 200
	ypos = 200
	sx = 750
	sy = 260

	#Dimension of the transient checking message
	wid_message = sx - 200
	hgt_message = 50
	xleft_message = (sx - 10 - wid_message) / 2
	ytop_message = (sy - 30 - hgt_message) / 2	
	@message_dim = "height: #{hgt_message}px ; width: #{wid_message}px ; left: #{xleft_message}px ; top: #{ytop_message}px ; "
	
	#Creating the dialog box
	@wdlg_lic = UI::WebDialog.new title, false, dlgkey, sx, sy, xpos, ypos, true
	@wdlg_lic.add_action_callback("top_callback") { |dialog, params| dialog_license_callback(params) }
	@wdlg_lic.set_background_color @dlg_background_color
	@wdlg_lic.navigation_buttons_enabled = false if defined?(@wdlg_lic.navigation_buttons_enabled)
	@wdlg_lic.set_on_close { dialog_license_on_close() }
	@wdlg_lic.min_width = 700
	@wdlg_lic.min_height = 250
	
	#Building the initial HTML
	@wdlg_lic.set_html dialog_license_format_html
	
	#Setting the position only once
	lst_info = Sketchup.read_default("SCF", dlgkey)
	unless lst_info && !lst_info.empty?
		@wdlg_lic.set_position xpos, ypos
		@wdlg_lic.set_size sx, sy
		Sketchup.write_default("SCF", dlgkey, [xpos, ypos, sx, sy])
	end	
	
	#Updating the Seats
	if @hsh_license_cur
		UI.start_timer(0.2) { seat_prepare_request }
	end
	
	#Showing the dialog box
	@wdlg_lic.show_modal
end

#DIALOG LICENSE INIT: Close of the dialog box
def dialog_license_on_close
	@wdlg_lic = nil
	@wdlg_glo.set_html dialog_global_format_html if @wdlg_glo
end

#----------------------------------------------------------
# DIALOG LICENSE FORMAT: HTML Formatting of the dialog box
#----------------------------------------------------------

#DIALOG LICENSE HTML: Formatting for the whole dialog box
def dialog_license_format_html
	#HTML Headers
	text = ""
	text << %q(<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/strict.dtd">)
	text << %q(<META http-equiv='Content-Type' Content='text/html; charset=UTF-8'> )
	text << %q(<META http-equiv='Content-Script-Type' content='text/javascript'>)
	
	#Scripts
	text << "<SCRIPT>"
	text << javascript_action
	text << javascript_capture_key
	text << javascript_resizing
	text << javascript_posting
	text << "</SCRIPT>"
	text << "<BODY onkeyup='CaptureKeyUp()' onkeydown='CaptureKeyDown()'>"
	text << "<BODY onload='action(\"wonload\")'>"

	#CSS styles
	text << "<style type='text/css'>"
	text << format_common_style
	text << ".MsgNote { color: #{@color_text_blue} ; font-size: 10pt ; font-style: italic }"
	text << ".Valid { color: green ; font-size: 11pt ; font-weight: bold }"
	text << ".Undef { color: red ; font-size: 11pt ; font-weight: bold }"
	text << ".Expired { color: darkorange ; font-size: 11pt ; font-weight: bold }"
	if Sketchup.version.to_i <= 17
		text << ".Label {  font-family: Helvetica, arial, sans serif, tahoma ; color: darkgray ; font-size: 11pt ; font-weight: bold }"
		text << ".ValueOK { font-family: arial, sans serif, tahoma ; color: slategray ; font-size: 11pt ; font-weight: bold }"
	else	
		text << ".ValueOK { color: slategray ; font-size: 11pt ; font-weight: bold }"
		text << ".Label { color: gray ; font-size: 11pt }"
	end	
	text << ".ValueExpired { color: orange ; font-size: 11pt ; font-weight: bold }"
	text << ".CheckMessage { background-color: green ; color: white ; font-size: 12pt ; font-weight: bold ; position: absolute ; #{@message_dim} }"
	text << "</style>"
	
	#Compute the license status
	txstatus, bclass = license_format_status
	hstatus = format_span(txstatus, bclass, "ID_STATUS")

	#Title and License status
	hscf = format_span "U", "SCFU", nil, "Sketchucation"
	title = @plugin_name
	hversion = format_span SCFLicense.visual_version + ' - ' + SCFLibrary.version() + ' - ' + "SU#{Sketchup.version.to_i}", "Version"
	htit = format_span title, "TitDialog"
	but_help = format_button("ButtonHelp", text_of(:txt_help) + '...', "H_Button", text_of(:tip_goto_page, SCFLicense.get_url_support))
	text << "<div><table width='100%' cellpadding='0' cellspacing='0'><tr>"
	text << "<td width='#{@wid_U}px' align='left' valign='top' style='padding-bottom: 2px'>#{hscf}</td>"
	text << "<td width='190px' align='left' valign='bottom' style='padding-bottom: 0px'>&nbsp;#{hversion}</td>"
	text << "<td align='left'>#{htit}<br>#{hstatus}</td>"
	text << "<td align='right'>#{but_help}</td>"
	text << "</tr></table></div><br>"
	
	#Plugin Information
	text << dialog_license_format_license_info(@hsh_license_cur)
	
	#Notification Message (for Internet connection)
	hmsg = format_span text_of(:msg_connected), "MsgNote"
	text << "<div><table width='100%' cellpadding='0' cellspacing='3px'>"
	text << "<tr align='left'><td>#{hmsg}</span><td><tr>"
	text << "</table></div>"
	
	#Buttons
	but_history = format_button("ButtonHistory", text_of(:txt_history), "Button", text_of(:tip_history_button))
	bclass_purchase = "Button"
	but_purchase = format_button("ButtonPurchase", text_of(:txt_purchase) + '...', bclass_purchase, text_of(:tip_goto_page, url_purchase))
	bclass_validate = (@hsh_license_cur) ? "Button" : "Button Y_Button"
	but_validate = format_button("ButtonValidate", text_of(:txt_validate), bclass_validate)
	bclass = (@hsh_license_cur) ? "Button" : "Button ButHidden"
	but_release = format_button("ButtonRelease", text_of(:txt_release), bclass)
	but_seat = format_button("ButtonSeat", text_of(:txt_seat), bclass, text_of(:tip_seat_button))
	but_close = format_button("ButtonClose", text_of(:txt_close), "Button R_Button")
	text << "<table width='100%' cellpadding='0' cellspacing='3px'><tr>"
	text << "<td align='left'>#{but_history}&nbsp;#{but_seat}</td>"
	text << "<td align='center'>#{but_purchase}&nbsp;#{but_validate}&nbsp;#{but_release}</td>"
	text << "<td align='right'>#{but_close}</td>"
	text << "</tr></table>"
	
	#Format the section for the message on Post for validation on Sketchucation
	text << "<div id='ID_msg_div' style='display: none' class='CheckMessage'>"
	text << "<table width='100%' height='100%'>"
	text << "<tr><td align='center' style='vertical-align:middle'>#{safe_text(text_of(:msg_check))}</td></tr>"
	text << "</table></div>"
	
	#End of body
	text << "</BODY>"

	text
end

#DIALOG LICENSE HTML: Format the status for the license
def license_format_status
	if @hsh_license_cur
		if license_expired?
			bclass = 'Expired'
			text = text_of(:txt_expired)
		else
			bclass = 'Valid'
			text = text_of(:txt_ok)
			texpire = license_expiration_date
			if texpire
				sdate = nice_expiration(texpire)
				text += "  [#{text_of(:txt_expires_on)} #{sdate}]"
			end
		end	
	else
		bclass = 'Undef'
		text = text_of(:txt_no)
		hval = format_span(text_of(:txt_no), "Undef", "ID_STATUS")
	end
	[text, bclass]
end

#DIALOG LICENSE HTML: Format the HTML for the license information
def dialog_license_format_license_info(hsh)
	hsh = Hash.new "" unless hsh
	vclass = (license_expired?) ? "ValueExpired" : "ValueOK"
	val_email = (hsh[:email] =~ /fredosix@hotmail.com/i) ? 'email of Fredo' : hsh[:email]
	
	#Span for information (Labels and fields)
	label_type = format_span text_of(:txt_license_type), 'Label'
	value_type = format_span hsh[:type], vclass, "ID_TYPE"
	
	label_email = format_span text_of(:txt_email), 'Label'
	value_email = format_span val_email, vclass, "ID_EMAIL"
	
	label_user = format_span text_of(:txt_scf_user), 'Label'
	value_user = format_span hsh[:username], vclass, "ID_USER"
	
	label_lid = format_span text_of(:txt_license_id), 'Label'
	value_lid = format_span "#{hsh[:lid]}", vclass, "ID_LID"
	
	label_date = format_span text_of(:txt_date_purchase), 'Label'
	value_date = format_span nice_date(hsh[:date]), vclass, "ID_DATE"

	label_hwid = format_span text_of(:txt_hwid), 'Label'
	value_hwid = format_span hsh[:hw], vclass, "ID_HWID"
	
	label_duration = format_span text_of(:txt_duration), 'Label'
	t1, t2 = format_duration(hsh)
	t = t1 + ((t2) ? ' ' + t2 : '')
	value_duration = format_span(t, vclass, "ID_DURATION")
	
	label_seat = format_span text_of(:txt_seats), 'Label'
	value_seat = format_span format_seats(hsh), vclass, "ID_SEATS"
	
	#Style for columns
	style_label = "width='50%'"
	style_label_left = "width='120px'"
	style_label_left = ''
	style_value_left = "width='150px'"
	style_value_left = ''
	style_label_right = "width='200px' align='right'"
	style_label_right = "align='right'"
	style_value_right = ''
	style_value_space = "width='30px'"
	
	#Formatting the table for display
	text = ""
	text << "<div width='100%' cellpadding='2px' style='border: solid 1px gainsboro'>"
	#text << "<div width='auto' cellpadding='2px'>"
	###text << "<table width='100%' cellpadding='2px'>"
	text << "<table width='auto' cellpadding='2px'>"
	
	#Specific distribution
	if @distributor_type
		text << "<tr><td #{style_label_left}>#{label_lid}</td>"
		text << "<td #{style_value_left}>#{value_lid}</td>"
		text << "<td #{style_value_space}></td>"
		text << "<td #{style_label_right}></td>"
		text << "<td #{style_value_right}></td></tr>"

	#Regular distribution by Sketchucation
	else
		text << "<tr><td #{style_label_left}>#{label_user}</td>"
		text << "<td #{style_value_left}>#{value_user}</td>"
		text << "<td #{style_value_space}></td>"
		text << "<td #{style_label_right}>#{label_email}</td>"
		text << "<td #{style_value_right}>#{value_email}</td></tr>"

		text << "<tr><td #{style_label_left}>#{label_lid}</td>"
		text << "<td #{style_value_left}>#{value_lid}</td>"
		text << "<td #{style_value_space}></td>"
		text << "<td #{style_label_right}>#{label_date}</td>"
		text << "<td #{style_value_right}>#{value_date}</td></tr>"
	end
	
	text << "<tr><td #{style_label_left}>#{label_type}</td>"
	text << "<td #{style_value_left}>#{value_type}</td>"
	text << "<td #{style_value_space}></td>"
	text << "<td #{style_label_right}>#{label_duration}</td>"
	text << "<td #{style_value_right}>#{value_duration}</td></tr>"
	
	text << "<tr><td #{style_label_left}>#{label_hwid}</td>"
	text << "<td #{style_value_left}>#{value_hwid}</td>"
	text << "<td #{style_value_space}></td>"
	text << "<td #{style_label_right}>#{label_seat}</td>"
	text << "<td #{style_value_right}>#{value_seat}</td></tr>"
	

	text << "</table></div>"
	text
end

#----------------------------------------------------
#DIALOG LICENSE ACTION: Management of Actions and Updates
#----------------------------------------------------

#DIALOG LICENSE ACTION: Call back for Statistics Dialog
def dialog_license_callback(event, *args)
	#puts "\nEVENT = #{event} #{args}"
	case event
		
	when /wonload/i
		@wdlg_lic.execute_script "resize_at_load() ;"
		UI.start_timer(0.5) { @wonloaded_lic += 1}

	when /resize_at_load/i
		dialog_resize_at_load(@wdlg_lic, event)
		
	#Error in the HTTPRequest process	
	when /\AFetch_Error/
		UI.messagebox text_of(:msg_error_fetch)	unless @fetch_id == "Seat_Result"
		
	#Answer from Skecthucation for Validation
	when /\AValidate_Result/
		validation_process_response(event.split(";;")[1])
		
	#Answer from Skecthucation for Release
	when /\ARelease_Result/
		release_process_response(event.split(";;")[1])
		
	when /\ASeat_Result/
		seat_process_response(event.split(";;")[1])
		
	#Command buttons
	when /ButtonPurchase/i
		license_purchase(@plugin_name)
	when /ButtonRelease/i
		release_prepare_request
	when /ButtonValidate/i
		validation_prepare_request
	when /ButtonHistory/i
		dialog_history_launch
	when /ButtonClose/i
		@wdlg_lic.close if @wdlg_lic
	when /ButtonHelp/i
		UI.openURL SCFLicense.get_url_support
	when /ButtonSeat/
		seat_prepare_request
	end
end

#DIALOG LICENSE ACTION: Update the fields with the License information
def dialog_license_update_license_fields
	return unless @wdlg_lic
	hsh = @hsh_license_cur
	if hsh
		texpire = license_expiration_date(hsh)
		expired = (texpire && Time.now > texpire)
	else
		hsh = Hash.new ""
		expired = false
	end	

	t1, t2 = format_duration(hsh)
	tdur = t1 + ((t2) ? ' ' + t2 : '')
	val_email = (hsh[:email] =~ /fredosix@hotmail.com/i) ? 'email of Fredo' : hsh[:email]
	
	#Updating the fields
	script = ""
	script << "document.getElementById(\"ID_LID\").innerHTML = '#{hsh[:lid]}' ; "
	script << "document.getElementById(\"ID_DURATION\").innerHTML = '#{tdur}' ; "
	script << "document.getElementById(\"ID_SEATS\").innerHTML = '#{format_seats(hsh)}' ; "
	script << "document.getElementById(\"ID_TYPE\").innerHTML = '#{hsh[:type]}' ; "
	script << "document.getElementById(\"ID_HWID\").innerHTML = '#{hsh[:hw]}' ; "
	unless @distributor_type
		script << "document.getElementById(\"ID_DATE\").innerHTML = '#{nice_date(hsh[:date])}' ; "
		script << "document.getElementById(\"ID_EMAIL\").innerHTML = '#{val_email}' ; "
		script << "document.getElementById(\"ID_USER\").innerHTML = '#{hsh[:username]}' ; "
	end
	
	#Updating the class for the field
	vclass = (license_expired?) ? "ValueExpired" : "ValueOK"
	["ID_LID", "ID_DURATION", "ID_SEATS", "ID_TYPE", 'ID_HWID'].each do |id_field|
		script << "document.getElementById(\"#{id_field}\").className = '#{vclass}' ; "	
	end
	unless @distributor_type
		["ID_EMAIL", "ID_USER", "ID_DATE"].each do |id_field|
			script << "document.getElementById(\"#{id_field}\").className = '#{vclass}' ; "	
		end
	end
	
	#Updating the license status
	text, bclass = license_format_status
	script << "document.getElementById(\"ID_STATUS\").innerHTML = '#{text}' ; "
	script << "document.getElementById(\"ID_STATUS\").className = '#{bclass}' ; "
	
	#Updating the buttons
	bclass_validate = (@hsh_license_cur) ? 'Button' : 'Button Y_Button'
	bclass_purchase = (hsh.empty? || expired) ? 'Button' : 'Button ButHidden'
	bclass_other = (hsh.empty?) ? 'ButHidden' : 'Button'
	script << "document.getElementById(\"ButtonValidate\").className = '#{bclass_validate}' ; "
	script << "document.getElementById(\"ButtonRelease\").className = '#{bclass_other}' ; "
	script << "document.getElementById(\"ButtonSeat\").className = '#{bclass_other}' ; "

	@wdlg_lic.execute_script script
end

#DIALOG LICENSE ACTION: Post a XML HTTP Request as a URL to SCF (this will generate a call back with event <fetch_id>)
def dialog_license_post_to_SCF(fetch_id, encrypted_key)
	#puts "\nPOST #{fetch_id} - key = #{encrypted_key}"
	case fetch_id 
	when "Validate_Result"
		action = :validate
	when "Release_Result"	
		action = :release
	when "Seat_Result"	
		action = :seat
	end	
	@fetch_id = fetch_id
	url = "https://s.sketchucation.com/plugin-license.php"
	vnum = (SCFLicense.visual_version.to_f * 10).round
	#puts "\nPOST to SCF #{url}"
	#puts "fetch id: #{fetch_id}"
	#puts "action: #{action} "
	#puts "data: #{encrypted_key} "
	#puts "vnum: #{vnum} "
	@wdlg_lic.execute_script "xfetch_post(\"#{url}\", \"action=#{action}&data=#{encrypted_key}&ac=#{vnum}\", \"#{fetch_id}\")"	
end

#----------------------------------------------------
# DIALOG LICENSE VALIDATION: Validation Sequence
#----------------------------------------------------
	
#DIALOG LICENSE VALIDATION: Initializing the Validation sequence
def validation_prepare_request
	#Creating a Signature file if it does not exist
	signature_file_path = signature_path
	unless FileTest.exist?(signature_file_path)
		status = ::SCFLibrary.signature_create(signature_file_path)
		if status =~ /ERROR_(.*)/
			return log_box($1.intern, status)
		end	
	end	

	#Selecting the SCF License file by invoking the File Open panel
	path = license_purchase_directory(@plugin_name)
	wild = "*#{@plugin_name}*.scflicense"
	filter = "#{wild}|#{wild}|ALL|*.*||"
	license_SCF_file_path = UI.openpanel text_of(:tit_open_panel, @plugin_name), path, filter
	return nil unless license_SCF_file_path
	return log_box(:license_file_not_exist, license_SCF_file_path) unless FileTest.exist?(license_SCF_file_path)
	license_purchase_directory(@plugin_name, File.dirname(license_SCF_file_path)) 
	
	#Calculating the encrypted key to be posted to SCF
	encrypted_key = ::SCFLibrary.validate_posting_key(@plugin_name, signature_file_path, license_SCF_file_path, Sketchup.version)	
	
	#Error in the SCF License detected locally	
	if encrypted_key =~ /\AERROR_/
		return validation_process_response_message(:validate_request_error, encrypted_key)
	end	

	#Formatting a XML HTTP request to SCF 
	dialog_license_post_to_SCF("Validate_Result", encrypted_key)
end

#DIALOG LICENSE VALIDATION: Processing the answer from SCF for a Validation
# Note: <encrypted_key_from_SCF> contains 
#        - either a valid encrypted message. If so, it is passed to the Binary module
#        - or an Error message beginning with ERROR:
def validation_process_response(encrypted_key_from_SCF)
	#License validation failed on SCF server side
	#puts "validate response = #{encrypted_key_from_SCF}"
	if encrypted_key_from_SCF =~ /\AERROR\:(.+)/
		return validation_process_response_message(:validate_response_error, $1)
	end

	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)

	#Decrypt the License key returned from SCF
	text_hsh = ::SCFLibrary.validate_process_response(@plugin_name, signature_file_path, encrypted_key_from_SCF, local_license_file_path)
	#puts "valid resp text hsh = #{text_hsh.inspect}"
	if text_hsh.empty? || text_hsh =~ /\AERROR/
		return validation_process_response_message(:validate_response_error, text_hsh)
	end	
	#puts "VALIDATE: HSH returned from SCF = #{text_hsh}"
	hsh_seat = seat_encode_hsh(text_hsh)
	#puts "VALDIATE: HSH returned from SCF = #{text_hsh} - hsh_seta = #{hsh_seat}"
	
	#Updating the license information
	@hsh_license_cur = license_information
	return log_box(:license_information, @error_license_information) unless @hsh_license_cur
	
	#puts "\nINFO VALIDATE = #{@hsh_license_cur}"
	@hsh_license_cur.update hsh_seat
	dialog_license_update_license_fields
	
	#Logging successful validation
	log :validate_success
end

#DIALOG LICENSE VALIDATION: Display of the error message after a Validation
def validation_process_response_message(event, text_error)
	#Special messages
	msg = code = nil
	case text_error
	when /A0C/
		msg = text_of(:error_A0C_1) + "\n\n" + text_of(:error_open_signature_folder)
		code = :folder
	when /F07/
		msg = text_of(:error_F07_1) + "\n\n" + text_of(:error_F07_2) + "\n\n" + text_of(:error_open_mylicenses)
		code = :mylicense
	when /F09/
		msg = text_of(:error_F09_1) + "\n\n" + text_of(:error_F09_2) + "\n\n" + text_of(:error_open_mylicences)
		code = :mylicense
	when /A04/
		msg = text_of(:error_A04_1) + "\n\n" + text_of(:error_A04_2) + "\n\n" + text_of(:error_open_signature_folder)
		code = :folder
	when /B03/
		comp_name = ENV['COMPUTERNAME']
		scomp_name = (comp_name) ? " [#{comp_name}]" : ''
		msg = text_of(:error_B03_1) + "\n\n" + text_of(:error_B03_2) + scomp_name + "\n\n" + text_of(:error_B03_3)
	end
	
	#Error with no special treatment
	return log_box(event, text_error) unless msg
	
	#Logging the event in the history log
	log(event, text_error)
	
	#Displaying the message box
	msg = log_build_message(event, text_error) + "\n\n" + msg
	return UI.messagebox(msg) unless code
	status = UI.messagebox(msg, MB_YESNO)
	return if status == IDNO
	
	#Extra actions
	case code
	when :folder
		open_file_location
	when :mylicense
		UI.openURL SCFLicense.get_url_mylicenses
	end
end

#----------------------------------------------------
# DIALOG LICENSE RELEASE: Validation Sequence
#----------------------------------------------------

#DIALOG LICENSE RELEASE: Initializing the Release sequence
def release_prepare_request
	#Confirmation for release
	return if UI.messagebox(text_of(:msg_release_confirm, @plugin_name), MB_YESNO) == IDNO

	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)
	return nil unless FileTest.exist?(local_license_file_path)

	#Calculating the encrypted key to be posted to SCF
	@shadow_path = nil
	#puts "\nRelease request - calling SCFLibrary.release_posting_key"
	#puts "Plugin name = #{@plugin_name}"
	#puts "signature_file_path = #{signature_file_path}"
	#puts "local_license_file_path = #{local_license_file_path}"
	#puts "SU version = #{Sketchup.version}"
	
	info_release = ::SCFLibrary.release_posting_key(@plugin_name, signature_file_path, local_license_file_path, Sketchup.version)	
	
	#puts "\nResponse from SCFLibrary.release_posting_key"
	#puts "Info release = #{info_release}"
	
	#Error in the SCF License detected locally	
	return log_box(:release_request_error, info_release) if info_release =~ /ERROR_/

	#Getting the shadow path
	if RUBY_PLATFORM =~ /darwin/i
		encrypted_key = info_release
		@shadow_path = ''
	else	
		@shadow_path, encrypted_key = info_release.split(';;')
	end	
	
	#Formatting a XML HTTP request to SCF 
	dialog_license_post_to_SCF("Release_Result", encrypted_key)
end

#DIALOG LICENSE RELEASE: Processing the answer from SCF for a Release
def release_process_response(encrypted_key_from_SCF)
	#puts "\nRelease response #{encrypted_key_from_SCF}"
	
	#License validation failed on SCF server side
	if encrypted_key_from_SCF =~ /\AERROR\:(.+)/
		return log_box(:release_response_error, encrypted_key_from_SCF)
	end

	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)

	#Decrypt the License key returned from SCF
	#puts "response shadow = #{@shadow_path}"
	#puts "response local = #{local_license_file_path}"
	status = ::SCFLibrary.release_process_response(encrypted_key_from_SCF, @shadow_path, local_license_file_path)
	#puts "RELEASE: HSH returned from SCF = #{status.inspect}"
	
	#Probleme in validating the license
	unless status == "OK"
		return log_box(:release_response_error, status)
	end	
	
	#Removing the local license file
	licfile_local_license_remove(@plugin_name)
	
	#Logging successful validation
	log :release_success
	
	#Updating the license information
	@hsh_license_cur = nil
	dialog_license_update_license_fields	
end

#----------------------------------------------------
# DIALOG LICENSE SEAT: Seat Info sequence
#----------------------------------------------------

#DIALOG LICENSE SEAT: Initializing the Seat Info sequence
def seat_prepare_request
	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)
	return nil unless FileTest.exist?(local_license_file_path)

	#Calculating the encrypted key to be posted to SCF
	encrypted_key = ::SCFLibrary.validate_posting_key(@plugin_name, signature_file_path, local_license_file_path, Sketchup.version)	
	#puts "encrypted key = #{encrypted_key}"
	
	#Error in the SCF License detected locally	
	return log_box(:seat_request_error, encrypted_key) if encrypted_key =~ /ERROR_/
	
	#Formatting a XML HTTP request to SCF 
	dialog_license_post_to_SCF("Seat_Result", encrypted_key)
end

#DIALOG LICENSE SEAT: Processing the answer from SCF for a Seat Info request
def seat_process_response(encrypted_key_from_SCF)
	#License validation failed on SCF server side
	if encrypted_key_from_SCF =~ /\AERROR\:/
		return log_box(:seat_response_error, encrypted_key_from_SCF)
	end

	#Getting the signature file and local license file
	signature_file_path = signature_path
	return nil unless FileTest.exist?(signature_file_path)
	local_license_file_path = licfile_local_license_path(@plugin_name)

	#Decrypt the License key returned from SCF
	#puts "SEAT encrypted = #{encrypted_key_from_SCF}"
	text_hsh = ::SCFLibrary.validate_process_response(@plugin_name, signature_file_path, encrypted_key_from_SCF, local_license_file_path)
	hsh_seat = seat_encode_hsh(text_hsh)
	#puts "SEAT INFO: HSH returned from SCF = #{text_hsh} - hsh_seta = #{hsh_seat}"
	
	#Updating the license information
	@hsh_license_cur.update hsh_seat
	dialog_license_update_license_fields	
end

#--------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------------------------------------
# DIALOG HISTORY: Display and manage the Dialog box for History
#--------------------------------------------------------------------------------------------------------------			 
#--------------------------------------------------------------------------------------------------------------			 

#----------------------------------------------------
# DIALOG HISTORY INIT: Dialog box initialization
#----------------------------------------------------

#DIALOG HISTORY INIT: Initialization
def dialog_history_launch	
	#Initialization
	title = encode_to_ruby(text_of(:txt_history_title))
	dlgkey = "SCFLicense History Dialog"	#Unique key for dialog box
	dialog_color_init

	#Initial position and size
	@table_history_height = 300
	xpos = 300
	ypos = 100
	sx = 1000
	sy = 160 + @table_history_height

	#Creating the dialog box
	@wdlg_his = UI::WebDialog.new title, false, dlgkey, sx, sy, xpos, ypos, true
	@wdlg_his.add_action_callback("top_callback") { |dialog, params| dialog_history_callback(params) }
	@wdlg_his.set_background_color @dlg_background_color
	@wdlg_his.navigation_buttons_enabled = false if defined?(@wdlg_his.navigation_buttons_enabled)
	@wdlg_his.min_width = 900
	@wdlg_his.min_height = 250
	
	#Setting the position only once
	lst_info = Sketchup.read_default("SCF", dlgkey)
	#unless lst_info && !lst_info.empty?
		@wdlg_his.set_position xpos, ypos
		@wdlg_his.set_size sx, sy
		Sketchup.write_default("SCF", dlgkey, [xpos, ypos, sx, sy])
	#end	
	
	#Building the initial HTML
	@wdlg_his.set_html dialog_history_format_html
	
	#Showing the dialog box
	@wdlg_his.show_modal
end

#----------------------------------------------------------
# DIALOG HISTORY HTML: HTML Formatting of the dialog box
#----------------------------------------------------------

#DIALOG HISTORY HTML: formatting for the whole dilaog box
def dialog_history_format_html
	#HTML Headers
	text = ""
	text << %q(<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/strict.dtd">)
	text << %q(<META http-equiv='Content-Type' Content='text/html; charset=UTF-8'> )
	text << %q(<META http-equiv='Content-Script-Type' content='text/javascript'>)
	
	#Scripts
	text << "<SCRIPT>"
	text << javascript_action
	text << javascript_capture_key
	text << javascript_resizing
	text << "</SCRIPT>"
	text << "<BODY onkeyup='CaptureKeyUp()' onkeydown='CaptureKeyDown()'>"
	text << "<BODY onload='action(\"wonload\")'>"
	text << "<BODY onresize='action(\"onresize_manual\")'>"

	#CSS styles
	text << "<style type='text/css'>"
	text << ".col_style { color: black ; font-size: 9pt }"

	text << format_common_style
	
	text << "</style>"
	
	#Title for History
	hscf = format_span "U", "SCFU", "Sketchucation"	
	hversion = format_span SCFLicense.visual_version + ' - ' + SCFLibrary.version() + ' - ' + "SU#{Sketchup.version.to_i}", "Version"
	title = text_of(:txt_history_title) + " - " + @plugin_name
	htit = format_span title, "TitDialog"
	but_help = format_button("ButtonHelp", text_of(:txt_help) + '...', "H_Button", text_of(:tip_goto_page, SCFLicense.get_url_support))
	text << "<div><table width='100%' cellpadding='0' cellspacing='0'><tr>"
	text << "<td width='#{@wid_U}px' align='left' valign='top' style='padding-bottom: 3px'>#{hscf}</td>"
	text << "<td width='190px' align='left' valign='bottom' style='padding-bottom: 0px'>&nbsp;#{hversion}</td>"
	text << "<td align='center'>#{htit}</td>"
	text << "<td align='right'>#{but_help}</td>"
	text << "</tr></table></div><br>"
	
	#History table
	text_header, text_body = dialog_history_format_html_table
	text << "<div OnSelectStart='return false;' width='100%' style='padding: 0px ; border: 2px solid gray ; border-bottom: 1px solid gray'>"
	text << text_header
	text << "</div>"
	text << "<div ID='DIV_Master' width='100%' style='padding: 0px ; border: 2px solid gray ; border-top: 0px ;"
	text << " height: #{@table_history_height}px ; position: relative ; overflow-y: auto'>"
	text << text_body
	text << "</div>"
	
	#Buttons
	but_location = format_button("ButtonLocation", "#{text_of(:txt_file_location)}...", "Button")
	but_close = format_button("ButtonClose", text_of(:txt_close), "Button R_Button")
	text << "<table width='100%' cellpadding='0' cellspacing='3px'><tr>"
	text << "<td align='left'>#{but_location}</td>"
	text << "<td align='right'>#{but_close}</td>"
	text << "</tr></table>"
	
	#End of body
	text << "</BODY>"

	text
end

#DIALOG HISTORY HTML: formatting for the whole dilaog box
def dialog_history_format_html_table
	#Reading the Log files
	logfile = log_path
	lines = (FileTest.exist?(logfile)) ? IO.readlines(logfile) : []
	
	#Filtering the lines for the plugin
	lst_columns = []
	lines.reverse.each do |line|
		columns = line.strip.split(";;;")
		plugin = columns[1]
		next unless plugin == @plugin_name || plugin == "SCF License"
		lst_columns.push [columns[0], columns[2], columns[3]]
	end
	
	#Definition for columns
	lst_col = []
	lst_col.push({ :title => "Date", :width => '120px' })
	lst_col.push({ :title => "Event Code", :width => '180px' })
	lst_col.push({ :title => "Description" })
	
	#Table header
	color_header = 'lightblue'
	text_header = "<table width='100%' cellspacing='0px' cellpadding='2px'>"
	text_header << "<tr style='background-color: #{color_header}'>"
	lst_col.each do |hcol|
		hwid = (hcol[:width]) ? "width='#{hcol[:width]}'" : ""
		hspan = format_span hcol[:title], "header_style"
		text_header << "<td #{hwid} align='center' style='border: solid 1px gray'>#{hspan}</td>"
	end	
	text_header << "</tr></table>"
	
	#Filling the table
	text_body = "<table width='100%' cellspacing='0px' cellpadding='2px'>"
	lst_columns.each_with_index do |columns, irow|
		#Color for the line
		event = columns[2]
		case event
		when /error/i
			color = @color_no
		when /success/
			color = @color_ok
		else
			color = @color_neutral
		end	
		
		#Begin of row
		text_body << "<tr style='background-color: #{color}'>"
		
		#Field cells
		lst_col.each_with_index do |hcol, i|
			hwid = (hcol[:width]) ? "width='#{hcol[:width]}'" : ""
			hspan = format_span columns[i], "col_style"
			text_body << "<td #{hwid} style='border: solid 1px gray'>#{hspan}</td>"
		end	
				
		#End of row
		text_body << "</tr>"
	end	
	text_body << "</table>"
	
	#Returning the table html
	[text_header, text_body]
end

#----------------------------------------------------
#DIALOG HISTORY ACTION: Management of Actions and Updates
#----------------------------------------------------

#DIALOG HISTORY ACTION: Call back for Statistics Dialog
def dialog_history_callback(event, *args)
	case event
		
	when /wonload/i
		@wonloading_his = true
		if @wonloaded_his == 0
			@wdlg_his.execute_script "resize_at_load() ;"
		end	
		UI.start_timer(0.5) { @wonloaded_his += 1 ; @wonloading_his = false}

	when /resize_at_load/i
		dialog_resize_at_load(@wdlg_his, event)
	
	when /resize_manual_done/
		@table_history_height = event.split(';;')[1].to_i
		
	when /resize_manual/i
		@wdlg_his.execute_script "resize_manual('history') ;" if !@wonloading_his && @wonloaded_his > 0
		
	#Command buttons
	when /ButtonClose/i
		@wdlg_his.close
	when /ButtonHelp/i
		UI.openURL SCFLicense.get_url_support
	when /ButtonLocation/i
		open_file_location
	end
end

#--------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------------------------------------
# DIALOG GLOBAL: Display and manage the Dialog box for Global Status
#--------------------------------------------------------------------------------------------------------------			 
#--------------------------------------------------------------------------------------------------------------			 

#----------------------------------------------------
# DIALOG GLOBAL INIT: Dialog box initialization
#----------------------------------------------------

#DIALOG GLOBAL INIT: Initialization
def dialog_global_launch
	#Initialization
	title = encode_to_ruby(text_of(:txt_global_status))
	dlgkey = "SCFLicense Global Dialog"	#Unique key for dialog box
	dialog_color_init

	#Initial position and size
	@table_global_height = 200
	xpos = 300
	ypos = 100
	sx = 1100
	sy = 160 + @table_global_height

	#Creating the dialog box
	@wdlg_glo = UI::WebDialog.new title, false, dlgkey, sx, sy, xpos, ypos, true
	@wdlg_glo.add_action_callback("top_callback") { |dialog, params| dialog_global_callback(params) }
	@wdlg_glo.set_background_color @dlg_background_color
	@wdlg_glo.navigation_buttons_enabled = false if defined?(@wdlg_glo.navigation_buttons_enabled)
	@wdlg_glo.set_on_close { dialog_global_on_close() }
	@wdlg_glo.min_width = 950
	@wdlg_glo.min_height = 250
	
	#Setting the position only once
	lst_info = Sketchup.read_default("SCF", dlgkey)
	unless lst_info && !lst_info.empty?
		@wdlg_glo.set_position xpos, ypos
		@wdlg_glo.set_size sx, sy
		Sketchup.write_default("SCF", dlgkey, [xpos, ypos, sx, sy])
	end	
	
	#Building the initial HTML
	@wdlg_glo.set_html dialog_global_format_html
	
	#Storing the handle
	SCFLicenseTop.set_dialog_global(@wdlg_glo)
	
	#Showing the dialog box
	(RUBY_PLATFORM =~ /darwin/i) ? @wdlg_glo.show_modal : @wdlg_glo.show
end

#DIALOG GLOBAL INIT: Close of the dialog box
def dialog_global_on_close
	@wdlg_glo = nil
end

#----------------------------------------------------------
# DIALOG GLOBAL HTML: HTML Formatting of the dialog box
#----------------------------------------------------------

#DIALOG GLOBAL HTML: formatting for the whole dilaog box
def dialog_global_format_html
	#HTML Headers
	text = ""
	text << %q(<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/strict.dtd">)
	text << %q(<META http-equiv='Content-Type' Content='text/html; charset=UTF-8'> )
	text << %q(<META http-equiv='Content-Script-Type' content='text/javascript'>)
	
	#Scripts
	text << "<SCRIPT>"
	text << javascript_action
	text << javascript_capture_key
	text << javascript_resizing
	text << "</SCRIPT>"
	text << "<BODY onkeyup='CaptureKeyUp()' onkeydown='CaptureKeyDown()'>"
	text << "<BODY onload='action(\"wonload\")'>"
	text << "<BODY onresize='action(\"onresize_manual\")'>"

	#CSS styles
	text << "<style type='text/css'>"
	text << ".col_style { color: black ; font-size: 10pt }"
	text << ".col_style2 { color: red ; font-size: 9pt }"
	text << ".col_ref { color: green ; font-size: 10pt ; cursor: pointer ; text-decoration: underline }"
	text << ".col_empty { color: green ; font-size: 10pt ; cursor: pointer }"

	text << format_common_style

	text << "</style>"
	
	#Title for Global Status
	hscf = format_span "U", "SCFU", "Sketchucation"
	hversion = format_span SCFLicense.visual_version + ' - ' + SCFLibrary.version() + ' - ' + "SU#{Sketchup.version.to_i}", "Version"
	title = text_of(:txt_global_status)
	htit = format_span title, "TitDialog"
	text << "<div><table width='100%' cellpadding='0' cellspacing='0'><tr>"
	text << "<td width='#{@wid_U}px' align='left' valign='top' style='padding-bottom: 3px'>#{hscf}</td>"
	text << "<td width='190px' align='left' valign='bottom' style='padding-bottom: 0px'>&nbsp;#{hversion}</td>"
	text << "<td align='left'>#{htit}</td>"
	text << "</tr></table></div><br>"
	
	#Global Status table
	text_header, text_body = dialog_global_format_html_table
	text << "<div OnSelectStart='return false;' width='100%' style='padding: 0px ; border: 2px solid gray ; border-bottom: 1px solid gray'>"
	text << text_header
	text << "</div>"
	text << "<div ID='DIV_Master' width='100%' style='padding: 0px ; border: 2px solid gray ; border-top: 0px ;"
	text << " height: #{@table_global_height}px ; position: relative ; overflow-y: auto'>"
	text << text_body
	text << "</div>"
	
	#Buttons
	distributor_name = @distributor_name
	distributor_name = 'Sketchucation' unless distributor_name
	txt_mylicenses = text_of(:txt_mylicenses).sub('%1', 'Sketchucation')
	txt_mylicenses_distrib = text_of(:txt_mylicenses).sub('%1', distributor_name)
	but_location = format_button("ButtonLocation", "#{text_of(:txt_file_location)}...", 'Button')
	but_close = format_button("ButtonClose", text_of(:txt_close), "Button R_Button")
	but_help = format_button("ButtonHelp", text_of(:txt_help) + '...', "H_Button", text_of(:tip_goto_page, SCFLicense.get_url_support))
	but_mylicenses = format_button("ButtonMyLicenses", txt_mylicenses + '...', "Button N_Button")
	but_mylicenses_distrib = format_button("ButtonMyLicensesDistrib", txt_mylicenses_distrib + '...', "Button Y_Button")
	but_mylicenses_distrib = '' unless SCFLicense.get_url_mylicenses
	text << "<table width='100%' cellpadding='0' cellspacing='3px'><tr>"
	text << "<td align='left'>#{but_location}&nbsp;&nbsp;#{but_mylicenses}&nbsp;&nbsp;#{but_mylicenses_distrib}</td>"
	text << "<td align='center'>#{but_help}</td>"
	text << "<td align='right'>#{but_close}</td>"
	text << "</tr></table>"
	
	#End of body
	text << "</BODY>"

	text
end

#DIALOG GLOBAL HTML: formatting for the whole dilaog box
def dialog_global_format_html_table
	#Getting the list of licensed plugins
	licdir = licfile_directory
	lst_plg = []
	Dir[File.join(licdir, "*.txt")].each do |f|
		lst_plg.push $1 if File.basename(f) =~ /\ASCFLicense_(.+)_this_computer.txt\Z/
	end

	hsh_plugin_info = {}
	lst_plg.each do |plugin_name|
		#puts "\nPLUGIN = #{plugin_name}"
		hsh_info = license_information(plugin_name)
		next unless hsh_info
		#puts "hsh = #{hsh_info}"
		hsh = { :plugin => plugin_name }
		hsh_plugin_info[plugin_name] = hsh.update(hsh_info)
	end
	
	#Getting the list of registered plugins
	method = :scf_license_register
	lst_reg = []
	ObjectSpace.each_object do |c|
		lst_reg.push(c.send(method)) if c.class == Module && c.respond_to?(method)
	end
	#puts "REGISTERED = #{lst_reg.length}"
	hsh_reg = {}
	lst_reg.each do |hsh|
		next unless hsh.class == Hash
		plugin = hsh[:plugin]
		next unless plugin
		ltip = [plugin]
		ltip.push hsh[:author] if hsh[:author]
		ltip.push hsh[:version] if hsh[:version]
		ltip.push hsh[:date] if hsh[:date]
		ltip.push hsh[:description] if hsh[:description]
		tip = ltip.join(" - ")
		hsh_plug = hsh_plugin_info[plugin]
		if hsh_plug
			hsh_plug[:tip] = tip
		else
			hsh_plugin_info[plugin] = { :plugin => plugin, :tip => tip }
		end	
	end
	
	#Sorting the array
	lst_first = []
	lst_second = []
	hsh_plugin_info.each do |plugin, hsh|
		if hsh[:date]
			lst_first.push [plugin, hsh]
		else
			lst_second.push [plugin, hsh]
		end
	end	
	lst_plugin_info = lst_first.sort + lst_second.sort
	
	#Definition for columns
	lst_col = []
	lst_col.push({ :symb => :plugin, :title => text_of_nosc(:txt_plugin), :width => '140px' })
	lst_col.push({ :symb => :type, :title => text_of_nosc(:txt_license_type), :width => '120px' })
	lst_col.push({ :symb => :lid, :title => text_of_nosc(:txt_license_id), :width => '80px', :align => :center })
	if !@distributor_type
		lst_col.push({ :symb => :username, :title => text_of_nosc(:txt_scf_user), :width => '150px' })
		lst_col.push({ :symb => :date, :title => text_of_nosc(:txt_date_purchase), :width => '130px' })
	end	
	lst_col.push({ :symb => :duration, :title => text_of_nosc(:txt_duration), :width => '150px' })
	lst_col.push({ :symb => :detail, :title => "&nbsp;", :width => '60px', :align => :center })
	lst_col.push({ :symb => :empty })
	
	#Table header
	text_header = "<div><table width='100%' cellspacing='0px' cellpadding='2px'>"
	text_header << "<tr>"
	lst_col.each do |hcol|
		symb = hcol[:symb]
		hwid = (hcol[:width]) ? "width='#{hcol[:width]}'" : ""
		halign = (hcol[:align]) ? "align='#{hcol[:align]}'" : ""
		hspan = (hcol[:title]) ? format_span(hcol[:title], "header_style") : ''
		hborder = (symb == :empty) ? "" : "border-left: 1px solid gray"
		text_header << "<td #{hwid} #{halign} style='background-color: lightblue ; border-bottom: 2px solid gray ; #{hborder}'>#{hspan}</td>"
	end	
	text_header << "</tr></table></div>"
	
	#Filling the table
	text_body = "<div><table width='100%' cellspacing='0px' cellpadding='2px'>"
	lst_plugin_info.each do |plugin, hsh|
		#Color for the line
		if license_expired?(hsh)
			color = @color_expired
		elsif hsh[:date]	
			color = @color_ok
		else
			color = @color_neutral
		end	
		
		#Begin of row
		text_body << "<tr style='background-color: #{color}'>"
		
		#Field cells
		lst_col.each do |hcol|
			symb = hcol[:symb]
			val2 = nil
			haction = nil
			bclass = "col_style"
			hborder = "border-bottom: 1px solid gray ; border-left: 1px solid gray"
			tip = nil
			case symb
			when :detail
				val = text_of(:txt_details)
				haction = "onClick='action(\"detail__#{hsh[:plugin]}\")'"
				bclass = "col_ref"
				hstyle = "cursor: pointer"
			when :empty
				val = "&nbsp;"
				haction = "onClick='action(\"detail__#{hsh[:plugin]}\")'"
				bclass = "col_empty"
				hstyle = "cursor: pointer"
				hborder = "border-bottom: 1px solid gray"
			when :duration
				if hsh[:date]
					t1, t2 = format_duration(hsh, true)
					val = t1
					val2 = t2
					tip, t2 = format_duration(hsh)
					tip << ' ' + t2 if t2
				else
					val = tip = ""
				end
			when :date
				val = nice_date(hsh[:date])
			when :plugin
				val = hsh[symb]
				tip = hsh[:tip]
			else
				val = hsh[symb]
			end	
			col_hstyle = "style='#{hborder} ; #{hstyle}'"
			htip = "title='#{tip}'"
			halign = (hcol[:align]) ? "align='#{hcol[:align]}'" : ""
			hwid = (hcol[:width]) ? "width='#{hcol[:width]}'" : ""
			hspan = format_span(val, bclass, nil, tip)
			hspan << "<br>" + format_span(val2, "col_style2", nil, tip) if val2			
			text_body << "<td #{hwid} #{htip} #{halign} #{haction} #{col_hstyle}>#{hspan}</td>"
		end	
				
		#End of row
		text_body << "</tr>"
	end	
	text_body << "</table></div>"
	
	#Returning the table html
	[text_header, text_body]
end

#----------------------------------------------------
#DIALOG GLOBAL ACTION: Management of Actions and Updates
#----------------------------------------------------

#DIALOG GLOBAL ACTION: Call back for Statistics Dialog
def dialog_global_callback(event, *args)
	case event
		
	when /wonload/i
		@wonloading_glo = true
		if @wonloaded_glo == 0
			@wdlg_glo.execute_script "resize_at_load() ;"
		end	
		UI.start_timer(0.5) { @wonloaded_glo += 1 ; @wonloading_glo = false }

	when /resize_at_load/i
		dialog_resize_at_load(@wdlg_glo, event)
		
	when /resize_manual_done/
		@table_global_height = event.split(';;')[1].to_i
		
	when /resize_manual/i
		@wdlg_glo.execute_script "resize_manual('global') ;" if !@wonloading_glo && @wonloaded_glo > 0
		
	#Command buttons
	when /ButtonClose/i
		@wdlg_glo.close
	when /ButtonHelp/i
		UI.openURL SCFLicense.get_url_support
	when 'ButtonMyLicenses'
		UI.openURL SCFLicense.get_url_mylicenses_sketchucation		
	when 'ButtonMyLicensesDistrib'
		UI.openURL SCFLicense.get_url_mylicenses		
	when /ButtonLocation/i
		open_file_location
	when /\Adetail__(.+)/i
		dialog_license_launch $1
	end
end

#--------------------------------------------------------------------------------------------------------------
#--------------------------------------------------------------------------------------------------------------
# DLG_UTIL: Common Utilities for dialog boxes
#--------------------------------------------------------------------------------------------------------------			 
#--------------------------------------------------------------------------------------------------------------			 

#----------------------------------------------------
# JAVASCRIPT: Javascript section
#----------------------------------------------------

#JAVASCRIPT: Javascript for action in callback
def javascript_action
	text = %Q~

	function action(msg) {	window.location = 'skp:top_callback@' + msg ; }
	
	~
	text
end

def javascript_resizing
	text = %Q~

	function resize_at_load() {
		var wbody = document.body.offsetWidth ;
		var hbody = document.body.offsetHeight ;
		var wwin = document.documentElement.clientWidth ;
		var hwin = document.documentElement.clientHeight ;
		action('resize_at_load;;' + wbody + ';;' + hbody + ';;' + wwin + ';;' + hwin) ;
	}
	
	function resize_manual(code) {
		var div_master = document.getElementById ('DIV_Master') ;
		var hdiv = div_master.offsetHeight
		var hbody = document.body.offsetHeight ;
		var hwin = window.innerHeight ;
		var new_h = hdiv + hwin - hbody -20 ;
		div_master.style.height = new_h.toString() + 'px' ;
		action('resize_manual_done;;' + new_h) ;
	}
	
	~
	text

end

#JAVASCRIPT: Javascript for capturing Return and Cancel
def javascript_capture_key
	text = %Q~
	
function CaptureKeyDown(e, event) { CaptureKey(e, "onKeyDown") }
function CaptureKeyUp(e, event) { CaptureKey(e, "onKeyUp") }	
function CaptureKey(e, event) {
	if (! e) e = window.event ;
	obj = (e.target) ? e.target : e.srcElement ;
	if (obj == null) return ;
	if ((event == "onKeyDown") && (e.keyCode == 13)) action("ButtonClose") ;
	if ((event == "onKeyUp") && (e.keyCode == 27)) action("ButtonClose") ;
	return true ;
}
	~
	text
end

#JAVASCRIPT: Specific scripts for Posting an XML HTTP Request
def javascript_posting
	text = %Q~

var $xt = null ;
if (window.XMLHttpRequest)
	$xt = new XMLHttpRequest() ;
else if (window.ActiveXObject) 
     $xt = new ActiveXObject('MSXML2.XMLHTTP.3.0');

var $requestTimer = 0 ;

function xfetch_post(url, data, fetch_id) {
	if (!$xt) return ;
	div = document.getElementById ('ID_msg_div') ;
	if (fetch_id != "Seat_Result") 
		div.style.display = "" ;
	$xt.open ("POST", url, true) ;

	$xt.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
	$xt.setRequestHeader("Content-length", data.length);
	$xt.setRequestHeader("Connection", "close"); 

	$requestTimer = setTimeout(function() { $xt.abort(); }, 10000) ;
 	if (!$xt) return ;
	$xt.onreadystatechange = function() { xfetch_checkData(fetch_id) } ;
	$xt.send(data) ;
}

function xfetch_checkData(fetch_id)
{
	state = $xt.readyState ;
	if (state != 4) {
		clearTimeout($requestTimer) ;
		return ;
	}
	
	//alert($xt.status);
	
	if ($xt.status != 200) {
		$xt.abort () ;
		div.style.display = "none" ;
		action("Fetch_Error") ;
		return ;
	}
	
	var text = $xt.responseText ;
	action(fetch_id + ";;" + text)
	div.style.display = "none" ;	
}

~
	text
end

#-------------------------------------------------
# DLG UTIL: Utility methods for dialog box
#-------------------------------------------------

#DLG UTIL: Initialize common colors
def dialog_color_init
	#@color_ok = 'palegreen'
	@color_ok = '#BDF4CB'
	@color_ok = '#DBFFE9'
	@color_no = '#FFF1F2'
	@color_neutral = 'white'	
	@color_expired = "#FFE099"
end

def dialog_dimension_init
	if RUBY_PLATFORM =~ /darwin/i
		@delta_w = 10
		@delta_h = 20
	else
		@delta_w = 14
		@delta_h = 36
	end
	@wonloaded_lic = @wonloaded_his = @wonloaded_glo = 0
end

def dialog_resize_at_load(wdlg, event)
	ls = event.split(';;')
	hbody = ls[2].to_i
	wwin = ls[3].to_i
	wdec = (Sketchup.version.to_i <= 17) ? 25 : 0
	hdec = (Sketchup.version.to_i <= 17) ? 20 : 0
	wdlg.set_size(wwin + @delta_w + wdec, hbody + 20 + @delta_h + hdec)
end

#DLG UTIL: Open the folder of Liecnse files
def open_file_location
	licdir = licfile_directory	
	if RUBY_PLATFORM =~ /darwin/i
		::Kernel.system("open \"#{licdir}\"")
	else
		UI.openURL licdir
	end	
end

#DLG UTIL: Encode the seat information as a Hash
def seat_encode_hsh(text_hsh)
	return {} if !text_hsh || text_hsh.empty?
	
	#text_hsh = "seat_max::8;;seat_taken::3"
	hsh = {}
	text_hsh.split(';;').each { |a| key, val = a.split('::') ; hsh[key.intern] = val }
	
	seat_max = hsh[:seat_max]
	seat_taken = hsh[:seat_taken]
	return {} unless seat_max && seat_taken
	seat_max = seat_max.to_i
	seat_taken = seat_taken.to_i
	seat_left = seat_max - seat_taken
	
	{ :seat_max => seat_max, :seat_taken => seat_taken, :seat_left => seat_left }
end

#DLG UTIL: Format the field for the duration
def format_duration(hsh, show_expired=false)
	return ["", nil] if !hsh || hsh.empty?
	text2 = nil
	duration = hsh[:duration]
	if duration
		texpire = license_expiration_date(hsh)
		if Time.now > texpire && show_expired
			text1 = text_of(:txt_expired)
		else
			date = texpire.strftime("%a %d %b %Y - %Hh%M")
			['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].each_with_index do |mm, i|
				date = date.sub(mm, text_of(:lst_months)[i+1]) if date.include?(mm)
			end
			['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].each_with_index do |wd, i|
				date = date.sub(wd, text_of(:lst_week_days)[i]) if date.include?(wd)
			end
			text1 = "#{duration} #{text_of(:txt_days)}"
			text2 = "[#{date}]"
		end	
	else
		text1 = text_of(:txt_infinite)
	end
	[text1, text2]
end
	
#DLG UTIL: Format the field for the seat information
def format_seats(hsh)
	return "" if !hsh || hsh.empty?
	seat_max = hsh.fetch :seat_max, "??"
	seat_taken = hsh.fetch :seat_taken, "??"
	seat_left = hsh.fetch :seat_left, "??"
	text = "#{text_of(:txt_max)}"
	text << " = #{seat_max}&nbsp;&nbsp;-&nbsp;&nbsp;#{text_of(:txt_taken)}"
	text << " = #{seat_taken}&nbsp;&nbsp;-&nbsp;&nbsp;#{text_of(:txt_left)} = #{seat_left}"
	text
end
	
#DLG UTIL: Encoding ISO and UTF
def encode_to_ruby(text)
	return text unless text.class == String
	begin
		return text.unpack("U*").pack("U*")
	rescue
		return text.unpack("C*").pack("U*")
	end
end

#DLG UTIL: Format the date for display
def nice_date(sdate)
	return "" if !sdate || sdate.length != 12
	year = sdate[0..3]
	month = sdate[4..5]
	day = sdate[6..7]
	hour = sdate[8..9]
	min = sdate[10..11]
	mm = text_of(:lst_months)[month.to_i]
	"#{day} #{mm} #{year} - #{hour}:#{min}"
end

#DLG UTIL: Format the expiration date for display
def nice_expiration(texpire)
	return "" if !texpire
	"#{texpire.day} #{text_of(:lst_months)[texpire.month]} #{texpire.year}"
end

#DLG UTIL: Format the HTML for a button
def format_button(id, text, classname=nil, tip=nil, color=nil)
	scolor = (color) ? " ; color:#{color}" : ""
	"<input type='button' style='cursor:pointer #{scolor}' id='#{id}' title='#{tip}' value='#{text}' class='#{classname}' onclick='action(\"#{id}\")'/>"
end

#DLG UTIL: Common styles for all dialog boxes
def format_common_style
	@wid_U = 35
	@color_but_def = '#0063a3'
	@color_but_def_hover = '#217cbb'
	@color_but = 'white'
	@color_but_hover = '#EEEEEE'
	@color_text_blue = '#217cbb'
	
	@font_family = "font-family: helvetica, arial, sans serif"
	text = ""
	text << "* { #{@font_family} ; font-size: 11pt }"
	if Sketchup.version.to_i <= 17
		text << ".Button { font-size: 10pt ; background-color: #{@color_but} ; border: 1px solid gray ; padding: 4px 0px 4px 0px ; color : black }"
	else	
		text << ".Button { font-size: 10pt ; background-color: #{@color_but} ; border: 1px solid gray ; padding: 6px ; color : black }"
	end	
	text << ".Button:Hover { font-size: 10pt ; background-color: #{@color_but_hover} }"
	text << ".H_Button { font-size: 10pt ; color: #{@color_text_blue} ; background-color: #{@dlg_background_color} ; border: 0px ; text-decoration: underline }"
	text << ".H_Button:Hover { color: navy }"
	text << ".Y_Button { background-color: #1e8a44 ; color : white }"
	text << ".Y_Button:Hover { background-color: #4ea646 }"
	text << ".R_Button { background-color: #{@color_but_def} ; color: white }"
	text << ".R_Button:Hover { background-color: #{@color_but_def_hover} }"
	text << ".ButHidden { visibility: hidden }"
	text << ".SCFU { color: red ; font-size: 22pt ; font-weight: bold ; text-shadow: 2px 2px 4px gray ; " +
					 "border: 2px solid gray ; display: inline-block ; width: #{@wid_U}px ; height: #{@wid_U}px ; text-align: center ; background-color: lightgrey }"
	text << ".TitDialog { color: navy ; font-size: 14pt ; font-weight: bold }"
	text << ".header_style { color: #{@color_text_blue} ; font-weight: bold ; font-size: 10pt }"
	text << ".Version { color: dimgray ; font-size: 11pt }"
	text
end

#DLG UTIL: Format the HTML for a span
def format_span(text, classname=nil, id=nil, tip=nil)
	hclass = (classname) ? "class='#{classname}'" : ""
	hid = (id) ? "ID='#{id}'" : ""
	text = (text) ? safe_text(text.gsub(/[\n]/, "<br>")) : ""
	"<span #{hclass} #{hid} title='#{tip}' >" + text + '</span>'
end

#DLG UTIL: Modify the string to make sure it displays in HTML
def safe_text(s)
	return s if s.class != String || (s =~ /\A<.+>\Z/ && s !~ /<<.+>>/)
	s = s.gsub("&", "&amp;") unless s =~ /&.+;/
	s = s.gsub("'", "&#39;")
	s = s.gsub("<", "&lt;")
	s = s.gsub(">", "&gt;")
	s = s.gsub("=", "&#61;")
	s
end

end	#class LicenseManager

#-----------------------------------------
# Freezing the Class LicenseManager
#-----------------------------------------

LicenseManager.freeze

#----------------------------------------
#  Creating the menu entry
#----------------------------------------

#Initialize the texts
SCFLicense.text_init

unless @menu_inserted
	distributor_name = SCFLicenseTop.get_custom(:distributor_name)
	distributor_name = 'Sketchucation' unless distributor_name
	txt_global = SCFLicense.get_text(:mnu_global_status)
	txt_mylicenses = SCFLicense.get_text(:mnu_mylicenses).sub('%1', distributor_name)
	UI.start_timer(0.025, false) do
		menu = (defined?(SCF::SUBMENU)) ? SCF::SUBMENU : UI.menu("Plugin")
		menu.add_item(txt_global + "...") { SCFLicense.license_dialog_global }
		if SCFLicense.get_url_mylicenses
			menu.add_item(txt_mylicenses + "...") { UI.openURL SCFLicense.get_url_mylicenses }
		end	
		mnu_text = SCFLicense.get_text(:mnu_mylicenses).sub('%1', "Sketchucation")
		menu.add_item(mnu_text + "...") { UI.openURL SCFLicense.get_url_mylicenses_sketchucation }
	end	
end	
@menu_inserted = true

end	#module SCFLicense

end	#unless defined?(SCFLicense)

#-----------------------------------------
# Freezing the Module SCFLicense
#-----------------------------------------

SCFLicense.freeze
