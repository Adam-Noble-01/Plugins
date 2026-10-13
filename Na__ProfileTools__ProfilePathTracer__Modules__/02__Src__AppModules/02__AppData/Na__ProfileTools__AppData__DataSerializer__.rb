# =============================================================================
# NA PROFILE TOOLS - APP DATA - DATA SERIALIZER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppData__DataSerializer__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DataSerializer
# PURPOSE    : AttributeDictionary stamping, reading, and ID management for
#              Profile Trace assemblies. Enables the Dynamic Regeneration system
#              to identify, cross-link, and reconstruct profile trace groups.
#
# DICTIONARY SCHEMA
#   Parent assembly group  -> Na__ProfilePathTracer__Info
#     ProfileTraceId       String   e.g. "NPT0001"
#     ProfileKey           String   Library key used to generate the profile
#     RotationStep         Integer  0-3
#     ToggleStates         String   JSON-encoded hash of toggle flags
#     IsClosedLoop         String   "true" | "false"
#     StartPoint           String   JSON-encoded [x, y, z] in inches, in PARENT
#                                   space (the assembly's own axes, before any
#                                   Reverse flip). The build pins the assembly to
#                                   the world axes (v1.6.12), so parent space is
#                                   world space as built, inside a group or not.
#     ReverseDirection     String   "true" | "false"
#     OriginOffset         String   JSON-encoded [y_mm, z_mm] datum shift
#     PathRuns             String   THE PATH (v1.6.16). JSON-encoded
#                                   [{"Points": [[x,y,z], ...], "IsClosedLoop": b}, ...]
#                                   in inches, in parent space like StartPoint:
#                                   every run the trace sweeps, in traversal
#                                   order, a loop's closing edge implied. Every
#                                   rebuild sweeps these. Edit Path draws them as
#                                   a red line for the edit and reads them back.
#     PathPoints           String   JSON-encoded [[x,y,z], ...] in inches, in
#                                   parent space like StartPoint: the PRIMARY
#                                   run only, kept for older readers and as the
#                                   last fallback for a trace with no PathRuns.
#     StartOffset          String   mm (signed) the sweep overshoots (+) or trims
#                                   (-) at the TRAVERSAL start of an open run —
#                                   the end nearest StartPoint. "0" on loops.
#     EndOffset            String   mm (signed), same at the traversal end.
#     OffsetEndsSwapped    String   "true" when the user's "Start" offset is the
#                                   stored EndOffset (an Interactive run the
#                                   canonical direction rule reversed). Geometry
#                                   never reads it; the swap engine does, so a
#                                   bound trace shows and takes offsets as typed.
#     DynamicRegenEnabled  String   LEGACY (to v1.6.15): "false" switched a
#                                   trace's Helpers linework off from rebuilding.
#     HelpersFingerprint   String   LEGACY (to v1.6.15): SHA1 of the Helpers
#                                   linework the solid was built from. Both are
#                                   deleted when a trace's Helpers are retired.
#     SchemaVersion        String   "1.2.0"
#     CreatedAt            String   ISO-8601 timestamp
#     ProfileSource        String   "library" | "local" (v1.6.14; absent = library)
#     LocalProfile         String   JSON of the trace's OWN profile asset data
#                                   (Profile2D + Mesh3D), drawn in the Draw
#                                   Profile tab and kept on this trace only.
#                                   While ProfileSource is "local" the rebuild
#                                   sweeps this instead of the library key;
#                                   ProfileKey stays the key it was drawn from.
#     LocalProfileName     String   what the local profile is called on screen
#
#   Edit Path group        -> Na__ProfilePathTracer__EditPathInfo (v1.6.16)
#     ProfileTraceId       String   Back-reference to the parent assembly id
#     BaselineFingerprint  String   SHA1 of the red line as it was drawn, so an
#                                   edit that changed nothing closes without a
#                                   rebuild
#     ForceRebuild         String   "true" when the path came from Helpers
#                                   linework that had been edited without a
#                                   rebuild: the solid must follow it even if
#                                   the red line is left as it is
#     SchemaVersion        String   "1.2.0"
#   The group (Na__ProfileTrace__EditPath) exists only while the path is being
#   edited. It is untagged, its edges painted red (MTE201).
#
#   Helpers sub-group      -> Na__ProfilePathTracer__HelpersInfo (LEGACY, to v1.6.15)
#     ProfileTraceId       String   Back-reference to the parent assembly id
#     SchemaVersion        String   "1.2.0"
#   Traces built before v1.6.16 carry their path as edges in this group, on the
#   02__ProfilePathTracer_Helpers tag. The first rebuild or Edit Path moves the
#   path into PathRuns and erases the group (Na__DataSerializer__RetireLegacyHelpers).
#
# SCHEMA COMPATIBILITY
#   1.0.0 assemblies (no ReverseDirection / OriginOffset / PathPoints) still
#   read back cleanly — the added keys default to false / nil / [] so an older
#   trace regenerates exactly as it did before. StartOffset / EndOffset /
#   OffsetEndsSwapped (v1.6.11) are optional in the same way: absent reads as
#   0 / 0 / false, which is exactly how every earlier trace was swept, so they
#   did not need a schema bump. PathRuns (v1.6.16) needs none either: a trace
#   without it is a legacy trace, read from its Helpers linework (or, with
#   none left, from PathPoints) until its first rebuild writes PathRuns.
#   1.2.0 marks assemblies built with the WYSIWYG (mirrored) path frame that
#   matches the 2D dialog preview. Traces stamped 1.1.0 or earlier were swept
#   with the legacy right-handed frame; the RegenerationEngine reads this
#   version and rebuilds them with that legacy frame so regeneration can never
#   mirror geometry that already stands in a model.
#
# PUBLIC API
#   Na__DataSerializer__StampParent(parent_group, payload_hash)
#   Na__DataSerializer__StampHelpers(helpers_group, profile_trace_id)
#   Na__DataSerializer__ReadParentPayload(group) -> Hash or nil
#   Na__DataSerializer__UpdateParentPlacement(parent_group, updates) -> Boolean
#   Na__DataSerializer__WritePathRuns(parent_group, runs) -> Boolean
#   Na__DataSerializer__ReadPathRuns(parent_group) -> [run, ...] or nil
#   Na__DataSerializer__IsProfileTraceParent?(group) -> Boolean
#   Na__DataSerializer__IsEditPathGroup?(group) -> Boolean
#   Na__DataSerializer__FindEditPathGroup(parent_group) -> group or nil
#   Na__DataSerializer__FindParentFromEditGroup(edit_group) -> group or nil
#   Na__DataSerializer__StampEditPathGroup(edit_group, trace_id, baseline, force)
#   Na__DataSerializer__IsHelpersSubGroup?(group) -> Boolean            (legacy)
#   Na__DataSerializer__FindHelpersSubGroup(parent_group) -> group or nil (legacy)
#   Na__DataSerializer__RetireLegacyHelpers(parent_group) -> Integer    (legacy)
#   Na__DataSerializer__GenerateNextProfileTraceId(model) -> String
#
#   A run is { ordered_points: [Geom::Point3d, ...], is_closed_loop: Boolean },
#   the shape Na__PathAnalysis builds and the regeneration engine sweeps.
#
# =============================================================================

