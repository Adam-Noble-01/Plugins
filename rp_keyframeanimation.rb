#----------------------------------------------------------------------------#
# File        :   Plugins/rp_keyframeanimation.rb
# Description :   Animate objects alongside scene properties like camera location, layer visibility, and section planes.
#                 Objects can be interpolated between scenes (keyframes) by translation, rotation, scale, reflection, and inversion.
#                 Export the animation to a video, animated GIF, or image sequence.
#                 Create Tweens (in-between scenes with the object animation baked in) to export RENDERED videos using 3rd party apps.
# Menu Item   :   Extensions (Plugins) -> Keyframe Animation
# Email       :   regular.polygon@gmail.com
# Website     :   http://regular-polygon.com
# Date        :   3/28/2023
#----------------------------------------------------------------------------#


require 'extensions.rb'


extension = SketchupExtension.new('Keyframe Animation', 'rp_keyframeanimation/load_all')
extension.description = "Animate objects between keyframe positions saved on each scene." +
	"  Objects can be interpolated by translation, rotation, scale, reflection, and inversion." +
	"  Export the animation to a video, animated GIF, or image sequence." +
	"  Create Tweens to export RENDERED videos of the object animation using third-party apps."
extension.version = '2.5.0'
extension.creator = 'Regular Polygon'
extension.copyright = "Copywrite 2010-#{ Time.now.year }, Regular Polygon"
Sketchup.register_extension(extension, true)