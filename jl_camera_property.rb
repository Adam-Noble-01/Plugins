# -*- coding: UTF-8 -*-
require 'sketchup.rb'
require 'extensions.rb'
require 'date'

module JLModule
    module CameraProperties

    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new('JL Camera Properties', 'jl_camera_property/jl_main')
      ex.description = 'Camera Properties to fix clipping (Windows platform only)'
      ex.version     = '1.0'
      ex.copyright   = 'Jason Li © 2021'
      ex.creator     = 'Jason Li'
      Sketchup.register_extension(ex, true)
      file_loaded(__FILE__)
    end

    end # CameraProperties
end # JLModule