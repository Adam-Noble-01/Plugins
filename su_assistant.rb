require 'sketchup.rb'
require 'extensions.rb'
require 'fileutils'

module SketchupAssistant
  EXTENSION_NAME = 'AI Assistant'.freeze unless const_defined?(:EXTENSION_NAME, false)

  # A manually installed copy can coexist with SketchUp's auto-installed one
  # under a differently-cased path, causing this file to load twice
  # (forums.sketchup.com/t/342259/60). Guard against re-registering; scoped
  # with inherit: false so an unrelated top-level ::Extension isn't mistaken
  # for ours.
  if const_defined?(:Extension, false)
    # Already loaded from another path; nothing to do.
  elsif Sketchup.version.to_i >= 24
    file = __FILE__.dup
    file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
    path = File.dirname(file)
    loader = File.join(path, "su_assistant/su_assistant_root_proxy")
    Extension = SketchupExtension.new(EXTENSION_NAME, loader)
    Extension.description = 'Talk to SketchUp. Get help. Generate objects.'
    Extension.version     = '1.0.6'
    Extension.copyright   = 'Trimble Inc. 2026'
    Extension.creator = 'Trimble'

    # Define uninstall callback to avoid errors during uninstallation.
    # SketchupAssistant.log lives in su_assistant_root.rb, which only loads
    # through the proxy - uninstalling a disabled extension would otherwise
    # raise NoMethodError from the very callback meant to prevent errors.
    def Extension.mark_as_uninstalled
      if SketchupAssistant.respond_to?(:log)
        SketchupAssistant.log("#{EXTENSION_NAME} extension is being uninstalled")
      end
      ""  # Return empty string as expected by SketchUp's CallRubyMethod
    end

    Sketchup.register_extension(Extension, true)
  else
    # Console only, never a modal. UI.messagebox here fired on every launch of
    # an unsupported SketchUp, blocking startup with a dialog the user can do
    # nothing about; the Extension Warehouse listing's minimum-version metadata
    # is what keeps this build off those releases.
    puts("#{EXTENSION_NAME}: SketchUp 2024 or higher is required; not loading.")
  end
end
