# copyright: Huynh Duong Phuong Vi
# www.sketchupforyou.com
module S4U
	module S4u_slice
		require 'sketchup.rb'
		require 'extensions.rb'
		require 'langhandler.rb'
		NAME="s4u_slice"
		Strings = LanguageHandler.new( NAME + ".strings")
		TOOL=Strings["Slice"]
		@ext = SketchupExtension.new(("s4u-" + TOOL),File.join(NAME,(NAME + "_loader")))
		@ext.copyright= 'Huynh Duong Phuong Vi'
		@ext.creator = 'Suforyou'
		@ext.version = '5.2.2'
		@ext.description = Strings["Slice,Cut,Detach objects,Create Group Section"]
		Sketchup.register_extension @ext, true
	end
end
