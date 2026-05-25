# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SELECTED HIERARCHY TAG REPORTER - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SelectedHierarchyTagReporter__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SelectedHierarchyTagReporter__DialogManager
# PURPOSE    : Manage the dedicated HtmlDialog for visual hierarchy reporting
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SelectedHierarchyTagReporter__DialogManager

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DIALOG_TITLE = 'Entity Tree Reporter'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__Noble3dModellingTools__SelectedHierarchyTagReporter'.freeze
        NA_DIALOG_WIDTH = 760
        NA_DIALOG_HEIGHT = 720

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__SelectedHierarchyTagReporter__DialogManager__ShowDialog(report_data)
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                na_push_report_data(@na_dialog, report_data)
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(
                dialog_title: NA_DIALOG_TITLE,
                preferences_key: NA_DIALOG_PREFERENCES_KEY,
                scrollable: true,
                resizable: true,
                width: NA_DIALOG_WIDTH,
                height: NA_DIALOG_HEIGHT,
                style: UI::HtmlDialog::STYLE_DIALOG
            )

            @na_dialog.set_html(na_render_dialog_html(report_data))
            na_setup_dialog_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show
            @na_dialog
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Rendering
# -----------------------------------------------------------------------------

        def self.na_render_dialog_html(report_data)
            html_template = File.read(na_ui_layout_file_path)
            stylesheet_content = File.read(na_stylesheet_file_path)
            ui_bridge_script = File.read(na_ui_bridge_file_path)

            html_template
                .gsub('{{STYLESHEET_CONTENT}}', stylesheet_content)
                .gsub('{{UI_BRIDGE_SCRIPT}}', ui_bridge_script)
                .gsub('{{REPORT_DATA_JSON}}', JSON.generate(report_data))
        end

        def self.na_ui_layout_file_path
            File.join(__dir__, 'Na__Noble3dModellingTools__SelectedHierarchyTagReporter__UiLayout__.html')
        end

        def self.na_stylesheet_file_path
            File.join(__dir__, 'Na__Noble3dModellingTools__SelectedHierarchyTagReporter__Styles__.css')
        end

        def self.na_ui_bridge_file_path
            File.join(__dir__, 'Na__Noble3dModellingTools__SelectedHierarchyTagReporter__UiBridge__.js')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Ruby and JavaScript Bridge
# -----------------------------------------------------------------------------

        def self.na_setup_dialog_callbacks(dialog)
            dialog.add_action_callback('refresh_report') do |_context, include_siblings|
                report_data = Na__SelectedHierarchyTagReporter__TreeData.Na__SelectedHierarchyTagReporter__TreeData__Build(na_truthy_value?(include_siblings))
                na_push_report_data(dialog, report_data)
            end

            dialog.add_action_callback('print_console_report') do |_context, include_siblings|
                report_data = Na__SelectedHierarchyTagReporter__TreeData.Na__SelectedHierarchyTagReporter__TreeData__Build(na_truthy_value?(include_siblings))
                Na__SelectedHierarchyTagReporter__ConsoleReport.Na__SelectedHierarchyTagReporter__ConsoleReport__PrintReportData(report_data)
                na_push_report_status(dialog, 'Printed current hierarchy report to the Ruby Console.', 'success')
            end
        end

        def self.na_push_report_data(dialog, report_data)
            script = <<~SCRIPT
            (function() {
                if (window.Na__SelectedHierarchyTagReporter__SetReportData) {
                    window.Na__SelectedHierarchyTagReporter__SetReportData(#{JSON.generate(report_data)});
                }
            })();
            SCRIPT
            dialog.execute_script(script)
        end

        def self.na_push_report_status(dialog, status_text, status_variant)
            script = <<~SCRIPT
            (function() {
                if (window.Na__SelectedHierarchyTagReporter__SetStatus) {
                    window.Na__SelectedHierarchyTagReporter__SetStatus(#{status_text.to_s.to_json}, #{status_variant.to_s.to_json});
                }
            })();
            SCRIPT
            dialog.execute_script(script)
        end

        def self.na_truthy_value?(value)
            value == true || value.to_s == 'true' || value.to_s == '1'
        end

# endregion -------------------------------------------------------------------

    end # module Na__SelectedHierarchyTagReporter__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
