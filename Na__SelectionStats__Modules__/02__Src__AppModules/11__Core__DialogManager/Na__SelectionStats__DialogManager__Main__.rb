# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__SelectionStats__DialogManager__Main__.rb
# PURPOSE    : HtmlDialog lifecycle, observer wiring, JSON push + Ruby action callbacks back into the HUD.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'
require 'json'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__DialogManager
        extend self

# -----------------------------------------------------------------------------
# REGION | Show & Lifecycle
# -----------------------------------------------------------------------------

        def na_show_dialog(html_file_path)
            @html_file_path_reserved = html_file_path
            na_attach_selection_observer_to_active_model()
            na_create_dialog_if_required()

            if @dialog.visible?
                @dialog.bring_to_front
            else
                @dialog.show
            end

            na_refresh_dialog()
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Selection Observation
# -----------------------------------------------------------------------------

        def na_attach_selection_observer_to_active_model()
            model = Sketchup.active_model
            return nil unless model

            selection = model.selection
            return nil unless selection

            @selection_observer ||= Na__SelectionStats::Na__SelectionStats__SelectionObserver.new

            if @observed_selection && @observed_selection != selection
                begin
                    @observed_selection.remove_observer(@selection_observer)
                rescue StandardError
                    # Ignore stale selection references from closed models.
                end
            end

            unless @observed_selection == selection
                selection.add_observer(@selection_observer)
                @observed_selection = selection
            end

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HtmlDialog Construction
# -----------------------------------------------------------------------------

        def na_create_dialog_if_required()
            return @dialog if @dialog && @dialog.visible?

            ext = Na__SelectionStats::Na__AppData::Na__Constants

            @dialog = UI::HtmlDialog.new(
                dialog_title: ext::EXTENSION_NAME,
                preferences_key: ext::PREFERENCES_KEY,
                scrollable: true,
                resizable: true,
                width: 860,
                height: 720,
                min_width: 560,
                min_height: 420,
                style: UI::HtmlDialog::STYLE_DIALOG
            )

            if @html_file_path_reserved && File.exist?(@html_file_path_reserved.to_s)
                @dialog.set_file(@html_file_path_reserved)
            else
                puts "#{ext::EXTENSION_NAME}: UI layout missing at #{@html_file_path_reserved}"
            end

            na_register_html_callbacks()

            @dialog.set_on_closed do
                Na__SelectionStats::Na__DialogManager.instance_eval { @dialog = nil }
            end

            @dialog
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HtmlDialog Callback Registration
# -----------------------------------------------------------------------------

        def na_register_html_callbacks()
            return nil unless @dialog

            @dialog.add_action_callback('na_generateMarkdownReport') do |_context|
                Na__SelectionStats::Na__GenerateReport::Na__MarkdownFile.na_export_current_selection_report()
            end

            nil
        end

        def na_push_report_status(kind, message)
            return nil unless @dialog && @dialog.visible?

            kind_json = JSON.generate(kind.to_s)
            msg_json  = JSON.generate(message.to_s)

            @dialog.execute_script(
                "try { window.NaSelectionStatsSetReportStatus(#{kind_json}, #{msg_json}); } catch (e) {}"
            )
            nil
        rescue StandardError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Refresh
# -----------------------------------------------------------------------------

        def na_refresh_dialog()
            return nil unless @dialog && @dialog.visible?

            na_attach_selection_observer_to_active_model()

            model = Sketchup.active_model
            stats = Na__SelectionStats::Na__StatsBuilder.na_build_stats(model)
            json  = JSON.generate(stats)
            @dialog.execute_script("window.NaSelectionStatsSetData(#{json});")
            nil
        rescue StandardError => error
            puts "#{Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME} refresh error: #{error.class} - #{error.message}"
            nil
        end

# endregion -------------------------------------------------------------------

    end
end
