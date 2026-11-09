# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MCP OPERATIONS - READ ACTIONS
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__McpOperations__Read__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility::Na__McpOperations
# AUTHOR     : Adam Noble - Noble Architecture
# CREATED    : 09-Nov-2026 (GLB Builder 2.14.0)
# PURPOSE    : The truevision_export actions. Each reads what the dialog's
#              tabs show, from the same builders (BuildModelStatus,
#              BuildProjectStatus, Na__SceneSync__BuildStatus,
#              Na__PointCloud__BuildStatus, Na__SitePlan__Scan), and changes
#              nothing. fetch_r2 is the one that starts something: a job that
#              lists the project's GLBs in Cloudflare R2, which changes nothing
#              there either.
#
# Loaded by Na__TrueVision__GlbBuilder__McpOperations__Main__.rb.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility
        module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | status
# -----------------------------------------------------------------------------

            # FUNCTION | Everything At A Glance
            # ------------------------------------------------------------
            def self.na_read_status(_params)
                g     = GlbBuilderUtility
                model = Sketchup.active_model
                link  = model ? na_link(model) : g.Na__ProjectLink__BlankLink

                missing = link[:linked] ? g.Na__PortalMapper__MissingProjectMessage(link[:project_root]) : nil
                target  = link[:target_phase_folder].to_s
                target_info = if link[:linked] && !missing && !target.empty?
                    g.Na__PortalMapper__InspectTargetFolder(link[:project_root], target)
                end

                manifest   = model ? na_model_status : nil
                pc         = model && g.respond_to?(:Na__PointCloud__Settings) ? g.Na__PointCloud__Settings(model) : nil
                ss         = model && g.respond_to?(:Na__SceneSync__Settings) ? g.Na__SceneSync__Settings(model) : nil
                group_open = model ? !(model.active_path.nil? || model.active_path.empty?) : false
                job        = na_job_brief

                result = {
                    'glb_builder' => {
                        'version'      => na_version,
                        'modules_root' => GlbBuilderUtility::NA_PLUGIN_ROOT.to_s.tr('\\', '/'),
                        'dialog_open'  => g.Na__UserInterface__DialogVisible,
                        'modules'      => {
                            'site_plan'    => g.respond_to?(:Na__SitePlan__Scan),
                            'point_clouds' => g.respond_to?(:Na__PointCloud__BuildStatus),
                            'scene_sync'   => g.respond_to?(:Na__SceneSync__BuildStatus),
                            'linetype'     => g.respond_to?(:Na__Linetype__PlanExport)
                        }
                    },
                    'model' => model && {
                        'name'           => g.Na__UserInterface__ModelDisplayName(model),
                        'path'           => model.path.to_s.tr('\\', '/'),
                        'modified'       => model.modified?,
                        'group_open'     => group_open,
                        'project_prefix' => g.Na__Helpers__ExtractProjectPrefix(model).to_s
                    },
                    'project' => {
                        'linked'              => link[:linked] == true,
                        'code'                => link[:project_code].to_s,
                        'name'                => link[:project_name].to_s,
                        'folder'              => link[:project_folder].to_s,
                        'year'                => link[:project_year].to_s,
                        'found_here'          => link[:linked] ? missing.nil? : nil,
                        'missing_why'         => missing,
                        'target_folder'       => target,
                        'target_glb_count'    => target_info && target_info[:glb_count].to_i,
                        'target_last_written' => target_info && target_info[:last_written].to_s,
                        'site_plan_store'     => model ? g.Na__ProjectLink__ReadSitePlanFolder(model) : ''
                    },
                    'manifest' => manifest && {
                        'files'          => manifest[:total_file_count].to_i,
                        'selected'       => manifest[:selected_file_count].to_i,
                        'storeys'        => manifest[:storey_count].to_i,
                        'site_plan_tags' => manifest[:site_plan_tag_count].to_i,
                        'can_export'     => manifest[:can_export_model] == true
                    },
                    'point_clouds' => pc && { 'enabled' => pc['enabled'] == true, 'scenes_left_out' => Array(pc['deselected']).length },
                    'scene_sync'   => ss && { 'scenes_on' => Array(ss['scenes']).count { |row| row['on'] }, 'detached' => Array(ss['detached']).length },
                    'job'          => job,
                    'r2_inventory_fetched' => !g.instance_variable_get(:@na_r2_inventory).nil?
                }

                parts = ["GLB Builder #{result['glb_builder']['version'] || '(version unknown)'}"]
                parts << (model ? result['model']['name'] : 'no model')
                parts << if !link[:linked] then 'not linked to a project'
                         elsif missing then "linked to #{link[:project_code]}, but the project is not on this computer"
                         elsif target.empty? then "linked to #{link[:project_code]}, no target scheme chosen"
                         else "linked to #{link[:project_code]}, target #{target} (#{target_info ? target_info[:glb_count].to_i : 0} GLBs)"
                         end
                parts << "#{manifest[:selected_file_count]} of #{manifest[:total_file_count]} files selected" if manifest
                parts << 'a group is open (exports refused)' if group_open
                parts << (job ? (job['running'] ? "job #{job['job_id'] || '(dialog)'} running" : "last job #{job['job_id']} ended") : 'no job running')
                result['summary'] = parts.join('; ') + '.'
                result
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | manifest
# -----------------------------------------------------------------------------

            # FUNCTION | The Files An Export Writes, As The Export Tab Lists Them
            # ------------------------------------------------------------
            def self.na_read_manifest(params)
                model  = na_model
                status = na_model_status
                rows   = na_manifest_rows(status)
                filter = na_text(params, 'filter').downcase
                unless filter.empty?
                    rows = rows.select { |row| row['name'].downcase.include?(filter) || row['group'].downcase.include?(filter) }
                end

                toggled_off = rows.reject { |row| row['selected'] }.map { |row| row['name'] }
                group_open  = !(model.active_path.nil? || model.active_path.empty?)
                result = {
                    'model_name'        => status[:model_name].to_s,
                    'project_prefix'    => status[:project_prefix].to_s,
                    'storeys'           => status[:storey_count].to_i,
                    'storey_containers' => status[:storey_container_count].to_i,
                    'site_plan_tags'    => status[:site_plan_tag_count].to_i,
                    'excluded_tags'     => status[:excluded_tag_count].to_i,
                    'linetype_tags'     => status[:linetype_tag_count].to_i,
                    'total_files'       => status[:total_file_count].to_i,
                    'selected_files'    => status[:selected_file_count].to_i,
                    'can_export'        => status[:can_export_model] == true,
                    'group_open'        => group_open,
                    'notes'             => Array(status[:notes]).map { |note| [note[:title], note[:text]].map(&:to_s).reject(&:empty?).join(' ') },
                    'files'             => rows,
                    'toggled_off'       => toggled_off
                }
                result['warnings'] = ['A group is open: the export would write only what is inside it. Close it with context_set {action: "close_all"}.'] if group_open
                shown = filter.empty? ? '' : " (#{rows.length} matching \"#{filter}\")"
                result['summary'] = "#{status[:selected_file_count]} of #{status[:total_file_count]} files selected for export#{shown}" \
                                    "#{status[:storey_count].to_i > 0 ? ", #{status[:storey_count]} storeys" : ''}" \
                                    "#{toggled_off.empty? ? '' : ", #{toggled_off.length} toggled off"}."
                result
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | project
# -----------------------------------------------------------------------------

            # FUNCTION | The Project Tab: Link, Schemes, Phases, Site Plan Stores
            # ------------------------------------------------------------
            def self.na_read_project(params)
                g      = GlbBuilderUtility
                model  = na_model
                status = g.Na__UserInterface__BuildProjectStatus
                link   = na_link(model)
                missing = link[:linked] ? g.Na__PortalMapper__MissingProjectMessage(link[:project_root]) : nil
                target  = status[:target_folder].to_s

                schemes = Array(status[:folders]).map do |folder|
                    {
                        'folder'       => folder[:folder_name].to_s,
                        'phase'        => folder[:phase_label].to_s,
                        'phase_id'     => folder[:phase_id].to_s,
                        'scheme'       => folder[:scheme_number].to_i,
                        'glb_count'    => folder[:glb_count].to_i,
                        'last_written' => folder[:last_written].to_s,
                        'recognised'   => folder[:recognised] == true,
                        'is_target'    => folder[:folder_name].to_s == target
                    }
                end
                phases = Array(status[:phases]).map do |phase|
                    {
                        'phase_id'         => phase[:phase_id].to_s,
                        'label'            => phase[:label].to_s,
                        'supports_schemes' => phase[:supports_schemes] == true,
                        'next_folder'      => phase[:next_folder_name].to_s
                    }
                end
                stores = Array(status[:siteplan_folders]).map do |store|
                    { 'folder' => store[:folder_name].to_s, 'variant' => store[:variant_id].to_s, 'label' => store[:variant_label].to_s,
                      'glb_count' => store[:glb_count].to_i, 'last_written' => store[:last_written].to_s, 'legacy' => store[:is_legacy] == true }
                end
                variants = Array(status[:siteplan_variants]).map do |variant|
                    { 'variant' => variant[:variant_id].to_s, 'label' => variant[:label].to_s, 'folder' => variant[:folder_name].to_s }
                end

                result = {
                    'linked'        => status[:linked] == true,
                    'should_prompt' => status[:should_prompt] == true,
                    'portal'        => { 'found' => status[:portal_found] == true, 'root' => status[:portal_root].to_s },
                    'project'       => {
                        'code'        => status[:project_code].to_s,
                        'name'        => status[:project_name].to_s,
                        'folder'      => status[:project_folder].to_s,
                        'root'        => status[:project_root].to_s,
                        'brief'       => status[:project_brief].to_s,
                        'found_here'  => link[:linked] ? missing.nil? : nil,
                        'missing_why' => missing
                    },
                    'target'        => { 'folder' => target, 'glb_count' => status[:target_glb_count].to_i },
                    'schemes'       => schemes,
                    'phases'        => phases,
                    'site_plan'     => {
                        'store'        => status[:siteplan_folder].to_s,
                        'path'         => status[:siteplan_folder_path].to_s,
                        'exists'       => status[:siteplan_exists] == true,
                        'glb_count'    => status[:siteplan_glb_count].to_i,
                        'last_written' => status[:siteplan_last_written].to_s,
                        'stores'       => stores,
                        'variants'     => variants
                    }
                }
                result['structure'] = na_plain(status[:structure]) if na_bool(params, 'include_structure', false)

                result['summary'] = if !result['linked']
                    "Not linked to a project#{result['portal']['found'] ? '' : '; the project portal was not found on this computer'}."
                elsif missing
                    "Linked to #{result['project']['code']}, but #{missing}"
                else
                    "#{result['project']['code']} - #{result['project']['name']}: #{schemes.length} scheme folder(s), target " \
                    "#{target.empty? ? '(none)' : "#{target} (#{result['target']['glb_count']} GLBs)"}; site plan store " \
                    "#{result['site_plan']['store'].empty? ? '(not chosen)' : result['site_plan']['store']}."
                end
                result
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | site_plan
# -----------------------------------------------------------------------------

            # FUNCTION | What A Site Plan Export Would Write, And Where
            # ------------------------------------------------------------
            def self.na_read_site_plan(_params)
                g = GlbBuilderUtility
                na_require_module(:Na__SitePlan__Scan, 'Site Plan Export')
                model   = na_model
                scan    = g.Na__SitePlan__Scan(model)
                prefix  = g.Na__SitePlan__ProjectPrefix(model)
                target  = g.Na__SitePlan__ProjectTarget(model)
                buckets = scan[:buckets] || {}
                skipped = scan[:skipped] || {}

                layers = buckets.keys.sort.map do |tag_name|
                    bucket = buckets[tag_name]
                    {
                        'tag'   => tag_name,
                        'lines' => bucket[:positions].length / 6,
                        'faces' => bucket[:face_count].to_i,
                        'fills' => bucket[:defn][:fills] == true,
                        'rings' => Array(bucket[:rings]).length
                    }
                end
                canonical = (scan[:layers] || {}).each_value.map { |defn| defn[:tag_name] }.uniq
                unused    = canonical - buckets.keys - skipped.keys

                target_info = na_site_plan_target(target)
                result = {
                    'ssot_version'   => scan[:ssot_version],
                    'site_plan_tags' => canonical.length,
                    'project_prefix' => prefix,
                    'layers'         => layers,
                    'unused_tags'    => unused.sort,
                    'skipped'        => na_plain(skipped),
                    'warnings'       => na_plain(g.Na__SitePlan__Warnings(buckets, skipped)),
                    'target'         => target_info,
                    'can_export'     => !canonical.empty? && !buckets.empty?,
                    'file_pattern'   => "#{prefix}TrueVision__SitePlan__{Layer}__LineworkModel__.glb"
                }
                result['summary'] = if canonical.empty?
                    'The Tags SSOT has no site plan tags (71-75): nothing can be exported.'
                elsif buckets.empty?
                    'No geometry sits on a site plan tag (71-75): nothing to export.'
                else
                    "#{layers.length} site plan layer(s) with geometry (#{layers.sum { |layer| layer['lines'] }} lines); " \
                    "target: #{target_info['state'] == 'ready' ? "#{target_info['label']} (#{target_info['site_plan_glbs']} site plan GLBs there now)" : target_info['note']}."
                end
                result
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Where Na__SitePlan__ProjectTarget Says It Goes
            # ------------------------------------------------------------
            def self.na_site_plan_target(target)
                case target
                when nil
                    { 'state' => 'unlinked', 'note' => 'not linked to a project, so export_site_plan needs path' }
                when :unchosen
                    { 'state' => 'unchosen', 'note' => 'linked, but no site plan store is chosen: set_site_plan_store or create_site_plan_store first (never guessed)' }
                else
                    missing = GlbBuilderUtility.Na__PortalMapper__MissingProjectMessage(target[:project_root])
                    exists  = !missing && Dir.exist?(target[:path].to_s)
                    files   = exists ? Dir.children(target[:path].to_s).select { |name| name =~ GlbBuilderUtility::NA__SITEPLAN__OLD_FILE_PATTERN } : []
                    {
                        'state'          => missing ? 'project_missing' : 'ready',
                        'store'          => target[:folder].to_s,
                        'label'          => target[:label].to_s,
                        'path'           => target[:path].to_s.tr('\\', '/'),
                        'exists'         => exists,
                        'site_plan_glbs' => files.length,
                        'note'           => missing || "the #{target[:label]}"
                    }
                end
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | scenes / point_clouds
# -----------------------------------------------------------------------------

            # FUNCTION | The Scene Sync Tab
            # ------------------------------------------------------------
            def self.na_read_scenes(_params)
                na_require_module(:Na__SceneSync__BuildStatus, 'Scene Sync')
                model  = na_model
                result = na_plain(GlbBuilderUtility.Na__SceneSync__BuildStatus(model))
                scenes = Array(result['scenes'])
                states = scenes.each_with_object(Hash.new(0)) { |row, counts| counts[row['syncState'].to_s] += 1 }
                result['summary'] = "#{scenes.length} SketchUp scene(s), #{result['onCount'].to_i} switched on for Scene Sync" \
                                    "#{states.empty? ? '' : " (#{states.map { |state, count| "#{count} #{state}" }.join(', ')})"}" \
                                    "#{result['lastSyncedIso'] ? "; last synced #{result['lastSyncedIso']}" : ''}."
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | The Point Cloud Tab
            # ------------------------------------------------------------
            def self.na_read_point_clouds(params)
                na_require_module(:Na__PointCloud__BuildStatus, 'Point Cloud Export')
                model  = na_model
                result = na_plain(GlbBuilderUtility.Na__PointCloud__BuildStatus(model))
                result['python'] = na_python_check if na_bool(params, 'check_python', false)
                scenes = Array(result['scenes'])
                viewer = result['viewer'].is_a?(Hash) ? result['viewer'] : {}
                result['summary'] = if viewer['available'] != true
                    "Point clouds unavailable: #{viewer['message']}"
                else
                    "Export Point Clouds is #{result['enabled'] ? 'on' : 'off'}; #{scenes.length} point cloud scene(s), " \
                    "#{result['selectedCount'].to_i} selected; cloud #{result['cloudLoaded'] ? 'loaded' : 'not loaded'}."
                end
                result
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | job / r2_inventory / fetch_r2
# -----------------------------------------------------------------------------

            # FUNCTION | The Last Job Started Through The MCP: Progress, Then Its Report
            # ------------------------------------------------------------
            def self.na_read_job(_params)
                job   = @na_job
                brief = na_job_brief(job)
                unless job
                    return {
                        'job'     => brief,
                        'summary' => brief ? 'A job started from the dialog is running; its report shows in the dialog.' :
                                             'No job has been started through the MCP in this SketchUp session, and none is running.'
                    }
                end

                recorder = job['recorder']
                report   = brief['running'] ? recorder.na_last_report : (recorder.na_final_report || recorder.na_last_report)
                r2       = recorder.na_r2
                result   = {
                    'job'      => brief,
                    'report'   => na_report(report),
                    'statuses' => recorder.na_statuses.last(8)
                }
                result['r2'] = na_r2_brief(r2) if r2

                result['summary'] = if brief['running']
                    "Job #{brief['job_id']} (#{brief['kind']}) has run #{brief['elapsed_s']} s: #{brief['status'] || 'starting'}."
                else
                    ok   = r2 ? r2['success'] == true : (report.is_a?(Hash) && report['success'] == true)
                    text = (report.is_a?(Hash) && !report['message'].to_s.empty? && !r2) ? report['message'] : (r2 ? r2['message'] : brief['status'])
                    "Job #{brief['job_id']} (#{brief['kind']}) #{ok ? 'succeeded' : 'FAILED'} after #{brief['elapsed_s']} s: #{text}"
                end
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | The Last R2 Inventory, Against The Scheme Folders Here
            # ------------------------------------------------------------
            def self.na_read_r2_inventory(params)
                g = GlbBuilderUtility
                snapshot = g.instance_variable_get(:@na_r2_inventory)
                unless snapshot.is_a?(Hash)
                    return { 'fetched' => false,
                             'summary' => 'No R2 inventory in this SketchUp session. Start one with truevision_export {action: "fetch_r2"}, then poll job.' }
                end

                model = Sketchup.active_model
                link  = model ? na_link(model) : g.Na__ProjectLink__BlankLink
                same  = link[:linked] && snapshot['project_root'] == link[:project_root]
                brief = na_r2_brief(snapshot)
                cloud = brief['folders'] || []
                local = same ? g.Na__PortalMapper__ListPhaseFolders(link[:project_root]) : []
                local_counts = local.each_with_object({}) { |folder, hash| hash[folder[:folder_name].to_s] = folder[:glb_count].to_i }
                cloud_counts = cloud.each_with_object({}) { |folder, hash| hash[folder['folder']] = folder['glb_count'] }

                result = brief.merge(
                    'fetched'        => true,
                    'for_this_model' => same,
                    'project_root'   => snapshot['project_root'].to_s,
                    'only_in_r2'     => same ? (cloud_counts.keys - local_counts.keys) : [],
                    'not_in_r2'      => same ? local_counts.select { |name, count| count > 0 && !cloud_counts.key?(name) }.keys : [],
                    'count_differs'  => same ? cloud_counts.select { |name, count| local_counts.key?(name) && local_counts[name] != count }
                                                           .map { |name, count| { 'folder' => name, 'r2' => count, 'here' => local_counts[name] } } : []
                )

                folder = na_text(params, 'folder')
                unless folder.empty?
                    objects = snapshot['folders'].is_a?(Hash) ? snapshot['folders'][folder] : nil
                    na_refuse('not_found', "No cloud folder #{folder.inspect} in the last R2 inventory.", "Cloud folders: #{cloud_counts.keys.join(', ')}.") unless objects
                    result['objects'] = Array(objects).map do |object|
                        { 'file' => File.basename(object['key'].to_s), 'size_kb' => (object['size'].to_i / 1024.0).round(1), 'modified' => object['modified'].to_s }
                    end
                end

                result['summary'] = "R2 holds #{cloud.length} scheme folder(s) for #{File.basename(snapshot['project_root'].to_s)}" \
                                    "#{same ? '' : ' (another project than this model\'s)'}" \
                                    "#{result['only_in_r2'].empty? ? '' : "; only in R2: #{result['only_in_r2'].join(', ')}"}" \
                                    "#{result['not_in_r2'].empty? ? '' : "; not pushed yet: #{result['not_in_r2'].join(', ')}"}" \
                                    "#{result['count_differs'].empty? ? '' : "; #{result['count_differs'].length} folder(s) differ in count"}."
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | Start Listing The Project's GLBs In R2 (A Job)
            # ------------------------------------------------------------
            def self.na_read_fetch_r2(_params)
                model = na_model
                na_require_link(model, 'there is no R2 folder to read')
                na_require_idle
                recorder = Na__McpDialog.new
                job = na_track('fetch_r2', recorder) { GlbBuilderUtility.Na__ProjectActions__ManageR2(recorder, 'fetch_r2', {}) }
                na_job_answer(job, recorder, 'The R2 fetch did not start.', expect_job: true)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | An R2 Report In Brief (fetch or purge)
            # ------------------------------------------------------------
            def self.na_r2_brief(report)
                return nil unless report.is_a?(Hash)

                brief = { 'success' => report['success'] == true, 'message' => report['message'].to_s }
                if report['folders'].is_a?(Hash)
                    brief['bucket']  = report['bucket'].to_s
                    brief['prefix']  = report['prefix'].to_s
                    brief['folders'] = report['folders'].map do |name, objects|
                        list = Array(objects)
                        { 'folder' => name.to_s, 'glb_count' => list.length,
                          'size_mb' => (list.sum { |object| object['size'].to_i } / 1_000_000.0).round(2),
                          'newest' => list.map { |object| object['modified'].to_s }.max }
                    end
                end
                brief['deleted']   = Array(report['deleted']).length if report.key?('deleted')
                brief['remaining'] = Array(report['remaining']).length if report.key?('remaining')
                brief['errors']    = Array(report['errors']).first(10) if report.key?('errors')
                brief['log_path']  = report['log_path'].to_s if report['log_path']
                brief
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | logs / python / config
# -----------------------------------------------------------------------------

            # FUNCTION | Cloud Sync Logs, The Last Export, And Any One Log's Tail
            # ------------------------------------------------------------
            def self.na_read_logs(params)
                dir   = File.join(Dir.tmpdir, 'Na__TrueVision__GlbBuilder__CloudSync')
                limit = [[(params['limit'] || 10).to_i, 1].max, 50].min
                logs  = Dir.exist?(dir) ? Dir.glob(File.join(dir, 'CloudSync__*.log')).sort_by { |path| File.mtime(path) }.reverse : []
                last  = GlbBuilderUtility.Na__ExportCore__LastExportSummary
                listing = logs.first(limit).map do |path|
                    { 'file' => File.basename(path), 'size_kb' => (File.size(path) / 1024.0).round(1),
                      'modified' => File.mtime(path).strftime('%d-%b-%Y %H:%M:%S') }
                end

                result = {
                    'cloud_log_folder' => dir.tr('\\', '/'),
                    'cloud_logs'       => listing,
                    'last_export'      => last ? na_plain(last) : nil
                }
                summary = "#{logs.length} cloud sync log(s) in #{dir.tr('\\', '/')}; " +
                          (last ? "last export #{last[:success] ? 'succeeded' : 'failed'}: #{last[:message].to_s.sub(/\.\z/, '')}" : 'no export in this session')

                file = na_text(params, 'file')
                unless file.empty?
                    path = file == 'last_export' ? (last && last[:log_path]) : logs.find { |item| File.basename(item) == file }
                    unless path && File.exist?(path.to_s)
                        na_refuse('not_found', "No log #{file.inspect}.", 'Pass a file name from cloud_logs, or "last_export" for the last export\'s log.')
                    end
                    lines = File.readlines(path.to_s, encoding: 'bom|utf-8')
                    tail  = [[(params['tail_lines'] || 80).to_i, 1].max, 400].min
                    text  = lines.last(tail).join.gsub(/\e\[[\d;]*m/, '')                # <-- the sync colours its output; agents read plain text
                    result['file'] = { 'path' => path.to_s.tr('\\', '/'), 'lines' => lines.length, 'tail' => text }
                    summary += "; the last #{[tail, lines.length].min} line(s) of #{File.basename(path.to_s)}"
                end

                result['summary'] = "#{summary}."
                result
            end
            # ---------------------------------------------------------------

            # FUNCTION | The Python The Pipeline And The Point Clouds Use
            # ------------------------------------------------------------
            def self.na_read_python(_params)
                check = na_python_check
                check.merge('summary' => "Python: #{check['command']} (#{check['trusted'] ? 'trusted' : 'not trusted'}); " \
                                         "Pillow with WebP #{check['pillow_webp'] ? 'ready' : "NOT ready: #{check['detail']}"}.")
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Resolve Python, And Check Pillow Can Write WebP
            # ------------------------------------------------------------
            # The Point Cloud tab's Check Python test, with one difference that
            # matters: Python writes its answer into a file itself. Inside
            # SketchUp 2026 a child process's stdout never arrives, through
            # Open3 pipes or a file redirect alike (09-Nov-2026: print("hello")
            # came back empty with exit 0), so reading stdout always said "not
            # ready" while the same Python, from a shell, wrote WebP fine.
            # ------------------------------------------------------------
            def self.na_python_check
                g       = GlbBuilderUtility
                python  = g.Na__CloudSync__ResolvePythonExecutable
                command = Array(python[:command])
                answer  = File.join(Dir.tmpdir, "Na__TrueVision__McpPythonCheck__#{Process.pid}_#{SecureRandom.hex(4)}.txt").tr('\\', '/')
                code    = "import sys\nresult = ''\ntry:\n    from PIL import Image, features\n    result = 'Pillow ok, WebP ' + str(features.check('webp'))\n" \
                          "except Exception as error:\n    result = 'ERROR ' + type(error).__name__ + ': ' + str(error)\n" \
                          "open(sys.argv[1], 'w', encoding='utf-8').write(result)\n"
                pid = Process.spawn(g.Na__CloudSync__SanitizedPythonEnv, *command, '-c', code, answer)
                Process.wait(pid)
                text   = File.exist?(answer) ? File.read(answer, encoding: 'UTF-8').strip : ''
                ready  = text.include?('WebP True')
                detail = text.empty? ? "Python exited #{$?.exitstatus} without an answer." : text
                detail = "...#{detail[-300..]}" if detail.length > 300
                { 'command' => command.join(' '), 'trusted' => python[:trusted] == true, 'note' => python[:note].to_s,
                  'pillow_webp' => ready, 'detail' => detail }
            rescue StandardError => e
                { 'command' => '', 'trusted' => false, 'note' => '', 'pillow_webp' => false, 'detail' => "#{e.class}: #{e.message}" }
            ensure
                File.delete(answer) if answer && File.exist?(answer)
            end
            # ---------------------------------------------------------------

            # FUNCTION | The Rules And Names The GLB Builder Works To
            # ------------------------------------------------------------
            def self.na_read_config(_params)
                g     = GlbBuilderUtility
                rules = {}
                {
                    'tag_ranges'           => :Na__ExportConfig__TagRanges,
                    'skip_ranges'          => :Na__ExportConfig__SkipRanges,
                    'storey_tags'          => :Na__ExportConfig__StoreyTagMap,
                    'storey_elements'      => :Na__ExportConfig__StoreyElementTagMap,
                    'storey_tag_range'     => :Na__ExportConfig__StoreyTagRange,
                    'fully_excluded_tags'  => :Na__ExportConfig__FullyExcludedTagNames,
                    'treat_as_untagged'    => :Na__ExportConfig__TreatAsUntaggedTagNames,
                    'linework_hidden_tags' => :Na__ExportConfig__LineworkHiddenTagNames,
                    'exclusion_pattern'    => :Na__ExportConfig__ExclusionPattern
                }.each { |key, name| rules[key] = na_plain(g.send(name)) if g.respond_to?(name) }

                {
                    'export_rules'   => rules,
                    'portal'         => {
                        'content_folder'     => g.Na__PortalMapper__ContentFolderName.to_s,
                        'point_cloud_folder' => g.Na__PortalMapper__PointCloudFolderName.to_s,
                        'scene_sync_folder'  => g.Na__PortalMapper__SceneSyncFolderName.to_s,
                        'site_plan_variants' => na_plain(g.Na__PortalMapper__SitePlanVariants),
                        'design_phases'      => na_plain(g.Na__PortalMapper__DesignPhases)
                    },
                    'pipeline'       => na_plain(g.Na__CloudSync__PipelineConfig),
                    'material_modes' => %w[no_materials all_materials indexed_only],
                    'file_suffixes'  => {
                        'mesh'     => (GlbBuilderUtility.const_defined?(:MESH_MODEL_SUFFIX) ? GlbBuilderUtility::MESH_MODEL_SUFFIX : nil),
                        'linework' => (GlbBuilderUtility.const_defined?(:LINEWORK_MODEL_SUFFIX) ? GlbBuilderUtility::LINEWORK_MODEL_SUFFIX : nil)
                    },
                    'summary'        => "Export rules: #{Array(rules['storey_tags']).length} storey tag(s), " \
                                        "#{rules['storey_elements'].is_a?(Hash) ? rules['storey_elements'].length : 0} storey element tag(s); " \
                                        "#{Array(g.Na__PortalMapper__DesignPhases).length} design phase(s)."
                }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end # module Na__McpOperations
    end # module GlbBuilderUtility
end # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
