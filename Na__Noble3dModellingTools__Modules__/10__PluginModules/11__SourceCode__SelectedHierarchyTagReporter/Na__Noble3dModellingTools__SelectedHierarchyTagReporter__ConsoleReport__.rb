# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECTED HIERARCHY TAG REPORTER - CONSOLE REPORT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectedHierarchyTagReporter__ConsoleReport__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectedHierarchyTagReporter__ConsoleReport
# PURPOSE    : Print hierarchy reports to the SketchUp Ruby Console
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SelectedHierarchyTagReporter__ConsoleReport

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_INDENT = '    '.freeze
        NA_RULE_WIDTH = 100

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Report Methods
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__ConsoleReport__PrintCurrentSelection(include_siblings)
            report_data = Na__SelectedHierarchyTagReporter__TreeData.Na__SelectedHierarchyTagReporter__TreeData__Build(include_siblings)
            self.Na__SelectedHierarchyTagReporter__ConsoleReport__PrintReportData(report_data)
        end

        def self.Na__SelectedHierarchyTagReporter__ConsoleReport__PrintReportData(report_data)
            puts ''
            puts 'SELECTED SKETCHUP OBJECT HIERARCHY WITH TAGS'
            puts '-' * NA_RULE_WIDTH
            puts report_data.fetch(:summary, '').to_s

            report_data.fetch(:nodes, []).each do |node|
                na_print_node(node)
            end

            puts '-' * NA_RULE_WIDTH
            puts 'Done.'
            puts ''

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Node Printing
# -----------------------------------------------------------------------------

        def self.na_print_node(node)
            level_number = node.fetch(:level, 0).to_i
            puts "#{na_indent(level_number)}Level #{level_number} | #{na_node_line_text(node)}"

            return if node.fetch(:node_type, '').to_s == 'grouped_instances'         # <-- summary line only; do not recurse into individual instances

            na_print_loose_geometry_summary(node)

            node.fetch(:children, []).each do |child_node|
                na_print_node(child_node)
            end
        end

        def self.na_print_loose_geometry_summary(node)
            summary = node[:loose_geometry_summary]
            return unless summary

            level_number = node.fetch(:level, 0).to_i + 1
            puts "#{na_indent(level_number)}Level #{level_number} | Lowest Level Loose Geometry | Items: #{summary.fetch(:item_count, 0)} | Types: #{summary.fetch(:type_summary, '')} | Tags: #{summary.fetch(:tag_summary, '')}"
        end

        def self.na_node_line_text(node)
            node_type    = node.fetch(:node_type, '').to_s
            display_text = node.fetch(:display_text, '').to_s
            role_label   = node.fetch(:role, '').to_s

            return display_text if node_type == 'model'

            if node_type == 'grouped_instances'
                count       = node.fetch(:instance_count, 0).to_i
                def_name    = node.fetch(:definition_name, '').to_s
                type_label  = node.fetch(:entity_type_label, 'Container').to_s
                is_solid    = node[:is_solid]
                solid_text  = is_solid == true ? ', Solid' : (is_solid == false ? ', Non-Solid' : '')
                quoted_name = def_name.empty? ? '(unnamed)' : "\"#{def_name}\""
                return "#{count}x #{quoted_name} (#{type_label}#{solid_text})"
            end

            return display_text if role_label.empty?
            return display_text if display_text.start_with?(role_label)

            "#{role_label} | #{display_text}"
        end

        def self.na_indent(level_number)
            NA_INDENT * level_number.to_i
        end

# endregion -------------------------------------------------------------------

    end # module Na__SelectedHierarchyTagReporter__ConsoleReport
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
