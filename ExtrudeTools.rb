=begin
  Copyright 2015-2019 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
     ExtrudeTools.rb
	   [formerly named #extrusionToolbar.rb]
###
Function:
  Makes an Extension called 'ExtrudeTools' loading 'ExtrudeToolsLoader.rb'
        
Donations:
  Are welcome [by PayPal], please use 'TIGdonations.htm' in the 
  ../Plugins/TIGtools/ folder; or use info @ revitrev.org
        
=end
###
require('sketchup.rb')
require('extensions.rb')
require('deBabelizer.rb')
###
module ExtrudeTools

	LNAME="ExtrudeTools"
	VERSION="5.0"
	CREATOR="TIG"
	COPYRIGHT="#{CREATOR} © #{Time.now.year}"
	###
	if defined?(Encoding)
		PLUGINS=File.dirname(__FILE__).force_encoding("UTF-8") ### v2014 lashup
	else
		PLUGINS=File.dirname(__FILE__)
	end
	EXTOOLS=File.join(PLUGINS, 'ExtrudeTools')
	TIGTOOLS=File.join(PLUGINS, 'TIGtools')
	###
	### remove unused files
	if File.exist?(File.join(PLUGINS, "#extrusionToolbar.rb"))
		File.delete(File.join(PLUGINS, "#extrusionToolbar.rb"))
	elsif File.exist?(File.join(PLUGINS, "#extrusionToolbar.rb!"))
		File.delete(File.join(PLUGINS, "#extrusionToolbar.rb!"))
	end
	["extrudeEdgesByOffset","extrudeEdgesByVectorToObject","extrudeEdgesByVector","extrudeEdgesByLathe","extrudeEdgesByRails","extrudeEdgesByEdges","extrudeEdgesByFace","extrudeEdgesByFaces","extrudeEdgesByRailsByFace","extrudeEdgesByLoft","extrudeEdgesByRailsToLattice"].each{|plugin|
		if File.exist?(File.join(PLUGINS, "#{plugin}.rb"))
			File.delete(File.join(PLUGINS, "#{plugin}.rb"))
		elsif File.exist?(File.join(PLUGINS, "#{plugin}.rb!"))
			File.delete(File.join(PLUGINS, "#{plugin}.rb!"))
		end
	}
	Dir.entries(TIGTOOLS).each{|f|
		["extrudeEdgesByOffset","extrudeEdgesByVectorToObject","extrudeEdgesByVector","extrudeEdgesByLathe","extrudeEdgesByRails","extrudeEdgesByEdges","extrudeEdgesByFace","extrudeEdgesByFaces","extrudeEdgesByRailsByFace","extrudeEdgesByLoft","extrudeEdgesByRailsToLattice"].each{|p|
			if f=~/^#{p}/ && (File.extname(f).downcase==".png" || File.extname(f).downcase==".lingvo")
				File.delete(File.join(TIGTOOLS, f)) if File.exist?(File.join(TIGTOOLS, f))
			end
		}
		File.delete(File.join(TIGTOOLS, f)) if f=="extrudeEdgesTools-VietnameseLingvos.rar" && File.exist?(File.join(TIGTOOLS, f))
	} if File.exist?(TIGTOOLS)
	###
	EXT=SketchupExtension.new(LNAME, File.join(EXTOOLS, "ExtrudeToolsLoader.rb"))
	EXT.name = LNAME
	EXT.description = "#{LNAME}..."
	EXT.version = VERSION
	EXT.creator = CREATOR
	EXT.copyright = COPYRIGHT
	Sketchup.register_extension(EXT, true) # show on 1st install
	###
end#module
###
