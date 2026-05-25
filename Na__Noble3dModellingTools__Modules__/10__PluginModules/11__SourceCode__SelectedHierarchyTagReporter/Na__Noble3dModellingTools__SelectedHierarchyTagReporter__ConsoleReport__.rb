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
            display_text = node.fetch(:display_text, '').to_s
            role_label = node.fetch(:role, '').to_s
            return display_text if node.fetch(:node_type, '') == 'model'
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
