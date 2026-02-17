# copyright: Huynh Duong Phuong Vi
# www.sketchupforyou.com
module S4U
	module S4u_find_gap
		require 'sketchup.rb'
		require 'extensions.rb'
		require 'langhandler.rb'
		NAME="s4u_find_gap"
		Strings = LanguageHandler.new( NAME + ".strings")
		TOOL=Strings["Find Gap"]
		@ext = SketchupExtension.new(("s4u-" + TOOL),File.join(NAME,(NAME + "_loader")))
		@ext.copyright= 'Huynh Duong Phuong Vi'
		@ext.creator = 'Suforyou'
		@ext.version = '2.1.1'
		@ext.description = Strings["Find gaps. Find end point of edge and Auto Connect."]
		Sketchup.register_extension @ext, true
	end
end
