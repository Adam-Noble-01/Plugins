# =============================================================================
# NA PROFILE TOOLS - MCP OPERATIONS - MAIN (THE SEAM AGENTS CALL)
# =============================================================================
#
# FILE       : Na__ProfileTracer__McpOperations__Main__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__McpOperations
# MODULE     : Na__McpOperations (module functions) and Na__McpOperationsError
# AUTHOR     : Noble Architecture
# PURPOSE    : What the Na SketchUp MCP tools profile_tracer (read),
#              profile_tracer_edit (the model) and profile_tracer_library (the
#              profile files) run. The MCP's handler stays thin: it resolves ids,
#              points and the container to build in, then forwards here, exactly
#              as the Agent Outliner, Element Assembly Studio, Point Cloud Viewer
#              and GLB Builder seams work.
# CREATED    : 11-Nov-2026 (v1.6.17)
#
# WHY AGENTS USE THIS PLUGIN (Adam, 11-Nov-2026):
#   Entablatures, wall cappings, cornices, covings, skirtings, window boards and
#   anything else with a standard profile are ALWAYS made with the Profile Path
#   Tracer: it colours and smooths the edges itself, keeps the path and the
#   profile on the trace so Adam can refine either afterwards in its editors,
#   and the library already holds his profiles. Use the closest library profile;
#   make a new one only when nothing fits, and save to the library only when
#   Adam asks.
#
# READ (profile_tracer):
#     status      plugin, library, traces in the model, dialog, Live default
#     profiles    the library: name, size, keywords; query, and near (the
#                 closest profiles to a width and height)
#     profile     one profile: size, outline points, arcs, edge colours, JSON
#     traces      every trace in the model: profile, settings, path, bounds
#     trace       one trace in full: world path, local profile, solid health
#     check_path  a path judged before building: runs, loops, branches, length,
#                 the direction the plugin will sweep it in
# EDIT (profile_tracer_edit), ONE undo step per call ("MCP: Profile Tracer
# Edit (<action>)"), or part of a batch's step:
#     create, set_path, set_placement, swap_profile, set_local_profile,
#     revert_local, regenerate, recreate, rename, delete; open_dialog and
#     reload change no model
# LIBRARY (profile_tracer_library), the profile files, never the model:
#     save_new, overwrite, set_meta, rename_file, redatum, flip, delete
#
# THE SEAM NEVER OPENS AN OPERATION. Every engine is called with
# wrap_in_operation: false, so the MCP owns the undo step: one Ctrl+Z takes a
# whole call back, and a call inside batch_execute joins the batch's step. A
# failure raises Na__McpOperationsError and the MCP aborts the step, so a
# refused call leaves the model exactly as it was.
#
# PARAMS ARRIVE STRING-KEYED. Profile lengths (sizes, stretches, datums,
# offsets) are millimetres in the profile's own Y (across) and Z (up) axes.
# World points arrive already resolved by the MCP handler as Geom::Point3d in
# inches; lengths going back out are multiplied by 'per_inch' (the call's
# unit). The handler also hands over:
#   'model_object'     the open model
#   'world_of'         lambda(instance) -> its definition-to-world transform
#   'path_of'          lambda(entity)   -> the instances from the root down to it
#   'container'        { entities:, to_world:, owner:, label: } where a build goes
#   'entity_objects'   the entities named by 'ids'
#   'path_runs'        [[Point3d, ...], ...] world runs from 'path'
#   'path_segments'    [[Point3d, Point3d], ...] world edges from 'path_edge_ids'
#   'profile_face_object' the face named by 'profile_face_id'
#
# =============================================================================

require 'json'
require 'time'

module Na__ProfileTools__ProfilePathTracer

