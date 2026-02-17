Sketchup.require 'sketchup'
Sketchup.require 'extensions'

module EVP
  module GltfExporter
    unless file_loaded?(__FILE__)
      TRANSLATE = LanguageHandler.new('lang_gltf_export.strings')

      ex = SketchupExtension.new(TRANSLATE['title'], 'skp_gltf_export/gltf_export')
      ex.description = TRANSLATE['description']
      ex.version     = '1.0.0'
      ex.copyright   = '©2020 Evan Prananta'
      ex.creator     = 'Evan Prananta'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end
  end
end
