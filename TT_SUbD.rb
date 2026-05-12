#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

require 'json'

#-------------------------------------------------------------------------------

module TT
 module Plugins
  module SUbD

  ### CONSTANTS ### ------------------------------------------------------------

  # Resource paths
  file = __FILE__.dup
  file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
  SUPPORT_FOLDER_NAME = File.basename(file, '.*').freeze
  PATH_ROOT           = File.dirname(file).freeze
  PATH                = File.join(PATH_ROOT, SUPPORT_FOLDER_NAME).freeze

  # Extension information
  extension_json_file = File.join(PATH, 'extension.json')
  extension_json = File.read(extension_json_file)
  EXTENSION = ::JSON.parse(extension_json, symbolize_names: true).freeze
  # Syntax shortcut to the extension namespace.
  PLUGIN          = self
  # Backward compatible constants. Prefer EXTENSION over these.
  PLUGIN_ID       = EXTENSION[:product_id].freeze
  PLUGIN_NAME     = EXTENSION[:name].freeze
  PLUGIN_VERSION  = EXTENSION[:version].freeze


  ### EXTENSION ### ------------------------------------------------------------

  unless file_loaded?(__FILE__)
    loader = File.join(PATH, 'bootstrap')
    ex = SketchupExtension.new(EXTENSION[:name], loader)
    ex.description = EXTENSION[:description]
    ex.version     = EXTENSION[:version]
    ex.copyright   = EXTENSION[:copyright]
    ex.creator     = EXTENSION[:creator]
    @extension = ex
    Sketchup.register_extension(ex, true)
  end

  end # module SUbD
 end # module Plugins
end # module TT

#-------------------------------------------------------------------------------

file_loaded(__FILE__)

#-------------------------------------------------------------------------------
