require 'sketchup.rb'
require 'extensions.rb'

module DM
module SketchUV

sketchuvExtension = SketchupExtension.new("SketchUV", (File.join(File.dirname(__FILE__),"DM_SketchUV","sketchuv_load.rb")))
sketchuvExtension.description=("Adds Plugins->SketchUV to the SketchUp interface.  This plugin adds several UV mapping features.")
sketchuvExtension.version="1.0.2"
sketchuvExtension.creator="Dale Martens (Whaat)"
sketchuvExtension.copyright="2017, Dale Martens. All rights reserved."
Sketchup.register_extension sketchuvExtension,true

end

end
