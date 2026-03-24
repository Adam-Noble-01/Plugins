require 'sketchup.rb'
require 'extensions.rb'

Sketchup.require(File.join(File.dirname(__FILE__), 'DM_artisan2/DMLanguageHandler'))


module DM
  module Artisan2

    VERSION = "2.1.2".freeze
    PLUGIN_NAME = "Artisan 2".freeze
    PLUGIN = self
    LH = DMLanguageHandler.new("")

    if Sketchup.version.to_i >= 18
      artisanExtension = SketchupExtension.new(PLUGIN_NAME, (File.join(File.dirname(__FILE__), "DM_artisan2", "artisan_load")))
      artisanExtension.description = LH["Subdivision, Sculpting, and Soft Transformation tools for creating and editing organic geometry."]
      artisanExtension.version = "#{VERSION}"
      artisanExtension.creator = "mind.sight.studios"
      artisanExtension.copyright = "2024, MindSight Studios Inc. All rights reserved."
      Sketchup.register_extension(artisanExtension, true)
    else
      # Don't localize the string below.  It will not be used often and the inner variables are very useful
      UI.messagebox("SketchUp 2018 or greater is required for Artisan #{VERSION}. " \
        "Please uninstall by going to #{Sketchup.find_support_file('Plugins')} and deleting both "\
        "the file DM_Artisan2.rb and the folder DM_Artisan2.")
    end
  end
end