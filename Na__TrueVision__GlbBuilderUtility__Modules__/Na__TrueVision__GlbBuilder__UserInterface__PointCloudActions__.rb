# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - USER INTERFACE POINT CLOUD ACTIONS
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__UserInterface__PointCloudActions__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Dialog actions for the Point Cloud tab, its status payload, and
#              the point cloud step of Export To Project Folder / Export And
#              Sync To Cloud (run only while Export Point Clouds is on).
# CREATED    : 19-Oct-2026
#
# DESCRIPTION:
# - Every action answers false when it is not one of ours, so the main
#   handler can report an unknown action, exactly like the Project tab's.
# - Every action finishes by pushing the point cloud status, which clears the
#   tab's own busy state; exports also push a report (running: false), which
#   clears the dialog-wide lock the main bridge set.
# - Renders run as a CloudJob: a Fiber resumed by a UI timer. SketchUp keeps
#   drawing between tiles and while Python converts them.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Oct-2026 - Version 2.13.1
# - pointcloud_reorder_scenes: the tab's drag to reorder, saved through the
#   viewer's Na__PublicApi__ReorderScenes (one undoable step in its record).
#
# 19-Oct-2026 - Version 2.12.0
# - Render Point Clouds And Sync To Cloud writes the synced scenes (Scene
#   Sync) before it pushes, as every push does.
#
# 19-Oct-2026 - Version 2.11.0
# - Initial Point Cloud tab actions.
#
# =============================================================================

