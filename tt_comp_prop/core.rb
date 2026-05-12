#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
begin
  require 'TT_Lib2/core.rb'
rescue LoadError => e
  module TT
    if @lib2_update.nil?
      url = 'http://www.thomthom.net/software/sketchup/tt_lib2/errors/not-installed'
      options = {
        :dialog_title => 'TT_Lib² Not Installed',
        :scrollable => false, :resizable => false, :left => 200, :top => 200
      }
      w = UI::WebDialog.new( options )
      w.set_size( 500, 300 )
      w.set_url( "#{url}?plugin=#{File.basename( __FILE__ )}" )
      w.show
      @lib2_update = w
    end
  end
end


#-------------------------------------------------------------------------------

if defined?( TT::Lib ) && TT::Lib.compatible?( '2.7.0', 'Component Properties' )

module TT::Plugins::CompProp
  
  ### CONSTANTS ### ------------------------------------------------------------
  
  GLUE_NONE       = nil
  GLUE_ANY        = SnapTo_Arbitrary
  GLUE_HORIZONTAL = SnapTo_Horizontal
  GLUE_VERTICAL   = SnapTo_Vertical
  GLUE_SLOPED     = SnapTo_Sloped
  
  
  ### MENU & TOOLBARS ### ------------------------------------------------------
  
  unless file_loaded?( __FILE__ )
    UI.add_context_menu_handler { |context_menu|
      if self.is_valid_selection?
        menu = context_menu.add_submenu( 'Component Properties' )
        
        menu_glue = menu.add_submenu( 'Glue to' )
        
          item = menu_glue.add_item( 'None' ) { self.glue_to( GLUE_NONE ) }
          menu.set_validation_proc( item )  { self.proc_glue( GLUE_NONE ) }
          
          item = menu_glue.add_item( 'Any' ) { self.glue_to( GLUE_ANY ) }
          menu.set_validation_proc( item )  { self.proc_glue( GLUE_ANY ) }
          
          item = menu_glue.add_item( 'Horizontal' ) { self.glue_to( GLUE_HORIZONTAL ) }
          menu.set_validation_proc( item )  { self.proc_glue( GLUE_HORIZONTAL ) }
          
          item = menu_glue.add_item( 'Vertical' ) { self.glue_to( GLUE_VERTICAL ) }
          menu.set_validation_proc( item )  { self.proc_glue( GLUE_VERTICAL ) }
          
          item = menu_glue.add_item( 'Sloped' ) { self.glue_to( GLUE_SLOPED ) }
          menu.set_validation_proc( item )  { self.proc_glue( GLUE_SLOPED ) }
        
        item = menu.add_item( 'Cut Opening' ) { self.toggle_cut_opening }
        menu.set_validation_proc( item )  { self.proc_cut_opening }
        
        item = menu.add_item( 'Always Face Camera' ) { self.toggle_face_camera }
        menu.set_validation_proc( item )  { self.proc_face_camera }
        
        item = menu.add_item( 'Shadows Face Sun' ) { self.toggle_shadows_face_sun }
        menu.set_validation_proc( item )  { self.proc_shadows_face_sun }
      end
    }
  end
  
  
  ### MAIN SCRIPT ### ----------------------------------------------------------
  
  
  # Macros
  
  
  def self.is_valid_selection?
    model = Sketchup.active_model
    sel = model.selection
    sel.length == 1 && sel[0].is_a?( Sketchup::ComponentInstance )
  end
  
  
  def self.selected_component
    Sketchup.active_model.selection[0].definition
  end
  
  
  # Toggle Properties
  
  
  def self.glue_to( type )
    b = self.selected_component.behavior
    if type == GLUE_NONE
      b.is2d = false
    else
      TT::Model.start_operation( 'Properties' )
      b.is2d = true
      b.snapto = type
      Sketchup.active_model.commit_operation
    end
  end
  
  
  def self.toggle_cut_opening
    b = self.selected_component.behavior
    b.cuts_opening = !b.cuts_opening?
  end
  
  
  def self.toggle_face_camera
    b = self.selected_component.behavior
    b.always_face_camera = !b.always_face_camera?
  end
  
  
  def self.toggle_shadows_face_sun
    b = self.selected_component.behavior
    b.shadows_face_sun = !b.shadows_face_sun?
  end
  
  
  # Validation Procs
  
  
  def self.proc_glue( type )
    b = self.selected_component.behavior
    if type == GLUE_NONE
      if b.is2d?
        MF_UNCHECKED
      else
        MF_CHECKED
      end
    else
      if b.is2d? && b.snapto == type
        MF_CHECKED
      else
        MF_UNCHECKED
      end
    end
  end
  
  
  def self.proc_cut_opening
    if self.selected_component.behavior.cuts_opening?
      MF_CHECKED
    else
      MF_UNCHECKED
    end
  end
  
  
  def self.proc_face_camera
    if self.selected_component.behavior.always_face_camera?
      MF_CHECKED
    else
      MF_UNCHECKED
    end
  end
  
  
  def self.proc_shadows_face_sun
    if self.selected_component.behavior.shadows_face_sun?
      MF_CHECKED
    else
      MF_UNCHECKED
    end
  end
  
  
  ### DEBUG ### ------------------------------------------------------------  
  
  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::CompProp.reload
  #
  # @param [Boolean] tt_lib Reloads TT_Lib2 if +true+.
  #
  # @return [Integer] Number of files reloaded.
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    TT::Lib.reload if tt_lib
    # Core file (this)
    load __FILE__
    # Supporting files
    if defined?( PATH ) && File.exist?( PATH )
      x = Dir.glob( File.join(PATH, '*.{rb,rbs}') ).each { |file|
        load file
      }
      x.length + 1
    else
      1
    end
  ensure
    $VERBOSE = original_verbose
  end
  
end # module

end # if TT_Lib

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------