#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

require 'TT_Lib2/core.rb'
require 'TT_Lib2/system.rb'
require 'TT_Lib2/win32.rb'
require 'TT_Lib2/window.rb'

# @example
#   w = TT::GUI::ToolWindow.new
#   w.show_window
#
# @since 2.5.0
class TT::GUI::ToolWindow < TT::GUI::Window


  # @return [Nil]
  # @since 2.5.0
  def show_window(modal = false)
    was_visible = self.visible?
    super
    if TT::System.is_windows? && !was_visible
      TT::Win32.make_toolwindow_frame( @props[:title] )
    end
    nil
  end


end # module TT::GUI::Window