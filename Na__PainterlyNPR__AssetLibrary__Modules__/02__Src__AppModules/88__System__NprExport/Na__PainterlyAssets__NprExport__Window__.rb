# =============================================================================
# NA PAINTERLYNPR ASSETS - NPR EXPORT - WINDOW
# =============================================================================
#
# FILE       : Na__PainterlyAssets__NprExport__Window__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprExport
# PURPOSE    : The NPR Export window: every export setting (what, format,
#              resolution, where, the name, what happens after), kept in the
#              model as it is changed; Export; the pen calibration sheet; the
#              look saved to and loaded from a .json file.
#              JS -> Ruby (the plugin's own page, its Bridge):
#                na_npr_dialog_ready()           - send the state
#                na_npr_action(actionId, json)   - settings | export | calibration | cancel |
#                                                  chooseFolder | openFolder | resetExport |
#                                                  saveLook | loadLook | restoreBackup |
#                                                  refresh | openViewport | openParameters
#              Ruby -> JS:
#                window.Na__PainterlyAssets__Receive(channel, payload)
#                channels: state | derived | progress | report | status
# CREATED    : 01-Nov-2026 (v0.3.0)
#
# DESCRIPTION:
# - Adam, 01-Nov-2026: "create a new button for exporting that opens up a new
#   menu that's got all of the export options you would expect ... it would be
#   really annoying having to keep reconfiguring those".
# - EVERY CHANGE IS KEPT IN THE MODEL (Na__NprSettings, one undo step a run of
#   changes), so the next export, after a reopen or on the other PC, starts
#   where this one left off. Reset Export Settings puts the plugin's defaults
#   back (AppConfig nprExport.defaults).
# - The scenes are read when the window is shown, when it gains focus and when
#   Refresh is pressed: SketchUp's scenes are never watched, never written.
# - Native panels (choose a folder, save and open a file) are deferred out of
#   the callback: inside it they can be lost behind the window on Windows.
#
# =============================================================================

require 'json'

