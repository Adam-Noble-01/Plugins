# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - USER INTERFACE PROJECT ACTIONS
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__UserInterface__ProjectActions__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Dialog actions for the Project tab, and the project-aware exports
# CREATED    : 19-Sep-2026
#
# DESCRIPTION:
# - Handles every action that needs the project link: linking and unlinking,
#   choosing and creating design phase folders, exporting straight into the
#   project portal, and pushing to Cloudflare R2.
# - Builds the Project tab's status payload (link, folders, phase catalogue).
# - Lives beside the main UI module rather than inside it purely for size; both
#   reopen the same module, and both sit flat in the modules root so the hot
#   reloader's Dir.glob picks them up.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 19-Sep-2026 - Version 2.9.0
# - Initial project actions.
#
# =============================================================================

require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # =============================================================================
    # REGION | Project Action Routing
    # =============================================================================

        # FUNCTION | Route A Project Tab Action, Or Report It Is Unknown
        # ---------------------------------------------------------------
        # Answers false when the action is not one of ours, so the main handler
        # can carry on and report an unknown action.
        # ---------------------------------------------------------------
        def self.Na__UserInterface__HandleProjectAction(dialog, action_id, params)
            case action_id
            when 'link_project'           then self.Na__ProjectActions__Link(dialog, params)
            when 'dismiss_project_prompt' then self.Na__ProjectActions__DismissPrompt(dialog)
            when 'unlink_project'         then self.Na__ProjectActions__Unlink(dialog)
            when 'set_target_folder'      then self.Na__ProjectActions__SetTargetFolder(dialog, params)
            when 'create_scheme'          then self.Na__ProjectActions__CreateScheme(dialog, params)
            when 'duplicate_scheme'       then self.Na__ProjectActions__DuplicateScheme(dialog, params)
            when 'save_portal_root'       then self.Na__ProjectActions__SavePortalRoot(dialog, params)
            when 'push_to_cloud'          then self.Na__ProjectActions__PushToCloud(dialog, dry_run: false)
            when 'push_dry_run'           then self.Na__ProjectActions__PushToCloud(dialog, dry_run: true)
            when 'open_pipeline'          then self.Na__ProjectActions__OpenPipeline(dialog)
            when 'export_to_project'      then self.Na__ProjectActions__ExportToProject(dialog, params, sync: false)
            when 'export_and_sync'        then self.Na__ProjectActions__ExportToProject(dialog, params, sync: true)
            else
                return false
            end

            # Always finish on a project status push. Several of these actions
            # report only through the status line, and the dialog clears its
            # "running" lock when the project status arrives - without this, an
            # action such as Open Build Pipeline would leave the UI locked.
            self.Na__UserInterface__PushProjectStatus(dialog)
            true
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Link Management
    # =============================================================================

        # ACTION HANDLER | Resolve A Project Code And Link The Model To It
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__Link(dialog, params)
            model = Sketchup.active_model
            code  = params['projectCode'].to_s

            resolution = self.Na__PortalMapper__ResolveProjectCode(code, self.Na__ProjectActions__StoredPortalRoot(model))
            unless resolution[:success]
                self.Na__UserInterface__PushProjectLinkResult(dialog, resolution)
                self.Na__UserInterface__PushStatus(dialog, resolution[:message], 'error')
                return
            end

            # Default the target folder to the phase folder that already holds the most GLBs
            existing = self.Na__PortalMapper__ListPhaseFolders(resolution[:project_root])
            busiest  = existing.max_by { |folder| folder[:glb_count] }
            resolution[:target_phase_folder] = busiest ? busiest[:folder_name] : ''
            resolution[:target_phase_id]     = busiest ? busiest[:phase_id]    : ''

            write = self.Na__ProjectLink__Write(model, resolution)
            self.Na__UserInterface__PushProjectLinkResult(dialog, write)

            unless write[:success]
                self.Na__UserInterface__PushStatus(dialog, write[:message], 'error')
                return
            end

            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(dialog, write[:message], 'success')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Record That The User Exports Without A Project
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__DismissPrompt(dialog)
            result = self.Na__ProjectLink__DismissPrompt(Sketchup.active_model)

            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(dialog, result[:message], 'info')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Remove The Project Link From This Model
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__Unlink(dialog)
            result = self.Na__ProjectLink__Clear(Sketchup.active_model)

            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(dialog, result[:message], result[:success] ? 'info' : 'error')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Store A Portal Root Override On The Model
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__SavePortalRoot(dialog, params)
            model = Sketchup.active_model
            path  = params['portalRoot'].to_s.strip.tr('\\', '/')

            unless path.empty? || Dir.exist?(path)
                self.Na__UserInterface__PushStatus(dialog, "That folder does not exist:\n#{path}", 'error')
                return
            end

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, true)
            dict['portal_root'] = path

            self.Na__PortalMapper__ForceReload                                    # <-- Drop the cached master index
            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(
                dialog,
                path.empty? ? 'Portal root override cleared.' : "Portal root set to #{path}.",
                'success'
            )
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Design Phase and Scheme Management
    # =============================================================================

        # ACTION HANDLER | Set The Design Phase Folder This Model Exports Into
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__SetTargetFolder(dialog, params)
            model       = Sketchup.active_model
            folder_name = params['targetFolder'].to_s
            phase       = self.Na__PortalMapper__IdentifyPhase(folder_name)

            result = self.Na__ProjectLink__WriteTargetPhase(model, folder_name, phase ? phase[:phase_id] : '')

            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(dialog, result[:message], result[:success] ? 'success' : 'error')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Create A New Design Phase / Scheme Folder
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__CreateScheme(dialog, params)
            link     = self.Na__ProjectLink__Read(Sketchup.active_model)
            phase_id = params['phaseId'].to_s

            result = self.Na__PortalMapper__CreatePhaseFolder(link[:project_root], phase_id)

            # A newly created folder becomes the export target straight away
            if result[:success]
                self.Na__ProjectLink__WriteTargetPhase(Sketchup.active_model, result[:folder_name], phase_id)
            end

            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(dialog, result[:message], result[:success] ? 'success' : 'warning')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Duplicate The Selected Scheme Into The Next Number
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__DuplicateScheme(dialog, params)
            link   = self.Na__ProjectLink__Read(Sketchup.active_model)
            source = params['selectedFolder'].to_s

            result = self.Na__PortalMapper__DuplicateScheme(link[:project_root], source)

            if result[:success]
                phase = self.Na__PortalMapper__IdentifyPhase(result[:folder_name])
                self.Na__ProjectLink__WriteTargetPhase(Sketchup.active_model, result[:folder_name], phase ? phase[:phase_id] : '')
            end

            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushStatus(dialog, result[:message], result[:success] ? 'success' : 'warning')
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Project Export
    # =============================================================================

        # ACTION HANDLER | Export Straight Into The Linked Project Folder
        # ---------------------------------------------------------------
        # The UI has already confirmed an overwrite where one was needed, so a
        # target that holds GLBs is archived rather than silently replaced.
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__ExportToProject(dialog, params, sync: false)
            model = Sketchup.active_model
            link  = self.Na__ProjectLink__Read(model)

            unless link[:linked]
                self.Na__UserInterface__PushStatus(dialog, 'This model is not linked to a project.', 'warning')
                self.Na__UserInterface__PushReport(dialog, self.Na__UserInterface__BuildIdleReport)
                return
            end

            target_folder = link[:target_phase_folder].to_s
            if target_folder.empty?
                self.Na__UserInterface__PushStatus(dialog, 'Choose a design phase folder on the Project tab first.', 'warning')
                self.Na__UserInterface__PushReport(dialog, self.Na__UserInterface__BuildIdleReport)
                return
            end

            target_path = self.Na__PortalMapper__PhaseFolderPath(link[:project_root], target_folder)
            FileUtils.mkdir_p(target_path) unless Dir.exist?(target_path)

            self.Na__UserInterface__PushStatus(dialog, "Exporting into #{target_folder}...", 'info')
            self.Na__UserInterface__PushReport(dialog, { running: true, steps: [] })

            # Archive whatever is already there, so a confirmed overwrite is recoverable
            archive_step = nil
            inspection   = self.Na__PortalMapper__InspectTargetFolder(link[:project_root], target_folder)
            if inspection[:glb_count].to_i > 0
                archived     = self.Na__PortalMapper__ArchiveFolderContents(target_path)
                archive_step = {
                    label:   'Previous Export',
                    success: archived[:success],
                    message: archived[:message]
                }
            end

            self.Na__UserInterface__ApplyExportParams(params.to_json)
            self.Na__PublicApi__PerformExport(target_path, quiet: true)

            summary = self.Na__ExportCore__LastExportSummary || {}
            report  = self.Na__UserInterface__BuildExportReport(summary, target_path)

            report[:steps].unshift(archive_step) if archive_step
            report[:steps].unshift(
                label:   'Project',
                success: true,
                message: "#{link[:project_code]} - #{link[:project_name]} → #{target_folder}"
            )

            if sync && report[:success]
                self.Na__UserInterface__PushReport(dialog, report.merge(running: true))
                self.Na__UserInterface__PushStatus(dialog, 'Exported. Building project data and pushing to Cloudflare R2...', 'info')

                push = self.Na__CloudSync__PushProject(link, dry_run: false)
                report[:steps].concat(Array(push[:steps]))
                report[:success] = push[:success]
                report[:message] = push[:success] ? "#{report[:message]} Synced to Cloudflare R2." : push[:message]
            elsif sync
                report[:steps] << { label: 'Cloudflare R2', status: 'skip', message: 'Skipped: the export did not succeed.' }
            end

            self.Na__UserInterface__PushReport(dialog, report)
            self.Na__UserInterface__PushStatus(dialog, report[:message], report[:success] ? 'success' : 'error')
            self.Na__UserInterface__PushProjectStatus(dialog)
            self.Na__UserInterface__PushModelStatus(dialog)
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Cloud Sync
    # =============================================================================

        # ACTION HANDLER | Build The Project Data And Push It To R2
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__PushToCloud(dialog, dry_run: false)
            link = self.Na__ProjectLink__Read(Sketchup.active_model)

            unless link[:linked]
                self.Na__UserInterface__PushStatus(dialog, 'This model is not linked to a project.', 'warning')
                return
            end

            self.Na__UserInterface__PushStatus(
                dialog,
                dry_run ? 'Running the R2 dry run, please wait...' : 'Building project data and pushing to Cloudflare R2...',
                'info'
            )
            self.Na__UserInterface__PushReport(dialog, { running: true, steps: [] })

            report = self.Na__CloudSync__PushProject(link, dry_run: dry_run)

            self.Na__UserInterface__PushReport(dialog, report)
            self.Na__UserInterface__PushStatus(dialog, report[:message], report[:success] ? 'success' : 'error')
        end
        # ---------------------------------------------------------------

        # ACTION HANDLER | Open The Build Pipeline In Its Own Console
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__OpenPipeline(dialog)
            link   = self.Na__ProjectLink__Read(Sketchup.active_model)
            result = self.Na__CloudSync__OpenBuildPipelineWindow(link, link[:project_code])

            self.Na__UserInterface__PushStatus(dialog, result[:message], result[:success] ? 'success' : 'error')
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================


    # =============================================================================
    # REGION | Project Status Payload
    # =============================================================================

        # FUNCTION | Build The Project Tab's Status Payload
        # ---------------------------------------------------------------
        def self.Na__UserInterface__BuildProjectStatus
            model = Sketchup.active_model
            link  = self.Na__ProjectLink__Read(model)

            portal_root = self.Na__PortalMapper__ResolvePortalRoot(self.Na__ProjectActions__StoredPortalRoot(model))
            folders     = link[:linked] ? self.Na__PortalMapper__ListPhaseFolders(link[:project_root]) : []
            target      = link[:target_phase_folder].to_s

            target_info = if link[:linked] && !target.empty?
                self.Na__PortalMapper__InspectTargetFolder(link[:project_root], target)
            else
                { glb_count: 0 }
            end

            {
                linked:           link[:linked],
                should_prompt:    self.Na__ProjectLink__ShouldPrompt?(model),
                portal_found:     !portal_root.nil?,
                portal_root:      portal_root.to_s,
                project_code:     link[:project_code],
                project_name:     link[:project_name],
                project_folder:   link[:project_folder],
                project_root:     link[:project_root],
                project_brief:    self.Na__ProjectActions__BriefFor(link),
                target_folder:    target,
                target_glb_count: target_info[:glb_count].to_i,
                folders:          folders,
                phases:           self.Na__ProjectActions__PhaseCatalogue(link)
            }
        rescue => e
            Na__Log__Warn "ERROR building the project status: #{e.message}"
            Na__Log__Warn e.backtrace.first(5).join("\n")
            {
                linked: false, should_prompt: false, portal_found: false,
                portal_root: '', project_code: '', project_name: '', project_folder: '',
                project_root: '', project_brief: "Project status failed: #{e.message}",
                target_folder: '', target_glb_count: 0, folders: [], phases: []
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push The Project Status To The Dialog
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushProjectStatus(dialog)
            return unless dialog

            status_json = self.Na__UserInterface__BuildProjectStatus.to_json
            dialog.execute_script(
                "window.Na__Tvgb__ReceiveProjectStatus && window.Na__Tvgb__ReceiveProjectStatus(#{status_json});"
            )
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push the project status: #{e.message}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Push The Outcome Of A Link Attempt To The Modal
        # ---------------------------------------------------------------
        def self.Na__UserInterface__PushProjectLinkResult(dialog, result)
            return unless dialog

            payload = { success: result[:success] == true, message: result[:message].to_s }.to_json
            dialog.execute_script(
                "window.Na__Tvgb__ReceiveProjectLinkResult && window.Na__Tvgb__ReceiveProjectLinkResult(#{payload});"
            )
        rescue => e
            Na__Log__Warn "[GlbBuilder] Could not push the link result: #{e.message}"
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build The Phase Catalogue With Next Folder Names
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__PhaseCatalogue(link)
            self.Na__PortalMapper__DesignPhases.map do |phase|
                phase_id = phase['PhaseId'].to_s
                supports = phase['SupportsSchemes'] == true

                next_number = if supports && link[:linked]
                    self.Na__PortalMapper__NextSchemeNumber(link[:project_root], phase_id)
                else
                    1
                end

                {
                    phase_id:         phase_id,
                    label:            phase['Label'].to_s,
                    supports_schemes: supports,
                    next_folder_name: self.Na__PortalMapper__BuildFolderName(phase_id, next_number).to_s
                }
            end
        rescue
            []
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read A Stored Portal Root Override From The Model
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__StoredPortalRoot(model)
            return nil unless model

            dict = model.attribute_dictionary(NA_PROJECT_LINK_DICT, false)
            dict ? dict['portal_root'].to_s : nil
        rescue
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Short Project Brief For The Project Card
        # ---------------------------------------------------------------
        def self.Na__ProjectActions__BriefFor(link)
            return '' unless link[:linked]

            admin = self.Na__PortalMapper__ReadProjectAdminData(link[:project_root])
            brief = admin[:brief_concise].to_s
            return '' if brief.empty?
            return brief if brief.length <= 220

            "#{brief[0, 217]}..."
        rescue
            ''
        end
        # ---------------------------------------------------------------

    # endregion ===================================================================

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
