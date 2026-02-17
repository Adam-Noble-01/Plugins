require 'sketchup.rb'
require 'extensions.rb'

Sketchup.require(File.join(File.dirname(__FILE__), 'DM_cutter/DMLanguageHandler'))

module DM
  module Cutter

    VERSION = "2.0.1"
    PLUGIN_NAME = "Double-Cut"
    LH = DMLanguageHandler.new("")

    if Sketchup.version.to_i >= 17
      ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__),"DM_cutter","load")))
      ext.description = ("Automatically extends your cutting component holes to the back face.")
      ext.version = VERSION
      ext.creator = "mind.sight.studios"
      ext.copyright = "2024, MindSight Studios Inc. All rights reserved."
      Sketchup.register_extension(ext, true)
     else
       UI.messagebox("Sketchup 2017 or greater is required to use #{PLUGIN_NAME}.")
     end

  end
end