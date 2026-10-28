=begin
#-------------------------------------------------------------------------------------------------------------------------------------------------
#*************************************************************************************************
# Copyright © 2008-2016 - Designed and written as of Dec 2008 by Fredo6
#
# Permission to use this software for any purpose and without fee is hereby granted
# Distribution of this software for commercial purpose is subject to:
#  - the expressed, written consent of the author
#  - the inclusion of the present copyright notice in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Name			:   Fredo6_!LibFredo6.rb
# Original Date	:   20 Aug 2008 - version 3.0
# Type			:   Ruby Library
# Description	:   Top loading module for all Library utilities of Fredo6's scripts
#-------------------------------------------------------------------------------------------------------------------------------------------------
#*************************************************************************************************
=end

if Sketchup.version.to_i >= 17

unless defined?(LibFredo6_Loader)

	require 'sketchup.rb'
	require 'extensions.rb'
	require 'fileutils.rb'
	
	module LibFredo6_Loader

		def LibFredo6_Loader.verify_encoding
			puts "__FILE__ = #{__FILE__}"
			puts "Encoding = #{__FILE__.encoding}"
		end
		
		def LibFredo6_Loader.time_loaded
			@time_loaded
		end
		
		#Method to register the LibFredo6 extension
		def self.declare_extension(hsh_ext)
			@ext.creator = hsh_ext[:creator] 
			@ext.description = hsh_ext[:description] 
			@ext.version = hsh_ext[:version] 
			@ext.copyright = hsh_ext[:copyright]
			Sketchup.require hsh_ext[:floader]
		end
		
		#Load the E6B module
		def self.load_E6B(top_dir)
			#Already loaded
			#return true if defined?(::E6B)
			
			#Ruby version and target directory
			platform = (RUBY_PLATFORM =~ /darwin/) ? 'Mac' : 'Win64'
			ruby_version = (RUBY_VERSION.to_f * 10).to_i
			root_sub = "#{platform}_#{ruby_version}"
			e6b_dir = File.join(top_dir, "Fredo6_!LibFredo6", "Binaries", root_sub)

			#E6B binary file
			ext = (RUBY_PLATFORM =~ /darwin/) ? 'bundle' : 'so'
			file_bin = File.join(e6b_dir, "E6B.#{ext}")
			
			#Copy the file for Windows
			#MAC: We can use the binary file in place
			if RUBY_PLATFORM =~ /darwin/i
				target_file = file_bin
				
			#WINDOWS: .so file must be copied to a temporary place
			else
				#Name of the target file in the temporary directory
				tmp_bin_dir = File.join(Sketchup.temp_dir, 'LibFredo6_Binaries')
				Dir.mkdir(tmp_bin_dir) unless File.directory?(tmp_bin_dir)
				basename = File.basename(file_bin)
					
				#Copying the file to a temporary directory
				for i in 0..9
					tmp_su_dir = File.join(tmp_bin_dir, "SU#{Sketchup.version.to_i}-#{i}")
					Dir.mkdir(tmp_su_dir) unless File.directory?(tmp_su_dir)
					target_file = File.join(tmp_su_dir, basename)
					begin
						FileUtils.copy(file_bin, target_file)
						break
					rescue StandardError => e
						if i >= 9 || !File.exist?(target_file)
							puts "ERROR in copying #{file_bin} to #{target_file}"
							puts "Error #{e}"
							return false 
						end	
					end
				end	
			end
			
			#Load the binary file
			status = error = nil
			if File.exist?(target_file)
				begin
					status = require(target_file)
				rescue LoadError => e
					error = e.message
					puts "Error loading E6B: #{error}"
				rescue StandardError => e
					error = e.message
					puts "Error loading E6B: #{error}"
				end
			end	
			
			#Registering the load
			if status
				true
			else
				puts "\nError in loading E6B"
				false
			end	
		end		

		#Top processing method
		def self.process
			#Account for non-ascii characters in the path
			file__ = __FILE__.dup
			file__ = file__.encode("UTF-8") if defined?(Encoding)
			f6__file__ = file__.gsub(/\\/, '/')
			f6__sudir = File.dirname(f6__file__)
			
			#Load the E6B module
			begin
				load_E6B(f6__sudir)
			rescue Exception => e
				puts "************ERROR in load_E6B"
				puts e.message
			end	
			
			#Finding the loader file in LibFredo6 folder and loading it
			file_top = File.join(f6__sudir, "Fredo6_!LibFredo6", "top_LibFredo6")
			file_loader = nil
			file_top_rb = nil
			['rb6', 'rb', 'rbe'].each do |ext|
				file_top_rb = file_top + '.' + ext
				if File.exist?(file_top_rb)
					file_loader = File.join(Sketchup.temp_dir, "Fredo6__loader_top_#{Time.now.to_i}.rb")
					File.open(file_loader, 'w') do |f|
						f.puts "E6B.require(\"#{file_top_rb}\", 'LibFredo6')"
					end	
					break
				end
			end	
			
			if file_top_rb && file_loader
				#@ext = SketchupExtension.new 'Fredo6 LibFredo6', file_top_rb
				@ext = SketchupExtension.new 'Fredo6 LibFredo6', file_loader
				status = Sketchup.register_extension @ext, true
				if defined?(LibFredo6)
					::LibFredo6.startup(f6__sudir) { |hsh_ext| declare_extension(hsh_ext) }
				end	
				File.delete file_loader
			else
				UI.messagebox "Wrong installation: Folder Fredo6_!LibFredo6 is missing in #{f6__sudir}"
			end
		end

		#Processing with the load
		process
				
		#Registering the time after load
		@time_loaded = Time.now
	
	end	#Module LibFredo6_Loader

#The module has already been loaded
else
	if defined?(LibFredo6_Loader.time_loaded)
		UI.messagebox "LibFredo6 already installed\nIt will be updated at next startup of Sketchup" if (Time.now - LibFredo6_Loader.time_loaded) > 30
	end	
	
end	#defined?(LibFredo6_Loader)

#Check of Sketchup version
else
	UI.messagebox("This version of LibFredo6 CANNOT run of Sketchup version PRIOR TO SU2017")
end