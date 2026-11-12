# =============================================================================
# NA AGENT OUTLINER - APP CORE - MAIN
# =============================================================================
#
# FILE       : Na__AgentOutliner__AppCore__Main__.rb
# NAMESPACE  : Na__AgentOutliner
# MODULE     : Na__AgentOutliner (module functions)
# AUTHOR     : Noble Architecture
# PURPOSE    : Constants, the load order of every Agent Outliner file, the one
#              undo wrapper every model change goes through, and the public
#              entry points the Noble 3D Tools loader and router call
# CREATED    : 10-Nov-2026
#
# DESCRIPTION:
# - WHAT IT IS: an Outliner built for working with Claude through the Na
#   SketchUp MCP. It lists the model's groups, components, images and section
#   planes in a sortable, searchable, groupable table; names objects with
#   standard prefixes (CAD__FrontElevation ...); flags objects for an agent;
#   keeps a two way comment thread on any object (Adam to agent, agent to
#   Adam); and tracks what is new or changed, and who did it (Adam or an
#   agent), with colour graded rows.
# - WHERE DATA LIVES:
#     flags and comments : the object's own dictionary Na__AgentOutliner__Notes
#                          (travels with the .skp; written in named undo steps)
#     change history     : 91__UserConfig__LocalOnly/ModelHistory (this PC only;
#                          never written into the model, so tracking adds no
#                          undo steps and never marks the model modified)
#     what has been seen : the same history file (reading a reply is not a
#                          model change)
#     naming standards   : 02__AppData/...NamingStandards__.json (shared by git)
# - AGENTS reach it through the Na SketchUp MCP tools agent_outliner and
#   agent_outliner_edit; 06__McpOperations is the seam they call.
# - LOAD ORDER: the require list below is the first load. Reload Plugin Data
#   `load`s every file in path order, so no file calls another at load time
#   except the deferred observer install at the end of this one, which runs
#   from a timer.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'fileutils'
require 'time'
require 'zlib'

require_relative 'Na__AgentOutliner__AppCore__DebugTools__'
require_relative '../02__AppData/Na__AgentOutliner__AppData__ConfigStore__'
require_relative '../03__ModelData/Na__AgentOutliner__ModelData__Walker__'
require_relative '../03__ModelData/Na__AgentOutliner__ModelData__Notes__'
require_relative '../03__ModelData/Na__AgentOutliner__ModelData__ChatCache__'
require_relative '../03__ModelData/Na__AgentOutliner__ModelData__ChatPick__'
require_relative '../03__ModelData/Na__AgentOutliner__ModelData__Naming__'
require_relative '../03__ModelData/Na__AgentOutliner__ModelData__EntityActions__'
require_relative '../04__ChangeTracking/Na__AgentOutliner__ChangeTracking__ActorDetect__'
require_relative '../04__ChangeTracking/Na__AgentOutliner__ChangeTracking__HistoryStore__'
require_relative '../04__ChangeTracking/Na__AgentOutliner__ChangeTracking__Tracker__'
require_relative '../04__ChangeTracking/Na__AgentOutliner__ChangeTracking__Observers__'
require_relative '../06__McpOperations/Na__AgentOutliner__McpOperations__Payloads__'
require_relative '../06__McpOperations/Na__AgentOutliner__McpOperations__Main__'
require_relative 'Na__AgentOutliner__AppCore__DialogManager__'
require_relative 'Na__AgentOutliner__AppCore__ActionRouter__'
require_relative 'Na__AgentOutliner__AppCore__PluginReloader__'

module Na__AgentOutliner

