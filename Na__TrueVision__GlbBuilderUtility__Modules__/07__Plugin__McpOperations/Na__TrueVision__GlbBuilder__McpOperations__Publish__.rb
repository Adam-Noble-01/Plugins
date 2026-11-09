# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MCP OPERATIONS - PUBLISH ACTIONS
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__McpOperations__Publish__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility::Na__McpOperations
# AUTHOR     : Adam Noble - Noble Architecture
# CREATED    : 09-Nov-2026 (GLB Builder 2.14.0)
# PURPOSE    : The truevision_publish actions: everything that reaches the
#              live TrueVision site. A push runs the ProjectVision build (which
#              rewrites the project index and data in the website repo on this
#              computer), then syncs the project's TrueVision content to
#              Cloudflare R2: it uploads what changed AND deletes GLBs that are
#              no longer here. A purge deletes one scheme folder from R2 for
#              good.
#
# EVERY ACTION BUT push_dry_run needs 'confirm' set to the linked project's
# code, as the dialog's own modals ask. An agent passes it only once the user
# has asked for exactly that push or purge in the conversation.
#
# Each one runs as the dialog's CloudJob, and answers at once with the job;
# truevision_export {action: "job"} follows it to its report.
#
# Loaded by Na__TrueVision__GlbBuilder__McpOperations__Main__.rb.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility
        module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Push