require 'json'
require 'time'

module Na__ProfileTools__ProfilePathTracer
    module Na__DataSerializer

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_PROFILE_TRACE_DICT  = 'Na__ProfilePathTracer__Info'.freeze
        NA_HELPERS_DICT        = 'Na__ProfilePathTracer__HelpersInfo'.freeze
        # 1.2.0 = swept with the WYSIWYG path frame (matches the 2D dialog).
        # Earlier versions were swept with the legacy right-handed frame — the
        # RegenerationEngine keys its frame choice off this stored value.
        NA_SCHEMA_VERSION      = '1.2.0'.freeze
        NA_ID_PREFIX           = 'NPT'.freeze
        NA_ID_REGEX            = /^NPT\d{4}$/.freeze
        NA_HELPERS_GROUP_NAME  = 'Na__ProfileTrace__Helpers'.freeze
        NA_SOLID_GROUP_NAME    = 'Na__ProfileTrace__SweptSolid'.freeze
        NA_EDIT_PATH_DICT       = 'Na__ProfilePathTracer__EditPathInfo'.freeze
        NA_EDIT_PATH_GROUP_NAME = 'Na__ProfileTrace__EditPath'.freeze
        NA_PATH_RUNS_KEY        = 'PathRuns'.freeze
        # Legacy only: what v1.6.15 and older appended to a trace's name.
        NA_LEGACY_DYNREGEN_SUFFIX = ' [DynRegen]'.freeze
        NA_LEGACY_KEYS            = %w[HelpersFingerprint DynamicRegenEnabled].freeze
        NA_LOCAL_PROFILE_KEY      = 'LocalProfile'.freeze
        NA_LOCAL_PROFILE_NAME_KEY = 'LocalProfileName'.freeze
        NA_PROFILE_SOURCE_KEY     = 'ProfileSource'.freeze

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Stamp Operations
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__StampParent(parent_group, payload_hash)
            return unless parent_group && payload_hash.is_a?(Hash)

            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            dict['ProfileTraceId']      = payload_hash['ProfileTraceId'].to_s
            dict['ProfileKey']          = payload_hash['ProfileKey'].to_s
            dict['RotationStep']        = payload_hash['RotationStep'].to_i.to_s
            dict['ToggleStates']        = self.Na__DataSerializer__SerialiseToggleStates(payload_hash['ToggleStates'])
            dict['IsClosedLoop']        = (payload_hash['IsClosedLoop'] == true).to_s
            dict['StartPoint']          = self.Na__DataSerializer__SerialisePoint(payload_hash['StartPoint'])
            dict['ReverseDirection']    = (payload_hash['ReverseDirection'] == true).to_s
            dict['OriginOffset']        = self.Na__DataSerializer__SerialiseOriginOffset(payload_hash['OriginOffset'])
            dict['PathPoints']          = self.Na__DataSerializer__SerialisePointList(payload_hash['PathPoints'])
            dict[NA_PATH_RUNS_KEY]      = self.Na__DataSerializer__SerialisePathRuns(
                payload_hash['PathRuns'] ||
                [{ ordered_points: Array(payload_hash['PathPoints']), is_closed_loop: payload_hash['IsClosedLoop'] == true }]
            )
            path_offsets                = payload_hash['PathOffsets'].is_a?(Hash) ? payload_hash['PathOffsets'] : {}
            dict['StartOffset']         = self.Na__DataSerializer__SerialiseOffsetMm(path_offsets['start'])
            dict['EndOffset']           = self.Na__DataSerializer__SerialiseOffsetMm(path_offsets['end'])
            dict['OffsetEndsSwapped']   = (payload_hash['OffsetEndsSwapped'] == true).to_s
            dict['SchemaVersion']       = NA_SCHEMA_VERSION
            dict['CreatedAt']           = Time.now.utc.iso8601
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: StampParent failed: #{error.message}")
        end

        def self.Na__DataSerializer__WritePathPoints(parent_group, points)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            return false unless dict
            dict['PathPoints'] = self.Na__DataSerializer__SerialisePointList(points)
            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: WritePathPoints failed: #{error.message}")
            false
        end

        # The path every rebuild sweeps: written by the build and by every
        # rebuild, inside the same operation as the geometry, so undo and redo
        # keep the stored path and the solid together. PathPoints follows the
        # primary run for older readers. Points go in exactly as given (parent
        # space, inches): JSON keeps a Float to the last bit, so a path read
        # back and written again without an edit is unchanged, however often.
        def self.Na__DataSerializer__WritePathRuns(parent_group, runs)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            list = Array(runs).select { |run| run.is_a?(Hash) && Array(run[:ordered_points]).length >= 2 }
            return false if list.empty?
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            return false unless dict
            dict[NA_PATH_RUNS_KEY] = self.Na__DataSerializer__SerialisePathRuns(list)
            dict['PathPoints']     = self.Na__DataSerializer__SerialisePointList(list.first[:ordered_points])
            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: WritePathRuns failed: #{error.message}")
            false
        end

        # The stored runs, or nil when the trace has none (a legacy trace).
        def self.Na__DataSerializer__ReadPathRuns(parent_group)
            return nil unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return nil unless dict
            runs = self.Na__DataSerializer__DeserialisePathRuns(dict[NA_PATH_RUNS_KEY])
            runs.empty? ? nil : runs
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: ReadPathRuns failed: #{error.message}")
            nil
        end

        # Patches ONLY the placement values a profile hot-swap is allowed to
        # touch, leaving ProfileTraceId, StartPoint, CreatedAt, SchemaVersion,
        # ReverseDirection, OffsetEndsSwapped and DynamicRegenEnabled exactly as
        # stamped. StartOffset / EndOffset arrive already in traversal order.
        #
        # SchemaVersion in particular must never be bumped here: it is what tells
        # the RegenerationEngine whether an assembly was swept with the legacy
        # right-handed path frame, and rewriting it would mirror geometry that
        # already stands in a model.
        #
        # Only keys present in `updates` are written. 'OriginOffset' => nil is a
        # meaningful instruction (clear the datum), so presence of the key, not
        # its value, decides whether it is applied.
        def self.Na__DataSerializer__UpdateParentPlacement(parent_group, updates)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            return false unless updates.is_a?(Hash)

            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            return false unless dict

            dict['ProfileKey']   = updates['ProfileKey'].to_s               if updates.key?('ProfileKey')
            dict['RotationStep'] = (updates['RotationStep'].to_i % 4).to_s  if updates.key?('RotationStep')

            if updates.key?('ToggleStates')
                dict['ToggleStates'] = self.Na__DataSerializer__SerialiseToggleStates(updates['ToggleStates'])
            end
            if updates.key?('OriginOffset')
                dict['OriginOffset'] = self.Na__DataSerializer__SerialiseOriginOffset(updates['OriginOffset'])
            end
            dict['StartOffset'] = self.Na__DataSerializer__SerialiseOffsetMm(updates['StartOffset']) if updates.key?('StartOffset')
            dict['EndOffset']   = self.Na__DataSerializer__SerialiseOffsetMm(updates['EndOffset'])   if updates.key?('EndOffset')

            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: UpdateParentPlacement failed: #{error.message}")
            false
        end

        # The fingerprint travels with the geometry through undo/redo (it is a
        # dictionary value on the parent), so a reverted edit never reads as a
        # pending change. Callers write it inside their open operation.
        def self.Na__DataSerializer__WriteHelpersFingerprint(parent_group, fingerprint)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            return false unless fingerprint.is_a?(String) && !fingerprint.empty?
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            dict['HelpersFingerprint'] = fingerprint
            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: WriteHelpersFingerprint failed: #{error.message}")
            false
        end

        def self.Na__DataSerializer__ReadHelpersFingerprint(parent_group)
            return nil unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return nil unless dict
            value = dict['HelpersFingerprint']
            value.is_a?(String) ? value : nil
        rescue
            nil
        end

        def self.Na__DataSerializer__ReadTraceId(parent_group)
            return '' unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return '' unless dict
            dict['ProfileTraceId'].to_s
        rescue
            ''
        end

        # Used by the copy repair: a duplicated assembly keeps its cloned id
        # until re-stamped here (parent id + helpers back-reference together).
        def self.Na__DataSerializer__RestampTraceId(parent_group, new_trace_id)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            return false unless new_trace_id.is_a?(String) && new_trace_id.match?(NA_ID_REGEX)

            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            dict['ProfileTraceId'] = new_trace_id

            helpers_group = self.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            self.Na__DataSerializer__StampHelpers(helpers_group, new_trace_id) if helpers_group
            edit_group = self.Na__DataSerializer__FindEditPathGroup(parent_group)
            if edit_group
                edit_dict = edit_group.attribute_dictionary(NA_EDIT_PATH_DICT, true)
                edit_dict['ProfileTraceId'] = new_trace_id
            end
            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: RestampTraceId failed: #{error.message}")
            false
        end

        def self.Na__DataSerializer__StampHelpers(helpers_group, profile_trace_id)
            return unless helpers_group && profile_trace_id.is_a?(String)

            dict = helpers_group.attribute_dictionary(NA_HELPERS_DICT, true)
            dict['ProfileTraceId'] = profile_trace_id
            dict['SchemaVersion']  = NA_SCHEMA_VERSION
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: StampHelpers failed: #{error.message}")
        end

        def self.Na__DataSerializer__StampEditPathGroup(edit_group, profile_trace_id, baseline_fingerprint, force_rebuild)
            return unless edit_group
            dict = edit_group.attribute_dictionary(NA_EDIT_PATH_DICT, true)
            dict['ProfileTraceId']      = profile_trace_id.to_s
            dict['BaselineFingerprint'] = baseline_fingerprint.to_s
            dict['ForceRebuild']        = (force_rebuild == true).to_s
            dict['SchemaVersion']       = NA_SCHEMA_VERSION
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: StampEditPathGroup failed: #{error.message}")
        end

        # { 'baseline' => String, 'forceRebuild' => Boolean } for an Edit Path group.
        def self.Na__DataSerializer__EditPathGroupInfo(edit_group)
            dict = edit_group && edit_group.respond_to?(:attribute_dictionary) ? edit_group.attribute_dictionary(NA_EDIT_PATH_DICT) : nil
            return { 'baseline' => '', 'forceRebuild' => false } unless dict
            { 'baseline' => dict['BaselineFingerprint'].to_s, 'forceRebuild' => dict['ForceRebuild'] == 'true' }
        rescue
            { 'baseline' => '', 'forceRebuild' => false }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Read Operations
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__ReadParentPayload(group)
            return nil unless group && group.respond_to?(:attribute_dictionary)
            dict = group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return nil unless dict

            {
                'ProfileTraceId'     => dict['ProfileTraceId'].to_s,
                'ProfileKey'         => dict['ProfileKey'].to_s,
                'RotationStep'       => dict['RotationStep'].to_i,
                'ToggleStates'       => self.Na__DataSerializer__DeserialiseToggleStates(dict['ToggleStates']),
                'IsClosedLoop'       => dict['IsClosedLoop'] == 'true',
                'StartPoint'         => self.Na__DataSerializer__DeserialisePoint(dict['StartPoint']),
                'ReverseDirection'   => dict['ReverseDirection'] == 'true',
                'OriginOffset'       => self.Na__DataSerializer__DeserialiseOriginOffset(dict['OriginOffset']),
                'PathPoints'         => self.Na__DataSerializer__DeserialisePointList(dict['PathPoints']),
                'StartOffset'        => self.Na__DataSerializer__DeserialiseOffsetMm(dict['StartOffset']),
                'EndOffset'          => self.Na__DataSerializer__DeserialiseOffsetMm(dict['EndOffset']),
                'OffsetEndsSwapped'  => dict['OffsetEndsSwapped'] == 'true',
                'SchemaVersion'      => dict['SchemaVersion'].to_s,
                # The local profile itself is only parsed where it is swept
                # (Na__DataSerializer__LocalProfileRecord): every reader of
                # this payload would otherwise pay for the JSON.
                'ProfileSource'      => self.Na__DataSerializer__LocalSource?(dict) ? 'local' : 'library',
                'LocalProfileName'   => dict[NA_LOCAL_PROFILE_NAME_KEY].to_s
            }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: ReadParentPayload failed: #{error.message}")
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Local Profiles (v1.6.14)
    # -------------------------------------------------------------------------

        # A local profile belongs to ONE trace: the Draw Profile tab's "Update
        # This Trace" and its Live mode write it, so a trace can be changed
        # without touching the library file every other trace shares. A copy
        # of the trace copies the dictionary, so the copy keeps the same shape
        # and goes its own way from there.
        def self.Na__DataSerializer__WriteLocalProfile(parent_group, asset_data, display_name)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            return false unless asset_data.is_a?(Hash)
            self.Na__DataSerializer__WriteLocalProfileJson(parent_group, JSON.generate(asset_data), display_name)
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: WriteLocalProfile failed: #{error.message}")
            false
        end

        def self.Na__DataSerializer__WriteLocalProfileJson(parent_group, json_text, display_name)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            return false unless json_text.is_a?(String) && !json_text.empty?
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            dict[NA_LOCAL_PROFILE_KEY]      = json_text
            dict[NA_LOCAL_PROFILE_NAME_KEY] = display_name.to_s
            dict[NA_PROFILE_SOURCE_KEY]     = 'local'
            true
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: WriteLocalProfileJson failed: #{error.message}")
            false
        end

        # Back to the library key. Returns true if there was a local profile.
        def self.Na__DataSerializer__ClearLocalProfile(parent_group)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return false unless dict
            had_local = self.Na__DataSerializer__LocalSource?(dict)
            dict.delete_key(NA_LOCAL_PROFILE_KEY) unless dict[NA_LOCAL_PROFILE_KEY].nil?
            dict.delete_key(NA_LOCAL_PROFILE_NAME_KEY) unless dict[NA_LOCAL_PROFILE_NAME_KEY].nil?
            dict[NA_PROFILE_SOURCE_KEY] = 'library' unless dict[NA_PROFILE_SOURCE_KEY].nil?
            had_local
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: ClearLocalProfile failed: #{error.message}")
            false
        end

        # { 'json' => raw text, 'name' => ... } or nil: what a rollback needs
        # to put the local profile back exactly as it was.
        def self.Na__DataSerializer__ReadLocalProfileRaw(parent_group)
            return nil unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return nil unless dict && self.Na__DataSerializer__LocalSource?(dict)
            { 'json' => dict[NA_LOCAL_PROFILE_KEY], 'name' => dict[NA_LOCAL_PROFILE_NAME_KEY].to_s }
        rescue
            nil
        end

        # The local profile as a unified profile record (the shape the library
        # hands out), or nil when the trace has none or it does not parse.
        def self.Na__DataSerializer__LocalProfileRecord(parent_group)
            raw = self.Na__DataSerializer__ReadLocalProfileRaw(parent_group)
            return nil unless raw
            asset_data = JSON.parse(raw['json'])
            return nil unless asset_data.is_a?(Hash)
            trace_id = self.Na__DataSerializer__ReadTraceId(parent_group)
            name = raw['name'].to_s.strip
            name = "Local profile of #{trace_id}" if name.empty?
            {
                'profileKey'     => "LOCAL__#{trace_id}",
                'displayName'    => name,
                'shortName'      => '',
                'category'       => 'Local',
                'isEnabled'      => true,
                'isLocal'        => true,
                'baseProfileKey' => parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)['ProfileKey'].to_s,
                'sourceFile'     => '',
                'profileData'    => {
                    'type'           => 'na_unified_asset',
                    'schemaContract' => 'meta + Na__Asset__Metadata + Na__Asset__Profile2D + Na__Asset__Mesh3D',
                    'assetData'      => asset_data,
                    'units'          => 'mm'
                }
            }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: local profile unreadable: #{error.message}")
            nil
        end

        def self.Na__DataSerializer__LocalSource?(dict)
            dict[NA_PROFILE_SOURCE_KEY] == 'local' && dict[NA_LOCAL_PROFILE_KEY].is_a?(String) && !dict[NA_LOCAL_PROFILE_KEY].empty?
        rescue
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Discriminators
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__IsProfileTraceParent?(group)
            return false unless self.Na__DataSerializer__GroupValid?(group)
            dict = group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return false unless dict
            id = dict['ProfileTraceId'].to_s
            id.match?(NA_ID_REGEX)
        rescue
            false
        end

        def self.Na__DataSerializer__IsHelpersSubGroup?(group)
            return false unless self.Na__DataSerializer__GroupValid?(group)
            dict = group.attribute_dictionary(NA_HELPERS_DICT)
            return false unless dict
            id = dict['ProfileTraceId'].to_s
            id.match?(NA_ID_REGEX)
        rescue
            false
        end

        def self.Na__DataSerializer__IsEditPathGroup?(group)
            return false unless self.Na__DataSerializer__GroupValid?(group)
            return false unless group.is_a?(Sketchup::Group)
            !group.attribute_dictionary(NA_EDIT_PATH_DICT).nil?
        rescue
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Group Navigation
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__FindHelpersSubGroup(parent_group)
            return nil unless self.Na__DataSerializer__GroupValid?(parent_group)
            parent_group.entities.grep(Sketchup::Group).find do |child|
                child.name == NA_HELPERS_GROUP_NAME || self.Na__DataSerializer__IsHelpersSubGroup?(child)
            end
        rescue
            nil
        end

        def self.Na__DataSerializer__FindSolidSubGroup(parent_group)
            return nil unless self.Na__DataSerializer__GroupValid?(parent_group)
            parent_group.entities.grep(Sketchup::Group).find do |child|
                child.name == NA_SOLID_GROUP_NAME
            end
        rescue
            nil
        end

        # The red line Edit Path spawns (v1.6.16). It exists only while the
        # path is being edited, or after an undo has brought it back.
        def self.Na__DataSerializer__FindEditPathGroup(parent_group)
            self.Na__DataSerializer__FindEditPathGroups(parent_group).first
        end

        def self.Na__DataSerializer__FindEditPathGroups(parent_group)
            return [] unless self.Na__DataSerializer__GroupValid?(parent_group)
            parent_group.entities.grep(Sketchup::Group).select do |child|
                self.Na__DataSerializer__IsEditPathGroup?(child)
            end
        rescue
            []
        end

        def self.Na__DataSerializer__FindParentFromEditGroup(edit_group)
            return nil unless self.Na__DataSerializer__GroupValid?(edit_group)
            direct_parent = self.Na__DataSerializer__ContainingInstance(edit_group)
            return direct_parent if direct_parent && self.Na__DataSerializer__IsProfileTraceParent?(direct_parent)
            nil
        rescue
            nil
        end

        # LEGACY. Moves a pre-v1.6.16 trace off its Helpers linework: erases the
        # Helpers group (and with it the trace's only use of the
        # 02__ProfilePathTracer_Helpers tag), deletes the fingerprint and
        # Dynamic Regeneration keys, and drops the " [DynRegen]" name suffix.
        # The caller has written PathRuns first and holds the open operation.
        # Returns the number of Helpers groups erased.
        def self.Na__DataSerializer__RetireLegacyHelpers(parent_group)
            return 0 unless self.Na__DataSerializer__GroupValid?(parent_group)

            helpers_groups = parent_group.entities.grep(Sketchup::Group).select do |child|
                child.valid? && (child.name == NA_HELPERS_GROUP_NAME || self.Na__DataSerializer__IsHelpersSubGroup?(child))
            end
            parent_group.entities.erase_entities(helpers_groups) unless helpers_groups.empty?

            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            if dict
                NA_LEGACY_KEYS.each { |key| dict.delete_key(key) unless dict[key].nil? }
            end

            name = parent_group.name.to_s
            parent_group.name = name.delete_suffix(NA_LEGACY_DYNREGEN_SUFFIX) if name.end_with?(NA_LEGACY_DYNREGEN_SUFFIX)
            helpers_groups.length
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: RetireLegacyHelpers failed: #{error.message}")
            0
        end

        def self.Na__DataSerializer__FindParentFromHelpers(helpers_group)
            return nil unless self.Na__DataSerializer__GroupValid?(helpers_group)

            # Fast path — walk straight up the containment chain. Avoids a full
            # model scan and works when the assembly is nested inside components.
            direct_parent = self.Na__DataSerializer__ContainingInstance(helpers_group)
            return direct_parent if direct_parent && self.Na__DataSerializer__IsProfileTraceParent?(direct_parent)

            dict = helpers_group.attribute_dictionary(NA_HELPERS_DICT)
            return nil unless dict
            target_id = dict['ProfileTraceId'].to_s
            return nil if target_id.empty?

            self.Na__DataSerializer__FindParentByIdInModel(target_id)
        rescue
            nil
        end

        # Resolves the Profile Trace assembly for ANY selected entity: the
        # parent itself, or a descendant such as the SweptSolid or Helpers
        # sub-group (walks up the containment chain a bounded number of steps).
        def self.Na__DataSerializer__ResolveTraceParentForEntity(entity)
            return nil unless entity
            return entity if self.Na__DataSerializer__IsProfileTraceParent?(entity)

            candidate = entity
            8.times do
                candidate = self.Na__DataSerializer__ContainingInstance(candidate)
                return nil unless candidate
                return candidate if self.Na__DataSerializer__IsProfileTraceParent?(candidate)
            end
            nil
        rescue
            nil
        end

        # Sketchup::Group#parent returns the ComponentDefinition that owns the
        # group, so its single instance is the enclosing group/component.
        def self.Na__DataSerializer__ContainingInstance(group)
            owner_definition = group.parent
            return nil unless owner_definition.is_a?(Sketchup::ComponentDefinition)
            instances = owner_definition.instances
            return nil unless instances.is_a?(Array) && instances.length == 1
            instance = instances.first
            return nil unless instance && instance.respond_to?(:valid?) && instance.valid?
            instance
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Legacy Dynamic Regeneration Switch
    # -------------------------------------------------------------------------

        # Up to v1.6.15 a trace's Helpers linework could be switched off from
        # rebuilding it. Such a trace keeps its linework as drawn until it is
        # rebuilt on purpose (Regenerate Now, Edit Path, a swap). There is no
        # switch any more: a trace always follows its path.
        def self.Na__DataSerializer__LegacyRegenSwitchedOff?(parent_group)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return false unless dict
            dict['DynamicRegenEnabled'] == 'false'
        rescue
            false
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | ID Generation
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__GenerateNextProfileTraceId(model)
            return "#{NA_ID_PREFIX}0001" unless model
            highest = self.Na__DataSerializer__ScanHighestId(model)
            format("#{NA_ID_PREFIX}%04d", highest + 1)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Model-wide Helpers
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__FindAllParentGroups(model)
            return [] unless model
            self.Na__DataSerializer__CollectStampedGroups(model.entities, [])
        end

        def self.Na__DataSerializer__FindParentByIdInModel(target_id)
            model = Sketchup.active_model
            return nil unless model
            self.Na__DataSerializer__SearchGroupsForId(model.entities, target_id)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Serialisation Helpers
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__SerialiseToggleStates(toggle_states)
            return '{}' unless toggle_states.is_a?(Hash)
            JSON.generate(toggle_states)
        rescue
            '{}'
        end

        def self.Na__DataSerializer__DeserialiseToggleStates(json_string)
            return {} unless json_string.is_a?(String) && !json_string.empty?
            parsed = JSON.parse(json_string)
            parsed.is_a?(Hash) ? parsed : {}
        rescue
            {}
        end

        def self.Na__DataSerializer__SerialisePoint(point)
            return '[0,0,0]' unless point
            coords = [point.x.to_f, point.y.to_f, point.z.to_f]
            JSON.generate(coords)
        rescue
            '[0,0,0]'
        end

        def self.Na__DataSerializer__DeserialisePoint(json_string)
            return nil unless json_string.is_a?(String) && !json_string.empty?
            coords = JSON.parse(json_string)
            return nil unless coords.is_a?(Array) && coords.length == 3
            Geom::Point3d.new(coords[0].to_f, coords[1].to_f, coords[2].to_f)
        rescue
            nil
        end

        def self.Na__DataSerializer__SerialisePointList(points)
            list = Array(points).compact.map do |point|
                next nil unless point.respond_to?(:x)
                [point.x.to_f, point.y.to_f, point.z.to_f]
            end.compact
            JSON.generate(list)
        rescue
            '[]'
        end

        def self.Na__DataSerializer__DeserialisePointList(json_string)
            return [] unless json_string.is_a?(String) && !json_string.empty?
            parsed = JSON.parse(json_string)
            return [] unless parsed.is_a?(Array)
            parsed.map do |coords|
                next nil unless coords.is_a?(Array) && coords.length == 3
                Geom::Point3d.new(coords[0].to_f, coords[1].to_f, coords[2].to_f)
            end.compact
        rescue
            []
        end

        def self.Na__DataSerializer__SerialisePathRuns(runs)
            list = Array(runs).map do |run|
                next nil unless run.is_a?(Hash)
                points = Array(run[:ordered_points]).compact.select { |point| point.respond_to?(:x) }
                next nil if points.length < 2
                {
                    'Points'       => points.map { |point| [point.x.to_f, point.y.to_f, point.z.to_f] },
                    'IsClosedLoop' => run[:is_closed_loop] == true
                }
            end.compact
            JSON.generate(list)
        rescue
            '[]'
        end

        def self.Na__DataSerializer__DeserialisePathRuns(json_string)
            return [] unless json_string.is_a?(String) && !json_string.empty?
            parsed = JSON.parse(json_string)
            return [] unless parsed.is_a?(Array)
            parsed.map do |record|
                next nil unless record.is_a?(Hash)
                points = Array(record['Points']).map do |coords|
                    next nil unless coords.is_a?(Array) && coords.length == 3
                    Geom::Point3d.new(coords[0].to_f, coords[1].to_f, coords[2].to_f)
                end.compact
                next nil if points.length < 2
                { ordered_points: points, is_closed_loop: record['IsClosedLoop'] == true }
            end.compact
        rescue
            []
        end

        # Origin offset is stored in the profile's own 2D millimetre space
        # (PosY_mm, PosZ_mm) so it stays meaningful independent of path or rotation.
        def self.Na__DataSerializer__SerialiseOriginOffset(origin_offset)
            return '[0,0]' unless origin_offset.is_a?(Hash)
            y_mm = (origin_offset['y'] || origin_offset[:y]).to_f
            z_mm = (origin_offset['z'] || origin_offset[:z]).to_f
            JSON.generate([y_mm, z_mm])
        rescue
            '[0,0]'
        end

        def self.Na__DataSerializer__DeserialiseOriginOffset(json_string)
            return nil unless json_string.is_a?(String) && !json_string.empty?
            coords = JSON.parse(json_string)
            return nil unless coords.is_a?(Array) && coords.length == 2
            return nil if coords[0].to_f.zero? && coords[1].to_f.zero?
            { 'y' => coords[0].to_f, 'z' => coords[1].to_f }
        rescue
            nil
        end

        # Path end offsets are plain signed millimetres. A missing key reads as
        # 0.0 — no overshoot — which is how every pre-v1.6.11 trace was swept.
        def self.Na__DataSerializer__SerialiseOffsetMm(value)
            offset_mm = value.to_f
            offset_mm = 0.0 unless offset_mm.finite?
            offset_mm.round(3).to_s
        rescue
            '0.0'
        end

        def self.Na__DataSerializer__DeserialiseOffsetMm(stored_value)
            offset_mm = stored_value.to_f
            offset_mm.finite? ? offset_mm : 0.0
        rescue
            0.0
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Private - Group Safety + Scanning
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__GroupValid?(group)
            group && group.respond_to?(:valid?) && group.valid? && group.respond_to?(:entities)
        end

        def self.Na__DataSerializer__ScanHighestId(model)
            highest = 0
            self.Na__DataSerializer__FindAllParentGroups(model).each do |group|
                dict = group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
                next unless dict
                id_string = dict['ProfileTraceId'].to_s
                next unless id_string.match?(NA_ID_REGEX)
                number = id_string[NA_ID_PREFIX.length..].to_i
                highest = number if number > highest
            end
            highest
        end

        def self.Na__DataSerializer__CollectStampedGroups(entities, accumulator)
            return accumulator unless entities
            self.Na__DataSerializer__EachChildContainer(entities) do |container|
                accumulator << container if self.Na__DataSerializer__IsProfileTraceParent?(container)
                self.Na__DataSerializer__CollectStampedGroups(container.definition.entities, accumulator)
            end
            accumulator
        rescue
            accumulator
        end

        def self.Na__DataSerializer__SearchGroupsForId(entities, target_id)
            return nil unless entities
            self.Na__DataSerializer__EachChildContainer(entities) do |container|
                if self.Na__DataSerializer__IsProfileTraceParent?(container)
                    dict = container.attribute_dictionary(NA_PROFILE_TRACE_DICT)
                    return container if dict && dict['ProfileTraceId'].to_s == target_id
                end
                result = self.Na__DataSerializer__SearchGroupsForId(container.definition.entities, target_id)
                return result if result
            end
            nil
        rescue
            nil
        end

        # Yields every valid Group and ComponentInstance so a trace assembly is
        # still found when it lives inside a component, not just nested groups.
        def self.Na__DataSerializer__EachChildContainer(entities)
            entities.each do |entity|
                next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                next unless entity.valid?
                next unless entity.respond_to?(:definition) && entity.definition
                yield entity
            end
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
