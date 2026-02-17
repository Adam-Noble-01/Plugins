=begin
  Copyright 2019 (c), TIG
  All Rights Reserved.
  THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED 
  WARRANTIES,INCLUDING,WITHOUT LIMITATION,THE IMPLIED WARRANTIES OF 
  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
###
     ExtrudeToolsLoader.rb
###
Function:
  Makes an Extension called ExtrudeTools and its Toolbar called 'ExtrudeTools'
  IF one of a number of extrudeEdges.. scripts are available... in the subfolder 
 'ExtrudeTools'
                
=end
###
module ExtrudeTools
	###
	@noPlugin=true
	plugins=['extrudeEdgesByRails','extrudeEdgesByRailsToLattice','extrudeEdgesByLoft','extrudeEdgesByEdges','extrudeEdgesByVector','extrudeEdgesByVectorToObject','extrudeEdgesByLathe','extrudeEdgesByFace','extrudeEdgesByFaces','extrudeEdgesByRailsByFace','extrudeEdgesByOffset']
  plugins.delete('extrudeEdgesByFace')# skip as v2019 breaks it.
	plugins.each{|plugin|
		if File.exist?(File.join(EXTOOLS, "#{plugin}.rb"))
			@noPlugin=false
			break
		end#if
	}
	#return nil if noPlugin ### we've got at least ONE plugin...
	###
	@model=Sketchup.active_model
	###
	def self.db(string)
		locale=Sketchup.get_locale.upcase
		path=File.join(EXTOOLS, "#extrusionToolbar"+locale+".lingvo")
		if File.exist?(path)
			deBabelizer(string,path)
		else
			return string
		end
	end#def
	###
	unless file_loaded?(__FILE__) && !@noPlugin
		SUBMENU = UI.menu("Plugins").add_submenu((db("Extrusion Tools"))+"...")
		TOOLBAR=UI::Toolbar.new(db("Extrusion Tools"))
		TOOLBAR.restore if TOOLBAR.get_last_state==TB_VISIBLE
		###
		plugins.each{|plugin|
			if File.exist?(File.join(EXTOOLS, "#{plugin}.rb"))
				load(File.join(EXTOOLS, "#{plugin}.rb"))
			end#if
		}
		###
	end#if
	file_loaded(__FILE__)
	###
end#module
###
