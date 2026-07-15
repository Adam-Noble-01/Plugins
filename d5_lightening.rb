# Copyright 2017, Trimble Inc

# This software is provided as an example of using the Ruby interface
# to SketchUp.

# Permission to use, copy, modify, and distribute this software for
# any purpose and without fee is hereby granted, provided that the above
# copyright notice appear in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

#-----------------------------------------------------------------------------
# Name        :   D5Converter Extension Manager
# Description :   A script that loads the D5Converter Tools as an extension to
#                 SketchUp
# Menu Item   :   Yes
# Context Menu:   Yes
# Usage       :   N/A
# Date        :   2021/7/22
# Type        :   N/A
#-----------------------------------------------------------------------------

require 'sketchup.rb'
require 'extensions.rb'
require 'langhandler.rb'

module D5Converter
  # Clear expired files
  expired_file=File.join(File.dirname(__FILE__),"su_to_d5render.rb")
  File.delete(expired_file) if File.exist?(expired_file)


  # set VERSION and ENVIRONMENT
  # VERSION = reserved.main.hotfix.build
  # ENVIRONMENT = enum[dev,test,pre,cn,usa]
  VERSION = "1.7.0.0055"
  LITE_VERSION = "1.5.0.0034"
  ENVIRONMENT = 4

  NAME = "D5 Lite (Beta)"

  D5RESOURCE_PATH = File.join(File.dirname(__FILE__ ),'d5_lightening')
  SU_INSTALL_PATH = Sketchup.find_support_file("", "")
  ENV_STRING = {0=>"dev",1=>"test",2=>"pre",3=>"cn",4=>"usa"}
  ENV_STRING.default = "test"

  # Register the Extension with SU's extension manager
  EXTENSION = SketchupExtension.new(NAME, File.join(D5RESOURCE_PATH,'su_to_d5render'))

  EXTENSION.description="SketchUp D5 Lite Plugin"

  EXTENSION.version = LITE_VERSION
  EXTENSION.creator = "D5 Inc."
  EXTENSION.copyright = "2025, D5 Inc."

  Sketchup.register_extension EXTENSION,true

end # module D5Converter
