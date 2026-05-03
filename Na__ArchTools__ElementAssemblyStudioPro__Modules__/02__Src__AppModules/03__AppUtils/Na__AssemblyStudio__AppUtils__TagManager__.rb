# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - TAG MANAGER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AppUtils__TagManager__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AppUtils
# MODULE     : Na__TagManager
# AUTHOR     : Noble Architecture
# PURPOSE    : Resolve SketchUp layer (tag) names per semantic role — prefer
#              DataLib `Na__DataLib__CoreIndex__Tags__.json`, fall back to
#              local constants — and apply them to drawable entities safely.
#
# DESCRIPTION:
# - Role symbols map to deterministic defaults when offline or cache misses.
# - Optional Na__DataLib__CacheData + Na__Role keys enrich swing / proposals.
#
# NAMING CONVENTION:
# - Na__TagManager exposes na_resolve_tag_name / na_apply_tag_to_entity style APIs.
#
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__AssemblyStudio__AppUtils__DebugTools__'

module Na__AssemblyStudio
    module Na__AppUtils
        module Na__TagManager

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

            DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Role Fallbacks & Default Colours
# -----------------------------------------------------------------------------

            NA_ROLE_FALLBACKS = {
                :door_swing       => '02__Linetype__DoorSwings'.freeze,
                :door_closed      => 'Na__Door__Closed'.freeze,
                :door_open        => 'Na__Door__Open'.freeze,
                :door_panel       => 'Na__DoorPanel'.freeze,
                :door_lining      => 'Na__DoorLining'.freeze,
                :architrave       => 'Na__Architrave'.freeze,
                :door_handle      => 'Na__DoorHandle'.freeze,
                :door_helpers     => '02__DoorHelpers__RotationPivots'.freeze,
                :proposed_doors   => '25__ProposedBuilding__Doors'.freeze,
                :proposed_windows => '25__ProposedBuilding__Windows'.freeze
            }.freeze

            NA_ROLE_DEFAULT_COLORS = {
                :door_swing       => [180, 180, 180],
                :door_closed      => [120, 160, 200],
                :door_open        => [200, 160, 120],
                :door_panel       => [165, 130,  90],
                :door_lining      => [200, 180, 150],
                :architrave       => [180, 150, 110],
                :door_handle      => [200, 175,  90],
                :door_helpers     => [255,   0,   0],
                :proposed_doors   => [120, 160, 200],
                :proposed_windows => [120, 200, 160]
            }.freeze

            NA_ROLE_DEFAULT_LINE_STYLES = {
                :door_helpers     => 'Dash'.freeze
            }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag Resolution & Application — Public API
