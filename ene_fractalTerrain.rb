#Eneroth Fractal Terrain Eroder

#Author:	Julia Christina Eneroth, Eneroth3, eneroth3@gmail.com

#Usage
#	Menu: Plugins
#		Erode:	Splits every selected face to smaller ones and randomly moves around endpoints to make it look more like a natural terrain.

#Copyright Julia Christina Eneroth (eneroh3)

#Load the normal support files
require 'sketchup.rb'
require 'extensions.rb'

module Ene_FractalTerrain

PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(self::PLUGIN_ROOT)

ex = SketchupExtension.new("Eneroth Fractal Terrain Eroder", File.join(PLUGIN_ROOT, "/ene_fractalTerrain/main.rb"))
ex.description = "Splits every selected face to smaller ones and randomly moves around endpoints to make it look more like a natural terrain."
ex.version = "1.1.0"
ex.copyright = "Julia Christina (eneroth3) Eneroth 2013"
ex.creator = "Julia Christina (eneroth3) Eneroth"
Sketchup.register_extension ex, true

end#module