require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # =============================================================================
    # REGION | Point Cloud Action Routing
    # =============================================================================

        # FUNCTION | Route A Point Cloud Tab Action, Or Report It Is Not Ours
        # ---------------------------------------------------------------
        def self.Na__UserInterface__HandlePointCloudAction(dialog, action_id, params)
            return false unless action_id.to_s.start_with?('pointcloud_')
            model = Sketchup.active_model
            case action_id
            when 'pointcloud_refresh'
                nil
            when 'pointcloud_set_enabled'
                result = self.Na__PointCloud__SetEnabled(model, params['enabled'] == true)
                message = if !result[:success] then result[:message]
                          elsif params['enabled'] == true then 'Point clouds are on: exports into the project now render the scenes switched on below.'
                          else 'Point clouds are off: exports leave them alone. Every setting is kept.'
                          end
                self.Na__UserInterface__PushStatus(dialog, message, result[:success] ? 'success' : 'error')
            when 'pointcloud_set_scene_selected'
                ids = params['sceneIds'].is_a?(Array) ? params['sceneIds'] : [params['sceneId']]
                result = self.Na__PointCloud__SetSceneSelected(model, ids, params['selected'] == true)
                self.Na__UserInterface__PushStatus(dialog, result[:message], 'error') unless result[:success]
            when 'pointcloud_set_scene_export'
                problem = if self.Na__PointCloud__ViewerStatus[:available]
                              ::Na__PointCloudViewer.Na__PublicApi__SetSceneExport(model, params['sceneId'].to_s, params['values'].is_a?(Hash) ? params['values'] : {})
                          else
                              self.Na__PointCloud__ViewerStatus[:message]
                          end
                self.Na__UserInterface__PushStatus(dialog, problem, 'warning') if problem
            when 'pointcloud_reorder_scenes'
                # The order is the viewer's own record (scenes API 3), so its
                # Scenes tab shows the same order and Undo puts it back.
                viewer  = self.Na__PointCloud__ViewerStatus
                problem = if !viewer[:available]
                              viewer[:message]
                          elsif !::Na__PointCloudViewer.respond_to?(:Na__PublicApi__ReorderScenes)
                              'This Na Point Cloud Viewer cannot reorder its scenes from here. Reload it, then try again.'
                          else
                              ::Na__PointCloudViewer.Na__PublicApi__ReorderScenes(model, Array(params['sceneIds']).map(&:to_s))
                          end
                self.Na__UserInterface__PushStatus(dialog, problem, 'warning') if problem
            when 'pointcloud_reload_cloud'
                problem = self.Na__PointCloud__ViewerStatus[:available] ? ::Na__PointCloudViewer.Na__PublicApi__ReloadPointCloud(model) :
                                                                         self.Na__PointCloud__ViewerStatus[:message]
                self.Na__UserInterface__PushStatus(dialog, problem || 'Reloading the point cloud in the Na Point Cloud Viewer. Refresh here when it has finished.',
                                                   problem ? 'warning' : 'info')
            when 'pointcloud_check_python'
                self.Na__PointCloud__CheckPython(dialog)
            when 'pointcloud_open_folder'
                store = self.Na__PointCloud__StorePath(self.Na__ProjectLink__Read(model))
                if store && Dir.exist?(store)
                    UI.openURL("file:///#{store.tr('\\', '/')}")
                else
                    self.Na__UserInterface__PushStatus(dialog, 'The point cloud folder does not exist yet. It is made by the first export.', 'info')
                end
            when 'pointcloud_export', 'pointcloud_export_sync'
                # Sent through the main bridge's Na__Tvgb__RunExportAction, which
                # locks every card until a report with running: false arrives.
                self.Na__PointCloud__StartExport(dialog, sync: action_id == 'pointcloud_export_sync')
                return true                                                    # <-- the job pushes its own report and status when it ends
            else
                return false
            end
            self.Na__UserInterface__PushPointCloudStatus(dialog)
            true
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Export (the Point Cloud tab's own button, and the main routine)
    # =============================================================================

        # ACTION HANDLER | Render The Point Clouds Into The Project, Optionally Sync
        # ---------------------------------------------------------------
        def self.Na__PointCloud__StartExport(dialog, sync: false)
            model = Sketchup.active_model
            link  = self.Na__ProjectLink__Read(model).dup
            unless link[:linked]
                self.Na__PointCloud__EndWithReport(dialog, { success: false, running: false, message: 'Link this model to a project first.',
                                                             steps: [{ label: 'Project', success: false, message: 'Not linked.' }] })
                return
            end
            self.Na__UserInterface__PushReport(dialog, { running: true, steps: [] })
            self.Na__ProjectActions__CloudJob(dialog,
                proc do
                    report = self.Na__PointCloud__ExportJob(model, link, ->(text) { self.Na__UserInterface__PushStatus(dialog, text, 'info') })
                    if sync && report[:success]
                        # Every push carries the synced scenes as they are now (Scene Sync)
                        self.Na__SceneSync__AfterModelExport(link.dup, report) if self.respond_to?(:Na__SceneSync__AfterModelExport)
                        self.Na__UserInterface__PushStatus(dialog, 'Point clouds exported. Building project data and pushing to Cloudflare R2...', 'info')
                        push = self.Na__CloudSync__PushProject(link, dry_run: false)
                        report[:steps].concat(Array(push[:steps]))
                        report[:success] = push[:success]
                        report[:message] = push[:success] ? "#{report[:message]} Synced to Cloudflare R2." : push[:message]
                    elsif sync
                        report[:steps] << { label: 'Cloudflare R2', status: 'skip', message: 'Skipped: the point cloud export did not succeed.' }
                    end
                    report
                end,
                proc { |report| self.Na__PointCloud__EndWithReport(dialog, report) })
        end
        # ---------------------------------------------------------------

        # FUNCTION | Point Clouds As One Step Of Export To Project / Export And Sync
        # ---------------------------------------------------------------
        # Called by Na__ProjectActions__ExportToProject after the GLBs are
        # written. Answers false (and does nothing) while Export Point Clouds is
        # off, so the main routine runs exactly as it always has.
        # ---------------------------------------------------------------
        def self.Na__PointCloud__RunAfterModelExport(dialog, link, report, sync)
            return false unless self.Na__PointCloud__Enabled?(Sketchup.active_model)
            model = Sketchup.active_model
            self.Na__UserInterface__PushReport(dialog, report.merge(running: true))
            self.Na__ProjectActions__CloudJob(dialog,
                proc do
                    pc = self.Na__PointCloud__ExportJob(model, link.dup, ->(text) { self.Na__UserInterface__PushStatus(dialog, text, 'info') })
                    report[:steps].concat(pc[:steps])
                    report[:message] = "#{report[:message]} #{pc[:message]}"
                    report[:success] = report[:success] && pc[:success]
                    if sync && report[:success]
                        self.Na__UserInterface__PushStatus(dialog, 'Exported. Building project data and pushing to Cloudflare R2...', 'info')
                        push = self.Na__CloudSync__PushProject(link.dup, dry_run: false)
                        report[:steps].concat(Array(push[:steps]))
                        report[:success] = push[:success]
                        report[:message] = push[:success] ? "#{report[:message]} Synced to Cloudflare R2." : push[:message]
                    elsif sync
                        report[:steps] << { label: 'Cloudflare R2', status: 'skip', message: 'Skipped: the export did not succeed.' }
                    end
                    report
                end,
                proc do |final|
                    self.Na__PointCloud__EndWithReport(dialog, final)
                    self.Na__UserInterface__PushModelStatus(dialog)
                end)
            true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Finish: Report (Clears The Lock), Status, Tab State
        # ---------------------------------------------------------------
        def self.Na__PointCloud__EndWithReport(dialog, report)
            final = (report || {}).merge(running: false)
            final[:steps] ||= []
            self.Na__UserInterface__PushReport(dialog, final)
            self.Na__UserInterface__PushStatus(dialog, final[:message].to_s, final[:success] ? 'success' : 'error')
            self.Na__UserInterface__PushPointCloudStatus(dialog)
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Check That Python Can Write WebP
        # ---------------------------------------------------------------
        def self.Na__PointCloud__CheckPython(dialog)
            python = self.Na__CloudSync__ResolvePythonExecutable
            out, err, status = Open3.capture3(self.Na__CloudSync__SanitizedPythonEnv, *python[:command], '-c',
                                              'from PIL import Image, features; import sys; sys.stdout.write("Pillow ok, WebP " + str(features.check("webp")))')
            if status.success? && out.include?('WebP True')
                self.Na__UserInterface__PushStatus(dialog, "Python is ready for point clouds (#{python[:command].join(' ')}: #{out.strip}).", 'success')
            else
                why = err.to_s.include?('PIL') ? 'Pillow is missing. Run  pip install pillow  once in a command window.' : (err.to_s.strip.empty? ? out.to_s : err.to_s).strip[-300..]
                self.Na__UserInterface__PushStatus(dialog, "Python cannot write WebP yet. #{why}", 'error')
            end
        rescue => e
            self.Na__UserInterface__PushStatus(dialog, "Python could not be checked (#{e.message}).", 'error')
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Point Cloud Status Push
    # =============================================================================

        # FUNCTION | Push The Point Cloud Tab Status To The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushPointCloudStatus(dialog)
            return unless dialog
            status_json = self.Na__PointCloud__BuildStatus(Sketchup.active_model).to_json
            dialog.execute_script(
                "window.Na__Tvgb__ReceivePointCloudStatus && window.Na__Tvgb__ReceivePointCloudStatus(#{status_json});"
            )
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push point cloud status to dialog: #{e.message}"
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
