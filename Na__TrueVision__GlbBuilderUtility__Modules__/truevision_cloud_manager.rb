require 'securerandom'
require 'fileutils'

module TrueVision3D
  module GlbBuilderUtility
    def self.Na__CloudSync__Execute(interpreter, script_path, script_args, working_dir, stdin_data = nil)
      dir = File.join(Dir.tmpdir, 'Na__TrueVision__GlbBuilder__CloudSync')
      FileUtils.mkdir_p(dir)
      stem = File.join(dir, SecureRandom.hex(12))
      request_path, result_path = stem + '.request.json', stem + '.result.json'
      command = Array(interpreter) + [script_path] + Array(script_args)
      File.write(request_path, { executable: command.first, arguments: command.drop(1),
        cwd: working_dir, stdin: stdin_data, result: result_path }.to_json)
      powershell = File.join(ENV.fetch('SystemRoot', 'C:/Windows'), 'System32/WindowsPowerShell/v1.0/powershell.exe')
      pid = Process.spawn(self.Na__CloudSync__SanitizedPythonEnv, powershell,
        '-NoLogo', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass', '-File', File.join(__dir__, 'truevision_process.ps1'),
        '-RequestPath', request_path, out: stem + '.launcher.log', err: [:child, :out])
      # Explicitly yield back to SketchUp. Never wait on a Ruby worker thread:
      # the embedded interpreter can stop scheduling it when the callback returns.
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1830
      until File.exist?(result_path)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise 'PowerShell did not report completion within 30 minutes. Check the job logs before retrying.'
        end
        begin
          exited = Process.waitpid(pid, Process::WNOHANG)
          raise 'PowerShell exited without a result file. Check its launcher log.' if exited && !File.exist?(result_path)
        rescue Errno::ECHILD
          raise 'PowerShell ended without a result file.' unless File.exist?(result_path)
        end
        Fiber.yield
      end
      begin
        Process.waitpid(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        # Already reaped during polling.
      end
      result = JSON.parse(File.read(result_path, encoding: 'bom|utf-8'), symbolize_names: true)
      result[:success] = result[:exit_code] == 0
      result[:log_path] = self.Na__CloudSync__WriteDebugLog(command.join(' '), result[:exit_code], result[:stdout], result[:stderr])
      result
    rescue => e
      { success: false, exit_code: nil, stdout: '', stderr: e.message }
    ensure
      [request_path, result_path].compact.each { |p| File.delete(p) if File.exist?(p) }
    end

    def self.Na__CloudSync__Worker(link, action, extra = {})
      script_dir = self.Na__CloudSync__ScriptDirectory(link[:portal_root])
      request = { action: action, project: link[:project_folder],
        year: File.basename(File.dirname(link[:project_root])),
        sync_script: File.join(script_dir, self.Na__CloudSync__PipelineConfig['R2SyncScriptName']) }.merge(extra)
      stem = File.join(Dir.tmpdir, 'truevision-r2-' + SecureRandom.hex(12))
      input, output = stem + '.json', stem + '.report.json'
      File.write(input, request.to_json)
      result = self.Na__CloudSync__Execute(self.Na__CloudSync__ResolvePythonExecutable[:command],
        File.join(__dir__, 'truevision_r2_worker.py'), [input, output], script_dir)
      report = File.exist?(output) ? JSON.parse(File.read(output), symbolize_names: false) :
        { 'success' => false, 'message' => self.Na__CloudSync__DescribeFailure(result) }
      audit = self.Na__CloudSync__WriteDebugLog("R2 #{action}: #{link[:project_folder]}", result[:exit_code], JSON.pretty_generate(report), result[:stderr])
      report['log_path'] = audit
      [report, result]
    ensure
      [input, output].compact.each { |p| File.delete(p) if File.exist?(p) }
    end

    def self.Na__CloudSync__RunR2Sync(interpreter, script_dir, project_folder, dry_run)
      # Explicit API auto-confirm avoids injecting answers into an interactive CLI.
      stem = File.join(Dir.tmpdir, 'truevision-sync-' + SecureRandom.hex(12))
      input, output = stem + '.json', stem + '.report.json'
      File.write(input, {action: 'sync', project: project_folder, dry_run: dry_run,
        sync_script: File.join(script_dir, self.Na__CloudSync__PipelineConfig['R2SyncScriptName'])}.to_json)
      result = self.Na__CloudSync__Execute(interpreter, File.join(__dir__, 'truevision_r2_worker.py'), [input, output], script_dir)
      self.Na__CloudSync__DescribeR2Outcome(result, project_folder, dry_run)
    ensure
      [input, output].compact.each { |p| File.delete(p) if File.exist?(p) }
    end

    # The Fiber is cooperatively resumed by UI.start_timer on the main thread.
    # It only preserves the build -> sync call stack between file polls; it is
    # not an OS/Ruby background thread and never invokes SketchUp from one.
    def self.Na__ProjectActions__CloudJob(dialog, work, complete)
      return if @na_cloud_job
      self.Na__UserInterface__PushStatus(dialog, 'Working with R2 through PowerShell...', 'info')
      dialog.execute_script('window.Na__Tvgb__LockR2 && window.Na__Tvgb__LockR2(true);')
      job = { fiber: Fiber.new { work.call }, timer: nil, finishing: false }
      @na_cloud_job = job
      job[:timer] = UI.start_timer(0.2, true) do
        next unless @na_cloud_job.equal?(job)
        next if job[:finishing]
        begin
          result = job[:fiber].resume
          unless job[:fiber].alive?
            job[:finishing] = true
            self.Na__ProjectActions__FinishCloudJob(job, dialog, complete, result)
          end
        rescue => e
          job[:finishing] = true
          failure = { 'success' => false, 'message' => e.message,
                      success: false, message: e.message }
          self.Na__ProjectActions__FinishCloudJob(job, dialog, complete, failure)
        end
      end
    rescue => e
      @na_cloud_job = nil
      self.Na__UserInterface__PushStatus(dialog, "Could not start R2 operation: #{e.message}", 'error')
      self.Na__UserInterface__PushProjectStatus(dialog)
    end

    def self.Na__ProjectActions__FinishCloudJob(job, dialog, complete, result)
      # Release ownership before invoking UI callbacks; a closed dialog or an
      # exception while rendering must never strand the global busy flag.
      @na_cloud_job = nil if @na_cloud_job.equal?(job)
      UI.stop_timer(job[:timer]) if job[:timer]
      begin
        complete.call(result)
      rescue => e
        self.Na__UserInterface__PushStatus(dialog, "R2 finished, but its report could not be displayed: #{e.message}", 'error')
      ensure
        self.Na__UserInterface__PushProjectStatus(dialog)
      end
    end

    def self.Na__ProjectActions__ManageR2(dialog, action, params)
      link = self.Na__ProjectLink__Read(Sketchup.active_model).dup
      return self.Na__UserInterface__PushStatus(dialog, 'Link a project first.', 'warning') unless link[:linked]
      extra = {}
      if action == 'purge_r2_folder'
        snapshot = @na_r2_inventory
        folder = params['cloudFolder'].to_s
        objects = snapshot && snapshot['folders'] && snapshot['folders'][folder]
        unless snapshot && snapshot['project_root'] == link[:project_root] && objects && !objects.empty?
          self.Na__UserInterface__PushStatus(dialog, 'Fetch R2 and select a non-empty cloud folder first.', 'warning')
          self.Na__UserInterface__PushProjectStatus(dialog)
          return
        end
        prefix = snapshot['prefix'] + folder + '/'
        # The dialog's own confirmation modal asks for the project code and only
        # then dispatches. Re-checked here so a UI fault cannot purge by itself.
        typed = params['typedConfirmation'].to_s.strip.upcase
        code  = link[:project_code].to_s.upcase
        if code.empty? || typed != code
          self.Na__UserInterface__PushStatus(dialog, "R2 purge cancelled: the code typed did not match #{code}.", 'info')
          self.Na__UserInterface__PushProjectStatus(dialog)
          return
        end
        extra = {folder: folder, objects: objects, bucket: snapshot['bucket'], prefix: prefix}
      end
      @na_r2_inventory = nil
      self.Na__ProjectActions__CloudJob(dialog,
        proc { self.Na__CloudSync__Worker(link, action == 'fetch_r2' ? 'fetch' : 'purge', extra).first },
        proc do |report|
          if report['success'] && report['folders']
            report['project_root'] = link[:project_root]
            @na_r2_inventory = report
          end
          dialog.execute_script("window.Na__Tvgb__ReceiveR2(#{report.to_json});")
          self.Na__UserInterface__PushStatus(dialog, report['message'], report['success'] ? 'success' : 'error')
        end)
    end
  end
end
