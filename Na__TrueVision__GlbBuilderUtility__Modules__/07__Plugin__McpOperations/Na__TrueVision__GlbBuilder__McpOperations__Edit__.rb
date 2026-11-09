# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MCP OPERATIONS - EDIT ACTIONS
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__McpOperations__Edit__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility::Na__McpOperations
# AUTHOR     : Adam Noble - Noble Architecture
# CREATED    : 09-Nov-2026 (GLB Builder 2.14.0)
# PURPOSE    : The truevision_export_edit actions: what changes this model
#              (the project link, target folder, file toggles, site plan store,
#              Scene Sync and point cloud settings) and this computer's files
#              (exports into a folder or the project, scheme folders, site plan
#              data, the Scene Sync manifest, point cloud renders). Nothing here
#              reaches Cloudflare R2: that is the Publish part.
#
# Each action checks what an agent most often gets wrong first (no link, no
# target, an open group, a job running), so the refusal names the fix; then it
# runs the dialog's own handler or the module function the dialog calls.
#
# Loaded by Na__TrueVision__GlbBuilder__McpOperations__Main__.rb.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility
        module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | Exports
# -----------------------------------------------------------------------------

            # FUNCTION | Export The GLBs Into Any Folder (the Export tab's Export GLB)
            # ------------------------------------------------------------
            def self.na_edit_export_folder(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_model_root(model)
                na_require_idle
                folder  = na_absolute_path(params, 'path')
                options = na_export_options(params)

                warnings = []
                content  = g.Na__PortalMapper__ContentFolderName.to_s
                if !content.empty? && folder.split('/').include?(content)
                    warnings << "#{folder} is inside a project's #{content}: export_project archives the previous export there first, export_folder does not."
                end

                FileUtils.mkdir_p(folder) unless Dir.exist?(folder)
                g.Na__UserInterface__ApplyExportParams(options.to_json)
                g.Na__PublicApi__PerformExport(folder, quiet: true)
                summary = g.Na__ExportCore__LastExportSummary || {}
                report  = na_report(na_plain(g.Na__UserInterface__BuildExportReport(summary, folder)))
                na_refresh_dialog

                unless summary[:success] == true
                    na_refuse('export_failed', report['message'], 'truevision_export {action: "logs", file: "last_export"} shows the export log.', { 'report' => report })
                end

                result = {
                    'folder'      => folder,
                    'mesh'        => summary[:mesh_count].to_i,
                    'linework'    => summary[:linework_count].to_i,
                    'linetype'    => summary[:linetype_count].to_i,
                    'total'       => summary[:total_count].to_i,
                    'toggled_off' => summary[:skipped_count].to_i,
                    'log_path'    => summary[:log_path] && summary[:log_path].to_s.tr('\\', '/'),
                    'report'      => report,
                    'summary'     => "#{report['message']} Written into #{folder}."
                }
                result['warnings'] = warnings unless warnings.empty?
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | Export Into The Linked Project's Target Scheme Folder
            # ------------------------------------------------------------
            def self.na_edit_export_project(params)
                na_export_project(params, sync: false)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Export To Project, With Or Without The Push After It
            # ------------------------------------------------------------
            # The dialog's own Export To Project: it archives (or clears) the
            # previous export, writes the GLBs, writes the synced scenes, and
            # with Export Point Clouds on renders them as a job; sync: true
            # pushes to R2 at the end (the Publish part checks confirm first).
            # ------------------------------------------------------------
            def self.na_export_project(params, sync:)
                g     = GlbBuilderUtility
                model = na_model
                na_require_model_root(model)
                na_require_idle
                link = na_require_link(model, 'there is no project folder to export into')
                na_require_project_here(link)
                target = link[:target_phase_folder].to_s
                if target.empty?
                    na_refuse('no_target', 'No target scheme folder is chosen for this model.',
                              'truevision_export {action: "project"} lists the schemes; choose one with set_target, or make one with create_scheme.')
                end

                existing = na_choice(params, 'existing', %w[archive replace], 'archive')
                if existing == 'replace' && !sync
                    na_require_confirm(link, params, 'Replacing the previous export without archiving it')
                end

                handler_params = na_export_options(params).merge('skipArchive' => existing == 'replace')
                recorder = Na__McpDialog.new
                kind = sync ? 'export_and_push' : 'export_project'
                job  = na_track(kind, recorder) { g.Na__ProjectActions__ExportToProject(recorder, handler_params, sync: sync) }
                answer = na_job_answer(job, recorder, "Exported into #{target}.")
                answer['target'] = target
                answer
            end
            # ---------------------------------------------------------------

            # FUNCTION | Toggle Files On Or Off For Export (Kept On The Model)
            # ------------------------------------------------------------
            def self.na_edit_select_files(params)
                g     = GlbBuilderUtility
                model = na_model
                on    = na_bool(params, 'on', true)
                all   = na_bool(params, 'all', false)
                files = Array(params['files']).map(&:to_s).reject(&:empty?)
                if !all && files.empty?
                    na_refuse('invalid_params', 'Pass files (names from truevision_export {action: "manifest"}), or all: true.')
                end

                unless all
                    known   = na_manifest_rows(na_model_status).map { |row| row['name'] }
                    unknown = files - known
                    unless unknown.empty?
                        na_refuse('not_found', "Not files this model exports: #{unknown.first(10).join(', ')}.",
                                  'File names come from truevision_export {action: "manifest"}.')
                    end
                end

                payload = all ? { 'scope' => 'all', 'selected' => on } : { 'scope' => 'files', 'fileNames' => files, 'selected' => on }
                na_handler(model, 'Export File Selection', 'selection_failed') do |dialog|
                    g.Na__UserInterface__ActionSetFileSelection(dialog, payload.to_json)
                end

                after = na_model_status
                off   = na_manifest_rows(after).reject { |row| row['selected'] }.map { |row| row['name'] }
                {
                    'selected_files' => after[:selected_file_count].to_i,
                    'total_files'    => after[:total_file_count].to_i,
                    'toggled_off'    => off,
                    'summary'        => "#{all ? 'Every file' : "#{files.length} file(s)"} switched #{on ? 'on' : 'off'}: " \
                                        "#{after[:selected_file_count]} of #{after[:total_file_count]} files now export."
                }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Project Link And Portal
# -----------------------------------------------------------------------------

            # FUNCTION | Link The Model To A Project Code (target: its latest scheme)
            # ------------------------------------------------------------
            def self.na_edit_link_project(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                code   = na_required_text(params, 'project_code', 'Two letters and two digits, e.g. "RB05".').upcase
                before = na_link(model)
                na_handler(model, 'Link Project', 'link_failed') do |dialog|
                    g.Na__ProjectActions__Link(dialog, { 'projectCode' => code })
                end

                link   = na_link(model)
                target = link[:target_phase_folder].to_s
                result = {
                    'link'    => na_link_brief(link),
                    'summary' => "Linked to #{link[:project_code]} - #{link[:project_name]}; target " \
                                 "#{target.empty? ? '(none yet: create_scheme)' : target}."
                }
                if before[:linked] && before[:project_code].to_s != link[:project_code].to_s
                    result['warnings'] = ["This model was linked to #{before[:project_code]} before."]
                end
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | Remove The Project Link (the project's folders are untouched)
            # ------------------------------------------------------------
            def self.na_edit_unlink_project(_params)
                model = na_model
                na_require_idle
                before = na_link(model)
                na_handler(model, 'Unlink Project', 'unlink_failed') { |dialog| GlbBuilderUtility.Na__ProjectActions__Unlink(dialog) }
                {
                    'was'     => before[:linked] ? before[:project_code].to_s : nil,
                    'summary' => before[:linked] ? "Unlinked from #{before[:project_code]}. Its folders on disk and in R2 are untouched." : 'This model was not linked to a project.'
                }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Stop The Dialog Asking To Link This Model
            # ------------------------------------------------------------
            def self.na_edit_dismiss_link_prompt(_params)
                model = na_model
                recorder = na_handler(model, 'Dismiss Link Prompt', 'dismiss_failed') do |dialog|
                    GlbBuilderUtility.Na__ProjectActions__DismissPrompt(dialog)
                end
                status = recorder.na_last_status
                { 'summary' => status ? status['text'] : 'The link prompt will not show again for this model.' }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Where This Model Looks For The Project Portal ("" clears it)
            # ------------------------------------------------------------
            def self.na_edit_set_portal_root(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                unless params.key?('path')
                    na_refuse('invalid_params', 'Pass path: the na-project-portal folder, or "" to clear the override.')
                end
                path = na_text(params, 'path').tr('\\', '/')
                na_handler(model, 'Portal Root', 'portal_root_failed') do |dialog|
                    g.Na__ProjectActions__SavePortalRoot(dialog, { 'portalRoot' => path })
                end
                root = g.Na__PortalMapper__ResolvePortalRoot(g.Na__ProjectActions__StoredPortalRoot(model))
                {
                    'portal_root' => root.to_s,
                    'summary'     => path.empty? ? "Portal root override cleared; in use now: #{root || '(none found)'}." : "Portal root set to #{path}."
                }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | A Project Link In Brief
            # ------------------------------------------------------------
            def self.na_link_brief(link)
                {
                    'linked'          => link[:linked] == true,
                    'code'            => link[:project_code].to_s,
                    'name'            => link[:project_name].to_s,
                    'folder'          => link[:project_folder].to_s,
                    'year'            => link[:project_year].to_s,
                    'root'            => link[:project_root].to_s,
                    'target_folder'   => link[:target_phase_folder].to_s,
                    'site_plan_store' => GlbBuilderUtility.Na__ProjectLink__ReadSitePlanFolder(Sketchup.active_model)
                }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scheme Folders
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | The Linked Project's Scheme Folder Names
            # ------------------------------------------------------------
            def self.na_scheme_folder(link, params, why)
                folder  = na_required_text(params, 'folder', 'A scheme folder name from truevision_export {action: "project"} (schemes).')
                folders = GlbBuilderUtility.Na__PortalMapper__ListPhaseFolders(link[:project_root]).map { |row| row[:folder_name].to_s }
                return folder if folders.include?(folder)

                na_refuse('not_found', "No scheme folder #{folder.inspect} in #{link[:project_code]} to #{why}.",
                          "Scheme folders: #{folders.empty? ? '(none)' : folders.join(', ')}. create_scheme makes a new one.")
            end
            # ---------------------------------------------------------------

            # FUNCTION | Choose The Scheme Folder Exports Go Into
            # ------------------------------------------------------------
            def self.na_edit_set_target(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no scheme folder to choose')
                na_require_project_here(link)
                folder = na_scheme_folder(link, params, 'export into')
                na_handler(model, 'Target Folder', 'target_failed') do |dialog|
                    g.Na__ProjectActions__SetTargetFolder(dialog, { 'targetFolder' => folder })
                end
                info = g.Na__PortalMapper__InspectTargetFolder(link[:project_root], folder)
                { 'target' => folder, 'glb_count' => info[:glb_count].to_i,
                  'summary' => "Exports now go into #{folder} (#{info[:glb_count].to_i} GLBs there now)." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Make The Next Scheme Folder Of A Phase (it becomes the target)
            # ------------------------------------------------------------
            def self.na_edit_create_scheme(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no project to make a scheme folder in')
                na_require_project_here(link)
                phase_id = na_required_text(params, 'phase_id', 'A phase_id from truevision_export {action: "project"} (phases).')
                ids = Array(g.Na__PortalMapper__DesignPhases).map { |phase| phase['PhaseId'].to_s }
                na_refuse('invalid_params', "Unknown phase_id #{phase_id.inspect}.", "Phases: #{ids.join(', ')}.") unless ids.include?(phase_id)

                na_handler(model, 'Create Scheme', 'create_failed') do |dialog|
                    g.Na__ProjectActions__CreateScheme(dialog, { 'phaseId' => phase_id })
                end
                target = na_link(model)[:target_phase_folder].to_s
                { 'folder' => target, 'summary' => "Created #{target}; it is now the export target." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Copy A Scheme Folder Into The Next Number (it becomes the target)
            # ------------------------------------------------------------
            def self.na_edit_duplicate_scheme(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no scheme folder to copy')
                na_require_project_here(link)
                folder = na_scheme_folder(link, params, 'copy')
                na_handler(model, 'Duplicate Scheme', 'duplicate_failed') do |dialog|
                    g.Na__ProjectActions__DuplicateScheme(dialog, { 'selectedFolder' => folder })
                end
                target = na_link(model)[:target_phase_folder].to_s
                { 'source' => folder, 'folder' => target, 'summary' => "Copied #{folder} into #{target}; it is now the export target." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Delete A Scheme Folder (into 00__Archive, or for good)
            # ------------------------------------------------------------
            def self.na_edit_delete_scheme(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no scheme folder to delete')
                na_require_project_here(link)
                folder    = na_scheme_folder(link, params, 'delete')
                permanent = na_bool(params, 'permanent', false)
                na_require_confirm(link, params, permanent ? "Deleting #{folder} for good" : "Deleting #{folder} (moved into the project's archive)")

                count      = g.Na__PortalMapper__InspectTargetFolder(link[:project_root], folder)[:glb_count].to_i
                was_target = link[:target_phase_folder].to_s == folder
                recorder = na_handler(model, 'Delete Scheme', 'delete_failed') do |dialog|
                    g.Na__ProjectActions__DeleteScheme(dialog, { 'targetFolder' => folder, 'typedConfirmation' => na_text(params, 'confirm'),
                                                                 'permanent' => permanent })
                end
                target = na_link(model)[:target_phase_folder].to_s
                status = recorder.na_last_status
                {
                    'deleted'   => folder,
                    'permanent' => permanent,
                    'glb_count' => count,
                    'target'    => target,
                    'summary'   => "#{status ? status['text'] : "#{folder} deleted."}" \
                                   "#{was_target ? " The target is now #{target.empty? ? '(none)' : target}." : ''}"
                }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Site Plan
# -----------------------------------------------------------------------------

            # FUNCTION | Choose The Site Plan Store (Existing Or Proposed)
            # ------------------------------------------------------------
            def self.na_edit_set_site_plan_store(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                link   = na_require_link(model, 'there is no site plan store to choose')
                folder = na_required_text(params, 'folder', 'A store from truevision_export {action: "project"} (site_plan.stores), e.g. "SitePlan__DrawingData__Proposed".')
                unless g.Na__PortalMapper__IdentifySitePlanFolder(folder)
                    na_refuse('invalid_params', "#{folder.inspect} is not a site plan store.",
                              'Use SitePlan__DrawingData__Existing or SitePlan__DrawingData__Proposed (or an original SitePlan__DrawingData).')
                end
                na_handler(model, 'Site Plan Store', 'store_failed') do |dialog|
                    g.Na__ProjectActions__SetSitePlanFolder(dialog, { 'folderName' => folder })
                end
                exists = Dir.exist?(g.Na__PortalMapper__PhaseFolderPath(link[:project_root], folder).to_s)
                { 'store' => folder, 'exists' => exists,
                  'summary' => "This model now exports its site plan into #{folder}#{exists ? '' : ' (not on disk yet: the first export makes it)'}." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Make A Site Plan Store And Choose It
            # ------------------------------------------------------------
            def self.na_edit_create_site_plan_store(params)
                g     = GlbBuilderUtility
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no project to make a site plan store in')
                na_require_project_here(link)
                variant = na_choice(params, 'variant', %w[existing proposed], '')
                na_handler(model, 'Create Site Plan Store', 'store_failed') do |dialog|
                    g.Na__ProjectActions__CreateSitePlanFolder(dialog, { 'variantId' => variant })
                end
                store = g.Na__ProjectLink__ReadSitePlanFolder(model)
                { 'store' => store, 'summary' => "Created #{store}; this model now exports its site plan into it." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Export The Site Plan Drawing Data (no message boxes)
            # ------------------------------------------------------------
            # The Site Plan tab's export, without Na__SitePlan__Run's confirm
            # and folder picker: the folder is the project's chosen store, or
            # path; older site plan files are kept unless stale is 'delete'.
            # ------------------------------------------------------------
            def self.na_edit_export_site_plan(params)
                g = GlbBuilderUtility
                na_require_module(:Na__SitePlan__Scan, 'Site Plan Export')
                model = na_model
                na_require_model_root(model)
                na_require_idle
                stale = na_choice(params, 'stale', %w[keep delete], 'keep')

                write = g.method(:Na__SitePlan__Write)
                unless write.parameters.any? { |_, name| name == :on_stale }
                    na_refuse('unsupported', "This GLB Builder's site plan writer asks about older files in a message box, which would stop SketchUp.",
                              'Update the GLB Builder to 2.14.0 and use Reload Scripts (truevision_export_edit {action: "reload"}).')
                end

                scan = g.Na__SitePlan__Scan(model)
                if scan[:layers].empty?
                    na_refuse('nothing_to_export', 'The Tags SSOT has no site plan tags (71-75), so there is nothing to export.',
                              'Na__DataLib__CoreIndex__Tags__.json v2.3.0 or later carries them.')
                end
                if scan[:buckets].empty?
                    skipped_edges = (scan[:skipped] || {}).values.sum { |counts| counts[:edges].to_i }
                    na_refuse('nothing_to_export',
                              "No geometry sits on a site plan tag (71-75).#{skipped_edges > 0 ? " #{skipped_edges} edge(s) on them are hidden, soft or smooth, so they were skipped." : ''}",
                              'Tag the site plan groups (or their edges and faces) on 71-75 first.')
                end

                link = na_link(model)
                if params.key?('path')
                    folder = na_absolute_path(params, 'path')
                    label  = folder
                else
                    target = g.Na__SitePlan__ProjectTarget(model)
                    if target.nil?
                        na_refuse('folder_required', 'This model is not linked to a project, so its site plan has nowhere set to go.',
                                  'Pass path (an absolute folder), or link the model first (link_project).')
                    end
                    if target == :unchosen
                        na_refuse('store_not_chosen', 'This model is linked, but no site plan store is chosen. It is never guessed, so an existing site plan cannot land on a proposed one.',
                                  'set_site_plan_store or create_site_plan_store first.')
                    end
                    na_require_project_here(link)
                    folder = target[:path].to_s.tr('\\', '/')
                    label  = "the #{target[:label]} for #{target[:code]}"
                end

                if stale == 'delete'
                    if link[:linked]
                        na_require_confirm(link, params, 'Deleting older site plan files the export did not write')
                    elsif na_text(params, 'confirm') != File.basename(folder)
                        na_refuse('confirmation_required', "Deleting older site plan files needs 'confirm' set to the folder's name (#{File.basename(folder)}).",
                                  'Only once the user has asked for exactly this.')
                    end
                end

                FileUtils.mkdir_p(folder) unless Dir.exist?(folder)
                prefix = g.Na__SitePlan__ProjectPrefix(model)
                result = write.call(model, scan, prefix, folder, on_stale: stale.to_sym)
                found  = result[:stale_found].to_i
                answer = {
                    'folder'   => folder,
                    'layers'   => result[:layers].to_i,
                    'files'    => result[:files].to_i,
                    'removed'  => result[:removed].to_i,
                    'checks'   => na_plain(result[:warnings] || {}),
                    'log_path' => result[:log_path] && result[:log_path].to_s.tr('\\', '/'),
                    'summary'  => "Site plan written into #{label}: #{result[:layers]} layer(s), #{result[:files]} GLB file(s) and the manifest" \
                                  "#{result[:removed].to_i > 0 ? "; #{result[:removed]} older file(s) removed" : ''}. Push to R2 to publish it."
                }
                if stale == 'keep' && found > 0
                    answer['warnings'] = ["#{found} older site plan GLB(s) in the folder were not written by this export and were kept, so the pipeline still publishes them. " \
                                          'export_site_plan with stale: "delete" (and confirm) removes them.']
                end
                answer
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Scene Sync
# -----------------------------------------------------------------------------

            # FUNCTION | Switch Scenes On Or Off For Scene Sync
            # ------------------------------------------------------------
            def self.na_edit_switch_scenes(params)
                g = GlbBuilderUtility
                na_require_module(:Na__SceneSync__SetOn, 'Scene Sync')
                model = na_model
                on    = na_bool(params, 'on', true)
                refs  = Array(params['scenes'])
                na_refuse('invalid_params', 'Pass scenes: scene names or persistent ids (truevision_export {action: "scenes"}).') if refs.empty?

                pages  = refs.map { |reference| na_page(model, reference) }.uniq
                result = g.Na__SceneSync__SetOn(model, pages.map(&:persistent_id), on)
                na_refuse('scene_sync_failed', result[:message].to_s) unless result[:success]
                na_refresh_dialog

                settings = g.Na__SceneSync__Settings(model)
                { 'scenes' => pages.map(&:name), 'on' => on, 'scenes_on' => Array(settings['scenes']).count { |row| row['on'] },
                  'summary' => "Scene Sync #{on ? 'on' : 'off'} for #{pages.map(&:name).join(', ')}.#{on ? ' write_scenes writes them into the project.' : ' TrueVision keeps them as last synced.'}" }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Choose What A Synced Scene Is In TrueVision
            # ------------------------------------------------------------
            def self.na_edit_set_scene_type(params)
                g = GlbBuilderUtility
                na_require_module(:Na__SceneSync__SetType, 'Scene Sync')
                model = na_model
                page  = na_page(model, na_required_text(params, 'scene', 'A scene name or persistent id.'))
                type  = na_choice(params, 'type', %w[plan elevation section view3d auto], '')
                result = g.Na__SceneSync__SetType(model, page.persistent_id, type == 'auto' ? nil : type)
                na_refuse('scene_sync_failed', result[:message].to_s, 'Switch it on first with switch_scenes.') unless result[:success]
                na_refresh_dialog
                { 'scene' => page.name, 'type' => type,
                  'summary' => "#{page.name} syncs as #{type == 'auto' ? 'whatever its camera suggests' : type}." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Detach A Scene: TrueVision Keeps Its Last Sync For Good
            # ------------------------------------------------------------
            def self.na_edit_detach_scene(params)
                g = GlbBuilderUtility
                na_require_module(:Na__SceneSync__Detach, 'Scene Sync')
                model  = na_model
                page   = na_page(model, na_required_text(params, 'scene', 'A scene name or persistent id.'))
                result = g.Na__SceneSync__Detach(model, page.persistent_id)
                na_refuse('scene_sync_failed', result[:message].to_s) unless result[:success]
                na_refresh_dialog
                { 'scene' => page.name,
                  'summary' => "#{page.name} detached: the next write hands TrueVision its last sync for good. Switching it on again starts a new synced scene." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Write The Synced Scenes Into The Project (the Sync button)
            # ------------------------------------------------------------
            def self.na_edit_write_scenes(_params)
                g = GlbBuilderUtility
                na_require_module(:Na__SceneSync__Write, 'Scene Sync')
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no project to write the scenes into')
                na_require_project_here(link)
                result = g.Na__SceneSync__Write(model, link)
                na_refresh_dialog
                return { 'synced' => 0, 'frozen' => 0, 'summary' => result[:message].to_s } if result[:skipped]

                na_refuse('scene_sync_failed', result[:message].to_s, nil, { 'steps' => na_plain(result[:steps]) }) unless result[:success]
                { 'synced' => result[:synced].to_i, 'frozen' => result[:frozen].to_i, 'steps' => na_plain(result[:steps]),
                  'summary' => "#{result[:message]} Push to R2 to publish them." }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Point Clouds
# -----------------------------------------------------------------------------

            # FUNCTION | Export Point Clouds On Or Off (a step of export_project)
            # ------------------------------------------------------------
            def self.na_edit_switch_point_clouds(params)
                g = GlbBuilderUtility
                na_require_module(:Na__PointCloud__SetEnabled, 'Point Cloud Export')
                model = na_model
                na_refuse('invalid_params', 'Pass on: true or false.') unless params.key?('on')
                on = na_bool(params, 'on', false)
                result = g.Na__PointCloud__SetEnabled(model, on)
                na_refuse('point_cloud_failed', result[:message].to_s) unless result[:success]
                na_refresh_dialog
                { 'enabled' => on,
                  'summary' => on ? 'Export Point Clouds is on: export_project renders the selected point cloud scenes after the GLBs.' :
                                    'Export Point Clouds is off: exports leave point clouds alone. Every setting is kept.' }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Choose Which Point Cloud Scenes Render
            # ------------------------------------------------------------
            def self.na_edit_select_point_cloud_scenes(params)
                g = GlbBuilderUtility
                na_require_module(:Na__PointCloud__SetSceneSelected, 'Point Cloud Export')
                model = na_model
                on    = na_bool(params, 'on', true)
                ids   = Array(params['scene_ids']).map(&:to_s).reject(&:empty?)
                na_refuse('invalid_params', 'Pass scene_ids: point cloud scene ids from truevision_export {action: "point_clouds"}.') if ids.empty?

                list = g.Na__PointCloud__SceneList(model)
                if list['ok']
                    known   = Array(list['scenes']).map { |row| row['id'].to_s }
                    unknown = ids - known
                    na_refuse('not_found', "No point cloud scene #{unknown.first.inspect}.", "Scenes: #{known.join(', ')}.") unless unknown.empty?
                end
                result = g.Na__PointCloud__SetSceneSelected(model, ids, on)
                na_refuse('point_cloud_failed', result[:message].to_s) unless result[:success]
                na_refresh_dialog
                { 'scene_ids' => ids, 'on' => on, 'summary' => "#{ids.length} point cloud scene(s) #{on ? 'selected' : 'left out'}." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | A Point Cloud Scene's Export Settings (the viewer's own record)
            # ------------------------------------------------------------
            def self.na_edit_set_point_cloud_scene(params)
                model  = na_model
                viewer = na_point_cloud_viewer
                id     = na_required_text(params, 'scene_id', 'A point cloud scene id from truevision_export {action: "point_clouds"}.')
                values = params['values']
                unless values.is_a?(Hash) && !values.empty?
                    na_refuse('invalid_params', 'Pass values: any of viewType, scale (the 1:N denominator), imageWidthPx (500-30000) and pointSizePx (null for Auto).')
                end
                problem = viewer.Na__PublicApi__SetSceneExport(model, id, values)
                na_refuse('point_cloud_failed', problem.to_s) if problem
                na_refresh_dialog
                { 'scene_id' => id, 'values' => values, 'summary' => "Export settings saved for point cloud scene #{id}." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Put The Point Cloud Scenes In Order (every id, top to bottom)
            # ------------------------------------------------------------
            def self.na_edit_order_point_cloud_scenes(params)
                model  = na_model
                viewer = na_point_cloud_viewer
                ids    = Array(params['scene_ids']).map(&:to_s).reject(&:empty?)
                na_refuse('invalid_params', 'Pass scene_ids: every point cloud scene id, top to bottom.') if ids.empty?
                unless viewer.respond_to?(:Na__PublicApi__ReorderScenes)
                    na_refuse('unsupported', 'This Na Point Cloud Viewer cannot reorder its scenes from here.', 'Reload the viewer, then try again.')
                end
                problem = viewer.Na__PublicApi__ReorderScenes(model, ids)
                na_refuse('point_cloud_failed', problem.to_s) if problem
                na_refresh_dialog
                { 'scene_ids' => ids, 'summary' => "Point cloud scenes reordered (#{ids.length})." }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Reload The Point Cloud In The Viewer
            # ------------------------------------------------------------
            def self.na_edit_reload_point_cloud(_params)
                model   = na_model
                problem = na_point_cloud_viewer.Na__PublicApi__ReloadPointCloud(model)
                na_refuse('point_cloud_failed', problem.to_s) if problem
                { 'summary' => 'Reloading the point cloud in the Na Point Cloud Viewer. Read point_clouds again when it has finished.' }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Render The Selected Point Cloud Scenes Into The Project (a job)
            # ------------------------------------------------------------
            def self.na_edit_export_point_clouds(_params)
                na_point_clouds_job(sync: false)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The Point Cloud Tab's Export, Optionally With A Push
            # ------------------------------------------------------------
            def self.na_point_clouds_job(sync:)
                g = GlbBuilderUtility
                na_require_module(:Na__PointCloud__StartExport, 'Point Cloud Export')
                model = na_model
                na_require_idle
                link = na_require_link(model, 'there is no project to render the point clouds into')
                na_require_project_here(link)
                na_point_cloud_viewer
                recorder = Na__McpDialog.new
                kind = sync ? 'export_point_clouds_and_push' : 'export_point_clouds'
                job  = na_track(kind, recorder) { g.Na__PointCloud__StartExport(recorder, sync: sync) }
                na_job_answer(job, recorder, 'The point cloud export did not start.', expect_job: true)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The Na Point Cloud Viewer, Or A Refusal Saying Why Not
            # ------------------------------------------------------------
            def self.na_point_cloud_viewer
                na_require_module(:Na__PointCloud__ViewerStatus, 'Point Cloud Export')
                viewer = GlbBuilderUtility.Na__PointCloud__ViewerStatus
                return ::Na__PointCloudViewer if viewer[:available]

                na_refuse('unsupported', viewer[:message].to_s, 'Open the Na Point Cloud Viewer for this model, then try again.')
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dialog And Reload
# -----------------------------------------------------------------------------

            # FUNCTION | Open The GLB Builder Dialog (for Adam to see)
            # ------------------------------------------------------------
            def self.na_edit_open_dialog(_params)
                GlbBuilderUtility.Na__UserInterface__ShowExportDialog
                { 'dialog_open' => GlbBuilderUtility.Na__UserInterface__DialogVisible,
                  'summary' => 'The TrueVision GLB Builder dialog is open.' }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Adam's Reload Scripts, Without Its Closing Message Box
            # ------------------------------------------------------------
            def self.na_edit_reload(_params)
                reloader = GlbBuilderUtility.method(:Na__DynamicReloader__ReloadAllScripts)
                unless reloader.parameters.any? { |_, name| name == :quiet }
                    na_refuse('unsupported', "This GLB Builder's Reload Scripts ends with a message box, which would stop SketchUp until someone clicks it.",
                              'Load its Na__TrueVision__GlbBuilder__DynamicReloaderPluginUtil__.rb once (ruby_eval load), then reload.')
                end
                outcome = reloader.call(quiet: true)
                outcome = {} unless outcome.is_a?(Hash)
                errors  = Array(outcome[:error_files])
                result  = {
                    'loaded'  => outcome[:loaded].to_i,
                    'errors'  => errors,
                    'version' => na_version,
                    'summary' => "Reloaded #{outcome[:loaded].to_i} GLB Builder file(s)#{errors.empty? ? '' : ", #{errors.length} with errors"}; now #{na_version}."
                }
                result['warnings'] = errors.map { |text| "Reload error: #{text}" } unless errors.empty?
                result
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end # module Na__McpOperations
    end # module GlbBuilderUtility
end # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
