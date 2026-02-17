# copyright: Huynh Duong Phuong Vi
# www.sketchupforyou.com
module S4U
	module S4u_mirror
		require 'sketchup.rb'
		require 'extensions.rb'
		require 'langhandler.rb'
		NAME="s4u_mirror"
		Strings = LanguageHandler.new( NAME + ".strings")
		TOOL=Strings["Mirror"]
		@ext = SketchupExtension.new(("s4u-" + TOOL),File.join(NAME,(NAME + "_loader")))
		@ext.copyright= 'Huynh Duong Phuong Vi'
		@ext.creator = 'Suforyou'
		@ext.version = '4.2.1'
		@ext.description = Strings["Mirror Objects"]
		Sketchup.register_extension @ext, true
	end
end
