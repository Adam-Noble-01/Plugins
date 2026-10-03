# =============================================================================
# NA POINT CLOUD VIEWER - APP CORE - ASYNC JOBS
# =============================================================================
#
# FILE       : Na__PointCloudViewer__AppCore__AsyncJobs__.rb
# NAMESPACE  : Na__PointCloudViewer::Na__AsyncJobs
# PURPOSE    : Runs long work as a chain of short steps on SketchUp's main
#              thread, one UI.start_timer tick per step. Between ticks
#              SketchUp pumps its message loop, so the dialog repaints its
#              loading overlay, progress updates arrive, and Cancel works.
#
# CONCURRENCY MODEL (see ARCHITECTURE.md):
#   Every step runs on the main thread, the only thread allowed to touch the
#   SketchUp API. The native LAS importer runs its heavy C++ on a worker
#   thread that never touches Ruby or SketchUp; a job step only POLLS that
#   worker's progress counters.
#
# JOB CONTRACT (duck-typed):
#   na_title          -> String for the loading overlay
#   na_step           -> Hash { 'done' => bool, 'status' => String, 'percent' => Float|nil,
#                               optional 'delay' => seconds before the next tick (polling jobs),
#                               optional 'quiet' => true to skip this tick's progress message }
#   na_cancel         -> undo any partial work (called once, on Cancel)
#   na_result_summary -> Hash pushed to the dialog when the job ends
#
# =============================================================================

module Na__PointCloudViewer
    module Na__AsyncJobs

    # -------------------------------------------------------------------------
    # REGION | State
    # -------------------------------------------------------------------------

        NA_TICK_SECONDS = 0.01

        @na_active_job       = nil   unless defined?(@na_active_job)
        @na_cancel_requested = false unless defined?(@na_cancel_requested)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        def self.Na__Jobs__Busy?
            !@na_active_job.nil?
        end

        def self.Na__Jobs__ActiveTitle
            @na_active_job ? @na_active_job.na_title : nil
        end

        def self.Na__Jobs__Start(job)
            return false if self.Na__Jobs__Busy?
            @na_active_job       = job
            @na_cancel_requested = false
            Na__DialogManager.Na__Dialog__SendProgress(job.na_title, 'Starting...', 0.0, 'running')
            self.na_schedule_tick
            true
        end

        def self.Na__Jobs__RequestCancel
            return false unless self.Na__Jobs__Busy?
            @na_cancel_requested = true
            true
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Tick Loop
    # -------------------------------------------------------------------------

        def self.na_schedule_tick(delay = NA_TICK_SECONDS)
            UI.start_timer(delay, false) { Na__PointCloudViewer::Na__AsyncJobs.na_tick }
        end

        def self.na_tick
            job = @na_active_job
            return unless job

            if @na_cancel_requested
                job.na_cancel
                return self.na_finish(job, 'cancelled', 'Cancelled. Nothing was changed.')
            end

            step = job.na_step
            if step['done']
                self.na_finish(job, 'done', step['status'])
            else
                Na__DialogManager.Na__Dialog__SendProgress(job.na_title, step['status'], step['percent'], 'running') unless step['quiet']
                self.na_schedule_tick(step['delay'] || NA_TICK_SECONDS)
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error("Job '#{job && job.na_title}' failed.", error)
            begin
                job.na_cancel if job
            rescue StandardError => cleanup_error
                Na__DebugTools.Na__Debug__Error('Job clean-up after failure also failed.', cleanup_error)
            end
            self.na_finish(job, 'failed', "#{job && job.na_title} did not finish: #{error.message}")
        end

        def self.na_finish(job, outcome, message)
            @na_active_job       = nil
            @na_cancel_requested = false
            summary = job && job.respond_to?(:na_result_summary) ? job.na_result_summary : {}
            Na__DialogManager.Na__Dialog__SendJobFinished(outcome, message.to_s, summary)
            Na__DialogManager.Na__Dialog__PushState
            nil
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
