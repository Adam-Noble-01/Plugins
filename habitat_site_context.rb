require "sketchup"
require "extensions"

module HabitatSiteContext
  unless file_loaded?(__FILE__)
    Sketchup.require("habitat_site_context/localise")

    PLUGIN_ID = "habitat_site_context".freeze
    TRANSLATIONS = L10n.new
    EXTENSION = SketchupExtension.new(
      TRANSLATIONS.get("EXTENSION.NAME"),
      "habitat_site_context/main"
    )

    EXTENSION.creator = "SketchUp"
    EXTENSION.description = TRANSLATIONS.get("EXTENSION.DESCRIPTION")
    # ensure that if we ever change where the version is defined that the build script is also updated
    EXTENSION.version = "1.7.8".freeze
    EXTENSION.copyright = "#{EXTENSION.creator} 2025"
    Sketchup.register_extension(EXTENSION, true)

    file_loaded(__FILE__)
  end
end
