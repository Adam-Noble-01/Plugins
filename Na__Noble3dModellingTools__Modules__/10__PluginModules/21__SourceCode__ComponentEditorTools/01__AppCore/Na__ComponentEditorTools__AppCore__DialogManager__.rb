# =============================================================================
# NA COMPONENT EDITOR TOOLS - APPCORE DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__AppCore__DialogManager__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__DialogManager
# PURPOSE    : Own HtmlDialog lifecycle and route JS callback actions to systems
# CREATED    : 2026
#
# =============================================================================

module Na__ComponentEditorTools
    module Na__DialogManager

# -----------------------------------------------------------------------------
# REGION | Dialog State
# -----------------------------------------------------------------------------

        @na_dialog = nil
        @na_selection_observer = nil
        @na_status_message = 'Ready.'
        @na_status_variant = 'info'
        @na_active_tab_id = 'gallery'
        @na_current_selection_key = nil
        @na_library_cache = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog Lifecycle
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ShowDialog
            if @na_dialog && @na_dialog.visible?
                @na_dialog.bring_to_front
                self.Na__ComponentEditorTools__BuildAndPushPayload
                return @na_dialog
            end

            @na_dialog = UI::HtmlDialog.new(self.Na__ComponentEditorTools__DialogOptions)

            ui_layout_path = Na__PathResolver.Na__ComponentEditorTools__UiLayoutFilePath
            if File.exist?(ui_layout_path)
                @na_dialog.set_file(ui_layout_path)
            else
                @na_dialog.set_html(self.Na__ComponentEditorTools__FallbackHtml)
            end

            self.Na__ComponentEditorTools__BindCallbacks(@na_dialog)
            @na_dialog.set_on_closed { @na_dialog = nil }
            @na_dialog.show

            self.Na__ComponentEditorTools__AttachSelectionObserverIfNeeded
            self.Na__ComponentEditorTools__BuildAndPushPayload
            self.Na__ComponentEditorTools__PushActiveTab
            self.Na__ComponentEditorTools__PushUserConfig
            self.Na__ComponentEditorTools__PushTaxonomy
            self.Na__ComponentEditorTools__PushCachedLibraryDataIfAvailable
            @na_dialog
        rescue => error
            UI.messagebox("Na__ComponentEditorTools\n\n#{error.class}: #{error.message}")
            nil
        end

        def self.Na__ComponentEditorTools__DialogHandle
            @na_dialog
        end

        def self.Na__ComponentEditorTools__HandleSelectionChanged
            selected_key = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstanceKey
            return if selected_key.nil? && @na_current_selection_key
            return if selected_key == @na_current_selection_key

            self.Na__ComponentEditorTools__BuildAndPushPayload
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public UI Sync
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__SetActiveTab(active_tab_id)
            return if active_tab_id.nil?

            @na_active_tab_id = active_tab_id.to_s
            @na_active_tab_id = Na__ComponentEditorTools::NA_DEFAULT_ACTIVE_TAB if @na_active_tab_id.empty?
            self.Na__ComponentEditorTools__PushActiveTab
        end

        def self.Na__ComponentEditorTools__PushStatus(message_text, status_variant = 'info')
            @na_status_message = message_text.to_s
            @na_status_variant = status_variant.to_s.empty? ? 'info' : status_variant.to_s

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveStatus',
                {
                    message: @na_status_message,
                    variant: @na_status_variant
                }
            )
        end

        def self.Na__ComponentEditorTools__BuildAndPushPayload
            selected_key = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstanceKey
            @na_current_selection_key = selected_key if selected_key

            payload_hash = Na__SelectionInspector.Na__ComponentEditorTools__BuildPayload(
                @na_status_message,
                @na_status_variant,
                @na_active_tab_id
            )

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceivePayload',
                payload_hash
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Callback Binding
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BindCallbacks(dialog)
            callback_registry = {

                # ----- Existing selection/editor callbacks -------------------

                'na_componenteditortools_request_selection' => proc {
                    self.Na__ComponentEditorTools__BuildAndPushPayload
                },
                'na_componenteditortools_set_active_tab' => proc { |tab_id|
                    self.Na__ComponentEditorTools__SetActiveTab(tab_id)
                },
                'na_componenteditortools_apply_basic_fields' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__ApplyBasicFields(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_update_component' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__UpdateComponent(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_set_attribute' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__SetAttribute(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_delete_attribute' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__MetadataEditor.Na__ComponentEditorTools__DeleteAttribute(payload_hash)
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_refresh_thumbnail' => proc {
                    result = Na__ThumbnailTools.Na__ComponentEditorTools__RefreshThumbnailFromCurrentView
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_capture_viewport_png' => proc {
                    result = Na__ThumbnailTools.Na__ComponentEditorTools__CaptureViewportPng
                    self.Na__ComponentEditorTools__HandleActionResult(result)
                },
                'na_componenteditortools_reload_plugin' => proc {
                    self.Na__ComponentEditorTools__HandleReloadRequest
                },

                # ----- User Config callbacks ---------------------------------

                'na_componenteditortools_get_user_config' => proc {
                    self.Na__ComponentEditorTools__PushUserConfig
                },
                'na_componenteditortools_set_library_path' => proc {
                    default_dir = Na__UserConfig.Na__ComponentEditorTools__LibraryPath
                    default_dir = Dir.home if default_dir.empty?
                    folder = UI.select_directory(title: 'Select Components Library Folder', directory: default_dir)
                    if folder
                        Na__UserConfig.Na__ComponentEditorTools__SetLibraryPath(folder)
                        @na_library_cache = nil
                        UI.start_timer(0.0, false) {
                            self.Na__ComponentEditorTools__PushUserConfig
                            self.Na__ComponentEditorTools__PushStatus("Library folder set. Click \"Load Library\" in the Gallery or Index tab, or use Refresh Library in Settings.", 'success')
                        }
                    else
                        UI.start_timer(0.0, false) {
                            self.Na__ComponentEditorTools__PushStatus('Ready.', 'info')
                        }
                    end
                },
                'na_componenteditortools_add_blocked_folder' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    folder_name = (payload_hash['folder_name'] || payload_hash[:folder_name]).to_s.strip
                    unless folder_name.empty?
                        Na__UserConfig.Na__ComponentEditorTools__AddBlockedFolder(folder_name)
                        self.Na__ComponentEditorTools__PushUserConfig
                        self.Na__ComponentEditorTools__PushStatus("Blocked: #{folder_name}", 'success')
                    end
                },
                'na_componenteditortools_remove_blocked_folder' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    folder_name = (payload_hash['folder_name'] || payload_hash[:folder_name]).to_s.strip
                    unless folder_name.empty?
                        Na__UserConfig.Na__ComponentEditorTools__RemoveBlockedFolder(folder_name)
                        self.Na__ComponentEditorTools__PushUserConfig
                        self.Na__ComponentEditorTools__PushStatus("Unblocked: #{folder_name}", 'success')
                    end
                },
                'na_componenteditortools_add_blocked_file' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    file_name = (payload_hash['file_name'] || payload_hash[:file_name]).to_s.strip
                    unless file_name.empty?
                        Na__UserConfig.Na__ComponentEditorTools__AddBlockedFile(file_name)
                        self.Na__ComponentEditorTools__PushUserConfig
                        self.Na__ComponentEditorTools__PushStatus("File blocked: #{file_name}", 'success')
                    end
                },
                'na_componenteditortools_remove_blocked_file' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    file_name = (payload_hash['file_name'] || payload_hash[:file_name]).to_s.strip
                    unless file_name.empty?
                        Na__UserConfig.Na__ComponentEditorTools__RemoveBlockedFile(file_name)
                        self.Na__ComponentEditorTools__PushUserConfig
                        self.Na__ComponentEditorTools__PushStatus("File unblocked: #{file_name}", 'success')
                    end
                },

                # ----- Library scan + data callbacks -------------------------

                'na_componenteditortools_scan_library' => proc {
                    self.Na__ComponentEditorTools__HandleScanLibrary(force_refresh: false)
                },
                'na_componenteditortools_refresh_library' => proc {
                    self.Na__ComponentEditorTools__HandleScanLibrary(force_refresh: true)
                },
                'na_componenteditortools_get_gallery' => proc {
                    self.Na__ComponentEditorTools__HandleGetGallery
                },
                'na_componenteditortools_get_index' => proc {
                    self.Na__ComponentEditorTools__HandleGetIndex
                },

                # ----- Placement callback ------------------------------------

                'na_componenteditortools_insert_library_component' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    component_path = (payload_hash['path'] || payload_hash[:path]).to_s
                    result = Na__LibraryPlacementTool.Na__ComponentEditorTools__StartPlacement(component_path, @na_dialog)
                    if result[:ok]
                        self.Na__ComponentEditorTools__PushStatus(result[:message], 'info')
                    else
                        self.Na__ComponentEditorTools__PushStatus(result[:message], 'error')
                    end
                },
                'na_componenteditortools_open_component_file' => proc { |raw_payload|
                    payload_hash    = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    component_path  = (payload_hash['path'] || payload_hash[:path]).to_s.strip
                    if component_path.empty? || !File.exist?(component_path)
                        self.Na__ComponentEditorTools__PushStatus("File not found: #{File.basename(component_path)}", 'error')
                    else
                        self.Na__ComponentEditorTools__PushStatus("Opening: #{File.basename(component_path)}", 'info')
                        UI.start_timer(0.0, false) {
                            if Sketchup.platform == :platform_win
                                system("start \"\" \"#{component_path}\"")
                            else
                                system("open \"#{component_path}\"")
                            end
                        }
                    end
                },
                'na_componenteditortools_copy_component_path' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    file_path    = (payload_hash['path'] || payload_hash[:path]).to_s
                    self.Na__ComponentEditorTools__CopyPathToClipboard(file_path)
                },

                # ----- Index editing callbacks --------------------------------

                'na_componenteditortools_rename_library_component' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__LibraryEditor.Na__ComponentEditorTools__RenameComponent(payload_hash)
                    self.Na__ComponentEditorTools__PushStatus(result[:message], result[:success] ? 'success' : 'error')
                    self.Na__ComponentEditorTools__HandleGetIndex if result[:success]
                },
                'na_componenteditortools_update_library_metadata' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__LibraryEditor.Na__ComponentEditorTools__UpdateMetadata(payload_hash)
                    self.Na__ComponentEditorTools__PushStatus(result[:message], result[:success] ? 'success' : 'error')
                    self.Na__ComponentEditorTools__HandleGetIndex if result[:success]
                },
                'na_componenteditortools_update_library_data' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    result = Na__LibraryEditor.Na__ComponentEditorTools__UpdateLibraryData(payload_hash)
                    self.Na__ComponentEditorTools__PushStatus(result[:message], result[:success] ? 'success' : 'error')
                    self.Na__ComponentEditorTools__HandleGetIndex if result[:success]
                },
                'na_componenteditortools_update_field' => proc { |raw_payload|
                    self.Na__ComponentEditorTools__HandleUpdateField(raw_payload)
                },

                # ----- Category taxonomy callbacks ----------------------------

                'na_componenteditortools_get_taxonomy' => proc {
                    self.Na__ComponentEditorTools__PushTaxonomy
                },
                'na_componenteditortools_add_category' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    name = (payload_hash['category'] || payload_hash[:category]).to_s.strip
                    if Na__Taxonomy.Na__ComponentEditorTools__AddCategory(name)
                        self.Na__ComponentEditorTools__PushStatus("Category added: #{name}", 'success')
                    else
                        self.Na__ComponentEditorTools__PushStatus("Category not added (empty or duplicate).", 'warning')
                    end
                    self.Na__ComponentEditorTools__PushTaxonomy
                },
                'na_componenteditortools_remove_category' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    name = (payload_hash['category'] || payload_hash[:category]).to_s.strip
                    Na__Taxonomy.Na__ComponentEditorTools__RemoveCategory(name)
                    self.Na__ComponentEditorTools__PushStatus("Category removed: #{name}", 'success')
                    self.Na__ComponentEditorTools__PushTaxonomy
                },
                'na_componenteditortools_add_type' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    category = (payload_hash['category'] || payload_hash[:category]).to_s.strip
                    type_val = (payload_hash['type']     || payload_hash[:type]).to_s.strip
                    if Na__Taxonomy.Na__ComponentEditorTools__AddType(category, type_val)
                        self.Na__ComponentEditorTools__PushStatus("Type added: #{category} \u2192 #{type_val}", 'success')
                    else
                        self.Na__ComponentEditorTools__PushStatus("Type not added (empty or duplicate).", 'warning')
                    end
                    self.Na__ComponentEditorTools__PushTaxonomy
                },
                'na_componenteditortools_remove_type' => proc { |raw_payload|
                    payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
                    category = (payload_hash['category'] || payload_hash[:category]).to_s.strip
                    type_val = (payload_hash['type']     || payload_hash[:type]).to_s.strip
                    Na__Taxonomy.Na__ComponentEditorTools__RemoveType(category, type_val)
                    self.Na__ComponentEditorTools__PushStatus("Type removed: #{category} \u2192 #{type_val}", 'success')
                    self.Na__ComponentEditorTools__PushTaxonomy
                },
                'na_componenteditortools_seed_taxonomy' => proc {
                    Na__Taxonomy.Na__ComponentEditorTools__SeedFromStandards
                    self.Na__ComponentEditorTools__PushStatus('Categories populated from SSOT standards.', 'success')
                    self.Na__ComponentEditorTools__PushTaxonomy
                }

            }

            Na__UiBridge.Na__ComponentEditorTools__RegisterCallbacks(dialog, callback_registry)
        end

        def self.Na__ComponentEditorTools__HandleActionResult(result_hash)
            success_flag = self.Na__ComponentEditorTools__ResultValue(result_hash, :success)
            message_text = self.Na__ComponentEditorTools__ResultValue(result_hash, :message)
            status_variant = success_flag ? 'success' : 'error'

            self.Na__ComponentEditorTools__PushStatus(message_text, status_variant)
            self.Na__ComponentEditorTools__PushRenderPreview(result_hash)
        end

        def self.Na__ComponentEditorTools__HandleReloadRequest
            dialog_reference = @na_dialog
            active_tab_id = @na_active_tab_id

            reload_result = Na__ComponentEditorTools.Na__ComponentEditorTools__ReloadPluginData(dialog_reference, active_tab_id)
            return if reload_result[:success]

            self.Na__ComponentEditorTools__PushStatus(reload_result[:message], 'error')
            self.Na__ComponentEditorTools__BuildAndPushPayload
        end

        def self.Na__ComponentEditorTools__ResultValue(result_hash, key_name)
            return nil unless result_hash.is_a?(Hash)

            result_hash[key_name] || result_hash[key_name.to_s]
        end

        def self.Na__ComponentEditorTools__PushRenderPreview(result_hash)
            preview_path = self.Na__ComponentEditorTools__ResultValue(result_hash, :visible_view_render_path)
            return if preview_path.to_s.empty?
            return unless defined?(Na__ThumbnailTools)

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveRenderPreview',
                {
                    current_thumbnail_preview_path: preview_path,
                    current_thumbnail_preview_uri: Na__ThumbnailTools.Na__ComponentEditorTools__FilePathToFileUri(preview_path),
                    current_thumbnail_preview_source: 'visible_viewport'
                }
            )
        end

        def self.Na__ComponentEditorTools__PushUserConfig
            config_payload = Na__UserConfig.Na__ComponentEditorTools__GetAll
            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveUserConfig',
                config_payload
            )
        end

        def self.Na__ComponentEditorTools__PushTaxonomy
            taxonomy_payload = Na__Taxonomy.Na__ComponentEditorTools__GetAll
            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveTaxonomy',
                taxonomy_payload
            )
        end

        def self.Na__ComponentEditorTools__HandleScanLibrary(force_refresh: false)
            if !force_refresh && @na_library_cache
                self.Na__ComponentEditorTools__PushLibraryData(@na_library_cache)
                return
            end

            if force_refresh
                @na_library_cache = nil
                Na__LibraryExtractor.Na__ComponentEditorTools__PurgeLastResult
                Na__LibraryExtractor.Na__ComponentEditorTools__InvalidateCache
            end

            self.Na__ComponentEditorTools__PushStatus('Scanning library...', 'info')
            scan_result = Na__LibraryScanner.Na__ComponentEditorTools__ScanLibrary

            unless scan_result[:ok]
                self.Na__ComponentEditorTools__PushStatus(scan_result[:message], 'error')
                return
            end

            self.Na__ComponentEditorTools__PushStatus(
                "#{scan_result[:message]} Extracting metadata (this may take a moment for large libraries)...",
                'info'
            )
            entries = Na__LibraryExtractor.Na__ComponentEditorTools__ExtractAll(scan_result[:entries])
            folders = Na__LibraryScanner.Na__ComponentEditorTools__FolderList

            library_data = {
                'ok'           => true,
                'library_path' => scan_result[:library_path],
                'entries'      => entries,
                'folders'      => folders,
                'message'      => "#{entries.length} component(s) loaded."
            }

            @na_library_cache = library_data
            Na__LibraryExtractor.Na__ComponentEditorTools__SaveLastResult(library_data)

            self.Na__ComponentEditorTools__PushLibraryData(library_data)
            self.Na__ComponentEditorTools__PushStatus("Library loaded: #{entries.length} component(s). Use Refresh to re-scan.", 'success')
        rescue => error
            self.Na__ComponentEditorTools__PushStatus("Scan failed: #{error.class}: #{error.message}", 'error')
        end

        def self.Na__ComponentEditorTools__HandleGetGallery
            if @na_library_cache
                self.Na__ComponentEditorTools__PushLibraryData(@na_library_cache)
            else
                self.Na__ComponentEditorTools__HandleScanLibrary(force_refresh: false)
            end
        end

        def self.Na__ComponentEditorTools__HandleGetIndex
            if @na_library_cache
                self.Na__ComponentEditorTools__PushLibraryData(@na_library_cache)
            else
                self.Na__ComponentEditorTools__HandleScanLibrary(force_refresh: false)
            end
        end

        def self.Na__ComponentEditorTools__PushLibraryData(library_data)
            entries      = library_data['entries']      || library_data[:entries]      || []
            folders      = library_data['folders']      || library_data[:folders]      || []
            library_path = library_data['library_path'] || library_data[:library_path] || ''
            message      = library_data['message']      || library_data[:message]      || "#{entries.length} component(s)."

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveGallery',
                {
                    ok:           true,
                    library_path: library_path,
                    entries:      entries,
                    folders:      folders,
                    message:      message
                }
            )

            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveIndex',
                {
                    ok:           true,
                    library_path: library_path,
                    entries:      entries,
                    message:      message
                }
            )
        end

        def self.Na__ComponentEditorTools__HandleUpdateField(raw_payload)
            payload_hash = Na__UiBridge.Na__ComponentEditorTools__ParseJsonPayload(raw_payload)
            old_path = (payload_hash['path'] || payload_hash[:path]).to_s

            result = Na__LibraryEditor.Na__ComponentEditorTools__UpdateField(payload_hash)
            self.Na__ComponentEditorTools__PushStatus(result[:message], result[:success] ? 'success' : 'error')

            # Always re-extract the component from disk and push it back, so the
            # row reflects the real on-disk state. On failure the file is
            # unchanged, which cleanly reverts the cell out of its "Saving" state.
            new_path = (result[:updated_path] || result['updated_path']).to_s
            new_path = old_path if new_path.empty?

            updated_entry = self.Na__ComponentEditorTools__RefreshSingleCacheEntry(old_path, new_path)

            if updated_entry
                self.Na__ComponentEditorTools__PushEntryUpdate(old_path, updated_entry)
            else
                self.Na__ComponentEditorTools__HandleGetIndex
            end
        rescue => error
            self.Na__ComponentEditorTools__PushStatus("Update failed: #{error.class}: #{error.message}", 'error')
        end

        def self.Na__ComponentEditorTools__RefreshSingleCacheEntry(old_path, new_path)
            library_root = Na__LibraryScanner.Na__ComponentEditorTools__NormalisePath(
                Na__UserConfig.Na__ComponentEditorTools__LibraryPath
            )
            entry_meta    = Na__LibraryScanner.Na__ComponentEditorTools__BuildEntryMeta(new_path, library_root)
            updated_entry = Na__LibraryExtractor.Na__ComponentEditorTools__ExtractFromFile(entry_meta)
            return nil unless updated_entry

            norm_old     = old_path.to_s.tr('\\', '/')
            norm_old_lc  = norm_old.downcase
            norm_new     = updated_entry['path'].to_s.tr('\\', '/')
            norm_new_lc  = norm_new.downcase

            if @na_library_cache
                entries = @na_library_cache['entries'] || @na_library_cache[:entries] || []

                index = entries.index do |existing|
                    (existing['path'] || existing[:path]).to_s.tr('\\', '/') == norm_old
                end

                # Fallback: case-insensitive match for Windows paths
                if index.nil?
                    index = entries.index do |existing|
                        (existing['path'] || existing[:path]).to_s.tr('\\', '/').downcase == norm_old_lc
                    end
                end

                if index
                    entries[index] = updated_entry
                else
                    # Old entry not found — purge any stale entries for either
                    # the old path or the new path before inserting the fresh one.
                    entries.reject! do |existing|
                        ep = (existing['path'] || existing[:path]).to_s.tr('\\', '/').downcase
                        ep == norm_old_lc || ep == norm_new_lc
                    end
                    entries << updated_entry
                end

                @na_library_cache['entries'] = entries
                Na__LibraryExtractor.Na__ComponentEditorTools__SaveLastResult(@na_library_cache)
            end

            updated_entry
        rescue => error
            puts "[Na__ComponentEditorTools] RefreshSingleCacheEntry warning: #{error.class}: #{error.message}"
            nil
        end

        def self.Na__ComponentEditorTools__PushEntryUpdate(old_path, updated_entry)
            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__ReceiveEntryUpdate',
                {
                    old_path: old_path,
                    entry:    updated_entry
                }
            )
        end

        def self.Na__ComponentEditorTools__PushCachedLibraryDataIfAvailable
            return if @na_library_cache

            disk_cache = Na__LibraryExtractor.Na__ComponentEditorTools__LoadLastResult
            return unless disk_cache

            @na_library_cache = disk_cache
            self.Na__ComponentEditorTools__PushLibraryData(disk_cache)
        rescue => error
            puts "[Na__ComponentEditorTools] PushCachedLibraryData warning: #{error.class}: #{error.message}"
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__CopyPathToClipboard(path)
            return unless path && !path.empty?

            native_path = Sketchup.platform == :platform_win ? path.tr('/', '\\') : path
            begin
                if Sketchup.platform == :platform_win
                    IO.popen('clip', 'w') { |cb| cb.write(native_path) }
                elsif system('which pbcopy > /dev/null 2>&1')
                    IO.popen('pbcopy', 'w') { |cb| cb.write(native_path) }
                end
                puts "[Na__ComponentEditorTools] Copied path to clipboard: #{native_path}"
            rescue => error
                UI.messagebox("Copy to clipboard failed: #{error.message}")
            end
        end

        def self.Na__ComponentEditorTools__AttachSelectionObserverIfNeeded
            return if @na_selection_observer

            active_model = Sketchup.active_model
            return unless active_model

            @na_selection_observer = Na__ComponentEditorTools__SelectionObserver.new
            active_model.selection.add_observer(@na_selection_observer)
        rescue => error
            puts "[Na__ComponentEditorTools] Selection observer attach warning: #{error.class}: #{error.message}"
        end

        def self.Na__ComponentEditorTools__PushActiveTab
            Na__UiBridge.Na__ComponentEditorTools__ExecuteJsonFunction(
                @na_dialog,
                'Na__ComponentEditorTools__SetActiveTab',
                {
                    active_tab: @na_active_tab_id
                }
            )
        end

        def self.Na__ComponentEditorTools__DialogOptions
            {
                dialog_title: Na__ComponentEditorTools::NA_DIALOG_TITLE,
                preferences_key: Na__ComponentEditorTools::NA_DIALOG_PREFERENCES_KEY,
                scrollable: true,
                resizable: true,
                width: 980,
                height: 820,
                min_width: 760,
                min_height: 560,
                style: UI::HtmlDialog::STYLE_DIALOG
            }
        end

        def self.Na__ComponentEditorTools__FallbackHtml
            <<~HTML
            <!doctype html>
            <html lang="en">
            <head>
                <meta charset="utf-8">
                <title>Na Component Editor Tools</title>
            </head>
            <body>
                <h2>Na Component Editor Tools</h2>
                <p>UI layout file was not found.</p>
            </body>
            </html>
            HTML
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
