# Plugins/NaKeys.rb  (Loader)
# Registers the extension and loads the main implementation file.

require 'sketchup.rb'
require 'extensions.rb'

ext = SketchupExtension.new(
  'NaKeys Toggle Hotkeys',
  'NaKeys/na_keys_main'
)

ext.description = 'Independent hotkeys that toggle visibility by Tag and Instance Name Prefix.'
ext.version     = '1.0.0'
ext.creator     = 'Noble Architecture'

Sketchup.register_extension(ext, true)
