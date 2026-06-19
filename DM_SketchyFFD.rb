require 'sketchup.rb'
require 'extensions.rb'

module DM
  module SketchyFFD
    PLUGIN_NAME = "SketchyFFD (Classic)"
    VERSION = "V7"
    if Sketchup.version.to_i >= 7
      ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__), "DM_SketchyFFD", "main")))
      ext.description = "Adds a control cage to an object that allows the mesh to be manipulated via control points."
      ext.version = VERSION
      ext.creator = "mind.sight.studios"
      ext.copyright = "2021, MindSight Studios Inc. All rights reserved."
      Sketchup.register_extension(ext, true)
    else
      UI.messagebox("SketchUp 7 or greater is required for SketchyFFD #{VERSION}. " \
        "Please uninstall using the Extension Manager or manually delete the plugin files.")
      ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__), "DM_SketchyFFD", "incompatible")))
      ext.description = "Incompatible with your version of SketchUp"
      Sketchup.register_extension(ext, true)
    end
  end
end

