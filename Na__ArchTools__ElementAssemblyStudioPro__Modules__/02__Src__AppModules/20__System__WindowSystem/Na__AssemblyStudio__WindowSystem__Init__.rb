# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM INIT PARTIAL
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__Init__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem::Na__Init
# AUTHOR     : Noble Architecture
# PURPOSE    : Window-system specific init partial called by AppCore::Main.
#              Owns NA_DEFAULT_CONFIG, registers the window dialog callbacks
#              with AppCore::DialogManager via UiBridge.na_register_callbacks,
#              and registers the window selection handler with the
#              SelectionCoordinator.
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__DialogManager__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__UiBridge__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__SelectionCoordinator__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__SerializerBase__'
require_relative 'Na__AssemblyStudio__WindowSystem__Defaults__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__WindowSystem__LeadedGlassBuilder__'
require_relative 'Na__AssemblyStudio__WindowSystem__SashHornBuilder__'
require_relative 'Na__AssemblyStudio__WindowSystem__EdgeColourPainter__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryEngine__'
require_relative 'Na__AssemblyStudio__WindowSystem__DataSerializer__'
require_relative 'Na__AssemblyStudio__WindowSystem__DxfExporter__'
require_relative 'Na__AssemblyStudio__WindowSystem__FuseParts__'
require_relative 'Na__AssemblyStudio__WindowSystem__DialogCallbacks__'
require_relative 'Na__AssemblyStudio__WindowSystem__SelectionHandler__'

module Na__AssemblyStudio
    module Na__WindowSystem
        module Na__Init

            DebugTools           = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
            DialogManager        = Na__AssemblyStudio::Na__AppCore::Na__DialogManager
            UiBridge             = Na__AssemblyStudio::Na__AppCore::Na__UiBridge
            SelectionCoordinator = Na__AssemblyStudio::Na__AppCore::Na__SelectionCoordinator
            DialogCallbacks      = Na__AssemblyStudio::Na__WindowSystem::Na__DialogCallbacks
            SelectionHandler     = Na__AssemblyStudio::Na__WindowSystem::Na__SelectionHandler

            def self.na_init
                DebugTools.na_debug_method("WindowSystem::Init.na_init")

                SelectionCoordinator.na_register_handler(SelectionHandler.na_handler_descriptor)

                DialogManager.na_register_system_init_hook do |dialog|
                    UiBridge.na_register_callbacks(dialog, DialogCallbacks.na_callback_registry)
                    DialogCallbacks.na_attach_dialog(dialog)
                    DialogCallbacks.na_check_initial_selection
                end
            end

        end
    end
end
