#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

# This file exist only as a compatibility with older version of TT_Lib when
# the implementation was in pure Ruby. It also ensures the correct version for
# the platform is loaded.

require 'TT_Lib2/core.rb'
require File.join( TT::Lib::PATH_LIBS_CEXT, 'tt_lib2' )
