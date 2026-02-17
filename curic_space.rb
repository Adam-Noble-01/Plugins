require 'sketchup.rb'
require 'extensions.rb'
module CURIC
  module Space
    PLUGIN = self
    PLUGIN_NAMESPACE  = 'Curic'.freeze
    PLUGIN_ID         = 'Space'.freeze
    PLUGIN_NAME       = "#{PLUGIN_NAMESPACE} #{PLUGIN_ID}".freeze
    PLUGIN_VERSION    = '1.1.2'.freeze

    FILENAMESPACE = File.basename(__FILE__, '.*')
    PATH_ROOT     = File.dirname(__FILE__).freeze
    PATH          = File.join(PATH_ROOT, FILENAMESPACE).freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(PLUGIN_NAME, "#{PATH}/loader")
      ex.version     = PLUGIN_VERSION
      ex.copyright   = 'Curic © 2019–2022'
      ex.creator     = 'Vo Quoc Hai (curic4su@gmail.com)'
      ex.description = 'To evenly space two or more selected elements'
      Sketchup.register_extension(ex, true)
      PLUGIN_EX = ex
    end
  end
end
file_loaded(__FILE__)
