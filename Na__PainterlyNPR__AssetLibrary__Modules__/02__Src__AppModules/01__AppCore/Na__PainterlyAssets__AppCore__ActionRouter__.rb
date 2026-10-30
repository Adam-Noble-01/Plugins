# =============================================================================
# NA PAINTERLYNPR ASSETS - APP CORE - ACTION ROUTER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__AppCore__ActionRouter__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__ActionRouter
# PURPOSE    : Every request the dialog makes, by its action id, to the system
#              that answers it; and what goes back to the page afterwards.
# CREATED    : 30-Oct-2026
#
# ACTIONS:
#   refresh            rescan the library, push the whole state
#   place              { assetId } load or build its component, start SketchUp's placement tool
#   writeSkp           { assetId } write its SKP from the proxy, mark its DAT, validate
#   writeMissingSkps   every asset with a MOD and no SKP, then validate (the page confirms first)
#   openFolder         { assetId } open the asset's folder in Explorer
#   readSelection      what the selected component offers as a new asset
#   checkAuthor        { form } the plan, with the next Id from the build utility (a dry run)
#   author             { form } plan afresh and file the asset, then validate
#   validate           PainterlyNPR's validate, then index
#   paintMaterial      { key } paint the selection with an NPR swatch, or arm the Paint Bucket
#   chooseLibrary / resetLibrary, choosePython / resetPython   this PC's overrides
#   setPref            { key: thumbs | tab, value } remembered per PC
#   reloadPlugin       Reload Plugin Data, then reopen the page
#
# ERRORS:
#   The ONE broad rescue for a request is here (the callback boundary): it
#   logs the detail, tells the person in plain words, and always ends the
#   page's busy state, so the dialog can never be left locked.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__ActionRouter

    # -------------------------------------------------------------------------
    # REGION | Dispatch
    # -------------------------------------------------------------------------

        def self.Na__Action__Dispatch(action_id, payload)
            case action_id
            when 'refresh'          then self.na_refresh
            when 'place'            then self.na_place(payload)
            when 'writeSkp'         then self.na_write_skp(payload)
            when 'writeMissingSkps' then self.na_write_missing_skps
            when 'openFolder'       then self.na_open_folder(payload)
            when 'readSelection'    then self.na_push_selection
            when 'checkAuthor'      then self.na_check_author(payload)
            when 'author'           then self.na_author(payload)
            when 'validate'         then self.na_validate('asked for')
            when 'paintMaterial'    then self.na_paint_material(payload)
            when 'chooseLibrary'    then self.na_choose_library
            when 'resetLibrary'     then self.na_reset_library
            when 'choosePython'     then self.na_choose_python
            when 'resetPython'      then self.na_reset_python
            when 'setPref'          then self.na_set_pref(payload)
            when 'reloadPlugin'     then Na__DialogManager.Na__Dialog__ReloadPlugin
            else
                Na__DebugTools.Na__Debug__Warn("Unknown dialog action '#{action_id}'.")
                Na__DialogManager.Na__Dialog__PushStatus("The dialog asked for '#{action_id}', which this version does not know. Reopen the window.", 'warn')
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Dialog action '#{action_id}' failed.", error)
            self.na_busy(false)
            Na__DialogManager.Na__Dialog__PushStatus("That did not work: #{error.message}", 'error')
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Catalogue and Place
    # -------------------------------------------------------------------------

        def self.na_refresh
            Na__Register.Na__Register__ClearCache
            Na__DialogManager.Na__Dialog__PushState
            catalogue = Na__Catalogue.Na__Catalogue__Last
            Na__DialogManager.Na__Dialog__PushStatus(catalogue['ok'] ? "Read the library: #{catalogue['message']}." : catalogue['message'], catalogue['ok'] ? 'info' : 'error')
        end

        def self.na_place(payload)
            result = Na__Placement.Na__Place__Asset(payload['assetId'].to_s)
            Na__DialogManager.Na__Dialog__Send('catalogue', Na__Catalogue.Na__Catalogue__Last)
            Na__DialogManager.Na__Dialog__PushStatus(result['message'], result['level'])
        end

        def self.na_write_skp(payload)
            result = Na__Placement.Na__Place__WriteSkp(payload['assetId'].to_s)
            self.na_after_library_change(result, "after writing #{payload['assetId']}'s SKP")
        end

        def self.na_write_missing_skps
            result = Na__Placement.Na__Place__WriteMissingSkps
            self.na_after_library_change(result, 'after writing the missing SKPs')
        end

        def self.na_open_folder(payload)
            asset = Na__Catalogue.Na__Catalogue__Find(payload['assetId'].to_s)
            folder = asset ? asset['FolderPath'] : Na__PathResolver.Na__Paths__Library
            return Na__DialogManager.Na__Dialog__PushStatus('The library folder was not found.', 'error') unless folder && File.directory?(folder)

            Na__DialogManager.Na__Dialog__Deferred { UI.openURL(Na__PathResolver.Na__Paths__FileUri(folder)) }
        end

        # A write changed the library: show the result, read the library again,
        # then let PainterlyNPR's validator have the last word.
        def self.na_after_library_change(result, reason)
            Na__DialogManager.Na__Dialog__PushStatus(result['message'], result['level'])
            return unless result['ok'] || Array(result['written']).any?

            Na__Catalogue.Na__Catalogue__Scan
            Na__DialogManager.Na__Dialog__Send('catalogue', Na__Catalogue.Na__Catalogue__Last)
            self.na_validate(reason, result['message'])
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Author
    # -------------------------------------------------------------------------

        def self.na_push_selection
            Na__DialogManager.Na__Dialog__Send('selection', Na__AuthorSelection.Na__Author__ReadSelection)
        end

        def self.na_check_author(payload)
            self.na_busy(true, 'Asking PainterlyNPR for the next Id...')
            Na__AuthorPlan.Na__Author__Plan(payload['form']) do |plan|
                manager = Na__PainterlyAssets::Na__DialogManager
                Na__PainterlyAssets::Na__ActionRouter.na_busy(false)
                manager.Na__Dialog__Send('plan', plan)
                manager.Na__Dialog__PushStatus(plan['ok'] ? "Ready to author #{plan['assetId']}: check the plan, then Author Asset." : "Not ready: #{Array(plan['errors']).first}", plan['ok'] ? 'info' : 'warn')
            end
        end

        def self.na_author(payload)
            self.na_busy(true, 'Filing the asset...')
            Na__AuthorCommit.Na__Author__Commit(payload['form']) do |result|
                manager = Na__PainterlyAssets::Na__DialogManager
                router  = Na__PainterlyAssets::Na__ActionRouter
                router.na_busy(false)
                manager.Na__Dialog__Send('plan', result['plan']) if result['plan']
                manager.Na__Dialog__Send('authored', result)                                         # <-- After the plan: the page then drops the plan, so one Check never files twice
                router.na_push_selection
                if result['ok']
                    router.na_after_library_change(result, "after authoring #{result['assetId']}")
                else
                    manager.Na__Dialog__PushStatus(result['message'], result['level'])
                end
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Validate
    # -------------------------------------------------------------------------

        # @param lead [String, nil] a status message the validation's verdict follows
        def self.na_validate(reason, lead = nil)
            self.na_busy(true, 'PainterlyNPR is checking the library...')
            Na__ValidateRunner.Na__Validate__Run(reason) do |report|
                manager = Na__PainterlyAssets::Na__DialogManager
                Na__PainterlyAssets::Na__ActionRouter.na_busy(false)
                manager.Na__Dialog__Send('validation', report)
                verdict = report['ran'] ? "Validate: #{report['summary']}#{report['index'] ? " Index: #{report['index']['text']}" : ''}" : "Validate did not run: #{report['summary']}"
                level   = report['ok'] ? (report['warnings'].to_i.zero? ? 'success' : 'warn') : 'error'
                manager.Na__Dialog__PushStatus(lead ? "#{lead} #{verdict}" : verdict, level)
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Materials
    # -------------------------------------------------------------------------

        def self.na_paint_material(payload)
            result = Na__MaterialPainter.Na__Painter__Apply(payload['key'].to_s)
            Na__DialogManager.Na__Dialog__PushStatus(result['message'], result['level'])
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Settings (this PC's overrides)
    # -------------------------------------------------------------------------

        def self.na_choose_library
            start = Na__PathResolver.Na__Paths__Root || Na__PainterlyAssets::NA_MODULES_ROOT
            Na__DialogManager.Na__Dialog__Deferred do                                                   # <-- A native panel inside a dialog callback can be lost behind it (Windows)
                picked = UI.select_directory(title: 'Choose the Na__PainterlyNPR folder (or its 12__Data__AssetLibrary)', directory: start)
                router = Na__PainterlyAssets::Na__ActionRouter
                next router.na_settings_changed('Library folder unchanged.', 'info') if picked.nil?

                root = Na__PainterlyAssets::Na__PathResolver.Na__Paths__NormaliseChosenRoot(picked)
                if root
                    Na__PainterlyAssets::Na__UserConfigStore.Na__UserConfig__Set('library', 'root', root)
                    router.na_settings_changed("Library folder set to #{root}.", 'success')
                else
                    router.na_settings_changed("#{picked} holds no asset library register. Choose the Na__PainterlyNPR folder.", 'error')
                end
            end
        end

        def self.na_reset_library
            Na__UserConfigStore.Na__UserConfig__Set('library', 'root', nil)
            self.na_settings_changed('Library folder: back to the default places.', 'info')
        end

        def self.na_choose_python
            current = Na__PathResolver.Na__Paths__Python
            start   = current ? File.dirname(current['console']) : 'C:/'
            Na__DialogManager.Na__Dialog__Deferred do
                picked = UI.openpanel('Choose python.exe (Python 3)', start, 'Python|python.exe||')
                router = Na__PainterlyAssets::Na__ActionRouter
                next router.na_settings_changed('Python unchanged.', 'info') if picked.nil?

                clean = picked.tr('\\', '/')
                if File.basename(clean).casecmp('python.exe').zero? && !clean.downcase.include?('/windowsapps/')
                    Na__PainterlyAssets::Na__UserConfigStore.Na__UserConfig__Set('python', 'executable', clean)
                    router.na_settings_changed("Python set to #{clean}.", 'success')
                else
                    router.na_settings_changed('Choose a python.exe from a Python 3 install (not the Windows Store stub in WindowsApps).', 'error')
                end
            end
        end

        def self.na_reset_python
            Na__UserConfigStore.Na__UserConfig__Set('python', 'executable', nil)
            self.na_settings_changed('Python: found automatically again.', 'info')
        end

        def self.na_set_pref(payload)
            key = payload['key'].to_s
            return unless %w[thumbs tab].include?(key)
            Na__UserConfigStore.Na__UserConfig__Set('ui', key, payload['value'].to_s)
        end

        def self.na_settings_changed(message, level)
            Na__Register.Na__Register__ClearCache
            Na__DialogManager.Na__Dialog__PushState
            Na__DialogManager.Na__Dialog__PushStatus(message, level)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        def self.na_busy(busy, label = nil)
            Na__DialogManager.Na__Dialog__Send('busy', { 'busy' => busy ? true : false, 'label' => label.to_s })
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
