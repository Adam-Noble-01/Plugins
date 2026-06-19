# Z5_Deform Loader
# Place this file in SketchUp's Plugins folder
# Place the z5_deform folder alongside it

require 'sketchup'
require 'extensions'

module Z5
  module Z5_Deform
    ext = SketchupExtension.new("Z5 Deform", "z5_deform/main")
    ext.description = "Bend, Scale, Skew deformation for Groups and Components"
    ext.version = "1.0.0"
    ext.creator = "Z5"
    ext.copyright = "Copyright (c) 2025 Z5. All rights reserved."
    Sketchup.register_extension(ext, true)
  end
end