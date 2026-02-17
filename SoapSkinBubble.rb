# Copyright 2006 - 2025 Josef Leibinger

# Name :          
# Description :   
# Author :        Josef Leibinger
# Usage :         
# Date :          2025.04.08
# Type :          Soap Skin & Bubble Tool

require 'sketchup.rb'
require 'extensions.rb'

soapSkinBubbleExtension = SketchupExtension.new "SoapSkinBubble", "SoapSkinBubble/SoapSkinBubbleMenus"

soapSkinBubbleExtension.description = ("Adds Tools-> Soap Skin & Bubble to the SketchUp interface.")

soapSkinBubbleExtension.name = "Soap Skin & Bubble"
soapSkinBubbleExtension.creator = "Josef Leibinger"
soapSkinBubbleExtension.copyright = "2006 - 2025 Josef Leibinger"
soapSkinBubbleExtension.version = "1.0.35"

Sketchup.register_extension soapSkinBubbleExtension, true
