# copyright: Huynh Duong Phuong Vi
# www.sketchupforyou.com
module S4U
	module S4u_makeface
		require 'sketchup.rb'
		require 'extensions.rb'
		require 'langhandler.rb'
		NAME="s4u_makeface"
		Strings = LanguageHandler.new( NAME + ".strings")
		TOOL=Strings["Make Face"]
		@ext = SketchupExtension.new(("s4u-" + TOOL),File.join(NAME,(NAME + "_loader")))
		@ext.copyright = 'Huynh Duong Phuong Vi'
		@ext.creator = 'Suforyou'
		@ext.version = '5.2.1'
		@ext.description = Strings["Make faces"]
		Sketchup.register_extension @ext, true
	end
end
