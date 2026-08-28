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
#     StartPoint           String   JSON-encoded [x, y, z] in inches
#     ReverseDirection     String   "true" | "false"
#     OriginOffset         String   JSON-encoded [y_mm, z_mm] datum shift
#     PathPoints           String   JSON-encoded [[x,y,z], ...] in inches.
#                                   Informational cache of the PRIMARY run only —
#                                   regeneration always re-derives the real path
#                                   from the Helpers edges, which may hold several.
#     DynamicRegenEnabled  String   "true" | "false"
#     HelpersFingerprint   String   SHA1 of the helpers linework (see
#                                   Na__RegenSweep). Written inside the same
#                                   operation as the geometry it describes, so
#                                   undo/redo keeps stored + actual in sync.
#     SchemaVersion        String   "1.2.0"
#     CreatedAt            String   ISO-8601 timestamp
#
#   Helpers sub-group      -> Na__ProfilePathTracer__HelpersInfo
#     ProfileTraceId       String   Back-reference to the parent assembly id
#     SchemaVersion        String   "1.2.0"
#
# SCHEMA COMPATIBILITY
#   1.0.0 assemblies (no ReverseDirection / OriginOffset / PathPoints) still
#   read back cleanly — the added keys default to false / nil / [] so an older
#   trace regenerates exactly as it did before.
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
#   Na__DataSerializer__WritePathPoints(parent_group, points) -> Boolean
#   Na__DataSerializer__IsProfileTraceParent?(group) -> Boolean
#   Na__DataSerializer__IsHelpersSubGroup?(group) -> Boolean
#   Na__DataSerializer__FindHelpersSubGroup(parent_group) -> group or nil
#   Na__DataSerializer__FindParentFromHelpers(helpers_group) -> group or nil
#   Na__DataSerializer__SetDynamicRegen(parent_group, enabled_bool)
#   Na__DataSerializer__DynamicRegenEnabled?(parent_group) -> Boolean
#   Na__DataSerializer__GenerateNextProfileTraceId(model) -> String
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
            dict['DynamicRegenEnabled'] = 'true'
            dict['SchemaVersion']       = NA_SCHEMA_VERSION
            dict['CreatedAt']           = Time.now.utc.iso8601
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: StampParent failed: #{error.message}")
        end

        # Refreshes only the cached path after a regeneration so the stored
        # payload always mirrors the current Helpers linework.
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
                'DynamicRegenEnabled'=> dict['DynamicRegenEnabled'] == 'true',
                'SchemaVersion'      => dict['SchemaVersion'].to_s
            }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: ReadParentPayload failed: #{error.message}")
            nil
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
    # REGION | Toggle Operations
    # -------------------------------------------------------------------------

        def self.Na__DataSerializer__SetDynamicRegen(parent_group, enabled_bool)
            return unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT, true)
            dict['DynamicRegenEnabled'] = (enabled_bool == true).to_s
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__DataSerializer: SetDynamicRegen failed: #{error.message}")
        end

        def self.Na__DataSerializer__DynamicRegenEnabled?(parent_group)
            return false unless self.Na__DataSerializer__GroupValid?(parent_group)
            dict = parent_group.attribute_dictionary(NA_PROFILE_TRACE_DICT)
            return false unless dict
            dict['DynamicRegenEnabled'] == 'true'
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