# -----------------------------------------------------------------------------

            @na_resolved_names_cache = {}

            # FUNCTION | Return canonical SketchUp layer name string for role
            # ------------------------------------------------------------
            def self.na_resolve_tag_name(role)
                return NA_ROLE_FALLBACKS[role] unless NA_ROLE_FALLBACKS.key?(role)
                cached = @na_resolved_names_cache[role]
                return cached if cached

                datalib_name = na_resolve_from_datalib(role)
                resolved     = datalib_name || NA_ROLE_FALLBACKS[role]
                @na_resolved_names_cache[role] = resolved
                DebugTools.na_debug_tag("Resolved role :#{role} -> '#{resolved}' (#{datalib_name ? 'DataLib' : 'fallback'})")
                resolved
            end
            # ---------------------------------------------------------------

            # FUNCTION | Fetch existing LayerTag or instantiate with palette tint
            # ------------------------------------------------------------
            def self.na_get_or_create_tag(role)
                model = Sketchup.active_model
                return nil unless model

                tag_name = na_resolve_tag_name(role)
                existing = model.layers[tag_name]
                if existing
                    na_apply_line_style_for_role(existing, role)
                    return existing
                end

                new_tag       = model.layers.add(tag_name)
                color_rgb     = NA_ROLE_DEFAULT_COLORS[role]
                new_tag.color = Sketchup::Color.new(*color_rgb) if color_rgb && new_tag.respond_to?(:color=)
                na_apply_line_style_for_role(new_tag, role)
                DebugTools.na_debug_tag("Created tag '#{tag_name}' for role :#{role}")
                new_tag
            end
            # ---------------------------------------------------------------

            # FUNCTION | Assign tag to entity.layer when mutable
            # ------------------------------------------------------------
            def self.na_apply_tag_to_entity(entity, role)
                return false unless entity && entity.respond_to?(:layer=)
                tag = na_get_or_create_tag(role)
                return false unless tag
                entity.layer = tag
                true
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — DataLib Lookup
# -----------------------------------------------------------------------------

            def self.na_resolve_from_datalib(role)
                return nil unless defined?(Na__DataLib__CacheData)

                data = na_load_tags_data
                return nil unless data.is_a?(Hash)

                datalib_keys = na_role_to_datalib_keys(role)
                return nil if datalib_keys.empty?

                tags_root = data['Na__DataLib__CoreIndex__Tags']
                return nil unless tags_root.is_a?(Hash)

                datalib_keys.each do |key|
                    found_name = na_find_tag_in_datalib(tags_root, key)
                    return found_name if found_name
                end
                nil
            end
            private_class_method :na_resolve_from_datalib

            def self.na_load_tags_data
                return nil unless defined?(Na__DataLib__CacheData)
                Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
            rescue StandardError => e
                DebugTools.na_debug_warn("DataLib :tags load failed: #{e.message}")
                nil
            end
            private_class_method :na_load_tags_data

            def self.na_role_to_datalib_keys(role)
                case role
                when :door_swing       then ['02__Linetype__DoorSwings']
                when :proposed_doors   then ['25__ProposedBuilding__Doors']
                when :proposed_windows then ['25__ProposedBuilding__Windows']
                else                        []
                end
            end
            private_class_method :na_role_to_datalib_keys

            def self.na_find_tag_in_datalib(node, target_key)
                return nil unless node.is_a?(Hash)
                node.each do |key, value|
                    if key == target_key && value.is_a?(Hash) && value['Tag__SketchUpName']
                        return value['Tag__SketchUpName']
                    end
                    found = na_find_tag_in_datalib(value, target_key) if value.is_a?(Hash)
                    return found if found
                end
                nil
            end
            private_class_method :na_find_tag_in_datalib

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Line Style Application
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Resolve and Apply Layout__LineStyleName for a Role
            # ------------------------------------------------------------
            # Looks up the line style name first from the DataLib Tags JSON
            # (Layout__LineStyleName field) then falls back to
            # NA_ROLE_DEFAULT_LINE_STYLES, then returns silently if no style
            # is configured for this role. Guards every API call with
            # respond_to? so older SketchUp versions degrade gracefully.
            def self.na_apply_line_style_for_role(layer, role)
                return unless layer
                style_name = na_resolve_line_style_name(role)
                return unless style_name
                na_apply_line_style_to_tag(layer, style_name)
            end
            private_class_method :na_apply_line_style_for_role

            # HELPER FUNCTION | Apply a Named Line Style to a Single Layer/Tag
            # ------------------------------------------------------------
            # Sketchup::Layer#line_style= was introduced in SketchUp 2019.
            # Sketchup.active_model.line_styles is a Sketchup::LineStyles
            # collection that supports lookup by name. Both calls are
            # respond_to-guarded so this is safe on any SketchUp version.
            def self.na_apply_line_style_to_tag(layer, style_name)
                return unless layer && layer.respond_to?(:line_style=)
                model = Sketchup.active_model
                return unless model && model.respond_to?(:line_styles)
                styles = model.line_styles
                return unless styles && styles.respond_to?(:[])
                style = styles[style_name]
                return unless style
                layer.line_style = style
                DebugTools.na_debug_tag("Applied line style '#{style_name}' to tag '#{layer.name}'")
            rescue StandardError => e
                DebugTools.na_debug_warn("na_apply_line_style_to_tag failed for '#{style_name}': #{e.message}")
            end
            private_class_method :na_apply_line_style_to_tag

            # HELPER FUNCTION | Resolve Line Style Name for a Role
            # ------------------------------------------------------------
            # DataLib lookup first, then NA_ROLE_DEFAULT_LINE_STYLES.
            def self.na_resolve_line_style_name(role)
                datalib_name = na_resolve_line_style_from_datalib(role)
                return datalib_name if datalib_name
                NA_ROLE_DEFAULT_LINE_STYLES[role]
            end
            private_class_method :na_resolve_line_style_name

            # HELPER FUNCTION | Read Layout__LineStyleName From DataLib for Role
            # ------------------------------------------------------------
            def self.na_resolve_line_style_from_datalib(role)
                return nil unless defined?(Na__DataLib__CacheData)

                data = na_load_tags_data
                return nil unless data.is_a?(Hash)

                tags_root = data['Na__DataLib__CoreIndex__Tags']
                return nil unless tags_root.is_a?(Hash)

                tag_name = NA_ROLE_FALLBACKS[role]
                return nil unless tag_name

                node = na_find_tag_node_in_datalib(tags_root, tag_name)
                return nil unless node.is_a?(Hash)

                value = node['Layout__LineStyleName']
                value if value.is_a?(String) && !value.empty?
            end
            private_class_method :na_resolve_line_style_from_datalib

            # HELPER FUNCTION | Recursively Find a Tag Hash Node by Tag__SketchUpName
            # ------------------------------------------------------------
            # Returns the FULL hash for the matching tag (so callers can
            # read sibling Layout__* fields), unlike na_find_tag_in_datalib
            # which returns just the name string.
            def self.na_find_tag_node_in_datalib(node, target_name)
                return nil unless node.is_a?(Hash)
                node.each do |_key, value|
                    next unless value.is_a?(Hash)
                    if value['Tag__SketchUpName'] == target_name
                        return value
                    end
                    found = na_find_tag_node_in_datalib(value, target_name)
                    return found if found
                end
                nil
            end
            private_class_method :na_find_tag_node_in_datalib

# endregion -------------------------------------------------------------------

        end
    end
end
