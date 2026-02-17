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

		#Top processing method
		def self.process
			#Account for non-ascii characters in the path
			file__ = __FILE__.dup
			file__ = file__.encode("UTF-8") if defined?(Encoding)
			f6__file__ = file__.gsub(/\\/, '/')
			f6__sudir = File.dirname(f6__file__)
			
			#Finding the loader file in LibFredo6 folder and loading it
			folder = File.join(f6__sudir, "Fredo6_!LibFredo6", "top_LibFredo6")
			file_encrypted = folder + ".rbe"	
			file_to_load = file_encrypted
			file_to_load = folder + ".rb" unless FileTest.exist?(file_to_load)
			
			if FileTest.exist?(file_to_load)
				@ext = SketchupExtension.new 'Fredo6 LibFredo6', file_to_load
				status = Sketchup.register_extension @ext, true
				if defined?(LibFredo6)
					::LibFredo6.startup(f6__sudir) { |hsh_ext| declare_extension(hsh_ext) }
				end	
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