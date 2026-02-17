#-----------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-----------------------------------------------------------------------------

require 'TT_Lib2/core.rb'
require 'TT_Lib2/instance.rb'

# Collection of Face methods.
#
# @since 2.0.0
module TT::Image
  
  # Returns the material for the given +Image+.
  #
  # @param [Sketchup::Image] image
  #
  # @return [Sketchup::Material]
  # @since 2.0.0
  def self.material(image)
    definition = TT::Instance.definition(image)
    face = definition.entities.grep(Sketchup::Face).first
    face.material
  end
  
end # module TT::Image