require 'sketchup.rb'
require 'extensions.rb'

fpath = __FILE__.dup
fpath.force_encoding('UTF-8') if fpath.respond_to?(:force_encoding)

unless file_loaded?(fpath)
  file_loaded(fpath)
  module AMS
    module WindowSettings

      NAME = 'FullScreen'.freeze

      MAJOR_VERSION = 5.freeze
      MINOR_VERSION = 1.freeze
      PATCH_VERSION = 3.freeze
      DEVEL_VERSION = 0.freeze

      VERSION_INT = (MAJOR_VERSION * 1000 + MINOR_VERSION * 100 + PATCH_VERSION * 10 + DEVEL_VERSION).to_i
      VERSION = sprintf("%d.%d.%d%c", MAJOR_VERSION, MINOR_VERSION, PATCH_VERSION, DEVEL_VERSION + 0x61).freeze

      RELEASE_YEAR_START = 2012.freeze
      RELEASE_YEAR_END = 2024.freeze
      RELEASE_DATE = '25 April 2024'.freeze

      PRODUCTION = true
      REQUIRED_AMS_LIBRARY_VERSION = '3.7.0'
      REQUIRED_AMS_LIBRARY_VERSION_INT = 3700

      cfpath = __FILE__.dup
      cfpath.force_encoding('UTF-8') if cfpath.respond_to?(:force_encoding)
      efpath = ::File.expand_path('../ams_WindowSettings/main_entry', cfpath)
      @extension = ::SketchupExtension.new(NAME, efpath)

      desc = "A UI for switching SketchUp full screen and controlling visiblity of docked toolbars, menu, status text, viewport border, and scene tabs."

      @extension.description = desc
      @extension.version = VERSION
      if (RELEASE_YEAR_START == RELEASE_YEAR_END)
        @extension.copyright = "(C) #{RELEASE_YEAR_START} Anton Synytsia"
      else
        @extension.copyright = "(C) #{RELEASE_YEAR_START} - #{RELEASE_YEAR_END} Anton Synytsia"
      end
      @extension.creator = 'Anton Synytsia'

      ::Sketchup.register_extension(@extension, true)

      class << self
        attr_reader :extension
      end # class << self

    end # module WindowSettings
  end # module AMS
end
