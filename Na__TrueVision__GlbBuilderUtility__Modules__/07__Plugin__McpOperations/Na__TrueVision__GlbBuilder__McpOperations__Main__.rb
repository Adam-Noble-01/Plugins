# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MCP OPERATIONS (AGENT SEAM)
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__McpOperations__Main__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Na__McpOperations
# AUTHOR     : Adam Noble - Noble Architecture
# CREATED    : 09-Nov-2026 (GLB Builder 2.14.0)
# PURPOSE    : Everything the GLB Builder dialog does, for an agent working
#              through Adam's Na SketchUp MCP plugin (its tools
#              truevision_export, truevision_export_edit and
#              truevision_publish). The MCP handlers are thin: they call the
#              three entry points below and pass refusals on.
#
# ENTRY POINTS:
# - Na__McpOperations.Na__GlbBuilder__McpRead(action, params)
#     reads only: status, manifest, project, site plan, scenes, point clouds,
#     jobs, the R2 inventory, logs, Python, the export rules
# - Na__McpOperations.Na__GlbBuilder__McpEdit(action, params)
#     changes this model and this computer's files: exports, the project link,
#     scheme folders, site plan stores, Scene Sync and point cloud settings
# - Na__McpOperations.Na__GlbBuilder__McpPublish(action, params)
#     reaches the live site: pushes to Cloudflare R2, the R2 purge, the build
#     pipeline
# - Na__McpOperations.Na__GlbBuilder__McpActions lists the actions of each.
# - Refusals raise Na__McpOperationsError (code, message, hint, details).
#
# WHAT IT REUSES (no second copy of any rule):
# - The dialog's own action handlers run unchanged (Export To Project, Push,
#   Fetch and Purge R2, the point cloud and Scene Sync jobs, link, scheme and
#   site plan store actions), handed Na__McpDialog: a stand-in for the dialog
#   that records the status lines and reports they push. Every script is also
#   passed on to the real dialog when it is open, so Adam's dialog shows what
#   the agent did, and locks while a job runs, as if he had clicked.
# - Scene Sync and point cloud settings go through Na__SceneSync__* and
#   Na__PointCloud__*, which return structured results of their own.
#
# NEVER A MESSAGE BOX:
# A modal stops SketchUp, and the MCP bridge with it, until someone clicks.
# Nothing here takes a path that asks: folders are parameters, never pickers;
# the site plan's "delete the older files?" question is answered by the
# 'stale' parameter (Na__SitePlan__Write on_stale:); Reload Scripts runs quiet
# (Na__DynamicReloader__ReloadAllScripts quiet:). Create Standardised Tags
# always shows a message box, so it is not offered: the MCP's tag_manage
# {action: "create_standard"} makes the same tags from the same SSOT.
#
# JOBS:
# R2 work (push, dry run, fetch, purge) and the point cloud render run as the
# dialog's CloudJob: a Fiber resumed by a UI timer, one job at a time. The call
# that starts one answers at once with the job; McpRead 'job' reports its
# progress and, when it has ended, its report. Nothing ever waits inside a
# call: SketchUp runs the bridge and the job's timer on one thread, so waiting
# would stop the very job it waits for.
#
# GATES (on top of the MCP client's own permission settings):
# - Anything that publishes (every McpPublish action except push_dry_run) or
#   deletes (a scheme folder, an R2 folder, files an export would otherwise
#   archive, older site plan files) needs params 'confirm' set to the linked
#   project's code: the same gate the dialog's modals use.
# - Exports refuse while a group or component is open: the exporter reads
#   model.active_entities, so it would write only what is inside it.
# - Every export and every job refuses while another job runs.
#
# UNDO:
# Settings written to the model (link, target folder, file toggles, site plan
# store, portal root) are one undo step each, named "TrueVision: ..."; the
# Scene Sync and point cloud settings open their own, named the same way.
#
# LOADING:
# Na__TrueVision__GlbBuilder__Main__.rb loads this file with `load`, not
# require, so the hot reloader (which re-loads Main) refreshes it as well. It
# loads its three parts the same way. Nothing runs at load time.
#
# PARAMS ARRIVE STRING-KEYED; a key sent as null counts as not given.
# RESULTS ARE STRING-KEYED, with a one-line 'summary' and optional 'warnings'.
#
# =============================================================================

