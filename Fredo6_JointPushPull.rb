=begin
#---------------------------------------------------------------------------------------------------------
#*********************************************************************************************************
# Copyright © 2011-2017 Fredo6 - Designed and written April 2017 by Fredo6
#
# Permission to use this software for any purpose and without fee is hereby granted
# Distribution of this software for commercial purpose is subject to:
#  - the expressed, written consent of the author
#  - the inclusion of the present copyright notice in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Description	:  Generic top loader for LibFredo6-compliant scripts.
#
# This file does a checking on the environment for correct installation of LibFredo6 and the script itself
# The file is identical for all my plugins relying on LibFredo6
#*********************************************************************************************************
#---------------------------------------------------------------------------------------------------------
=end

require 'sketchup.rb'
require 'extensions.rb'

module Fredo6

@file__ = __FILE__
@file__ = @file__.force_encoding("UTF-8") if defined?(Encoding)
@file__ = @file__.gsub(/\\/, '/')

#Dialog for missing LibFredo6
def self.missing_LibFredo6(missing=false)
	return if @already_asked
	@already_asked = true
	filename = File.basename(@file__, ".rb")
	text = (missing) ? " " : " (v7.6 or higher) "
	plugin_name = (filename =~ /\AFredo6_(.+)\Z/) ? $1 : filename
	msg = "You must install LibFredo6#{text}to run #{plugin_name}"
	url = "https://sketchucation.com/plugin/903-libfredo6"
	msg += "\n\nOpen the download page of LibFredo6\n at #{url}"
	UI.openURL(url) if UI.messagebox(msg, MB_YESNO) == IDYES
end

#LibFredo6 is present
if FileTest.exist?(File.join(File.dirname(@file__), 'Fredo6_!LibFredo6.rb'))
	require 'Fredo6_!LibFredo6.rb'

	if defined?(LibFredo6.top_load)
		hsh_ext, plugin, ext = LibFredo6.top_load(@file__, true)
		if hsh_ext && plugin && !ext
			ext = SketchupExtension.new hsh_ext[:name], hsh_ext[:floader]
			ext.creator = hsh_ext[:creator] 
			ext.description = hsh_ext[:description] 
			ext.version = hsh_ext[:version] 
			ext.copyright = hsh_ext[:copyright] 	
			status = Sketchup.register_extension ext, true
			plugin.load_finalize ext
		end	
	else
		missing_LibFredo6
	end

#LibFredo6 is absent: Propose to get it
else
	missing_LibFredo6 true

end	#if LibFredo6 exist?

end	#module Fredo6
