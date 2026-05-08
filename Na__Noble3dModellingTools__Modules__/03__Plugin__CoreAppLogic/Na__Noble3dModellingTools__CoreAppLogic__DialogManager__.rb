# =============================================================================
# NA NOBLE3D MODELLING TOOLS - CORE DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__CoreAppLogic__DialogManager__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__DialogManager
# PURPOSE    : Render and manage JSON-driven HtmlDialog UI
# CREATED    : 2026
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__Noble3dModellingTools__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(
                dialog_title: Na__ConfigLoader.Na__Noble3dModellingTools__DialogTitle,
                preferences_key: Na__ConfigLoader.Na__Noble3dModellingTools__DialogPreferencesKey,
                scrollable: true,
                resizable: Na__ConfigLoader.Na__Noble3dModellingTools__DialogResizable,
                width: Na__ConfigLoader.Na__Noble3dModellingTools__DialogWidth,
                height: Na__ConfigLoader.Na__Noble3dModellingTools__DialogHeight,
                style: UI::HtmlDialog::STYLE_DIALOG
            )

            @na_dialog.set_html(na_render_dialog_html)
            na_setup_dialog_callbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show
            @na_dialog
        end

        def self.Na__Noble3dModellingTools__DialogVisible
            !!(@na_dialog && @na_dialog.visible?)
        end

        def self.Na__Noble3dModellingTools__RefreshDialogIfVisible
            return false unless self.Na__Noble3dModellingTools__DialogVisible

            @na_dialog.set_html(na_render_dialog_html)
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | HTML Rendering
# -----------------------------------------------------------------------------

        def self.na_render_dialog_html
            html_template = File.read(Na__PathResolver.Na__Noble3dModellingTools__UiLayoutFilePath)
            stylesheet_content = File.read(Na__PathResolver.Na__Noble3dModellingTools__UiStylesheetFilePath)
            ui_bridge_script = File.read(Na__PathResolver.Na__Noble3dModellingTools__UiBridgeFilePath)

            html_template
                .gsub('{{DIALOG_TITLE}}', na_escape_html(Na__ConfigLoader.Na__Noble3dModellingTools__DialogTitle))
                .gsub('{{EXTENSION_NAME}}', na_escape_html(Na__ConfigLoader.Na__Noble3dModellingTools__ExtensionName))
                .gsub('{{LOGO_FILE_URI}}', na_resolve_logo_file_uri)
                .gsub('{{TAB_BUTTONS_HTML}}', na_build_tab_buttons_html)
                .gsub('{{TAB_CONTENT_HTML}}', na_build_tab_content_html)
                .gsub('{{STYLESHEET_CONTENT}}', stylesheet_content)
                .gsub('{{UI_BRIDGE_SCRIPT}}', ui_bridge_script)
        end

        def self.na_resolve_logo_file_uri
            path = Na__PathResolver.Na__Noble3dModellingTools__NaLogoFilePath
            return '' unless File.exist?(path)
            forward_path = path.tr('\\', '/').gsub(/^\//, '')
            'file:///' + forward_path.gsub(' ', '%20')
        end

        def self.na_build_tab_buttons_html
            tabs = Na__ConfigLoader.Na__Noble3dModellingTools__Tabs
            tabs.each_with_index.map do |tab, index|
                active_class = index.zero? ? ' naNoble3d__TabButton--active' : ''
                tab_id = tab.fetch('tab_id', '')
                tab_name = tab.fetch('tab_name', tab_id)

                <<~HTML_BUTTON.strip
                <button class="naNoble3d__TabButton#{active_class}" onclick='Na__Noble3d__ShowTab(#{tab_id.to_json}, this)'>#{na_escape_html(tab_name)}</button>
                HTML_BUTTON
            end.join("\n        ")
        end

        def self.na_build_tab_content_html
            tabs = Na__ConfigLoader.Na__Noble3dModellingTools__Tabs
            tabs.each_with_index.map do |tab, index|
                active_class = index.zero? ? ' naNoble3d__TabPanel--active' : ''
                tab_id = tab.fetch('tab_id', '')
                tab_name = tab.fetch('tab_name', tab_id)
                tab_description = tab.fetch('tab_description', '')
                buttons = Na__ConfigLoader.Na__Noble3dModellingTools__ButtonsForTabName(tab_name)

                <<~HTML_TAB
                <section id="tab-#{na_escape_html(tab_id)}" class="naNoble3d__TabPanel#{active_class}">
                    <header class="naNoble3d__TabHeader">
                        <h2 class="naNoble3d__TabTitle">#{na_escape_html(tab_name)}</h2>
                        <p class="naNoble3d__TabDescription">#{na_escape_html(tab_description)}</p>
                    </header>
                    <div class="naNoble3d__ToolGrid">
                        #{na_build_button_cards_html(buttons)}
                    </div>
                </section>
                HTML_TAB
            end.join("\n")
        end

        def self.na_build_button_cards_html(buttons)
            return '<p class="naNoble3d__EmptyState">No commands configured for this tab.</p>' if buttons.empty?

            buttons.map do |button|
                button_label = button.fetch('button_label', 'Run')
                button_description = button.fetch('description', '')
                command_id = button.fetch('command_id', '')

                <<~HTML_CARD
                <article class="naNoble3d__ToolCard">
                    <p class="naNoble3d__ToolDescription">#{na_escape_html(button_description)}</p>
                    <button class="naNoble3d__ActionButton" onclick='Na__Noble3d__RunCommand(#{command_id.to_json})'><strong>#{na_escape_html(button_label)}</strong></button>
                </article>
                HTML_CARD
            end.join("\n")
        end

        def self.na_escape_html(raw_text)
            raw_text.to_s
                .gsub('&', '&amp;')
                .gsub('<', '&lt;')
                .gsub('>', '&gt;')
                .gsub('"', '&quot;')
                .gsub("'", '&#39;')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | JS Bridge and Status Sync
# -----------------------------------------------------------------------------

        def self.na_setup_dialog_callbacks(dialog)
            dialog.add_action_callback('run_command') do |_context, command_id|
                command_result = na_run_command_with_module_load(command_id)
                na_update_status_element(
                    dialog,
                    command_result.fetch(:message, ''),
                    command_result.fetch(:success, false) ? 'success' : 'error'
                )
            end
        end

        def self.na_run_command_with_module_load(command_id)
            if Na__Noble3dModellingTools.respond_to?(:Na__Noble3dModellingTools__RunCommandById)
                Na__Noble3dModellingTools.Na__Noble3dModellingTools__RunCommandById(command_id)
            else
                Na__CommandRouter.Na__Noble3dModellingTools__RunCommand(command_id)
            end
        end

        def self.Na__Noble3dModellingTools__PushStatus(status_text, status_variant = 'info')
            return unless self.Na__Noble3dModellingTools__DialogVisible

            na_update_status_element(@na_dialog, status_text, status_variant)
        end

        def self.na_update_status_element(dialog, status_text, status_variant)
            script = <<~SCRIPT
            (function() {
                var statusElement = document.getElementById('naNoble3dStatus');
                if (!statusElement) { return; }
                statusElement.textContent = #{status_text.to_s.to_json};
                statusElement.className = 'naNoble3d__Status naNoble3d__Status--' + #{status_variant.to_s.to_json};
            })();
            SCRIPT
            dialog.execute_script(script)
        end

# endregion -------------------------------------------------------------------

    end # module Na__DialogManager
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
