require 'sketchup.rb'
require 'extensions.rb'
module CURIC
  module FaceKnife
    PLUGIN            = self
    PLUGIN_NAMESPACE  = 'Curic'.freeze
    PLUGIN_ID         = 'Face Knife'.freeze
    PLUGIN_NAME       = "#{PLUGIN_NAMESPACE} #{PLUGIN_ID}".freeze
    PLUGIN_VERSION    = '1.0.2'.freeze

    FILENAMESPACE = File.basename(__FILE__, '.*')
    PATH_ROOT     = File.dirname(__FILE__).freeze
    PATH          = File.join(PATH_ROOT, FILENAMESPACE).freeze

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(PLUGIN_NAME, "#{PATH}/loader")
      ex.version     = PLUGIN_VERSION
      ex.copyright   = 'Curic © 2024-2027 - All rights reserved'
      ex.creator     = 'Vo Quoc Hai (support@curic.io)'
      ex.description = 'Cut objects by face.'
      Sketchup.register_extension(ex, true)
      PLUGIN_EX = ex
    end
  end
end

file_loaded(__FILE__)
