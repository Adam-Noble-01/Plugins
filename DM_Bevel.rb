require 'sketchup.rb'
require 'extensions.rb'

Sketchup.require(File.join(File.dirname(__FILE__), 'DM_Bevel/DMLanguageHandler'))

module DM
  module Bevel
    VERSION = "1.1.0"
    PLUGIN = DM::Bevel
    PLUGIN_NAME = "Bevel".freeze
    LH = DMLanguageHandler.new("")

    if Sketchup.version.to_i >= 17
      @@ext = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__), "DM_Bevel", "load")))
      @@ext.description = "Create chamfered and rounded edges"
      @@ext.version = VERSION
      @@ext.creator = "mind.sight.studios"
      @@ext.copyright = "2025, MindSight Studios Inc. All rights reserved."
      Sketchup.register_extension(@@ext, true)
    else
      UI.messagebox("SketchUp 2017 or greater is required for Bevel #{VERSION}.")
    end
  end
end
