#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'

#-------------------------------------------------------------------------------

module TT
  module Lib

  ### CONSTANTS ### ------------------------------------------------------------

  # Plugin information
  PLUGIN_ID       = 'TT_Lib2'.freeze
  PLUGIN_NAME     = 'TT_Lib²'.freeze
  PLUGIN_VERSION  = '2.15.1'.freeze


  ### EXTENSION ### ------------------------------------------------------------

  unless file_loaded?( __FILE__ )
    # This library is still loaded by plugins because they require
    # 'TT_Lib2/core.rb' directly. Disabling the library via the extension
    # manager will have no effect on the dependant extensions.
    #
    # The purpose of this file is solely to make it compatible with the
    # Extension Warehouse policies.
    file_loaded( __FILE__ )
    loader = File.join( 'TT_Lib2', 'core.rb' )
    ex = SketchupExtension.new( PLUGIN_NAME, loader)
    ex.description = 'Library of shared functions used by other extensions.'
    ex.version     = PLUGIN_VERSION
    ex.copyright   = 'Thomas Thomassen © 2010-2024'
    ex.creator     = 'Thomas Thomassen (thomas@thomthom.net)'
    Sketchup.register_extension( ex, true )
  end

  end # module Lib
end # module TT

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------