module Na__PainterlyAssets
    module Na__NprExport

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_EXPORT_PAGE = 'Na__PainterlyAssets__NprExport__UiLayout__.html'.freeze unless defined?(NA_EXPORT_PAGE)

        @na_window = nil unless defined?(@na_window)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Window
    # -------------------------------------------------------------------------

        # FUNCTION | Open NPR Export (or bring it to the front)
        # ------------------------------------------------------------
        def self.Na__Export__OpenWindow
            return @na_window.bring_to_front if self.Na__Export__WindowVisible?
            dialog = UI::HtmlDialog.new(self.na_window_options)
            self.na_bind_window(dialog)
            dialog.set_file(File.join(Na__PainterlyAssets::NA_MODULES_ROOT, NA_EXPORT_PAGE))
            dialog.set_on_closed do
                Na__PainterlyAssets::Na__NprExport.na_forget_window(dialog)
            end
            @na_window = dialog
            dialog.show
            Na__NprSettings.Na__Settings__WindowsChanged
        end
        # ---------------------------------------------------------------

        def self.Na__Export__WindowVisible?
            @na_window && @na_window.visible? ? true : false
        rescue StandardError
            false
        end

        # FUNCTION | Everything the Window Shows, Sent Again
        # ------------------------------------------------------------
        def self.Na__Export__PushState
            return false unless self.Na__Export__WindowVisible?
            model = Sketchup.active_model
            return false unless model
            self.na_send_window('state', self.na_state(model))
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | What the Window Shows
    # -------------------------------------------------------------------------

        def self.na_state(model)
            settings = Na__NprSettings.Na__Settings__Export(model)
            engine   = Na__RemoteEngine.Na__Remote__Current
            {
                'Model'      => { 'Title' => Na__NprSettings.Na__Settings__Title(model), 'Saved' => !model.path.to_s.empty?, 'Path' => model.path.to_s.tr('\\', '/') },
                'Settings'   => settings,
                'Defaults'   => Na__NprSettings.Na__Settings__ExportDefaults,
                'Scenes'     => self.na_scenes(model, settings),
                'Sheet'      => Na__NprExportNaming.Na__Naming__Sheet(engine && engine['folder'], Na__NprWindows.Na__Windows__Info('viewport')['SheetMm']),
                'DpiPresets' => Array(Na__ConfigLoader.Na__Config__GetOr([127, 150, 200, 254, 300, 400, 600], 'nprExport', 'dpiPresets')).map(&:to_i),
                'DpiLimits'  => Array(Na__ConfigLoader.Na__Config__GetOr([50, 1200], 'nprExport', 'dpiLimits')).map(&:to_i),
                'Viewport'   => { 'Open' => Na__NprWindows.Na__Windows__Visible?('viewport'), 'Ready' => Na__NprWindows.Na__Windows__Ready?('viewport') },
                'Engine'     => engine ? { 'Version' => engine['appVersion'].to_s, 'Commit' => engine['commit'].to_s } : nil,
                'Running'    => self.Na__Export__Running?,
                'Version'    => Na__PainterlyAssets.Na__PublicApi__Version
            }.merge(self.na_derived(model, settings))
        end

        # What follows from the settings: the folder, the first name, the record's line
        def self.na_derived(model, settings)
            folder = Na__NprExportNaming.Na__Naming__Folder(model.path, settings)
            {
                'Folder'  => { 'Path' => folder['path'], 'Exists' => folder['exists'], 'Make' => folder['make'], 'Problem' => folder['problem'] },
                'Preview' => self.na_preview(model, settings),
                'Record'  => Na__NprSettings.Na__Settings__Status(model)
            }
        end

        # The model's scenes in its own order: { 'Pid', 'Name', 'Ticked', 'Camera' }
        def self.na_scenes(model, settings)
            ticked = self.Na__Export__TickedPages(model, settings['scenes'])
            model.pages.to_a.map do |page|
                { 'Pid' => page.persistent_id.to_i, 'Name' => page.name.to_s, 'Ticked' => ticked.include?(page), 'Camera' => page.use_camera? ? true : false }
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The model's scenes could not be listed: #{error.message}")
            []
        end

        # The first picture's file name, as Export would give it
        def self.na_preview(model, settings)
            view = if settings['views'] == 'scenes'
                       page = self.Na__Export__TickedPages(model, settings['scenes']).first
                       page ? page.name.to_s : 'Scene'
                   else
                       'CurrentView'
                   end
            seed   = self.na_seed(model)
            values = Na__NprExportNaming.Na__Naming__Values(Na__NprSettings.Na__Settings__Title(model), view, settings['dpi'], seed)
            Na__NprExportNaming.Na__Naming__FileName(settings['fileName'], values, settings['format'])
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | JS -> Ruby
    # -------------------------------------------------------------------------

        def self.na_bind_window(dialog)
            dialog.add_action_callback('na_npr_dialog_ready') do |_context|
                begin
                    Na__PainterlyAssets::Na__NprExport.Na__Export__PushState
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error('NPR Export could not be given its state.', error)
                end
            end
            dialog.add_action_callback('na_npr_action') do |_context, action_id, payload_json|
                begin
                    payload = Na__PainterlyAssets::Na__NprExport.na_parse(payload_json)
                    Na__PainterlyAssets::Na__NprExport.na_window_action(action_id.to_s, payload)
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error("NPR Export's #{action_id} failed.", error)
                    Na__PainterlyAssets::Na__NprExport.na_status("That did not work: #{error.message}", 'error')
                end
            end
        end

        def self.na_window_action(action, payload)
            model = Sketchup.active_model
            case action
            when 'settings'       then self.na_save_settings(model, payload['Settings'])
            when 'export'         then self.na_export(model, payload['Settings'], nil)
            when 'calibration'    then self.na_export(model, payload['Settings'], payload['Which'].to_s)
            when 'cancel'         then self.Na__Export__Cancel
            when 'chooseFolder'   then self.na_defer { self.na_choose_folder(Sketchup.active_model) }
            when 'openFolder'     then self.na_open_folder(model)
            when 'resetExport'    then self.na_reset(model)
            when 'saveLook'       then self.na_defer { self.na_save_look(Sketchup.active_model) }
            when 'loadLook'       then self.na_defer { self.na_load_look(Sketchup.active_model) }
            when 'restoreBackup'  then self.na_restore(model)
            when 'refresh'        then self.Na__Export__PushState
            when 'openViewport'   then self.na_defer { Na__NprWindows.Na__Windows__Open('viewport') }
            when 'openParameters' then self.na_defer { Na__NprWindows.Na__Windows__Open('parameters') }
            else
                Na__DebugTools.Na__Debug__Warn("NPR Export asked for an unknown action: #{action}")
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Actions
    # -------------------------------------------------------------------------

        # A setting changed on the page: kept in the model, what follows from it sent back
        def self.na_save_settings(model, settings)
            return unless model && settings.is_a?(Hash)
            problem = Na__NprSettings.Na__Settings__SaveExport(model, settings)
            self.na_send_window('derived', self.na_derived(model, Na__NprSettings.Na__Settings__Export(model)))
            self.na_status(problem, 'warn') if problem
        end

        def self.na_export(model, settings, calibration)
            self.na_save_settings(model, settings) if settings.is_a?(Hash)
            problem = self.Na__Export__Start(model, Na__NprSettings.Na__Settings__Export(model), calibration)
            self.na_status(problem, 'error') if problem
            self.na_send_window('progress', { 'Running' => self.Na__Export__Running?, 'Text' => problem, 'Level' => 'error' }) if problem
        end

        def self.na_reset(model)
            problem = Na__NprSettings.Na__Settings__SaveExport(model, Na__NprSettings.Na__Settings__ExportDefaults, 'exportReset')
            self.Na__Export__PushState
            self.na_status(problem || 'NPR Export\'s settings are back to the plugin\'s defaults. Undo in SketchUp puts the last ones back.', problem ? 'warn' : 'success')
        end

        def self.na_restore(model)
            problem = Na__NprSettings.Na__Settings__Restore(model)
            self.Na__Export__PushState
            self.na_status(problem || 'The NPR settings this PC kept for this model are back in it. Undo in SketchUp takes them out again.', problem ? 'warn' : 'success')
        end

        def self.na_choose_folder(model)
            settings = Na__NprSettings.Na__Settings__Export(model)
            current  = Na__NprExportNaming.Na__Naming__Folder(model.path, settings)
            start    = current['path'] && File.directory?(current['path']) ? current['path'] : (model.path.to_s.empty? ? nil : File.dirname(model.path))
            picked   = start ? UI.select_directory(title: 'Choose the Folder for the NPR Pictures', directory: start) : UI.select_directory(title: 'Choose the Folder for the NPR Pictures')
            return unless picked
            stored = Na__NprExportNaming.Na__Naming__StoreFolder(model.path, picked)
            problem = Na__NprSettings.Na__Settings__SaveExport(model, settings.merge('folderMode' => 'chosen', 'folder' => stored))
            self.Na__Export__PushState
            self.na_status(problem, 'warn') if problem
        end

        def self.na_open_folder(model)
            folder = Na__NprExportNaming.Na__Naming__Folder(model.path, Na__NprSettings.Na__Settings__Export(model))
            return self.na_status(folder['problem'], 'warn') if folder['problem']
            return self.na_status('That folder is made with the first export.', 'info') unless folder['exists']
            self.na_defer { UI.openURL(Na__PathResolver.Na__Paths__FileUri(folder['path'])) }
        end

        # FUNCTION | Save the Look As .json: the engine's own settings object, the drawing's part
        # ------------------------------------------------------------
        # The PainterlyNPR app opens it (Export > Open .json), and so does Load a Look.
        def self.na_save_look(model)
            look = Na__NprSettings.Na__Settings__Look(model)
            return self.na_status('The look is still PainterlyNPR\'s defaults: there is nothing of this model\'s to save yet. Change a parameter in NPR Parameters first.', 'info') unless look['settings']
            folder = model.path.to_s.empty? ? nil : File.dirname(model.path)
            name   = "#{Na__NprExportNaming.Na__Naming__Safe(Na__NprSettings.Na__Settings__Title(model))}__NprLook__.json"
            path   = UI.savepanel('Save the NPR Look As', folder, name)
            return unless path
            path = "#{path}.json" unless File.extname(path).casecmp('.json').zero?
            engine = Na__RemoteEngine.Na__Remote__Current || {}
            data = { 'EngineVersion' => engine['appVersion'].to_s }.merge(look['settings']).merge(
                'SavedBy' => "Na PainterlyNPR Assets #{Na__PainterlyAssets.Na__PublicApi__Version} (SketchUp), from #{Na__NprSettings.Na__Settings__Title(model)}",
                'SavedAt' => Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
            )
            Na__SafeFileWriter.Na__SafeFile__WriteJson(path, data, 2)
            self.na_status("The look is saved as #{File.basename(path)}.", 'success')
        rescue SystemCallError => error
            self.na_status("The look could not be saved: #{error.message}", 'error')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load a Look From .json: its Seed, Sun, Style, Paper and Composition into the model
        # ------------------------------------------------------------
        def self.na_load_look(model)
            folder = model.path.to_s.empty? ? nil : File.dirname(model.path)
            path   = UI.openpanel('Load an NPR Look', folder, 'PainterlyNPR Look|*.json||')
            return unless path
            data = Na__SafeFileWriter.Na__SafeFile__ReadJson(path)
            return self.na_status("#{File.basename(path)} is not a JSON settings file.", 'error') unless data
            problem = Na__NprSettings.Na__Settings__SaveLook(model, data, 'lookLoad')
            return self.na_status(problem, 'error') if problem
            Na__NprSettings.Na__Settings__Announce(model)
            self.na_status("The look from #{File.basename(path)} is now this model's (one step: Undo in SketchUp puts the last one back).", 'success')
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS
    # -------------------------------------------------------------------------

        def self.na_send_window(channel, payload)
            return false unless self.Na__Export__WindowVisible?
            @na_window.execute_script("window.Na__PainterlyAssets__Receive && window.Na__PainterlyAssets__Receive(#{JSON.generate(channel.to_s)}, #{JSON.generate(payload)});")
            true
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Sending '#{channel}' to NPR Export failed.", error)
            false
        end

        def self.na_status(message, level = 'info')
            self.na_send_window('status', { 'message' => message.to_s, 'level' => level.to_s })
        end

        def self.na_progress(text, level)
            self.na_send_window('progress', { 'Running' => self.Na__Export__Running?, 'Text' => text.to_s, 'Level' => level.to_s })
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_forget_window(dialog)
            @na_window = nil if @na_window.equal?(dialog)
            Na__NprSettings.Na__Settings__WindowsChanged
        end

        def self.na_parse(json)
            text = json.to_s.strip
            return {} if text.empty?
            parsed = JSON.parse(text)
            parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError => error
            Na__DebugTools.Na__Debug__Warn("Ignored a malformed NPR Export payload: #{error.message}")
            {}
        end

        def self.na_window_options
            spec = Na__ConfigLoader.Na__Config__Get('nprExport', 'window') || {}
            {
                dialog_title:    spec['title'] || 'NPR Export',
                preferences_key: spec['preferencesKey'] || 'Na__PainterlyNPR__NprExport',
                scrollable:      false,
                resizable:       true,
                width:           (spec['width'] || 540).to_i,
                height:          (spec['height'] || 860).to_i,
                min_width:       (spec['minWidth'] || 420).to_i,
                min_height:      (spec['minHeight'] || 480).to_i,
                style:           UI::HtmlDialog::STYLE_DIALOG
            }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
