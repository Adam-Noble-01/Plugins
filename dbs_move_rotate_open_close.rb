=begin

by DBS - Daniel Bieńkowski Solutions

v.1.0.0 - 2019.07.19
- base
v.1.0.1 - 2019.07.21
- move LIB inside MOVE_ROTATE_OPEN_CLOSE module
- add Toggle Tool button to main menu
- remove About button from bar
v.2.1.0 - 2019.08.09
- podwojne sprawdzanie licencji
v.3.1.1 - 2019.09.14
- fix bug on MAC - SU crash after Set Axis button
- added lic online check
- module name: MOVE_ROTATE_OPEN_CLOSE - > MoveRotateOpenClose
v.3.1.2 - 2019.09.16
- openes EW if trial expired
- added lic online check to lic html dialog
v.3.2
- poprawka "wielkiej lapy"
- wywalenie nr wersji z tytulu toolbara
- dodanie przedrostka DBS w menu Extensions
- dodanie 1s animacji ruchu
v.3.3 - 2020.12.04
- Lic v6
v.3.4 - 2021.04.17
- make it free
v3.5
- add DBS to ext name
v3.6
- smoother manual moves
- lock object select during animation
v3.7
- added require 'set' for to_set method
v3.8
- clear selection and no drawing shapes during open/close animation
- fixed cursor
- improved config dialog window
- dialog window position and size persist between open
- fixed issue when try to activate open/close move during current movement
- fixed changing tools
- fixed issue with clipping view after distant move
- change tool bar buttons positions
new:
- new buttons in config dialog for setting Open and Close positions
- visualization of Open and Close positions
- animation time
- ESC button close config dialog window
v3.9
- fix issue with Sketchup::image class in model definitions
- Main menu moved to Extensions -> DBS ->

=end

require 'sketchup.rb'
require 'extensions.rb'

module DBS
module MoveRotateOpenClose

  unless file_loaded?(__FILE__)

  path = __FILE__
  path.force_encoding("UTF-8") if path.respond_to?(:force_encoding)

  FILE_BASENAME = File.basename(path, ".*")
  PLUGIN_DIR = File.join(File.dirname(path), FILE_BASENAME)

  EXTENSION = SketchupExtension.new("DBS Move Rotate Open Close", File.join(PLUGIN_DIR, "main"))
  EXTENSION.name
  EXTENSION.creator     = "DBS"
  EXTENSION.description = "Configure movable joints and move them as you need. Quick toggle between open and close position."
  EXTENSION.version     = "3.10"
  EXTENSION.copyright   = "2024, #{EXTENSION.creator}"
  Sketchup.register_extension(EXTENSION, true)

  end
end
end