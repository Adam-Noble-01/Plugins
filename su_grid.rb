# Copyright 2014, Trimble Navigation Limited

# This software is provided as an example of using the Ruby interface
# to SketchUp.

# Permission to use, copy, modify, and distribute this software for 
# any purpose and without fee is hereby granted, provided that the above
# copyright notice appear in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------
# Name        :   Grid Tool 1.0
# Description :   A tool to create grids.
# Menu Item   :   Tools->Grid
# Context Menu:   None
# Date        :   4/2/2013
# Type        :   Tool
#-----------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

module Sketchup::Samples
module Grid

# Create the extension.
grid_ext = SketchupExtension.new 'Grid Tool', 'su_grid/grid.rb'
grid_ext.description = 'Grid sample script from SketchUp.com'
grid_ext.version =  '1.1.3'
grid_ext.creator = "SketchUp"
grid_ext.copyright = "2013-2022, Trimble Inc."

# Register the extension with Sketchup so it shows up in the Preference panel.
Sketchup.register_extension grid_ext, true

end # module Grid
end # module Sketchup::Samples