# -----------------------------------------------------------------------------

            # FUNCTION | Build, Then Show What A Push Would Upload And Delete (nothing is uploaded)
            # ------------------------------------------------------------
            def self.na_publish_push_dry_run(_params)
                link     = na_publish_ready('there is nothing to check against R2')
                recorder = Na__McpDialog.new
                job = na_track('push_dry_run', recorder) do
                    GlbBuilderUtility.Na__UserInterface__HandleProjectAction(recorder, 'push_dry_run', {})
                end
                answer = na_job_answer(job, recorder, 'The dry run did not start.', expect_job: true)
                answer['warnings'] = [na_build_warning(link) + ' Nothing is uploaded or deleted in R2.']
                answer
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | What The ProjectVision Build Does Besides This Project
            # ------------------------------------------------------------
            # Seen on 09-Nov-2026 (SK02's dry run): the build is not per project.
            # It regenerated 14 tracked files across 9 projects, and dropped
            # JW02's LayoutEditor__DrawingRegister, a key its preserve list
            # (TRUEVISION_DEV_OWNED_KEYS) does not hold.
            # ------------------------------------------------------------
            def self.na_build_warning(link)
                "The ProjectVision build ran: it regenerates the master index and every project's data files in the website repo " \
                "on this computer, not only #{link[:project_code]}'s, and drops any key it does not know (such as a TrueVision drawing " \
                'register). Check git status there before committing.'
            end
            # ---------------------------------------------------------------

            # FUNCTION | Build And Push The Project To R2 (the live site)
            # ------------------------------------------------------------
            def self.na_publish_push(params)
                link = na_publish_ready('there is nothing to push')
                na_require_confirm(link, params, "Pushing #{link[:project_code]} to Cloudflare R2 (the live TrueVision site)")
                recorder = Na__McpDialog.new
                job = na_track('push', recorder) do
                    GlbBuilderUtility.Na__UserInterface__HandleProjectAction(recorder, 'push_to_cloud', {})
                end
                answer = na_job_answer(job, recorder, 'The push did not start.', expect_job: true)
                answer['warnings'] = [na_build_warning(link)]
                answer
            end
            # ---------------------------------------------------------------

            # FUNCTION | Export To Project, Then Push (the Export And Sync button)
            # ------------------------------------------------------------
            def self.na_publish_export_and_push(params)
                link = na_publish_ready('there is no project to export into and push')
                na_require_confirm(link, params, "Exporting into #{link[:target_phase_folder]} and pushing #{link[:project_code]} to Cloudflare R2")
                na_export_project(params, sync: true)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Write The Synced Scenes, Then Push
            # ------------------------------------------------------------
            def self.na_publish_write_scenes_and_push(params)
                na_require_module(:Na__SceneSync__StartSyncAndPush, 'Scene Sync')
                link = na_publish_ready('there is no project to write the scenes into and push')
                na_require_confirm(link, params, "Writing the synced scenes and pushing #{link[:project_code]} to Cloudflare R2")
                recorder = Na__McpDialog.new
                job = na_track('write_scenes_and_push', recorder) { GlbBuilderUtility.Na__SceneSync__StartSyncAndPush(recorder) }
                na_job_answer(job, recorder, 'The scene sync and push did not start.', expect_job: true)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Render The Point Clouds, Then Push
            # ------------------------------------------------------------
            def self.na_publish_export_point_clouds_and_push(params)
                link = na_publish_ready('there is no project to render the point clouds into and push')
                na_require_confirm(link, params, "Rendering the point clouds and pushing #{link[:project_code]} to Cloudflare R2")
                na_point_clouds_job(sync: true)
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | R2 Purge And The Build Pipeline
# -----------------------------------------------------------------------------

            # FUNCTION | Delete One Scheme Folder's GLBs From R2, For Good
            # ------------------------------------------------------------
            # Exactly the GLBs the last fetch listed; the worker refuses if R2
            # has changed since. The folder here is untouched, so the next push
            # uploads it again unless it is deleted here too (delete_scheme).
            # ------------------------------------------------------------
            def self.na_publish_purge_r2_folder(params)
                g      = GlbBuilderUtility
                link   = na_publish_ready('there is no R2 folder to purge')
                folder = na_required_text(params, 'cloud_folder', 'A cloud folder from truevision_export {action: "r2_inventory"}.')

                snapshot = g.instance_variable_get(:@na_r2_inventory)
                unless snapshot.is_a?(Hash) && snapshot['project_root'] == link[:project_root]
                    na_refuse('inventory_required', 'Fetch this project\'s R2 inventory first: a purge deletes exactly the GLBs that listing showed, and refuses if R2 has changed since.',
                              'truevision_export {action: "fetch_r2"}, poll job until it ends, then review r2_inventory {folder}.')
                end
                objects = snapshot['folders'].is_a?(Hash) ? snapshot['folders'][folder] : nil
                if objects.nil? || objects.empty?
                    na_refuse('not_found', "No cloud folder #{folder.inspect} with GLBs in the last R2 inventory.",
                              "Cloud folders: #{snapshot['folders'].is_a?(Hash) ? snapshot['folders'].keys.join(', ') : '(none)'}.")
                end
                na_require_confirm(link, params, "Deleting #{objects.length} GLB(s) in #{folder} from Cloudflare R2 for good")

                recorder = Na__McpDialog.new
                job = na_track('purge_r2_folder', recorder) do
                    g.Na__ProjectActions__ManageR2(recorder, 'purge_r2_folder', { 'cloudFolder' => folder, 'typedConfirmation' => na_text(params, 'confirm') })
                end
                answer = na_job_answer(job, recorder, 'The R2 purge did not start.', expect_job: true)
                answer['warnings'] = ["A purge cannot be undone. While #{folder} still holds GLBs on this computer, the next push uploads them again."]
                answer
            end
            # ---------------------------------------------------------------

            # FUNCTION | Open The Build Pipeline Console For This Project
            # ------------------------------------------------------------
            # ProjectVision__BuildScript__.bat --Project--{CODE}--TV runs the
            # project's TrueVision sync in its own console window, which the
            # user drives from there.
            # ------------------------------------------------------------
            def self.na_publish_open_pipeline(params)
                link = na_publish_ready('there is no project to run the pipeline for')
                na_require_confirm(link, params, "Opening the build pipeline for #{link[:project_code]} (it syncs the project to R2 when run)")
                result = GlbBuilderUtility.Na__CloudSync__OpenBuildPipelineWindow(link, link[:project_code])
                na_refuse('pipeline_failed', result[:message].to_s) unless result[:success]
                { 'summary' => "#{result[:message]} It runs in its own console window, which the user drives." }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | A Linked Model, Its Project Here, No Job Running
            # ------------------------------------------------------------
            def self.na_publish_ready(why)
                model = na_model
                na_require_idle
                link = na_require_link(model, why)
                na_require_project_here(link)
                link
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end # module Na__McpOperations
    end # module GlbBuilderUtility
end # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
