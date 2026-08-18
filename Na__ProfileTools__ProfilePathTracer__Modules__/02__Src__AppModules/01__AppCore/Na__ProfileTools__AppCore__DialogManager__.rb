# =============================================================================
# NA PROFILE TOOLS - APP CORE - DIALOG MANAGER
# =============================================================================
#
# FILE       : Na__ProfileTools__AppCore__DialogManager__.rb
# NAMESPACE  : Na__ProfileTools__ProfilePathTracer::Na__DialogManager
# PURPOSE    : HtmlDialog lifecycle and JS <-> Ruby callbacks
#
# =============================================================================

require 'json'

module Na__ProfileTools__ProfilePathTracer
    module Na__DialogManager

    # -------------------------------------------------------------------------
    # REGION | Dialog State
    # -------------------------------------------------------------------------

        @na_dialog = nil
        @na_pending_save_meta = nil
        @na_pending_create_validation = false
        @na_pending_export_origin_point = nil
        @na_pending_replace_geometry_params = nil

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Options
    # -------------------------------------------------------------------------

        NA_DIALOG_TITLE           = 'Na Profile Path Tracer'.freeze
        NA_DIALOG_PREFERENCES_KEY = 'Na__ProfileTools__ProfilePathTracer'.freeze

        NA_DIALOG_WIDTH           = 980
        NA_DIALOG_HEIGHT          = 740

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Show
            return @na_dialog.bring_to_front if @na_dialog && @na_dialog.visible?

            Na__EdgeColourManager.Na__EdgeColours__ForceRefreshFromUrl if defined?(Na__EdgeColourManager)

            @na_dialog = UI::HtmlDialog.new(self.Na__Dialog__Options)

            self.Na__Dialog__BindCallbacks(@na_dialog)
            @na_dialog.set_file(Na__ProfileTools__ProfilePathTracer::NA_HTML_FILE)
            @na_dialog.show
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dialog Options Builder
    # -------------------------------------------------------------------------

        def self.Na__Dialog__Options
            {
                dialog_title:     NA_DIALOG_TITLE,
                preferences_key:  NA_DIALOG_PREFERENCES_KEY,
                scrollable:       true,
                resizable:        true,
                width:            NA_DIALOG_WIDTH,
                height:           NA_DIALOG_HEIGHT,
                style:            UI::HtmlDialog::STYLE_DIALOG
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Callback Binding (JS -> Ruby)
    # -------------------------------------------------------------------------

        def self.Na__Dialog__BindCallbacks(dialog)
            dialog.add_action_callback('na_profilepathtracer_request_bootstrap') do |_context|
                payload = self.Na__Dialog__BuildBootstrapPayload
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveBootstrap', payload)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Bootstrap callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveBootstrap',
                    {
                        'profileKey' => '',
                        'profileSourceMode' => 'library',
                        'pathMode' => 'interactive',
                        'rotationStep' => 0,
                        'isPreviewEnabled' => true,
                        'toggleDefinitions' => {},
                        'toggleStates' => {},
                        'profileOptions' => [],
                        'profilesByKey' => {},
                        'sceneProfileStatus' => Na__SceneProfileRegistry.Na__SceneProfileRegistry__StatusPayload,
                        'edgeMaterialsStatus' => 'failed',
                        'isBootstrapError' => true,
                        'statusMessage' => "Bootstrap failed: #{error.message}"
                    }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_run_headless') do |_context, json_payload|
                config = JSON.parse(json_payload.to_s)
                result = Na__HeadlessRunner.Na__Headless__Run(config)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveHeadlessResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Headless callback failed.', error)
            end

            dialog.add_action_callback('na_profilepathtracer_reload_plugin') do |_context|
                dialog_reference = dialog
                reload_result = Na__PluginReloader.Na__Reload__PluginFiles(Na__ProfileTools__ProfilePathTracer::NA_PLUGIN_ROOT)
                self.Na__Dialog__HandleReloadCompletion(dialog_reference, reload_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Plugin reload callback failed.', error)
                self.Na__Dialog__HandleReloadCompletion(
                    dialog,
                    {
                        'isSuccess' => false,
                        'statusMessage' => "Reload failed: #{error.message}",
                        'issues' => [error.message]
                    }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_refresh_edge_materials') do |_context|
                result = self.Na__Dialog__HandleRefreshEdgeMaterials
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Refresh edge materials callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus',
                    { 'isSuccess' => false, 'statusMessage' => "Refresh failed: #{error.message}", 'loadStatus' => 'failed' }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_purge_edge_materials_cache') do |_context|
                result = self.Na__Dialog__HandlePurgeEdgeMaterialsCache
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Purge edge materials cache callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveEdgeMaterialsStatus',
                    { 'isSuccess' => false, 'statusMessage' => "Purge failed: #{error.message}", 'loadStatus' => 'failed' }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_generate') do |_context, json_payload|
                generate_config = JSON.parse(json_payload.to_s)
                generate_result = self.Na__Dialog__HandleGenerateRequest(generate_config)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveGenerateResult', generate_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Generate callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveGenerateResult',
                    { 'isStarted' => false, 'statusMessage' => "Generate failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_pick_scene_profile') do |_context|
                model = Sketchup.active_model
                unless model
                    self.Na__Dialog__SetStatusFromRuby('No active model for scene profile picking.')
                    next
                end
                model.select_tool(Na__SceneProfilePicker.new(self))
                self.Na__Dialog__SetStatusFromRuby('Pick a Group/Component with one planar face to use as scene profile.')
            rescue => error
                Na__DebugTools.Na__Debug__Error('Pick scene profile callback failed.', error)
                self.Na__Dialog__SetStatusFromRuby("Scene profile pick failed: #{error.message}")
            end

            dialog.add_action_callback('na_profilepathtracer_clear_scene_profile') do |_context|
                Na__SceneProfileRegistry.Na__SceneProfileRegistry__Clear
                self.Na__Dialog__PushSceneProfileStatus('Scene profile source cleared.')
            rescue => error
                Na__DebugTools.Na__Debug__Error('Clear scene profile callback failed.', error)
                self.Na__Dialog__SetStatusFromRuby("Scene profile clear failed: #{error.message}")
            end

            dialog.add_action_callback('na_profilepathtracer_request_scene_profile_status') do |_context|
                self.Na__Dialog__PushSceneProfileStatus
            rescue => error
                Na__DebugTools.Na__Debug__Error('Scene profile status callback failed.', error)
            end

            dialog.add_action_callback('na_profilepathtracer_validate_for_export') do |_context|
                create_result = self.Na__Dialog__HandleCreateProfileRequest
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveExportValidation', create_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Export validation callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveExportValidation',
                    { 'isValid' => false, 'reason' => "Validation failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_save_profile') do |_context, json_payload|
                meta_fields = JSON.parse(json_payload.to_s)
                save_result = self.Na__Dialog__HandleSaveProfileRequest(meta_fields)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveSaveProfileResult', save_result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Save profile callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveSaveProfileResult',
                    { 'isSaved' => false, 'reason' => "Save failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_dynregen_stats') do |_context|
                stats = self.Na__Dialog__HandleDynRegenStats
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveDynRegenStats', stats)
            rescue => error
                Na__DebugTools.Na__Debug__Error('DynRegen stats callback failed.', error)
            end

            dialog.add_action_callback('na_profilepathtracer_dynregen_enable_all') do |_context|
                result = self.Na__Dialog__HandleDynRegenEnableAll
                self.Na__Dialog__SetStatusFromRuby(result['statusMessage'])
                stats = self.Na__Dialog__HandleDynRegenStats
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveDynRegenStats', stats)
            rescue => error
                Na__DebugTools.Na__Debug__Error('DynRegen enable-all callback failed.', error)
                self.Na__Dialog__SetStatusFromRuby("Enable all failed: #{error.message}")
            end

            dialog.add_action_callback('na_profilepathtracer_dynregen_disable_all') do |_context|
                result = self.Na__Dialog__HandleDynRegenDisableAll
                self.Na__Dialog__SetStatusFromRuby(result['statusMessage'])
                stats = self.Na__Dialog__HandleDynRegenStats
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveDynRegenStats', stats)
            rescue => error
                Na__DebugTools.Na__Debug__Error('DynRegen disable-all callback failed.', error)
                self.Na__Dialog__SetStatusFromRuby("Disable all failed: #{error.message}")
            end

            dialog.add_action_callback('na_profilepathtracer_dynregen_detach_all') do |_context|
                Na__ObserverRegistry.Na__ObserverRegistry__DetachAll if defined?(Na__ObserverRegistry)
                self.Na__Dialog__SetStatusFromRuby('All Dynamic Regeneration observers detached.')
                stats = self.Na__Dialog__HandleDynRegenStats
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveDynRegenStats', stats)
            rescue => error
                Na__DebugTools.Na__Debug__Error('DynRegen detach-all callback failed.', error)
                self.Na__Dialog__SetStatusFromRuby("Detach all failed: #{error.message}")
            end

            dialog.add_action_callback('na_profilepathtracer_update_profile_meta') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                result = Na__EditProfile__MetaWriter.Na__MetaWriter__SaveMeta(params)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Update profile meta callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveUpdateProfileMetaResult',
                    { 'isSaved' => false, 'reason' => "Save failed: #{error.message}",
                      'statusMessage' => "Save failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_replace_profile_geometry') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                result = self.Na__Dialog__HandleReplaceGeometryRequest(params)
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveReplaceGeometryResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Replace profile geometry callback failed.', error)
                self.Na__Dialog__ClearPendingReplaceGeometry
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveReplaceGeometryResult',
                    { 'isReplaced' => false, 'isPending' => false,
                      'reason' => "Geometry re-capture failed: #{error.message}",
                      'statusMessage' => "Geometry re-capture failed: #{error.message}" }
                )
            end

            dialog.add_action_callback('na_profilepathtracer_delete_profile') do |_context, json_payload|
                params = JSON.parse(json_payload.to_s)
                result = Na__EditProfile__ProfileDeleter.Na__ProfileDeleter__Delete(params)

                # Bootstrap first: the gallery and every key lookup must be
                # rebuilt from what is now on disk before the dialog is told the
                # delete landed, or the JS still holds the removed profile.
                if result['isDeleted']
                    self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveBootstrap', self.Na__Dialog__BuildBootstrapPayload)
                end

                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveDeleteProfileResult', result)
            rescue => error
                Na__DebugTools.Na__Debug__Error('Delete profile callback failed.', error)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveDeleteProfileResult',
                    { 'isDeleted' => false, 'reason' => "Delete failed: #{error.message}",
                      'statusMessage' => "Delete failed: #{error.message}" }
                )
            end
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Edge Materials Handlers
    # -------------------------------------------------------------------------

        def self.Na__Dialog__HandleRefreshEdgeMaterials
            return { 'isSuccess' => false, 'statusMessage' => 'Edge colour manager not loaded.', 'loadStatus' => 'failed' } unless defined?(Na__EdgeColourManager)

            Na__EdgeColourManager.Na__EdgeColours__ForceRefreshFromUrl
            status = Na__EdgeColourManager.Na__EdgeColours__LoadStatus
            {
                'isSuccess' => status == :url,
                'statusMessage' => status == :url ? 'Edge materials refreshed from URL.' : "Edge materials status: #{status}",
                'loadStatus' => status.to_s
            }
        end

        def self.Na__Dialog__HandlePurgeEdgeMaterialsCache
            return { 'isSuccess' => false, 'statusMessage' => 'Edge colour manager not loaded.', 'loadStatus' => 'failed' } unless defined?(Na__EdgeColourManager)

            purge_result = Na__EdgeColourManager.Na__EdgeColours__PurgeCache
            status = Na__EdgeColourManager.Na__EdgeColours__LoadStatus
            {
                'isSuccess' => purge_result == true,
                'statusMessage' => purge_result ? 'Edge materials cache purged. Fresh copy downloaded.' : 'Cache purge failed or fresh download unavailable.',
                'loadStatus' => status.to_s
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Dynamic Regeneration Handlers
    # -------------------------------------------------------------------------

        def self.Na__Dialog__HandleDynRegenStats
            return { 'total' => 0, 'enabled' => 0, 'active' => 0 } unless defined?(Na__DataSerializer) && defined?(Na__ObserverRegistry)

            model = Sketchup.active_model
            return { 'total' => 0, 'enabled' => 0, 'active' => 0 } unless model

            parents = Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)
            total   = parents.length
            enabled = parents.count { |g| Na__DataSerializer.Na__DataSerializer__DynamicRegenEnabled?(g) }
            active  = Na__ObserverRegistry.Na__ObserverRegistry__Count

            { 'total' => total, 'enabled' => enabled, 'active' => active }
        rescue => error
            Na__DebugTools.Na__Debug__Warn("Na__Dialog__HandleDynRegenStats failed: #{error.message}")
            { 'total' => 0, 'enabled' => 0, 'active' => 0 }
        end

        def self.Na__Dialog__HandleDynRegenEnableAll
            return { 'statusMessage' => 'DataSerializer not loaded.' } unless defined?(Na__DataSerializer) && defined?(Na__ObserverRegistry)

            model = Sketchup.active_model
            return { 'statusMessage' => 'No active model.' } unless model

            parents = Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)
            count = 0

            model.start_operation('Na__ProfilePathTracer__DynRegenEnableAll', true)
            parents.each do |parent_group|
                Na__DataSerializer.Na__DataSerializer__SetDynamicRegen(parent_group, true)
                helpers_group = Na__DataSerializer.Na__DataSerializer__FindHelpersSubGroup(parent_group)
                next unless helpers_group
                Na__ObserverRegistry.Na__ObserverRegistry__AttachToHelpers(helpers_group)
                Na__ContextMenuHandlers.Na__ContextMenu__UpdateGroupNameSuffix(parent_group, true) \
                    if defined?(Na__ContextMenuHandlers)
                count += 1
            end
            model.commit_operation

            { 'statusMessage' => "Dynamic Regeneration enabled on #{count} profile trace(s)." }
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("Na__Dialog__HandleDynRegenEnableAll failed: #{error.message}")
            { 'statusMessage' => "Enable all failed: #{error.message}" }
        end

        def self.Na__Dialog__HandleDynRegenDisableAll
            return { 'statusMessage' => 'DataSerializer not loaded.' } unless defined?(Na__DataSerializer) && defined?(Na__ObserverRegistry)

            model = Sketchup.active_model
            return { 'statusMessage' => 'No active model.' } unless model

            Na__ObserverRegistry.Na__ObserverRegistry__DetachAll

            parents = Na__DataSerializer.Na__DataSerializer__FindAllParentGroups(model)
            count = 0

            model.start_operation('Na__ProfilePathTracer__DynRegenDisableAll', true)
            parents.each do |parent_group|
                Na__DataSerializer.Na__DataSerializer__SetDynamicRegen(parent_group, false)
                Na__ContextMenuHandlers.Na__ContextMenu__UpdateGroupNameSuffix(parent_group, false) \
                    if defined?(Na__ContextMenuHandlers)
                count += 1
            end
            model.commit_operation

            { 'statusMessage' => "Dynamic Regeneration disabled on #{count} profile trace(s)." }
        rescue => error
            model.abort_operation rescue nil
            Na__DebugTools.Na__Debug__Warn("Na__Dialog__HandleDynRegenDisableAll failed: #{error.message}")
            { 'statusMessage' => "Disable all failed: #{error.message}" }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Payload Builders / Request Handlers
    # -------------------------------------------------------------------------

        def self.Na__Dialog__BuildBootstrapPayload
            default_run_config = Na__ProfileTools__ProfilePathTracer.Na__State__DefaultRunConfig
            default_profile_key = Na__ProfileLibrary.Na__ProfileLibrary__DefaultProfileKey
            scene_profile_status = Na__SceneProfileRegistry.Na__SceneProfileRegistry__StatusPayload

            edge_materials_status = if defined?(Na__EdgeColourManager)
                Na__EdgeColourManager.Na__EdgeColours__LoadStatus.to_s
            else
                'pending'
            end

            default_run_config.merge(
                'profileKey'      => default_run_config['profileKey'] || default_profile_key,
                'toggleDefinitions' => Na__ProfileTools__ProfilePathTracer.Na__Config__ToggleDefinitions,
                'profileOptions'  => Na__ProfileLibrary.Na__ProfileLibrary__UiProfileOptions,
                'profilesByKey'   => Na__ProfileLibrary.Na__ProfileLibrary__ProfilesByKey,
                'sceneProfileStatus' => scene_profile_status,
                'edgeMaterialsStatus' => edge_materials_status
            )
        end

        def self.Na__Dialog__HandleCreateProfileRequest
            validation = Na__ProfileExporter.Na__Exporter__ValidateSelection
            unless validation['isValid']
                return validation.merge(
                    'isPendingOrigin' => false,
                    'statusMessage' => "Create blocked: #{validation['reason']}"
                )
            end

            model = Sketchup.active_model
            unless model
                return {
                    'isValid' => false,
                    'isPendingOrigin' => false,
                    'reason' => 'No active model.',
                    'statusMessage' => 'Create blocked: no active model.'
                }
            end

            @na_pending_create_validation = true
            @na_pending_export_origin_point = nil
            model.select_tool(Na__Dialog__OriginPointPickerTool.new(self, :create_profile))

            validation.merge(
                'isPendingOrigin' => true,
                'statusMessage' => 'Click in model to place 00__OriginPoint first for create-profile preview.'
            )
        end

        def self.Na__Dialog__HandleSaveProfileRequest(meta_fields)
            origin_point = @na_pending_export_origin_point
            validation = Na__ProfileExporter.Na__Exporter__ValidateSelection(origin_point)
            unless validation['isValid']
                return {
                    'isSaved' => false,
                    'isPending' => false,
                    'reason' => validation['reason'],
                    'statusMessage' => "Save blocked: #{validation['reason']}"
                }
            end

            model = Sketchup.active_model
            unless model
                return {
                    'isSaved' => false,
                    'isPending' => false,
                    'reason' => 'No active model.',
                    'statusMessage' => 'Save blocked: no active model.'
                }
            end

            resolved_meta_fields = meta_fields.is_a?(Hash) ? meta_fields : {}
            if origin_point
                @na_pending_export_origin_point = nil
                @na_pending_create_validation = false
                save_result = Na__ProfileExporter.Na__Exporter__RunExport(resolved_meta_fields, origin_point)

                if save_result['isSaved']
                    updated_bootstrap = self.Na__Dialog__BuildBootstrapPayload
                    self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveBootstrap', updated_bootstrap)
                end

                return self.Na__Dialog__BuildSaveResultPayload(save_result)
            end

            @na_pending_save_meta = resolved_meta_fields
            model.select_tool(Na__Dialog__OriginPointPickerTool.new(self, :save_profile))

            {
                'isSaved' => false,
                'isPending' => true,
                'reason' => nil,
                'statusMessage' => 'Click in model to place 00__OriginPoint and continue export.'
            }
        end

        def self.Na__Dialog__FinalizePendingCreateProfileOrigin(origin_point)
            unless @na_pending_create_validation == true
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveExportValidation',
                    {
                        'isValid' => false,
                        'isPendingOrigin' => false,
                        'reason' => 'No pending create-profile request was found.',
                        'statusMessage' => 'Create profile cancelled: no pending request.'
                    }
                )
                return
            end

            @na_pending_create_validation = false
            @na_pending_export_origin_point = origin_point
            validation = Na__ProfileExporter.Na__Exporter__ValidateSelection(origin_point)

            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveExportValidation',
                validation.merge(
                    'isPendingOrigin' => false,
                    'originPointPicked' => true,
                    'statusMessage' => validation['isValid'] ? 'Origin point set. Fill in profile details and save.' : "Create blocked: #{validation['reason']}"
                )
            )
        rescue => error
            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveExportValidation',
                {
                    'isValid' => false,
                    'isPendingOrigin' => false,
                    'reason' => error.message,
                    'statusMessage' => "Create profile failed: #{error.message}"
                }
            )
        end

        def self.Na__Dialog__CancelPendingCreateProfileOrigin
            @na_pending_create_validation = false
            @na_pending_export_origin_point = nil
            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveExportValidation',
                {
                    'isValid' => false,
                    'isPendingOrigin' => false,
                    'reason' => 'Origin point selection cancelled.',
                    'statusMessage' => 'Create profile cancelled: origin point selection was cancelled.'
                }
            )
        end

        def self.Na__Dialog__FinalizePendingSave(origin_point)
            pending_meta = @na_pending_save_meta
            @na_pending_save_meta = nil

            unless pending_meta.is_a?(Hash)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveSaveProfileResult',
                    {
                        'isSaved' => false,
                        'isPending' => false,
                        'reason' => 'No pending save request was found.',
                        'statusMessage' => 'Save cancelled: no pending request.'
                    }
                )
                return
            end

            save_result = Na__ProfileExporter.Na__Exporter__RunExport(pending_meta, origin_point)

            if save_result['isSaved']
                updated_bootstrap = self.Na__Dialog__BuildBootstrapPayload
                self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveBootstrap', updated_bootstrap)
            end

            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveSaveProfileResult',
                self.Na__Dialog__BuildSaveResultPayload(save_result)
            )
        rescue => error
            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveSaveProfileResult',
                {
                    'isSaved' => false,
                    'isPending' => false,
                    'reason' => error.message,
                    'statusMessage' => "Save failed: #{error.message}"
                }
            )
        end

        def self.Na__Dialog__BuildSaveResultPayload(save_result)
            helper_created = save_result['originHelperCreated'] == true
            helper_reason = save_result['originHelperReason'].to_s
            helper_status_message = if helper_created
                'Origin helper inserted at picked point.'
            elsif !helper_reason.empty?
                "Origin helper note: #{helper_reason}"
            else
                ''
            end

            {
                'isSaved' => save_result['isSaved'] == true,
                'isPending' => false,
                'reason' => save_result['reason'],
                'filePath' => save_result['filePath'],
                'originHelperCreated' => helper_created,
                'originHelperReason' => save_result['originHelperReason'],
                'statusMessage' => save_result['isSaved'] ?
                    "Profile saved: #{save_result['filePath']} #{helper_status_message}".strip :
                    "Save failed: #{save_result['reason']} #{helper_status_message}".strip
            }
        end

        def self.Na__Dialog__CancelPendingSave
            @na_pending_save_meta = nil
            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveSaveProfileResult',
                {
                    'isSaved' => false,
                    'isPending' => false,
                    'reason' => 'Origin point selection cancelled.',
                    'statusMessage' => 'Save cancelled: origin point selection was cancelled.'
                }
            )
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Replace Geometry Handlers (Edit Profile tab)
    # -------------------------------------------------------------------------

        # Everything that can refuse the re-capture is checked BEFORE the picker
        # tool is armed, so a blocked request never leaves the user stranded in a
        # model tool waiting for a click that cannot lead anywhere.
        def self.Na__Dialog__HandleReplaceGeometryRequest(params)
            params = {} unless params.is_a?(Hash)

            profile_key = params['profileKey'].to_s.strip
            if profile_key.empty?
                return self.Na__Dialog__BuildReplaceBlockedPayload('No profile is loaded in the Edit tab.')
            end

            path_check = Na__EditProfile__LibraryPaths.Na__LibraryPaths__ValidateProfileFile(params['sourceFile'])
            unless path_check['isValid']
                return self.Na__Dialog__BuildReplaceBlockedPayload(path_check['reason'], profile_key)
            end

            validation = Na__ProfileExporter.Na__Exporter__ValidateSelection
            unless validation['isValid']
                return self.Na__Dialog__BuildReplaceBlockedPayload(validation['reason'], profile_key)
            end

            model = Sketchup.active_model
            unless model
                return self.Na__Dialog__BuildReplaceBlockedPayload('No active model.', profile_key)
            end

            @na_pending_replace_geometry_params = params
            model.select_tool(Na__Dialog__OriginPointPickerTool.new(self, :replace_geometry))

            {
                'isReplaced'    => false,
                'isPending'     => true,
                'profileKey'    => profile_key,
                'reason'        => nil,
                'statusMessage' => 'Click in model to set the new origin point for this profile. ESC cancels.'
            }
        end

        def self.Na__Dialog__FinalizePendingReplaceGeometry(origin_point)
            pending_params = @na_pending_replace_geometry_params
            @na_pending_replace_geometry_params = nil

            unless pending_params.is_a?(Hash)
                self.Na__Dialog__SendToJs(
                    'Na__ProfilePathTracer__ReceiveReplaceGeometryResult',
                    self.Na__Dialog__BuildReplaceBlockedPayload('No pending geometry re-capture request was found.')
                )
                return
            end

            result = Na__EditProfile__GeometryReplacer.Na__GeometryReplacer__Replace(pending_params, origin_point)
            self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveReplaceGeometryResult', result)
        rescue => error
            Na__DebugTools.Na__Debug__Error('Finalize replace geometry failed.', error)
            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveReplaceGeometryResult',
                self.Na__Dialog__BuildReplaceBlockedPayload("Geometry re-capture failed: #{error.message}")
            )
        end

        def self.Na__Dialog__ClearPendingReplaceGeometry
            @na_pending_replace_geometry_params = nil
        end

        def self.Na__Dialog__CancelPendingReplaceGeometry
            @na_pending_replace_geometry_params = nil
            self.Na__Dialog__SendToJs(
                'Na__ProfilePathTracer__ReceiveReplaceGeometryResult',
                {
                    'isReplaced'    => false,
                    'isPending'     => false,
                    'isCancelled'   => true,
                    'reason'        => 'Origin point selection cancelled.',
                    'statusMessage' => 'Geometry re-capture cancelled — the profile file was not changed.'
                }
            )
        end

        def self.Na__Dialog__BuildReplaceBlockedPayload(reason, profile_key = '')
            {
                'isReplaced'    => false,
                'isPending'     => false,
                'profileKey'    => profile_key,
                'reason'        => reason,
                'statusMessage' => "Geometry re-capture blocked: #{reason}"
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Generate Handler
    # -------------------------------------------------------------------------

        def self.Na__Dialog__HandleGenerateRequest(generate_config)
            profile_resolution = Na__ProfilePlacementEngine.Na__Engine__ResolveProfileData(generate_config)
            unless profile_resolution['isValid']
                return {
                    'isStarted' => false,
                    'statusMessage' => "Generate blocked: #{profile_resolution['reason']}"
                }
            end

            path_mode = generate_config['pathMode'].to_s
            path_mode = 'selection' if path_mode.empty?

            profile_key = profile_resolution['profileKey']
            profile_data = profile_resolution['profileData']
            toggle_states = self.Na__Dialog__NormalizedToggleStates(generate_config)
            rotation_step = generate_config['rotationStep'].to_i % 4
            reverse_direction = generate_config['reverseDirection'] == true
            origin_offset = self.Na__Dialog__NormalizedOriginOffset(generate_config)

            if path_mode == 'selection'
                validation = Na__PathAnalysis.Na__Path__BuildSegments(Sketchup.active_model.selection.to_a)
                unless validation[:isValid]
                    return {
                        'isStarted' => false,
                        'statusMessage' => "Generate blocked: #{validation[:reason]}"
                    }
                end

                path_data = {
                    ordered_points: validation[:orderedPoints],
                    ordered_edges: validation[:orderedEdges],
                    is_closed_loop: validation[:isClosedLoop]
                }

                generation_result = Na__ProfilePlacementEngine.Na__Engine__GenerateFromPathData(
                    profile_key: profile_key,
                    profile_data: profile_data,
                    path_data: path_data,
                    start_point: path_data[:ordered_points].first,
                    rotation_step: rotation_step,
                    toggle_states: toggle_states,
                    reverse_direction: reverse_direction,
                    origin_offset: origin_offset
                )

                return {
                    'isStarted' => generation_result['isBuilt'] == true,
                    'statusMessage' => generation_result['statusMessage']
                }
            end

            model = Sketchup.active_model
            interactive_tool = Na__PathSelectionTool.new(
                profile_key, profile_data, toggle_states, rotation_step, reverse_direction, origin_offset
            )
            model.select_tool(interactive_tool)

            {
                'isStarted' => true,
                'statusMessage' => "Interactive drawing active. Rotation #{rotation_step * 90} deg. Click to set start, then draw waypoints. Enter/right-click/double-click to finish."
            }
        end

        def self.Na__Dialog__HandleReloadCompletion(previous_dialog, reload_result)
            status_payload = self.Na__Dialog__BuildReloadStatusPayload(reload_result)
            runtime_status = Na__ProfileTools__ProfilePathTracer.Na__Runtime__EnsureUnifiedGeometryBuilders
            if runtime_status['isUnified'] != true
                status_payload['isSuccess'] = false
                status_payload['statusMessage'] = "#{status_payload['statusMessage']} Runtime sync issue: #{runtime_status['statusMessage']}"
            end

            begin
                previous_dialog.close if previous_dialog && previous_dialog.visible?
            rescue => error
                Na__DebugTools.Na__Debug__Warn("Reload close warning: #{error.message}")
            end

            self.Na__Dialog__Show
            self.Na__Dialog__SendReloadStatus(status_payload)
        end

        def self.Na__Dialog__BuildReloadStatusPayload(reload_result)
            status_message = 'Reload complete.'
            is_success = true
            issues = []

            if reload_result.is_a?(Hash)
                status_message = reload_result['statusMessage'].to_s.strip
                status_message = 'Reload complete.' if status_message.empty?
                is_success = reload_result['isSuccess'] != false
                issues = reload_result['issues'].is_a?(Array) ? reload_result['issues'] : []
            else
                is_success = false
                status_message = 'Reload finished with unknown response.'
            end

            if !is_success && !issues.empty?
                status_message = "#{status_message} First issue: #{issues.first}"
            end

            {
                'statusMessage' => status_message,
                'isSuccess' => is_success
            }
        end

        def self.Na__Dialog__SendReloadStatus(status_payload)
            return unless @na_dialog

            status_message = status_payload['statusMessage'].to_s
            escaped_status = status_message.gsub('\\', '\\\\').gsub("'", "\\\\'")
            @na_dialog.execute_script("window.setTimeout(function(){ if (window.Na__ProfilePathTracer__Ui__SetStatusFromBridge) { window.Na__ProfilePathTracer__Ui__SetStatusFromBridge('#{escaped_status}'); } }, 700);")
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Ruby -> JS Bridge
    # -------------------------------------------------------------------------

        def self.Na__Dialog__SetStatusFromRuby(message)
            return unless @na_dialog
            escaped_status = message.to_s.gsub('\\', '\\\\').gsub("'", "\\\\'")
            @na_dialog.execute_script(
                "if (window.Na__ProfilePathTracer__Ui__SetStatusFromBridge) { window.Na__ProfilePathTracer__Ui__SetStatusFromBridge('#{escaped_status}'); }"
            )
        end

        def self.Na__Dialog__PushSceneProfileStatus(status_message_override = nil)
            status_payload = Na__SceneProfileRegistry.Na__SceneProfileRegistry__StatusPayload
            status_payload = status_payload.merge('statusMessage' => status_message_override.to_s) if status_message_override
            self.Na__Dialog__SendToJs('Na__ProfilePathTracer__ReceiveSceneProfileStatus', status_payload)
            self.Na__Dialog__SetStatusFromRuby(status_payload['statusMessage'])
        end

        def self.Na__Dialog__SendToJs(function_name, payload)
            return unless @na_dialog
            @na_dialog.execute_script("window.#{function_name}(#{payload.to_json});")
        end

        def self.Na__Dialog__NormalizedToggleStates(generate_config)
            incoming_toggle_states = generate_config['toggleStates']
            default_toggle_states = Na__ProfileTools__ProfilePathTracer.Na__Config__ToggleDefaults
            return default_toggle_states unless incoming_toggle_states.is_a?(Hash)

            default_toggle_states.each_with_object({}) do |(toggle_key, default_value), normalized|
                if incoming_toggle_states.key?(toggle_key)
                    normalized[toggle_key] = incoming_toggle_states[toggle_key] == true
                else
                    normalized[toggle_key] = default_value
                end
            end
        end

        # originOffset arrives from the 2D preview vertex picker as
        # { y: <mm>, z: <mm> } in the profile's own PosY_mm / PosZ_mm space.
        # A zero offset means "use the profile's authored origin" — return nil so
        # the geometry builder skips the shift entirely.
        def self.Na__Dialog__NormalizedOriginOffset(generate_config)
            incoming = generate_config['originOffset']
            return nil unless incoming.is_a?(Hash)

            y_mm = incoming['y'].to_f
            z_mm = incoming['z'].to_f
            return nil if y_mm.zero? && z_mm.zero?

            { 'y' => y_mm, 'z' => z_mm }
        rescue
            nil
        end

    # endregion ----------------------------------------------------------------

    end

    class Na__Dialog__OriginPointPickerTool

        NA_STATUS_PROMPT_KEY = SB_PROMPT
        NA_CROSSHAIR_SIZE = 180.mm

        def initialize(dialog_manager_module, picker_mode = :save_profile)
            @na_dialog_manager = dialog_manager_module
            @na_picker_mode = picker_mode
            @na_input_point = Sketchup::InputPoint.new
            @na_cursor_point = nil
        end

        def activate
            prompt_text = case @na_picker_mode
                          when :create_profile
                              'Click to place 00__OriginPoint for create-profile preview + save. ESC cancels.'
                          when :replace_geometry
                              'Click to set the NEW origin point for the profile being edited. ESC cancels — nothing is written until you click.'
                          else
                              'Click to place 00__OriginPoint helper for export UCS. ESC cancels.'
                          end
            Sketchup::set_status_text(prompt_text, NA_STATUS_PROMPT_KEY)
            Sketchup.active_model.active_view.invalidate
        end

        def onMouseMove(_flags, x, y, view)
            @na_input_point.pick(view, x, y)
            return unless @na_input_point.valid?
            @na_cursor_point = @na_input_point.position
            view.invalidate
        end

        def onLButtonDown(_flags, x, y, view)
            @na_input_point.pick(view, x, y)
            return unless @na_input_point.valid?

            selected_point = @na_input_point.position
            case @na_picker_mode
            when :create_profile
                @na_dialog_manager.Na__Dialog__FinalizePendingCreateProfileOrigin(selected_point)
            when :replace_geometry
                @na_dialog_manager.Na__Dialog__FinalizePendingReplaceGeometry(selected_point)
            else
                @na_dialog_manager.Na__Dialog__FinalizePendingSave(selected_point)
            end
            Sketchup.active_model.select_tool(nil)
            view.invalidate
        end

        def onCancel(_reason, view)
            case @na_picker_mode
            when :create_profile
                @na_dialog_manager.Na__Dialog__CancelPendingCreateProfileOrigin
            when :replace_geometry
                @na_dialog_manager.Na__Dialog__CancelPendingReplaceGeometry
            else
                @na_dialog_manager.Na__Dialog__CancelPendingSave
            end
            Sketchup.active_model.select_tool(nil)
            view.invalidate
        end

        def draw(view)
            return unless @na_cursor_point
            @na_input_point.draw(view)
            Na__PreviewGraphics.Na__Preview__DrawCrosshair(view, @na_cursor_point, NA_CROSSHAIR_SIZE)
        end
    end

end

# =============================================================================
# END OF FILE
# =============================================================================
