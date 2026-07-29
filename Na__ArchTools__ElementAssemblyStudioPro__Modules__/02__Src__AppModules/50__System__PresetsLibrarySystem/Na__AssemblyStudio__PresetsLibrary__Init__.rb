# frozen_string_literal: true

# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - PRESETS LIBRARY INIT PARTIAL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__PresetsLibrary__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__PresetsLibrarySystem
# MODULE     : Na__Init
# AUTHOR     : Noble Architecture
# CREATED    : 2026
# PURPOSE    : Presets-library specific init partial called by AppCore::Main.
#              Registers the presets dialog callbacks with
#              AppCore::DialogManager via UiBridge.na_register_callbacks.
#
# DESCRIPTION
# - Requires the Store + DialogCallbacks partials for the presets system.
# - Registers a DialogManager init hook so every dialog (re)open rebinds the
#   presets callbacks and hands the live dialog to DialogCallbacks.
# - No proactive push is scheduled: the JS bridge requests the library once
#   the DOM is ready (sketchup.na_presetsRequestLibrary) and the gallery
#   re-requests on mount if its cache is empty.
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative 'Na__AssemblyStudio__PresetsLibrary__Store__'
require_relative 'Na__AssemblyStudio__PresetsLibrary__DialogCallbacks__'

module Na__AssemblyStudio
    module Na__PresetsLibrarySystem
        module Na__Init

            DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            DialogManager   = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
            UiBridge        = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
            DialogCallbacks = Na__AssemblyStudio::Na__PresetsLibrarySystem::Na__DialogCallbacks

            # -----------------------------------------------------------------
            # REGION | System Init Entry Point
            # -----------------------------------------------------------------

            # FUNCTION | Initialise the Presets Library System
            # ------------------------------------------------------------
            # @return [void]
            def self.na_init
                DebugTools.na_debug_method("PresetsLibrarySystem::Init.na_init")

                DialogManager.na_register_system_init_hook do |dialog|
                    UiBridge.na_register_callbacks(dialog, DialogCallbacks.na_callback_registry)
                    DialogCallbacks.na_attach_dialog(dialog)
                end
            end
            # ---------------------------------------------------------------

        end
    end
end
