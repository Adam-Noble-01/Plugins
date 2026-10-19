# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - USER INTERFACE SCENE SYNC ACTIONS
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__UserInterface__SceneSyncActions__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Dialog actions for the Scene Sync tab, its status payload, and
#              the Scene Sync step of every export into the project.
# CREATED    : 19-Oct-2026
#
# DESCRIPTION:
# - Every action answers false when it is not one of ours, so the main
#   handler can report an unknown action, exactly like the other tabs'.
# - Writing the scenes is quick (nothing renders), so Sync Scenes runs at once
#   and only its "and push to Cloudflare R2" form needs a CloudJob.
# - Na__SceneSync__AfterModelExport is called by Export To Project straight
#   after the GLBs are written, BEFORE any point cloud job or R2 push: the
#   build that a push runs must find the scene file already on disk. Only one
#   CloudJob can run at a time, so Scene Sync never starts one of its own here.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Oct-2026 - Version 2.12.0
# - Initial Scene Sync tab actions.
#
# =============================================================================

require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # =============================================================================
    # REGION | Scene Sync Action Routing
    # =============================================================================

        # FUNCTION | Route A Scene Sync Tab Action, Or Report It Is Not Ours
        # ---------------------------------------------------------------
        def self.Na__UserInterface__HandleSceneSyncAction(dialog, action_id, params)
            return false unless action_id.to_s.start_with?('scenesync_')
            model = Sketchup.active_model
            case action_id
            when 'scenesync_refresh'
                nil
            when 'scenesync_set_on'
                pids = params['pids'].is_a?(Array) ? params['pids'] : [params['pid']]
                result = self.Na__SceneSync__SetOn(model, pids.compact, params['on'] == true)
                self.Na__UserInterface__PushStatus(dialog, result[:message], 'error') unless result[:success]
            when 'scenesync_set_type'
                result = self.Na__SceneSync__SetType(model, params['pid'], params['type'].to_s.empty? ? nil : params['type'].to_s)
                self.Na__UserInterface__PushStatus(dialog, result[:message], 'error') unless result[:success]
            when 'scenesync_detach'
                result = self.Na__SceneSync__Detach(model, params['pid'])
                self.Na__UserInterface__PushStatus(dialog, result[:success] ?
                    'Detached. The next sync hands TrueVision this scene as it was last synced, for good. Switching the SketchUp scene on again starts a new synced scene.' :
                    result[:message], result[:success] ? 'info' : 'error')
            when 'scenesync_open_folder'
                store = self.Na__SceneSync__StorePath(self.Na__ProjectLink__Read(model))
                if store && Dir.exist?(store)
                    UI.openURL("file:///#{store.tr('\\', '/')}")
                else
                    self.Na__UserInterface__PushStatus(dialog, 'The Scene Sync folder does not exist yet. It is made by the first sync.', 'info')
                end
            when 'scenesync_sync'
                result = self.Na__SceneSync__Write(model, self.Na__ProjectLink__Read(model))
                self.Na__SceneSync__EndWithReport(dialog, self.na_ss_report(result))
                return true
            when 'scenesync_sync_push'
                self.Na__SceneSync__StartSyncAndPush(dialog)                     # <-- sent through Na__Tvgb__RunExportAction: the job reports when it ends
                return true
            else
                return false
            end
            self.Na__UserInterface__PushSceneSyncStatus(dialog)
            true
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Sync (the tab's own buttons, and the main export)
    # =============================================================================

        # HELPER FUNCTION | A Scene Sync Result As A Dialog Report
        # ---------------------------------------------------------------
        def self.na_ss_report(result)
            steps = Array(result[:steps]).dup
            steps.unshift({ label: 'Scene Sync', success: result[:success], message: result[:message].to_s }) unless result[:skipped]
            { success: result[:success], running: false, message: result[:message].to_s, steps: steps }
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Sync The Scenes, Then Rebuild And Push The Project
        # ---------------------------------------------------------------
        def self.Na__SceneSync__StartSyncAndPush(dialog)
            model = Sketchup.active_model
            link  = self.Na__ProjectLink__Read(model).dup
            unless link[:linked]
                self.Na__SceneSync__EndWithReport(dialog, { success: false, running: false, message: 'Link this model to a project first.',
                                                            steps: [{ label: 'Project', success: false, message: 'Not linked.' }] })
                return
            end
            written = self.Na__SceneSync__Write(model, link)
            report  = self.na_ss_report(written)
            unless written[:success]
                report[:steps] << { label: 'Cloudflare R2', status: 'skip', message: 'Skipped: the scenes could not be written.' }
                self.Na__SceneSync__EndWithReport(dialog, report)
                return
            end
            self.Na__UserInterface__PushReport(dialog, report.merge(running: true))
            self.Na__ProjectActions__CloudJob(dialog,
                proc do
                    self.Na__UserInterface__PushStatus(dialog, 'Scenes written. Building project data and pushing to Cloudflare R2...', 'info')
                    push = self.Na__CloudSync__PushProject(link, dry_run: false)
                    report[:steps].concat(Array(push[:steps]))
                    report[:success] = push[:success]
                    report[:message] = push[:success] ? "#{report[:message]} Synced to Cloudflare R2." : push[:message]
                    report
                end,
                proc { |final| self.Na__SceneSync__EndWithReport(dialog, final) })
        end
        # ---------------------------------------------------------------

        # FUNCTION | Scene Sync As One Step Of Export To Project / Export And Sync
        # ---------------------------------------------------------------
        # Called straight after the GLBs are written. Adds its steps to the
        # export's report and answers nothing else: the export carries on to
        # its point clouds and its push exactly as before. A model with no scene
        # ever switched on adds nothing at all.
        # ---------------------------------------------------------------
        def self.Na__SceneSync__AfterModelExport(link, report)
            result = self.Na__SceneSync__Write(Sketchup.active_model, link)
            return report if result[:skipped]
            report[:steps] << { label: 'Scene Sync', success: result[:success], message: result[:message].to_s }
            report[:steps].concat(Array(result[:steps]).reject { |step| step[:success] })   # <-- only the scenes that could not be read
            report
        rescue => e
            Na__Log__Warn "[SceneSync] The Scene Sync step failed: #{e.message}"
            report[:steps] << { label: 'Scene Sync', success: false, message: "#{e.class}: #{e.message}" }
            report
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Finish: Report (Clears The Lock), Status, Tab State
        # ---------------------------------------------------------------
        def self.Na__SceneSync__EndWithReport(dialog, report)
            final = (report || {}).merge(running: false)
            final[:steps] ||= []
            self.Na__UserInterface__PushReport(dialog, final)
            self.Na__UserInterface__PushStatus(dialog, final[:message].to_s, final[:success] ? 'success' : 'error')
            self.Na__UserInterface__PushSceneSyncStatus(dialog)
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Scene Sync Status Push
    # =============================================================================

        # FUNCTION | Push The Scene Sync Tab Status To The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushSceneSyncStatus(dialog)
            return unless dialog
            status_json = self.Na__SceneSync__BuildStatus(Sketchup.active_model).to_json
            dialog.execute_script(
                "window.Na__Tvgb__ReceiveSceneSyncStatus && window.Na__Tvgb__ReceiveSceneSyncStatus(#{status_json});"
            )
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push Scene Sync status to dialog: #{e.message}"
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
