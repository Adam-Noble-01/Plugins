# frozen_string_literal: true

require "extensions"
require "langhandler"

# SketchUp Team Extensions
module Trimble
  # Extension Migration Extension
  #
  # Lowers the barrier of upgrading SketchUp by allowing extensions to carry
  # over between major installations.
  module ExtensionMigrator
    # Translated UI strings
    LH = LanguageHandler.new("extension_migrator.strings")

    # Correct for encoding issue in Windows.
    # https://sketchucation.com/forums/viewtopic.php?f=180&t=57017
    path = __FILE__.dup
    path.force_encoding("UTF-8") if path.respond_to?(:force_encoding)

    # Identifier for this extension.
    EXTENSION_ID = File.basename(path, ".*")

    # Root directory of this extension.
    EXTENSION_ROOT = File.join(File.dirname(path), EXTENSION_ID)

    # Extension object for this extension.
    EXTENSION = SketchupExtension.new(
      LH["EXTENSION_NAME"],
      File.join(EXTENSION_ROOT, "main")
    )

    EXTENSION.creator     = "SketchUp"
    EXTENSION.description = LH["EXTENSION_DESCRIPTION"]
    EXTENSION.version     = "1.0.1"
    EXTENSION.copyright   = "2025, #{EXTENSION.creator}"
    Sketchup.register_extension(EXTENSION, true)
  end
end