# -----------------------------------------------------------------------------
# REGION | The Seam's Refusal
# -----------------------------------------------------------------------------

    # CLASS | A Refusal the MCP Shows the Agent As It Is
    # ------------------------------------------------------------
    class Na__McpOperationsError < StandardError
        attr_reader :na_code, :na_hint, :na_details

        def initialize(code, message, hint = nil, details = nil)
            super(message)
            @na_code    = code.to_s
            @na_hint    = hint
            @na_details = details
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        # The action lists are REPLACED on every load, never guarded: Reload
        # Plugin Files re-runs this file, and a guarded list would keep the old
        # actions until SketchUp restarts (the MCP compares its lists to these).
        %i[NA_READ_ACTIONS NA_EDIT_ACTIONS NA_LIBRARY_ACTIONS NA_EDIT_WITHOUT_UNDO NA_SEAM_VERSION].each do |name|
            remove_const(name) if const_defined?(name, false)
        end
        NA_READ_ACTIONS      = %w[status profiles profile traces trace check_path].freeze
        NA_EDIT_ACTIONS      = %w[create set_path set_placement swap_profile set_local_profile revert_local
                                  regenerate recreate rename delete open_dialog reload].freeze
        NA_LIBRARY_ACTIONS   = %w[save_new overwrite set_meta rename_file redatum flip delete].freeze
        # Edit actions that change no model, so the MCP opens no undo step.
        NA_EDIT_WITHOUT_UNDO = %w[open_dialog reload].freeze
        NA_SEAM_VERSION      = '1.0.0'.freeze

        NA_MM_PER_INCH = 25.4 unless defined?(NA_MM_PER_INCH)
        NA_MAX_IDS     = 200 unless defined?(NA_MAX_IDS)
        NA_TOGGLE_KEYS = %w[flipXCenter flipYCenter flipXWorld flipYWorld].freeze unless defined?(NA_TOGGLE_KEYS)

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | The Actions Each Tool Accepts (the MCP checks its lists match)
        # ------------------------------------------------------------
        def self.Na__ProfileTracer__McpActions
            {
                'read'           => NA_READ_ACTIONS.dup,
                'edit'           => NA_EDIT_ACTIONS.dup,
                'library'        => NA_LIBRARY_ACTIONS.dup,
                'edit_no_undo'   => NA_EDIT_WITHOUT_UNDO.dup,
                'seam_version'   => NA_SEAM_VERSION
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | profile_tracer (read only)
        # ------------------------------------------------------------
        def self.Na__ProfileTracer__McpRead(action, params)
            params = self.na_params(params)
            case action.to_s
            when 'status'     then self.na_read_status(params)
            when 'profiles'   then self.na_read_profiles(params)
            when 'profile'    then self.na_read_profile(params)
            when 'traces'     then self.na_read_traces(params)
            when 'trace'      then self.na_read_trace(params)
            when 'check_path' then self.na_read_check_path(params)
            else
                self.na_refuse('invalid_params', "Unknown profile_tracer action '#{action}'.", "Use one of: #{NA_READ_ACTIONS.join(', ')}.")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | profile_tracer_edit (the model; the MCP owns the undo step)
        # ------------------------------------------------------------
        def self.Na__ProfileTracer__McpEdit(action, params)
            params = self.na_params(params)
            # Every sweep paints the SSOT edge materials from the registry, so
            # it is loaded (from the local cache) before anything is built.
            self.na_ensure_edge_colours unless NA_EDIT_WITHOUT_UNDO.include?(action.to_s)
            case action.to_s
            when 'create'            then self.na_edit_create(params)
            when 'set_path'          then self.na_edit_set_path(params)
            when 'set_placement'     then self.na_edit_set_placement(params)
            when 'swap_profile'      then self.na_edit_swap_profile(params)
            when 'set_local_profile' then self.na_edit_set_local_profile(params)
            when 'revert_local'      then self.na_edit_revert_local(params)
            when 'regenerate'        then self.na_edit_regenerate(params)
            when 'recreate'          then self.na_edit_recreate(params)
            when 'rename'            then self.na_edit_rename(params)
            when 'delete'            then self.na_edit_delete(params)
            when 'open_dialog'       then self.na_edit_open_dialog(params)
            when 'reload'            then self.na_edit_reload(params)
            else
                self.na_refuse('invalid_params', "Unknown profile_tracer_edit action '#{action}'.", "Use one of: #{NA_EDIT_ACTIONS.join(', ')}.")
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | profile_tracer_library (the profile files only)
        # ------------------------------------------------------------
        def self.Na__ProfileTracer__McpLibrary(action, params)
            params = self.na_params(params)
            case action.to_s
            when 'save_new'    then self.na_library_save_new(params)
            when 'overwrite'   then self.na_library_overwrite(params)
            when 'set_meta'    then self.na_library_set_meta(params)
            when 'rename_file' then self.na_library_rename_file(params)
            when 'redatum'     then self.na_library_redatum(params)
            when 'flip'        then self.na_library_flip(params)
            when 'delete'      then self.na_library_delete(params)
            else
                self.na_refuse('invalid_params', "Unknown profile_tracer_library action '#{action}'.", "Use one of: #{NA_LIBRARY_ACTIONS.join(', ')}.")
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Status
# -----------------------------------------------------------------------------

        def self.na_read_status(params)
            model    = self.na_model(params)
            profiles = Na__ProfileLibrary.Na__ProfileLibrary__EnabledProfiles
            traces   = self.na_all_traces(model)
            local    = traces.count { |group| Na__DataSerializer.Na__DataSerializer__LocalSource?(group.attribute_dictionary(Na__DataSerializer::NA_PROFILE_TRACE_DICT)) }
            defaults = Na__ProfileTools__ProfilePathTracer.Na__Config__Defaults rescue {}
            self.na_ensure_edge_colours
            edge_status = defined?(Na__EdgeColourManager) ? (Na__EdgeColourManager.Na__EdgeColours__LoadStatus.to_s rescue 'unknown') : 'pending'
            {
                'plugin'  => {
                    'name'        => 'Na Profile Path Tracer',
                    'version'     => self.na_plugin_version,
                    'seam'        => NA_SEAM_VERSION,
                    'library_dir' => Na__EditProfile__LibraryPaths::NA_PROFILE_DATA_DIR
                },
                'library' => { 'profiles' => profiles.length },
                'model'   => {
                    'traces'       => traces.length,
                    'local'        => local,
                    'library'      => traces.length - local,
                    'next_trace_id' => Na__DataSerializer.Na__DataSerializer__GenerateNextProfileTraceId(model)
                },
                'dialog'  => {
                    'open'                 => Na__DialogManager.Na__Dialog__Visible?,
                    'draw_live_by_default' => defaults.is_a?(Hash) ? defaults['drawProfileLiveDefault'] != false : true
                },
                'edge_colours' => edge_status,
                'summary' => "Profile Path Tracer #{self.na_plugin_version}: #{profiles.length} library profiles, #{traces.length} trace(s) in this model (#{local} with their own local profile)."
            }
        end

        # The version the newest devlog entry names (the plugin keeps no
        # version constant).
        def self.na_plugin_version
            devlog = File.join(Na__ProfileTools__ProfilePathTracer::NA_PLUGIN_ROOT, 'Na__ProfileTools__ProfilePathTracer__DEVLOG__.md')
            head = File.exist?(devlog) ? File.read(devlog, 4000, encoding: 'utf-8') : ''
            match = head.match(/v(\d+\.\d+\.\d+)/)
            match ? match[1] : 'unknown'
        rescue
            'unknown'
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Helpers
# -----------------------------------------------------------------------------

        # Without the registry the sweep falls back to raw hex materials named
        # Na__ProfileEdge__<hex> instead of Adam's MTE edge materials.
        def self.na_ensure_edge_colours
            return unless defined?(Na__EdgeColourManager) && Na__EdgeColourManager.respond_to?(:Na__EdgeColours__EnsureLoaded)
            Na__EdgeColourManager.Na__EdgeColours__EnsureLoaded
        end

        def self.na_refuse(code, message, hint = nil, details = nil)
            raise Na__McpOperationsError.new(code, message, hint, details)
        end

        def self.na_params(params)
            params.is_a?(Hash) ? params : {}
        end

        def self.na_model(params)
            model = params['model_object'] || Sketchup.active_model
            self.na_refuse('no_model', 'No model is open.', 'Open a model in SketchUp first.') unless model
            model
        end

        # A key is given when present and not null (the MCP drops nulls too).
        def self.na_has?(params, key)
            params.key?(key) && !params[key].nil?
        end

        def self.na_per_inch(params)
            value = params['per_inch'].to_f
            value > 0 ? value : NA_MM_PER_INCH
        end

        # Inches -> the call's unit, rounded.
        def self.na_out(inches, params, places = 3)
            (inches.to_f * self.na_per_inch(params)).round(places)
        end

        def self.na_point_out(point, params, places = 3)
            [point.x, point.y, point.z].map { |value| self.na_out(value, params, places) }
        end

        def self.na_number(params, key, default = nil, min: nil, max: nil)
            return default unless self.na_has?(params, key)
            value = params[key]
            number = value.is_a?(Numeric) ? value.to_f : Float(value.to_s)
            self.na_refuse('invalid_params', "#{key} must be a finite number.", nil) unless number.finite?
            self.na_refuse('invalid_params', "#{key} must be at least #{min}, not #{number}.", nil) if min && number < min
            self.na_refuse('invalid_params', "#{key} must be at most #{max}, not #{number}.", nil) if max && number > max
            number
        rescue ArgumentError, TypeError
            self.na_refuse('invalid_params', "#{key} must be a number, not #{params[key].inspect}.", nil)
        end

        def self.na_limit(params, default, max)
            [[self.na_number(params, 'limit', default).to_i, 1].max, max].min
        end

        def self.na_offset(params)
            [self.na_number(params, 'offset', 0).to_i, 0].max
        end

        def self.na_bool(params, key, default = false)
            return default unless self.na_has?(params, key)
            value = params[key]
            return value if value == true || value == false
            self.na_refuse('invalid_params', "#{key} must be true or false, not #{value.inspect}.", nil)
        end

        def self.na_text(params, key, default = nil)
            return default unless self.na_has?(params, key)
            params[key].to_s
        end

        def self.na_deep_copy(value)
            JSON.parse(JSON.generate(value))
        end

        # Every trace assembly in the model, once each (a trace inside a
        # component used twice is the same group object both times).
        def self.na_all_traces(model)
            Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model).select(&:valid?).uniq
        end

# endregion -------------------------------------------------------------------

    end # module Na__McpOperations
end # module Na__ProfileTools__ProfilePathTracer

require_relative 'Na__ProfileTracer__McpOperations__Profiles__'
require_relative 'Na__ProfileTracer__McpOperations__Traces__'
require_relative 'Na__ProfileTracer__McpOperations__Library__'

# =============================================================================
# END OF FILE
# =============================================================================
