require 'sketchup.rb'
require 'extensions.rb'
require 'fileutils'

module SketchUpDiffusion
	if Sketchup.version.to_i >= 24
		file = __FILE__.dup
		file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
		path = File.dirname(file)

		loader = File.join(path, "su_diffusion/su_loader")

		extension = SketchupExtension.new('AI Render', loader)
		extension.description = 'AI Render'
		extension.version     = '1.2025.12.12'
		extension.copyright   = 'Trimble Inc. 2025'
		extension.creator = 'Trimble'
		@@mCurrentVersion = extension.version
		@@mCurrentExtensionPath = extension.extension_path

		Sketchup.register_extension(extension, true)
	else
		message = "SketchUp 2024.0 or higher is required to use this version of the AI Render Extension.\n\nPlease disable the extension or remove it from your plugins folder."
		UI.messagebox(message)
	end
end
