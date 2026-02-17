require 'sketchup.rb'
require 'extensions.rb'
module CURIC
  module ALIGN
    PLUGIN = self
    PLUGIN_NAMESPACE  = 'Curic'.freeze
    PLUGIN_ID         = 'Align'.freeze
    PLUGIN_NAME       = "#{PLUGIN_NAMESPACE} #{PLUGIN_ID}".freeze
    PLUGIN_VERSION    = '1.6.9 (♡ 10-2 ♡)'.freeze

    FILENAMESPACE = File.basename(__FILE__, '.*')
    PATH_ROOT     = File.dirname(__FILE__).freeze
    PATH          = File.join(PATH_ROOT, FILENAMESPACE).freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(PLUGIN_NAME, "#{FILENAMESPACE}/loader")
      ex.version     = PLUGIN_VERSION
      ex.copyright   = 'Curic © 2022–2025'
      ex.creator     = 'Vo Quoc Hai (curic4su@gmail.com)'
      ex.description = 'Align objects'
      Sketchup.register_extension(ex, true)
    end
  end
end
file_loaded(__FILE__)
