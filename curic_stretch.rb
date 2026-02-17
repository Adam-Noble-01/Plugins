require 'sketchup.rb'
require 'extensions.rb'
module CURIC
  # Stretch Namespace
  module Stretch
    PLUGIN            = self
    PLUGIN_NAMESPACE  = 'Curic'.freeze
    PLUGIN_ID     	  = 'Stretch'.freeze
    PLUGIN_NAME     	= "#{PLUGIN_NAMESPACE} #{PLUGIN_ID}".freeze
    PLUGIN_VERSION  	= '1.3.0'.freeze

    FILENAMESPACE = File.basename(__FILE__, '.*')
    PATH_ROOT     = File.dirname(__FILE__).freeze
    PATH          = File.join(PATH_ROOT, FILENAMESPACE).freeze

    Sketchup.require "#{PATH}/load_rubyencoder_helper"

    ex = SketchupExtension.new(PLUGIN_NAME, "#{PATH}/loader")
    ex.version     = PLUGIN_VERSION
    ex.copyright   = 'Vo Quoc Hai © 2023–2026'
    ex.creator     = 'Vo Quoc Hai (curic4su@gmail.com)'
    ex.description = 'Stretching objects for SketchUp.'

    Sketchup.register_extension(ex, true)
  end

end
