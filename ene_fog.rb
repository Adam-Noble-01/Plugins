#Eneroth Fog Tool

#Author: Julia Christina Eneroth, eneroth3@gmail.com

#Copyright Julia Christina Eneroth (eneroh3)

#Menu
# Tools > Fog Tool

#Use
# Click in model to select distance for fog start (where fog is completely transparent) and fog end (where fog is completely opaque).
# Exact values for distance to fog start and fog thickness can also be typed in.

#Load the normal support files
require "sketchup.rb"
require "extensions.rb"

module Ene_Fog

PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(self::PLUGIN_ROOT)

ex = SketchupExtension.new("Eneroth Fog Tool", File.join(PLUGIN_ROOT, "ene_fog/main.rb"))
ex.description = "Set fog start and end distance exactly from points in model or custom lengths."
ex.version = "1.0.0"
ex.copyright = "Julia Christina (eneroth3) Eneroth 2014"
ex.creator = "Julia Christina (eneroth3) Eneroth"
Sketchup.register_extension ex, true

end#module