# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - MEMBER SYNC
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__MemberSync__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__MemberSync
# AUTHOR     : Noble Architecture
# PURPOSE    : Keeps a run's panels at the sizes the run gives them. A panel is
#              an ordinary element, edited in its own tab (Windows, Cabinets),
#              where its width and height can be typed over. The run sets
#              those from its path, so a panel rebuilt at another size would
#              overlap its neighbours or leave a gap. After such a rebuild the
#              run is rebuilt once, which puts the sizes back, and the user is
#              told where to change them instead.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# WHAT A RUN SETS ON ITS PANELS (Na__PanelTypes.na_apply_size! writes them)
#   Frames   : width, height (less the cill), and with Fuse Framework on, no
#              left or right frame. V2.7.3: a fused window has no frame at
#              all (the run builds its head and bottom rail), and a panel on
#              the run's joined cill has no cill or window board of its own.
#   Cabinets : width.
#   Everything else on a panel (glaze bars, rails, door style, shelves) is
#   the panel type's own and is never touched here.
#
# HOW IT IS TOLD
# - Na__OperationScope tells its commit listeners after every real commit.
#   The listener here looks at the selection only: the element just rebuilt
#   in a tab is the one selected. It SCHEDULES the check (a timer); nothing
#   is built inside the pipeline that committed.
# - An agent's update goes through the seam, which refuses a change to a
#   run-set value before anything is built (na_owned_keys).
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__DataSerializer__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PanelTypes__'
require_relative 'Na__AssemblyStudio__AssemblyRun__RunPipelines__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__MemberSync

