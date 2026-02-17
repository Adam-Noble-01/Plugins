require 'sketchup.rb'
require 'extensions.rb'
module CURIC
  module Extend
    PLUGIN            = self
    PLUGIN_NAMESPACE  = 'Curic'.freeze
    PLUGIN_ID     	  = 'Extend'.freeze
    PLUGIN_NAME     	= "#{PLUGIN_NAMESPACE} #{PLUGIN_ID}".freeze
    PLUGIN_VERSION  	= '1.1.0'.freeze

    FILENAMESPACE = File.basename(__FILE__, '.*')
    PATH_ROOT     = File.dirname(__FILE__).freeze
    PATH          = File.join(PATH_ROOT, FILENAMESPACE).freeze

    Sketchup.require "#{PATH}/load_rubyencoder_helper"

    ex = SketchupExtension.new(PLUGIN_NAME, "#{PATH}/loader")
    ex.version     = PLUGIN_VERSION
    ex.copyright   = 'Vo Quoc Hai © 2023–2026'
    ex.creator     = 'Vo Quoc Hai (curic4su@gmail.com)'
    ex.description = 'Extend tools for SketchUp'
    Sketchup.register_extension(ex, true)
  end
end
file_loaded( __FILE__ )
