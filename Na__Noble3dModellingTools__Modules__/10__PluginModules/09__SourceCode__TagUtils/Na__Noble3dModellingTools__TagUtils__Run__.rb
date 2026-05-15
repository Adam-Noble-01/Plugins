# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TAG UTILS - RUN ENTRYPOINTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TagUtils__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TagUtils
# PURPOSE    : Build standard SketchUp tags from SSOT tags index
# CREATED    : 2026
#
# =============================================================================

require 'json'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__StandardDataCache__'

module Na__Noble3dModellingTools
    module Na__TagUtils

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_TAGS_ROOT_KEY = 'Na__DataLib__CoreIndex__Tags'.freeze
        NA_EDGE_MATERIALS_ROOT_KEY = 'Na__DataLib__CoreIndex__EdgeMaterials'.freeze
        NA_META_KEY = 'meta'.freeze

        NA_ATTRIBUTE_DICTIONARY_NAME = 'Na__Noble3dModellingTools__TagUtils'.freeze
        NA_ATTRIBUTE_KEY_TAG_KEY = 'Na__TagKey'.freeze
        NA_ATTRIBUTE_KEY_TAG_JSON = 'Na__TagJson'.freeze
        NA_ATTRIBUTE_KEY_SOURCE_FILE = 'Na__SourceFile'.freeze
        NA_ATTRIBUTE_KEY_LIBRARY_VERSION = 'Na__LibraryVersion'.freeze
        NA_ATTRIBUTE_KEY_LINE_STYLE = 'Na__LineStyleName'.freeze
        NA_ATTRIBUTE_KEY_EDGE_COLOUR = 'Na__EdgeColourKey'.freeze
        NA_ATTRIBUTE_KEY_WARNING_SUMMARY = 'Na__WarningSummary'.freeze

        NA_MAX_REASON_ITEMS = 6

        NA_MODELING_HELPER_GROUP_KEYS = [
            '00__SystemAndUtilityTags__'
        ].freeze

        NA_LINE_THICKNESS_GROUP_KEYS = [
            '03__LayoutDrawingLineworkTags__'
        ].freeze

        NA_TRUEVISION_ALL_GROUP_KEYS = [
            '07__EnvironmentTags__',
            '10_19__ExistingBuildingTags__',
            '20_29__ProposedBuildingTags__',
            '30_70__FurnitureAndContextTags__',
            '90_93__StoreyContainerTags__'
        ].freeze

        NA_TRUEVISION_MINIMAL_TAG_NAMES = [
            '01__OrbitHelperCube',
            '07__Landscape',
            '10__ExistingBuilding',
            '20__ProposedBuilding',
            '90__Storey__GroundFloor',
            '91__Storey__FirstFloor',
            '92__Storey__SecondFloor',
            '93__Storey__ThirdFloor'
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        def self.Na__TagUtils__LoadStandardTags
            Na__TagUtils__LoadAllTags
        end

        def self.Na__TagUtils__LoadAllTags
            na_load_tag_set(
                'Load All Tags',
                :all
            )
        end

        def self.Na__TagUtils__LoadModelingHelperTags
            na_load_tag_set(
                'Load Modeling Helper Tags',
                { group_keys: NA_MODELING_HELPER_GROUP_KEYS }
            )
        end

        def self.Na__TagUtils__LoadLineThicknessTags
            na_load_tag_set(
                'Load Line Thickness Tags',
                { group_keys: NA_LINE_THICKNESS_GROUP_KEYS }
            )
        end

        def self.Na__TagUtils__LoadTrueVisionMinimalTags
            na_load_tag_set(
                'Load TrueVision Minimal Tags',
                { tag_names: NA_TRUEVISION_MINIMAL_TAG_NAMES }
            )
        end

        def self.Na__TagUtils__LoadTrueVisionAllTags
            na_load_tag_set(
                'Load TrueVision All Tags',
                { group_keys: NA_TRUEVISION_ALL_GROUP_KEYS }
            )
        end

        def self.na_load_tag_set(operation_name, tag_selection)
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model available.') unless model

            tags_payload = Na__StandardDataCache.Na__Noble3dModellingTools__LoadStandardData(:tags)
            tags_root = na_tags_root_from_payload(tags_payload)
            return na_result(false, "#{operation_name}: tags payload missing '#{NA_TAGS_ROOT_KEY}'.") unless tags_root

            edge_materials_payload = Na__StandardDataCache.Na__Noble3dModellingTools__LoadStandardData(:edge_materials)
            edge_materials_root = na_edge_materials_root_from_payload(edge_materials_payload)
            tag_entries = na_tag_entries_for_selection(tags_root, tag_selection)
            return na_result(false, "#{operation_name}: no matching tag entries found for #{tag_selection.inspect}.") if tag_entries.empty?

            created_count = 0
            updated_count = 0
            skipped_count = 0
            failed_count = 0
            warning_reasons = []
            skipped_reasons = []
            failure_reasons = []
            operation_started = false

            model.start_operation(operation_name, true)
            operation_started = true

            tag_entries.each do |tag_entry|
                tag_key = tag_entry[:key]
                tag_data = tag_entry[:data]
                tag_name = tag_data.fetch('Tag__SketchUpName', '').to_s.strip

                if tag_name.empty?
                    skipped_count += 1
                    na_append_reason(skipped_reasons, "#{tag_key}: missing Tag__SketchUpName")
                    next
                end

                apply_result = na_create_or_update_tag(
                    model,
                    tag_key,
                    tag_name,
                    tag_data,
                    tags_payload[NA_META_KEY],
                    edge_materials_root
                )

                case apply_result[:status]
                when :created
                    created_count += 1
                when :updated
                    updated_count += 1
                when :skipped
                    skipped_count += 1
                    na_append_reason(skipped_reasons, apply_result[:reason])
                when :failed
                    failed_count += 1
                    na_append_reason(failure_reasons, apply_result[:reason])
                else
                    skipped_count += 1
                    na_append_reason(skipped_reasons, "#{tag_key}: unknown apply status")
                end

                na_append_reason(warning_reasons, apply_result[:warning]) if apply_result[:warning]
            rescue => error
                failed_count += 1
                na_append_reason(failure_reasons, "#{tag_key}: #{error.class}: #{error.message}")
            end

            model.commit_operation
            operation_started = false

            source_label = Na__StandardDataCache.Na__Noble3dModellingTools__LastSource(:tags) || :unknown
            message = na_build_result_message(
                operation_name,
                source_label,
                tag_entries.length,
                created_count,
                updated_count,
                skipped_count,
                failed_count,
                skipped_reasons,
                failure_reasons,
                warning_reasons
            )

            na_result(failed_count.zero?, message)
        rescue => error
            model.abort_operation if model && operation_started
            na_result(false, "#{operation_name} failed: #{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Helpers
# -----------------------------------------------------------------------------

        def self.na_tags_root_from_payload(tags_payload)
            return nil unless tags_payload.is_a?(Hash)

            tags_root = tags_payload[NA_TAGS_ROOT_KEY]
            tags_root.is_a?(Hash) ? tags_root : nil
        end

        def self.na_edge_materials_root_from_payload(edge_materials_payload)
            return nil unless edge_materials_payload.is_a?(Hash)

            edge_root = edge_materials_payload[NA_EDGE_MATERIALS_ROOT_KEY]
            edge_root.is_a?(Hash) ? edge_root : nil
        end

        def self.na_collect_tag_entries(node, entries = [])
            return entries unless node.is_a?(Hash)

            node.each do |key, value|
                next unless value.is_a?(Hash)

                if value['Tag__SketchUpName'].is_a?(String)
                    entries << {
                        key: key.to_s,
                        data: value
                    }
                end

                na_collect_tag_entries(value, entries)
            end

            entries
        end

        def self.na_tag_entries_for_selection(tags_root, tag_selection)
            return na_collect_tag_entries(tags_root) if tag_selection == :all

            if tag_selection.is_a?(Hash) && tag_selection[:group_keys].is_a?(Array)
                return tag_selection[:group_keys].flat_map do |group_key|
                    group_node = tags_root[group_key]
                    na_collect_tag_entries(group_node)
                end
            end

            if tag_selection.is_a?(Hash) && tag_selection[:tag_names].is_a?(Array)
                allowed_names = tag_selection[:tag_names].map(&:to_s)
                return na_collect_tag_entries(tags_root).select do |entry|
                    allowed_names.include?(entry[:data]['Tag__SketchUpName'].to_s)
                end
            end

            []
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag Creation and Attribute Application
# -----------------------------------------------------------------------------

        def self.na_create_or_update_tag(model, tag_key, tag_name, tag_data, meta_data, edge_materials_root)
            existing_layer = model.layers[tag_name]
            layer = existing_layer || model.layers.add(tag_name)
            layer.visible = true if layer.respond_to?(:visible=)

            warning_items = []
            line_style_name = na_resolve_line_style_name(tag_data)
            edge_colour_key = na_resolve_edge_colour_key(tag_data)

            na_apply_line_style(model, layer, line_style_name, warning_items) if line_style_name
            na_apply_tag_colour(layer, tag_data, edge_colour_key, edge_materials_root, warning_items)
            na_write_tag_metadata(layer, tag_key, tag_data, meta_data, line_style_name, edge_colour_key, warning_items)

            status = existing_layer ? :updated : :created
            warning = warning_items.empty? ? nil : "#{tag_name}: #{warning_items.join('; ')}"
            na_apply_result(status, nil, warning)
        rescue => error
            na_apply_result(:failed, "#{tag_name}: #{error.class}: #{error.message}")
        end

        def self.na_resolve_line_style_name(tag_data)
            line_style_name = tag_data['Tag__LineStyle__Config'].to_s.strip
            line_style_name = tag_data['Layout__LineStyleName'].to_s.strip if line_style_name.empty?
            line_style_name.empty? ? nil : line_style_name
        end

        def self.na_apply_line_style(model, layer, line_style_name, warning_items)
            return unless layer.respond_to?(:line_style=)
            unless model.respond_to?(:line_styles)
                warning_items << "line styles unavailable in this SketchUp version"
                return
            end

            styles = model.line_styles
            unless styles && styles.respond_to?(:[])
                warning_items << "model.line_styles lookup unavailable"
                return
            end

            style = styles[line_style_name]
            style ||= na_find_line_style_case_insensitive(styles, line_style_name)

            unless style
                warning_items << "line style '#{line_style_name}' not found"
                return
            end

            layer.line_style = style
        rescue => error
            warning_items << "line style '#{line_style_name}' failed (#{error.class}: #{error.message})"
        end

        def self.na_find_line_style_case_insensitive(styles, line_style_name)
            return nil unless styles.respond_to?(:names)

            matching_name = styles.names.find { |name| name.to_s.downcase == line_style_name.to_s.downcase }
            matching_name ? styles[matching_name] : nil
        rescue
            nil
        end

        def self.na_resolve_edge_colour_key(tag_data)
            edge_key = tag_data['Tag__EdgeMaterial__Config'].to_s.strip
            edge_key = tag_data['Layout__EdgeColourID'].to_s.strip if edge_key.empty?
            edge_key.empty? ? nil : edge_key
        end

        def self.na_apply_tag_colour(layer, tag_data, edge_colour_key, edge_materials_root, warning_items)
            return unless layer.respond_to?(:color=)

            explicit_rgb = tag_data['Layout__EdgeColourRGB']
            if explicit_rgb.is_a?(Array) && explicit_rgb.length == 3
                layer.color = Sketchup::Color.new(*explicit_rgb.map(&:to_i))
                return
            end

            return unless edge_colour_key

            rgb_values = na_rgb_values_for_edge_colour_key(edge_materials_root, edge_colour_key)
            unless rgb_values
                warning_items << "edge colour '#{edge_colour_key}' not found"
                return
            end

            layer.color = Sketchup::Color.new(*rgb_values.map(&:to_i))
        rescue => error
            warning_items << "tag colour failed (#{error.class}: #{error.message})"
        end

        def self.na_rgb_values_for_edge_colour_key(edge_materials_root, edge_colour_key)
            edge_entry = na_find_edge_material_entry(edge_materials_root, edge_colour_key)
            return nil unless edge_entry.is_a?(Hash)

            rgb_value = edge_entry['RgbValue']
            return rgb_value if rgb_value.is_a?(Array) && rgb_value.length == 3

            na_rgb_from_hex(edge_entry['HexValue'])
        end

        def self.na_find_edge_material_entry(node, edge_colour_key)
            return nil unless node.is_a?(Hash)

            node.each do |key, value|
                next unless value.is_a?(Hash)

                if key.to_s == edge_colour_key.to_s || value['SketchUpName'].to_s == edge_colour_key.to_s
                    return value
                end

                found = na_find_edge_material_entry(value, edge_colour_key)
                return found if found
            end

            nil
        end

        def self.na_rgb_from_hex(hex_value)
            match = hex_value.to_s.match(/\A#?([0-9a-fA-F]{6})\z/)
            return nil unless match

            hex = match[1]
            [
                hex[0, 2].to_i(16),
                hex[2, 2].to_i(16),
                hex[4, 2].to_i(16)
            ]
        end

        def self.na_write_tag_metadata(layer, tag_key, tag_data, meta_data, line_style_name, edge_colour_key, warning_items)
            dictionary = layer.attribute_dictionary(NA_ATTRIBUTE_DICTIONARY_NAME, true)
            dictionary[NA_ATTRIBUTE_KEY_TAG_KEY] = tag_key.to_s
            dictionary[NA_ATTRIBUTE_KEY_TAG_JSON] = JSON.generate(tag_data)
            dictionary[NA_ATTRIBUTE_KEY_SOURCE_FILE] = meta_data.is_a?(Hash) ? meta_data.fetch('fileName', '').to_s : ''
            dictionary[NA_ATTRIBUTE_KEY_LIBRARY_VERSION] = meta_data.is_a?(Hash) ? meta_data.fetch('version', '').to_s : ''
            dictionary[NA_ATTRIBUTE_KEY_LINE_STYLE] = line_style_name.to_s
            dictionary[NA_ATTRIBUTE_KEY_EDGE_COLOUR] = edge_colour_key.to_s
            dictionary[NA_ATTRIBUTE_KEY_WARNING_SUMMARY] = warning_items.join(' | ')
        rescue => error
            warning_items << "metadata write failed (#{error.class}: #{error.message})"
        end

        def self.na_apply_result(status_symbol, reason_text = nil, warning_text = nil)
            {
                status: status_symbol,
                reason: reason_text,
                warning: warning_text
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        def self.na_build_result_message(operation_name, source_label, total_count, created_count, updated_count, skipped_count, failed_count, skipped_reasons, failure_reasons, warning_reasons)
            loaded_count = created_count + updated_count
            message = "#{operation_name}: #{loaded_count} loaded (#{created_count} created, #{updated_count} updated, " \
                "#{skipped_count} skipped, #{failed_count} failed, #{total_count} discovered) [source: #{source_label}]."

            message += " SkipReasons: #{skipped_reasons.join(' | ')}." if skipped_reasons.any?
            message += " FailureReasons: #{failure_reasons.join(' | ')}." if failure_reasons.any?
            message += " Warnings: #{warning_reasons.join(' | ')}." if warning_reasons.any?
            message
        end

        def self.na_append_reason(target_array, reason_text)
            return if reason_text.nil? || reason_text.to_s.strip.empty?
            return if target_array.length >= NA_MAX_REASON_ITEMS

            target_array << reason_text.to_s
        end

        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__TagUtils
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