# -----------------------------------------------------------------------------
# REGION | Constants (guarded: Reload Plugin Data loads this file again)
# -----------------------------------------------------------------------------

    NA_MODULE_ROOT  = File.expand_path('..', __dir__).freeze                          unless defined?(NA_MODULE_ROOT)
    NA_UI_ROOT      = File.join(NA_MODULE_ROOT, '05__UserInterface').freeze             unless defined?(NA_UI_ROOT)
    NA_HTML_FILE    = File.join(NA_UI_ROOT, 'Na__AgentOutliner__UiLayout__.html').freeze unless defined?(NA_HTML_FILE)
    NA_APPDATA_ROOT = File.join(NA_MODULE_ROOT, '02__AppData').freeze                   unless defined?(NA_APPDATA_ROOT)
    NA_LOCAL_ROOT   = File.join(NA_MODULE_ROOT, '91__UserConfig__LocalOnly').freeze     unless defined?(NA_LOCAL_ROOT)
    NA_DICT_NOTES   = 'Na__AgentOutliner__Notes'.freeze                                 unless defined?(NA_DICT_NOTES)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

    # FUNCTION | The Version (a method, not a constant, so a reload updates it)
    # ------------------------------------------------------------
    def self.Na__AgentOutliner__Version
        '0.1.18'
    end
    # ---------------------------------------------------------------

    # FUNCTION | Open the Agent Outliner (Noble 3D Tools Router and Menu)
    # ------------------------------------------------------------
    def self.Na__AgentOutliner__OpenDialog
        Na__AgentOutliner::Na__DialogManager.Na__Dialog__Show
        { success: true, message: 'Agent Outliner opened.' }
    rescue StandardError => error
        Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('The Agent Outliner could not open.', error)
        { success: false, message: "Agent Outliner failed to open: #{error.class}: #{error.message}" }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Show or Hide the Agent Outliner (Noble 3D Tools: the key Adam binds, 0.1.17)
    # ------------------------------------------------------------
    # Open it, or close it when it is open: SketchUp's shortcuts only fire while
    # the model has the keyboard; with the Outliner focused the page closes
    # itself on the same key (DialogManager.Na__Dialog__ToggleKeys).
    def self.Na__AgentOutliner__ToggleDialog
        state = Na__AgentOutliner::Na__DialogManager.Na__Dialog__Toggle
        { success: true, message: state == :closed ? 'Agent Outliner closed.' : 'Agent Outliner opened.' }
    rescue StandardError => error
        Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('The Agent Outliner could not be shown or hidden.', error)
        { success: false, message: "Agent Outliner failed to show or hide: #{error.class}: #{error.message}" }
    end
    # ---------------------------------------------------------------

    # FUNCTION | Reload This Tool's Ruby, HTML, CSS and JS
    # ------------------------------------------------------------
    def self.Na__AgentOutliner__ReloadPluginData
        Na__AgentOutliner::Na__DialogManager.Na__Dialog__ReloadPlugin
    end
    # ---------------------------------------------------------------

    # FUNCTION | Called by the Noble 3D Tools Reload Manager After Its Reload
    # ------------------------------------------------------------
    # Its reload `load`s these files too. The observers stay attached (their
    # classes are reopened, so they run the new code); the dialog is closed
    # and reopened so its HTML, CSS and JS reload.
    def self.Na__AgentOutliner__AfterHostReload
        Na__AgentOutliner::Na__ConfigStore.Na__Config__ClearCache
        Na__AgentOutliner::Na__Observers.Na__Observers__InstallDeferred
        Na__AgentOutliner::Na__DialogManager.Na__Dialog__ReopenIfVisible
        true
    rescue StandardError => error
        Na__AgentOutliner::Na__DebugTools.Na__Debug__Error('The Agent Outliner did not settle after the Noble 3D Tools reload.', error)
        false
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Undo Operations (the one wrapper every model change goes through)
# -----------------------------------------------------------------------------

    # FUNCTION | Run a Block as One Named Undo Step
    # ------------------------------------------------------------
    # Callers validate BEFORE calling this. Raising inside the block aborts the
    # step, so nothing is ever half written. Only an operation this method
    # started is ever aborted. Never transparent: a comment or a rename is its
    # own Ctrl+Z, never folded into whatever Adam or an agent did before it.
    def self.Na__Model__WithOperation(model, operation_name)
        raise ArgumentError, 'No model is open.' unless model

        started = false
        model.start_operation(operation_name.to_s, true)
        started = true
        result = yield
        model.commit_operation
        started = false
        result
    rescue Exception                                                                     # <-- Anything at all (SyntaxError included): abort, then re-raise
        model.abort_operation if started && model
        raise
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Name Adam Signs His Comments With
    # ------------------------------------------------------------
    def self.Na__AgentOutliner__UserName
        name = Na__AgentOutliner::Na__ConfigStore.Na__Config__Setting('user', 'name').to_s.strip
        name.empty? ? 'Adam' : name
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Time Every Record Carries (ISO 8601, local time with offset)
    # ------------------------------------------------------------
    def self.Na__Time__Now
        Time.now.iso8601
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

end # module Na__AgentOutliner

# -----------------------------------------------------------------------------
# REGION | Start Watching (deferred, so SketchUp finishes loading the model)
# -----------------------------------------------------------------------------

begin
    Na__AgentOutliner::Na__Observers.Na__Observers__InstallDeferred
rescue ScriptError, StandardError => error
    puts "[Na__AgentOutliner] Observer install skipped: #{error.class}: #{error.message}"
end

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