require 'json'
require 'open3'
require 'fileutils'
require 'securerandom'
require 'tmpdir'

module TrueVision3D
    module GlbBuilderUtility

# -----------------------------------------------------------------------------
# REGION | Refusal Type
# -----------------------------------------------------------------------------

        # CLASS | A Refusal The MCP Handler Passes On With Its Fix
        # ------------------------------------------------------------
        class Na__McpOperationsError < StandardError
            attr_reader :na_code, :na_hint, :na_details

            def initialize(code, message, hint = nil, details = nil)
                super(message)
                @na_code    = code.to_s
                @na_hint    = hint
                @na_details = details
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        module Na__McpOperations

# -----------------------------------------------------------------------------
# REGION | The Recording Dialog
# -----------------------------------------------------------------------------

            # CLASS | A Stand-In For The Dialog That Remembers What It Was Told
            # ------------------------------------------------------------
            # The action handlers talk to their dialog only through
            # execute_script. This answers that call, reads the status lines,
            # report panels and R2 reports out of the scripts (the shapes
            # Na__UserInterface__PushStatus, PushReport and ManageR2 write),
            # and hands every script on to the real dialog while it is open.
            # ------------------------------------------------------------
            class Na__McpDialog
                attr_reader :na_statuses, :na_reports, :na_r2, :na_finished_at

                def initialize
                    @na_statuses    = []
                    @na_reports     = []
                    @na_r2          = nil
                    @na_finished_at = nil
                end

                # A job has just started: what came before it is not its end.
                def na_job_started
                    @na_finished_at = nil
                end

                def execute_script(script)
                    text = script.to_s
                    na_record(text)
                    real = TrueVision3D::GlbBuilderUtility.instance_variable_get(:@export_dialog)
                    real.execute_script(text) if real && !real.equal?(self) && real.visible?
                    true
                rescue StandardError
                    true
                end

                def visible?
                    true
                end

                # The last status line: { 'text', 'variant', 'at' }, or nil.
                def na_last_status
                    @na_statuses.last
                end

                # The last report panel pushed, or nil.
                def na_last_report
                    @na_reports.last
                end

                # The last report that is not "running", or nil.
                def na_final_report
                    @na_reports.reverse.find { |report| report['running'] != true }
                end

                # True when the last status line is an error or a warning.
                def na_failed?
                    status = na_last_status
                    !status.nil? && %w[error warning].include?(status['variant'])
                end

                private

                def na_record(text)
                    if (match = text.match(/\Awindow\.Na__Tvgb__ReceiveReport && window\.Na__Tvgb__ReceiveReport\((.*)\);\s*\z/m))
                        report = JSON.parse(match[1])
                        @na_reports << report
                        @na_reports.shift while @na_reports.length > 6
                        @na_finished_at = Time.now unless report['running'] == true
                    elsif (match = text.match(/\Awindow\.Na__Tvgb__ReceiveR2\((.*)\);\s*\z/m))
                        @na_r2 = JSON.parse(match[1])
                        @na_finished_at = Time.now
                    elsif text.include?("getElementById('naTvgbStatus')")
                        status  = text[/^\s*el[.]textContent = (.*);\s*$/, 1]
                        variant = text[/naTvgb__Status--' \+ (".*?");\s*$/, 1]
                        return unless status

                        @na_statuses << {
                            'text'    => JSON.parse("[#{status}]").first.to_s,
                            'variant' => variant ? JSON.parse("[#{variant}]").first.to_s : 'info',
                            'at'      => Time.now.strftime('%H:%M:%S')
                        }
                        @na_statuses.shift while @na_statuses.length > 30
                    end
                rescue StandardError
                    nil
                end
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Read-Only Actions (truevision_export)
            # ------------------------------------------------------------
            def self.Na__GlbBuilder__McpRead(action, params)
                na_dispatch(:read, action, params)
            end
            # ---------------------------------------------------------------

            # FUNCTION | Local Changes: This Model And This Computer (truevision_export_edit)
            # ------------------------------------------------------------
            def self.Na__GlbBuilder__McpEdit(action, params)
                na_dispatch(:edit, action, params)
            end
            # ---------------------------------------------------------------

            # FUNCTION | The Live Site: R2 And The Build Pipeline (truevision_publish)
            # ------------------------------------------------------------
            def self.Na__GlbBuilder__McpPublish(action, params)
                na_dispatch(:publish, action, params)
            end
            # ---------------------------------------------------------------

            # FUNCTION | The Actions Each Entry Point Answers
            # ------------------------------------------------------------
            def self.Na__GlbBuilder__McpActions
                {
                    'read'    => na_action_table(:read).keys,
                    'edit'    => na_action_table(:edit).keys,
                    'publish' => na_action_table(:publish).keys
                }
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dispatch
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Action Name To Method, Per Entry Point
            # ------------------------------------------------------------
            def self.na_action_table(kind)
                case kind
                when :read
                    {
                        'status'       => :na_read_status,
                        'manifest'     => :na_read_manifest,
                        'project'      => :na_read_project,
                        'site_plan'    => :na_read_site_plan,
                        'scenes'       => :na_read_scenes,
                        'point_clouds' => :na_read_point_clouds,
                        'job'          => :na_read_job,
                        'r2_inventory' => :na_read_r2_inventory,
                        'fetch_r2'     => :na_read_fetch_r2,
                        'logs'         => :na_read_logs,
                        'python'       => :na_read_python,
                        'config'       => :na_read_config
                    }
                when :edit
                    {
                        'export_folder'            => :na_edit_export_folder,
                        'export_project'           => :na_edit_export_project,
                        'select_files'             => :na_edit_select_files,
                        'link_project'             => :na_edit_link_project,
                        'unlink_project'           => :na_edit_unlink_project,
                        'dismiss_link_prompt'      => :na_edit_dismiss_link_prompt,
                        'set_portal_root'          => :na_edit_set_portal_root,
                        'set_target'               => :na_edit_set_target,
                        'create_scheme'            => :na_edit_create_scheme,
                        'duplicate_scheme'         => :na_edit_duplicate_scheme,
                        'delete_scheme'            => :na_edit_delete_scheme,
                        'set_site_plan_store'      => :na_edit_set_site_plan_store,
                        'create_site_plan_store'   => :na_edit_create_site_plan_store,
                        'export_site_plan'         => :na_edit_export_site_plan,
                        'switch_scenes'            => :na_edit_switch_scenes,
                        'set_scene_type'           => :na_edit_set_scene_type,
                        'detach_scene'             => :na_edit_detach_scene,
                        'write_scenes'             => :na_edit_write_scenes,
                        'switch_point_clouds'      => :na_edit_switch_point_clouds,
                        'select_point_cloud_scenes' => :na_edit_select_point_cloud_scenes,
                        'set_point_cloud_scene'    => :na_edit_set_point_cloud_scene,
                        'order_point_cloud_scenes' => :na_edit_order_point_cloud_scenes,
                        'reload_point_cloud'       => :na_edit_reload_point_cloud,
                        'export_point_clouds'      => :na_edit_export_point_clouds,
                        'open_dialog'              => :na_edit_open_dialog,
                        'reload'                   => :na_edit_reload
                    }
                when :publish
                    {
                        'push_dry_run'                 => :na_publish_push_dry_run,
                        'push'                         => :na_publish_push,
                        'export_and_push'              => :na_publish_export_and_push,
                        'write_scenes_and_push'        => :na_publish_write_scenes_and_push,
                        'export_point_clouds_and_push' => :na_publish_export_point_clouds_and_push,
                        'purge_r2_folder'              => :na_publish_purge_r2_folder,
                        'open_pipeline'                => :na_publish_open_pipeline
                    }
                else
                    {}
                end
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Run One Action, Faults Turned Into Refusals
            # ------------------------------------------------------------
            def self.na_dispatch(kind, action, params)
                params = na_present(params)
                table  = na_action_table(kind)
                method_name = table[action.to_s]
                unless method_name && respond_to?(method_name)
                    tool = { read: 'truevision_export', edit: 'truevision_export_edit', publish: 'truevision_publish' }[kind]
                    na_refuse('invalid_params', "Unknown #{tool} action '#{action}'.", "Use one of: #{table.keys.join(', ')}.")
                end
                send(method_name, params)
            rescue Na__McpOperationsError
                raise
            rescue StandardError => e
                if GlbBuilderUtility.respond_to?(:Na__Log__Warn)
                    GlbBuilderUtility.Na__Log__Warn("[GlbBuilder MCP] #{kind} #{action} failed: #{e.class}: #{e.message}")
                end
                raise Na__McpOperationsError.new('glb_builder_error', "The GLB Builder failed: #{e.class}: #{e.message}",
                                                 'See the Ruby Console. If the GLB Builder was just updated, use its Reload Scripts (truevision_export_edit {action: "reload"}).',
                                                 { 'backtrace' => Array(e.backtrace).first(6) })
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Drop Keys Sent As null
            # ------------------------------------------------------------
            def self.na_present(params)
                return {} unless params.is_a?(Hash)

                params.each_with_object({}) { |(key, value), hash| hash[key.to_s] = value unless value.nil? }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Raise A Refusal
            # ------------------------------------------------------------
            def self.na_refuse(code, message, hint = nil, details = nil)
                raise Na__McpOperationsError.new(code, message, hint, details)
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Parameters
# -----------------------------------------------------------------------------

            def self.na_text(params, key, default = '')
                value = params[key.to_s]
                value.nil? ? default : value.to_s.strip
            end

            def self.na_bool(params, key, default = false)
                return default unless params.key?(key.to_s)

                value = params[key.to_s]
                return value if value == true || value == false

                na_refuse('invalid_params', "'#{key}' must be true or false, got #{value.inspect}.")
            end

            def self.na_required_text(params, key, hint = nil)
                text = na_text(params, key)
                na_refuse('invalid_params', "Missing '#{key}'.", hint) if text.empty?
                text
            end

            def self.na_choice(params, key, allowed, default)
                text = na_text(params, key, default.to_s)
                return text if allowed.include?(text)

                na_refuse('invalid_params', "'#{key}' is #{text.inspect}; it must be one of: #{allowed.join(', ')}.")
            end

            # An absolute folder path, with forward slashes.
            def self.na_absolute_path(params, key)
                path = na_required_text(params, key, "Pass '#{key}' as an absolute folder path, e.g. \"D:/Exports/RB05\".").tr('\\', '/')
                unless path.match?(%r{\A([A-Za-z]:/|//)})
                    na_refuse('invalid_params', "'#{key}' must be an absolute path (a drive letter or a network share), got #{path.inspect}.")
                end
                path.sub(%r{/+\z}, '')
            end

            # The material options both exports take, as the dialog sends them.
            def self.na_export_options(params)
                {
                    'materialExportMode' => na_choice(params, 'material_mode', %w[no_materials all_materials indexed_only], 'no_materials'),
                    'downscaleTextures'  => na_bool(params, 'downscale_textures', false)
                }
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Guards
# -----------------------------------------------------------------------------

            def self.na_model
                model = Sketchup.active_model
                na_refuse('no_model', 'No model is open in this SketchUp window.') unless model
                model
            end

            def self.na_link(model)
                GlbBuilderUtility.Na__ProjectLink__Read(model)
            end

            def self.na_require_link(model, why)
                link = na_link(model)
                return link if link[:linked]

                na_refuse('not_linked', "This model is not linked to a TrueVision project, so #{why}.",
                          'Link it first: truevision_export_edit {action: "link_project", project_code: "RB05"}.')
            end

            def self.na_require_project_here(link)
                missing = GlbBuilderUtility.Na__PortalMapper__MissingProjectMessage(link[:project_root])
                return unless missing

                na_refuse('project_missing', missing.to_s,
                          'truevision_export {action: "project"} shows the portal root in use; set another with truevision_export_edit {action: "set_portal_root"}.')
            end

            # The exporter reads model.active_entities: an open group would be all it writes.
            def self.na_require_model_root(model)
                path = model.active_path
                return if path.nil? || path.empty?

                na_refuse('context_error', 'A group or component is open for editing. The GLB Builder exports model.active_entities, so it would write only what is inside it.',
                          'Close it first: context_set {action: "close_all"}.')
            end

            def self.na_require_idle
                return unless na_cloud_job

                na_refuse('busy', 'A GLB Builder job (R2 or point clouds) is already running; it runs one at a time.',
                          'Poll truevision_export {action: "job"} until it has ended, then try again.')
            end

            # The dialog's own deliberation gate: the project code, typed back.
            def self.na_require_confirm(link, params, what)
                code  = link[:project_code].to_s.upcase
                typed = na_text(params, 'confirm').upcase
                return if !code.empty? && typed == code

                na_refuse('confirmation_required', "#{what} needs 'confirm' set to the linked project's code (#{code}).",
                          "Only once the user has asked for exactly this: pass confirm: \"#{code}\".")
            end

            def self.na_require_module(method_name, what)
                return if GlbBuilderUtility.respond_to?(method_name)

                na_refuse('unsupported', "The GLB Builder's #{what} module is not loaded in this SketchUp.",
                          'Check the Ruby Console for its load error, then use Reload Scripts (truevision_export_edit {action: "reload"}).')
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Undo, Jobs And The Real Dialog
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | One Undo Step Around A Model Change
            # ------------------------------------------------------------
            # The block answers [result, ok]. Not ok aborts the step, so a
            # refused action leaves nothing half-written in the model.
            # ------------------------------------------------------------
            def self.na_operation(model, name)
                model.start_operation("TrueVision: #{name}", true)
                result, ok = yield
                ok ? model.commit_operation : model.abort_operation
                result
            rescue StandardError
                model.abort_operation rescue nil
                raise
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Run A Dialog Handler With The Recorder, In One Undo Step
            # ------------------------------------------------------------
            # A handler that ends on an error or warning status is refused with
            # that status as the message, and its model change is undone.
            # ------------------------------------------------------------
            def self.na_handler(model, undo_name, code)
                recorder = Na__McpDialog.new
                na_operation(model, undo_name) do
                    yield recorder
                    [recorder, !recorder.na_failed?]
                end
                if recorder.na_failed?
                    status = recorder.na_last_status
                    na_refuse(code, status['text'].to_s)
                end
                recorder
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The Dialog's Running Job, Or nil
            # ------------------------------------------------------------
            def self.na_cloud_job
                GlbBuilderUtility.instance_variable_get(:@na_cloud_job)
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Run Something That May Start A Job, And Remember It
            # ------------------------------------------------------------
            def self.na_track(kind, recorder)
                before = na_cloud_job
                yield
                after = na_cloud_job
                return nil unless after && !after.equal?(before)

                recorder.na_job_started
                @na_job = { 'id' => SecureRandom.hex(4), 'kind' => kind, 'started' => Time.now,
                            'handle' => after, 'recorder' => recorder, 'finished' => nil }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The Last Job Started Here, In Brief
            # ------------------------------------------------------------
            def self.na_job_brief(job = @na_job)
                handle = na_cloud_job
                unless job
                    return handle ? { 'running' => true, 'started_by' => 'dialog' } : nil
                end

                running = !handle.nil? && handle.equal?(job['handle'])
                job['finished'] ||= (job['recorder'].na_finished_at || Time.now) unless running
                status = job['recorder'].na_last_status
                {
                    'job_id'            => job['id'],
                    'kind'              => job['kind'],
                    'running'           => running,
                    'started'           => job['started'].strftime('%d-%b-%Y %H:%M:%S'),
                    'elapsed_s'         => ((job['finished'] || Time.now) - job['started']).round,
                    'status'            => status && status['text'],
                    'status_variant'    => status && status['variant'],
                    'other_job_running' => !running && !handle.nil?
                }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | What A Call That May Start A Job Answers
            # ------------------------------------------------------------
            # expect_job: the call exists to start one (a push, a fetch), so
            # not starting is a refusal even when no error status was pushed.
            # ------------------------------------------------------------
            def self.na_job_answer(job, recorder, done_summary, expect_job: false)
                if job
                    status = recorder.na_last_status
                    text   = status ? status['text'].to_s.strip : 'running'
                    text  += '.' unless text.end_with?('.', '!', '?')
                    return {
                        'job'     => na_job_brief(job),
                        'report'  => na_report(recorder.na_last_report),
                        'summary' => "Started job #{job['id']} (#{job['kind']}): #{text} " \
                                     'Poll truevision_export {action: "job"} about every 10 s until running is false.'
                    }
                end

                if recorder.na_failed? || expect_job
                    report = recorder.na_final_report
                    status = recorder.na_last_status
                    na_refuse(recorder.na_failed? ? 'glb_builder_refused' : 'job_not_started',
                              status ? status['text'].to_s : done_summary, nil,
                              report ? { 'report' => na_report(report) } : nil)
                end

                report = recorder.na_final_report
                status = recorder.na_last_status
                summary = if report && !report['message'].to_s.empty? then report['message'].to_s
                          elsif status then status['text'].to_s
                          else done_summary
                          end
                { 'report' => na_report(report), 'summary' => summary }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | A Report Panel As Plain Data
            # ------------------------------------------------------------
            def self.na_report(report)
                return nil unless report.is_a?(Hash)

                {
                    'success' => report['success'],
                    'running' => report['running'] == true,
                    'message' => report['message'].to_s,
                    'steps'   => Array(report['steps']).map do |step|
                        {
                            'label'   => step['label'].to_s,
                            'status'  => step['status'] || (step['success'] == true ? 'ok' : (step['success'] == false ? 'failed' : 'info')),
                            'message' => step['message'].to_s
                        }
                    end
                }
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The Real Dialog When It Is Open, Else nil
            # ------------------------------------------------------------
            def self.na_real_dialog
                dialog = GlbBuilderUtility.instance_variable_get(:@export_dialog)
                dialog && dialog.visible? ? dialog : nil
            rescue StandardError
                nil
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Bring An Open Dialog Up To Date After A Change
            # ------------------------------------------------------------
            def self.na_refresh_dialog
                dialog = na_real_dialog
                return unless dialog

                GlbBuilderUtility.Na__UserInterface__PushModelStatus(dialog)
                GlbBuilderUtility.Na__UserInterface__PushProjectStatus(dialog)
            rescue StandardError
                nil
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Shared Readers
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Symbols, Times And Ranges Made Plain For JSON
            # ------------------------------------------------------------
            def self.na_plain(value)
                case value
                when Hash   then value.each_with_object({}) { |(key, item), hash| hash[key.to_s] = na_plain(item) }
                when Array  then value.map { |item| na_plain(item) }
                when Range  then value.to_a
                when Regexp then value.source
                when Symbol then value.to_s
                when Time   then value.strftime('%Y-%m-%dT%H:%M:%S%z')
                when String, Numeric, true, false, nil then value
                else value.to_s
                end
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The GLB Builder's Version, From Its DevLog
            # ------------------------------------------------------------
            def self.na_version
                path = File.join(GlbBuilderUtility::NA_PLUGIN_ROOT, 'Na__TrueVision__GlbBuilder__Doc__DevLog__.md')
                return nil unless File.exist?(path)

                File.foreach(path, encoding: 'UTF-8').first(80).each do |line|
                    match = line.match(/GLB Builder Utility - Version (\d+\.\d+\.\d+)/)
                    return match[1] if match
                end
                nil
            rescue StandardError
                nil
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The Export Manifest, Read Without Writing
            # ------------------------------------------------------------
            # BuildModelStatus forgets toggles for files the model no longer
            # makes; a read must not write, so it is asked not to (prune:).
            # ------------------------------------------------------------
            def self.na_model_status
                method = GlbBuilderUtility.method(:Na__UserInterface__BuildModelStatus)
                method.parameters.any? { |_, name| name == :prune } ? method.call(prune: false) : method.call
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Every File Name The Model Exports
            # ------------------------------------------------------------
            def self.na_manifest_rows(status)
                Array(status[:groups]).flat_map do |group|
                    label = group[:label].to_s.empty? ? 'Flat files' : group[:label].to_s
                    Array(group[:rows]).map do |row|
                        { 'name' => row[:name].to_s, 'group' => label, 'meta' => row[:meta].to_s, 'selected' => row[:selected] == true }
                    end
                end
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | A Scene By Persistent Id Or Name
            # ------------------------------------------------------------
            def self.na_page(model, reference)
                pages = model.pages.to_a
                text  = reference.to_s.strip
                page  = pages.find { |item| item.persistent_id.to_s == text } ||
                        pages.find { |item| item.name == text } ||
                        pages.find { |item| item.name.casecmp?(text) }
                return page if page

                na_refuse('not_found', "No scene #{reference.inspect} in this model.",
                          "Scenes: #{pages.first(20).map { |item| "#{item.name} (#{item.persistent_id})" }.join(', ')}.")
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

        end # module Na__McpOperations
    end # module GlbBuilderUtility
end # module TrueVision3D

# -----------------------------------------------------------------------------
# REGION | Parts (loaded, not required, so Reload Scripts refreshes them)
# -----------------------------------------------------------------------------

%w[Read Edit Publish].each do |na_part|
    load File.join(__dir__, "Na__TrueVision__GlbBuilder__McpOperations__#{na_part}__.rb")
end

# endregion -------------------------------------------------------------------

# =============================================================================
# END OF FILE
# =============================================================================
