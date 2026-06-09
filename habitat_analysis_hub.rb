require "sketchup"
require "extensions"

module HabitatAnalysisHub
  unless file_loaded?(__FILE__)
    Sketchup.require("habitat_analysis_hub/localise")

    PLUGIN_ID = "habitat_analysis_hub".freeze
    TRANSLATIONS = L10n.new
    EXTENSION = SketchupExtension.new(
      TRANSLATIONS.get("EXTENSION.NAME"),
      "habitat_analysis_hub/main"
    )

    EXTENSION.creator = "SketchUp"
    EXTENSION.description = TRANSLATIONS.get("EXTENSION.DESCRIPTION")
    # ensure that if we ever change where the version is defined that the build script is also updated
    EXTENSION.version = "0.2.3".freeze
    EXTENSION.copyright = "Copyright #{EXTENSION.creator} 2026"
    Sketchup.register_extension(EXTENSION, true)

    file_loaded(__FILE__)
  end
end
