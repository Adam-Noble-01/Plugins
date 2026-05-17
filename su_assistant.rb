require 'sketchup.rb'
require 'extensions.rb'
require 'fileutils'

module SketchupAssistant
  EXTENSION_NAME = 'AI Assistant'.freeze

  if Sketchup.version.to_i >= 24
    file = __FILE__.dup
    file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
    path = File.dirname(file)
    loader = File.join(path, "su_assistant/su_assistant_root_proxy")
    Extension = SketchupExtension.new(EXTENSION_NAME, loader)
    Extension.description = EXTENSION_NAME
    Extension.version     = '1.0.3'
    Extension.copyright   = 'Trimble Inc. 2025'
    Extension.creator = 'Trimble'

    # Define uninstall callback to avoid errors during uninstallation
    def Extension.mark_as_uninstalled
      SketchupAssistant.log("#{EXTENSION_NAME} extension is being uninstalled")
      ""  # Return empty string as expected by SketchUp's CallRubyMethod
    end

    Sketchup.register_extension(Extension, true)
  else
    message = "SketchUp 2024 or higher is required to use #{EXTENSION_NAME}."
    UI.messagebox(message)
  end
end
