require 'sketchup.rb'
require 'extensions.rb'

Sketchup.require(File.join(File.dirname(__FILE__), 'DM_SketchPlus/DMLanguageHandler'))

module DM
  module SketchPlus

    VERSION = "1.3.0"
    PLUGIN = self
    PLUGIN_NAME = "SketchPlus".freeze
    LH = DMLanguageHandler.new("sketchPlus.strings")

    if Sketchup.version.to_i >= 17
      ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__), "DM_SketchPlus", "load")))
      ext.description = LH["Add to and improve your SketchUp tools."]
      ext.version = VERSION
      ext.creator = "mind.sight.studios"
      ext.copyright = "2025, MindSight Studios Inc. All rights reserved."
      Sketchup.register_extension(ext, true)
    else
      # Don't localize the string below.  It will not be used often and the inner variables are very useful
      UI.messagebox("SketchUp 2017 or greater is required for SketchPlus #{VERSION}. " \
        "Please uninstall using the Extension Manager or manually delete the plugin files.")
      ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__), "DM_SketchPlus", "reducer")))
      ext.description = LH["Incompatible with your version of SketchUp"]
      Sketchup.register_extension(ext, true)
    end
  end
end
