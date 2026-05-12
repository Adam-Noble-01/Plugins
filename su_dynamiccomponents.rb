# Copyright 2013-2026, Trimble Inc

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

require 'sketchup.rb'
require 'extensions.rb'
require 'langhandler.rb'

$dc_strings = LanguageHandler.new("dynamiccomponents.strings")

$dc_extension = SketchupExtension.new($dc_strings.GetString(
  "Dynamic Components"), "su_dynamiccomponents/ruby/dcloader")

$dc_extension.description = $dc_strings.GetString("Provides ability to " +
  "interact with specially-authored components. Dynamic Components can have " +
  "behaviors such as smart scaling, animation, and configuration. SketchUp " +
  "Pro users additionally are given the ability to create their own Dynamic " +
  "Components.")
# Version History:
# SketchUp 2015:  1.3.2
# SketchUp 2016:  1.4.1
# SketchUp 2017:  1.4.2
# SketchUp 2018:  1.5.0
# SketchUp 2019:  1.6.0
# SketchUp 2020.0: 1.7.0
# SketchUp 2021.0: 1.8.0
# SketchUp 2021.1: 1.8.1
# SketchUp 2022.0: 1.8.2
# SketchUp 2023.1: 1.8.3
# Security patch: 1.8.4
# Security patch: 1.8.5
$dc_extension.version = "1.8.5"
$dc_extension.creator = "SketchUp"
$dc_extension.copyright = "2021-2026, Trimble Inc."

Sketchup.register_extension $dc_extension, true
