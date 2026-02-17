#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'
require 'json'


module TT
module Plugins
module VertexTools2

  file = __FILE__.dup
  file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)

  # Basename of the support folder.
  SUPPORT_FOLDER_NAME = File.basename(file, '.*')

  # Absolute path to this file.
  ROOT_PATH = File.dirname(File.expand_path(file)).freeze

  # Absolute path to the support folder
  PATH = File.join(ROOT_PATH, SUPPORT_FOLDER_NAME).freeze

  # Path to the bootstrap file that loads when the extension is enabled.
  BOOTSTRAP_PATH = File.join(PATH, 'bootstrap').freeze


  # Extension information
  extension_json_file = File.join(PATH, 'extension.json')
  extension_json = File.read(extension_json_file)
  EXTENSION = ::JSON.parse(extension_json, symbolize_names: true).freeze

  # Syntax shortcut to the extension namespace.
  # TODO: Avoid using this. Move logic to modules and reference those instead.
  PLUGIN = self

  unless file_loaded?(__FILE__)
    @extension = SketchupExtension.new(EXTENSION[:name], BOOTSTRAP_PATH)
    @extension.description = EXTENSION[:description]
    @extension.version     = EXTENSION[:version]
    @extension.copyright   = EXTENSION[:copyright]
    @extension.creator     = EXTENSION[:creator]
    Sketchup.register_extension(@extension, true)
    file_loaded(__FILE__)
  end

  def self.extension
    @extension
  end

end # module VertexTools2
end # module Plugins
end # module TT