# -----------------------------------------------------------------------------
# REGION | Module References, Constants and State
# -----------------------------------------------------------------------------

        DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        Defaults       = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        DataSerializer = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer
        PanelTypes     = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PanelTypes
        RunPipelines   = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunPipelines

        NA_REFIT_OPERATION = "Refit Panel to Run".freeze

        # The element values a run sets, by the element's system. With Fuse
        # Framework on, the side frames are the run's too.
        NA_OWNED_KEYS = {
            PanelTypes::NA_SYSTEM_WINDOWS  => %w[width_mm height_mm].freeze,
            PanelTypes::NA_SYSTEM_CABINETS => %w[Na__CabinetConfig__Width_mm].freeze
        }.freeze
        NA_OWNED_KEYS_FUSED     = %w[advanced_frame_controls frame_left_thickness_mm frame_right_thickness_mm].freeze
        NA_OWNED_KEYS_FRAMELESS = %w[frame_top_thickness_mm frame_bottom_thickness_mm].freeze    # <-- V2.7.3: a fused window's head and bottom are the run's
        NA_OWNED_KEYS_JOINED    = PanelTypes::NA_JOIN_KEYS                                         # <-- V2.7.3: on the run's joined cill

        @na_pending   ||= false     # <-- A check is scheduled
        @na_refitting ||= false     # <-- The commit being heard is this module's own rebuild
        @na_on_refit  ||= nil       # <-- Proc(result Hash) the dialog router sets, to report back

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Who to Tell When a Panel Was Put Back to Its Run's Sizes
        # ------------------------------------------------------------
        # @yield [Hash] { :run, :run_id, :type, :leg, :span, :message }
        def self.na_on_refit(&block)
            @na_on_refit = block
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Panel and Its Run, and Whether the Panel Is Off Its Run's Sizes
        # ------------------------------------------------------------
        # @return [Hash, nil] nil when the instance is no panel of a run (or
        #     the run's stored layout no longer resolves); else { :run,
        #     :run_id, :root, :type, :system, :fuse, :leg, :span, :off }
        def self.na_state_of(member)
            info = DataSerializer.na_member_of(member)
            return nil unless info
            run    = DataSerializer.na_instance_of(info[:run_definition])
            loaded = run ? RunPipelines.na_pipeline_load(run) : nil
            return nil unless loaded

            layout = RunPipelines.na_layout(loaded[:root])
            return nil unless layout[:errors].empty?
            type    = layout[:types][info[:type]]
            row     = PanelTypes.na_row(RunPipelines.na_config(loaded[:root]), info[:type])
            element = Na__AssemblyStudio::Na__McpOperations.na_element_of(member)
            return nil unless type && row && element

            # A trial on copies: would the run change anything it sets?
            fuse = layout[:settings][:fuse] == true
            off  = PanelTypes.na_apply_size!(type[:system], PanelTypes.na_deep_copy(element["root"]), PanelTypes.na_deep_copy(row), type, fuse)
            { :run => run, :run_id => info[:run_id], :root => loaded[:root], :type => type, :system => type[:system], :fuse => fuse,
              :leg => info[:leg], :span => info[:span], :off => off }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Element Values a Run Sets on One of Its Panels
        # ------------------------------------------------------------
        # Read by the agent seam, which refuses a change to any of them.
        # @param type [Hash] the panel type as the layout resolved it
        #     (:frameless, :cill_joined)
        # @return [Array<String>] full value keys
        def self.na_owned_keys(system, fuse, type = {})
            keys = NA_OWNED_KEYS[system] || []
            return keys unless system == PanelTypes::NA_SYSTEM_WINDOWS
            keys += NA_OWNED_KEYS_FUSED if fuse
            keys += NA_OWNED_KEYS_FRAMELESS if fuse && type[:frameless]
            keys += NA_OWNED_KEYS_JOINED if type[:cill_joined]
            keys
        end
        # ---------------------------------------------------------------

        # FUNCTION | After Any Real Commit: Check the Selected Panel, a Moment From Now
        # ------------------------------------------------------------
        # Cheap for everything that is not a panel of a run: one attribute
        # read on the selection.
        def self.na_schedule_for_selection
            return if @na_pending || @na_refitting
            model = Sketchup.active_model
            return unless model && model.selection.length == 1
            member = model.selection.first
            return unless member.is_a?(Sketchup::ComponentInstance) &&
                          member.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_RUN_ID)

            @na_pending = true
            UI.start_timer(0, false) do
                @na_pending = false
                begin
                    na_refit(member) if member.valid?
                rescue StandardError => e
                    DebugTools.na_debug_error("Run panel could not be put back to its run's sizes", e)
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Put a Panel Back to Its Run's Sizes (When It Is Off Them)
        # ------------------------------------------------------------
        # The run is rebuilt from what it stores, which resizes the panel
        # type's element and every span of it. It is an undo step of its
        # own ("Refit Panel to Run"), never a transparent one joined to
        # the edit before it: a failed transparent operation aborts the
        # step it joined, which here would be the user's own edit. Undo
        # goes back in order (measured 16-Nov-2026): the run opened again,
        # the put-back, the run closed for it, then the edit itself.
        # @return [Hash, nil] the result handed to na_on_refit, or nil when
        #     nothing needed doing
        def self.na_refit(member)
            state = na_state_of(member)
            return nil unless state && state[:off]

            @na_refitting = true
            RunPipelines.na_pipeline_update(state[:run], state[:root], operation_name: NA_REFIT_OPERATION)
            result = { :run => state[:run], :run_id => state[:run_id], :type => state[:type][:code], :leg => state[:leg], :span => state[:span],
                       :message => na_message(state) }
            begin
                @na_on_refit.call(result) if @na_on_refit
            rescue StandardError => e
                DebugTools.na_debug_warn("Run panel refit listener failed: #{e.message}")
            end
            result
        ensure
            @na_refitting = false
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | What Was Put Back, and Where to Change It
        # ------------------------------------------------------------
        def self.na_message(state)
            # No sizes are quoted: the run's panel height includes the cill,
            # the element's own Height field does not, and two numbers that
            # disagree would only confuse.
            head = "Panel type #{state[:type][:code]} is sized by its run, #{state[:run_id]}:"
            if state[:system] == PanelTypes::NA_SYSTEM_CABINETS
                return "#{head} its width was put back. Change it on the Assembly Runs tab."
            end
            parts = ["its width", "height"]
            parts << (state[:type][:frameless] ? "frame" : "fused side frames") if state[:fuse]
            parts << "cill and window board" if state[:type][:cill_joined]
            "#{head} #{parts[0..-2].join(', ')} and #{parts.last} were put back. Change them on the Assembly Runs tab."
        end
        private_class_method :na_message
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__MemberSync
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
