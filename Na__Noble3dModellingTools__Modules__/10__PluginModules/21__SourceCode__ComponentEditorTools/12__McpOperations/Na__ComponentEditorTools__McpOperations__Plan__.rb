# =============================================================================
# NA COMPONENT EDITOR TOOLS - MCP OPERATIONS | LIBRARY CHANGE PLANS
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__McpOperations__Plan__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__McpLibraryPlan
# PURPOSE    : Every change the agent makes to the library runs here as a plan
#              of steps: checked as a whole first, applied in order with a
#              journal, and revertible to the exact original files.
# CREATED    : 2026
#
# STEP OPS (paths absolute, relative to the library root, or relative to the
# default set):
#   create_folder   {path}
#   rename_folder   {from, to}
#   move_file       {from, to}          any file (.skb, notes...); never opened
#   archive_file    {from, to}          zip into the set's 00__Archive as
#                   <name>__30-Sep-2026.zip (to is optional); the original
#                   moves into the journal, so revert puts it back
#   rename_asset    {from, to, def_name, library_data, description}
#                   the .skp is renamed on disk AND the component inside is
#                   renamed; def_name "auto" (default) = the new file name
#   update_asset    {path, library_data, description, def_name}
#   save_definition internal: asset_library_edit save (a definition object)
#
# CHECKED FIRST (a dry run is the default for apply_plan):
# The whole plan is played on a virtual copy of the library's file list, so a
# clash at step 40 stops the plan before step 1 runs: sources exist, targets
# are free (case-insensitive, as on Windows), names follow the convention,
# components are not placed in the open model, and no code ends up used twice
# by a file this plan touches.
#
# JOURNAL (<library root>/00__Archive/00__McpLibraryJournals/<id>/):
# The plan, every finished step, and a byte copy of each .skp before it is
# rewritten (backup/). revert walks the finished steps backwards: moves go
# back and rewritten files get their original bytes. Nothing is deleted: a
# file created by save moves into the journal's removed/ folder.
#
# TIME BUDGET:
# A call stops cleanly between steps after time_budget_s (default 45 s);
# apply_plan with journal carries on from there.
#
# =============================================================================

require 'json'
require 'fileutils'

module Na__ComponentEditorTools
    module Na__McpLibraryPlan

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPS                   = %w[create_folder rename_folder move_file archive_file rename_asset update_asset save_definition].freeze
        NA_ASSET_OPS             = %w[rename_asset update_asset save_definition].freeze
        NA_MAX_STEPS             = 500
        NA_DEFAULT_TIME_BUDGET_S = 45
        NA_JOURNAL_FILE          = 'Na__LibraryJournal__.json'.freeze
        NA_DEFAULT_JOURNAL_DIR   = '00__Archive/00__McpLibraryJournals'.freeze
        # SketchUp's Ruby cannot open a path longer than Windows' MAX_PATH (260 with
        # the terminator), found the hard way on 30-Sep-2026 by a journal backup.
        NA_MAX_PATH              = 259

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # apply_plan: {plan | plan_file | journal, dry_run (default true),
        # time_budget_s, allow_duplicate_codes}. journal continues a paused or
        # failed journal.
        def self.Na__ComponentEditorTools__ApplyPlan(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            journal_ref = params['journal'].to_s.strip
            return self.Na__ComponentEditorTools__Continue(root, journal_ref, params) unless journal_ref.empty?

            plan = self.Na__ComponentEditorTools__PlanFromParams(params)
            dry_run = params.key?('dry_run') ? params['dry_run'] == true : true
            self.Na__ComponentEditorTools__Run(root, plan, params, dry_run)
        end

        # Single edits (save, rename, move, update, create_folder) arrive as a
        # one-step plan and apply unless dry_run is true.
        def self.Na__ComponentEditorTools__RunSteps(steps, params, title_text)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            self.Na__ComponentEditorTools__Run(root, { 'title' => title_text, 'steps' => steps }, params, params['dry_run'] == true)
        end

        def self.Na__ComponentEditorTools__Revert(params)
            root = Na__McpCatalogue.Na__ComponentEditorTools__LibraryRoot
            journal = self.Na__ComponentEditorTools__LoadJournal(root, params['journal'])
            if journal['status'] == 'reverted'
                return { 'journal' => journal['journal_id'], 'status' => 'reverted', 'summary' => 'This journal was already reverted.' }
            end

            results = []
            journal['done'].reverse_each do |record|
                next if record['reverted']

                begin
                    note = self.Na__ComponentEditorTools__RevertRecord(root, journal, record)
                    record['reverted'] = self.Na__ComponentEditorTools__Stamp
                    results << { 'step' => record['step'], 'op' => record['op'], 'note' => note }
                rescue StandardError => error
                    journal['revert_failed'] = { 'step' => record['step'], 'op' => record['op'], 'message' => error.message }
                    results << { 'step' => record['step'], 'op' => record['op'], 'error' => error.message }
                    break
                ensure
                    self.Na__ComponentEditorTools__SaveJournal(journal)
                end
            end

            all_back = journal['done'].all? { |record| record['reverted'] }
            journal['status'] = all_back ? 'reverted' : 'partly_reverted'
            self.Na__ComponentEditorTools__SaveJournal(journal)
            self.Na__ComponentEditorTools__ForgetLibraryCaches("Library change reverted (#{journal['journal_id']}).")

            {
                'journal' => journal['journal_id'], 'status' => journal['status'], 'reverted' => results.count { |item| !item.key?('error') },
                'results' => results, 'failed' => journal['revert_failed'],
                'summary' => all_back ? "Reverted #{results.length} step(s); the library is as it was before #{journal['journal_id']}." :
                                        "Stopped at step #{journal['revert_failed'] && journal['revert_failed']['step']}: #{journal['revert_failed'] && journal['revert_failed']['message']}"
            }
        end

        # The latest journals, newest first: {id, title, status, created, steps, done}.
        def self.Na__ComponentEditorTools__RecentJournals(root, count)
            directory = self.Na__ComponentEditorTools__JournalRoot(root)
            return [] unless Dir.exist?(directory)

            Dir.children(directory).select { |name| File.file?(File.join(directory, name, NA_JOURNAL_FILE)) }.sort.reverse.first(count).map do |name|
                journal = JSON.parse(File.read(File.join(directory, name, NA_JOURNAL_FILE), encoding: 'UTF-8'))
                { 'id' => name, 'title' => journal['title'], 'status' => journal['status'], 'created' => journal['created'],
                  'steps' => (journal['steps'] || []).length, 'done' => (journal['done'] || []).length }
            rescue StandardError
                { 'id' => name, 'status' => 'unreadable' }
            end
        end

        # After any change on disk: the next Gallery / Index visit re-scans. The
        # per-file extract cache is kept, so unchanged files are not re-opened.
        def self.Na__ComponentEditorTools__ForgetLibraryCaches(status_text = nil)
            Na__LibraryExtractor.Na__ComponentEditorTools__PurgeLastResult if defined?(Na__LibraryExtractor)
            return unless defined?(Na__DialogManager) && Na__DialogManager.respond_to?(:Na__ComponentEditorTools__ForgetLibraryCache)

            Na__DialogManager.Na__ComponentEditorTools__ForgetLibraryCache(status_text)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Run (check, then apply)
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Run(root, plan, params, dry_run)
            steps = self.Na__ComponentEditorTools__NormaliseSteps(root, plan['steps'])
            report = self.Na__ComponentEditorTools__Simulate(root, steps, params)
            checks = report['steps']

            if dry_run
                # 'warnings' is left out on purpose: the bridge moves a result's
                # 'warnings' list onto the response, so the count has its own key.
                return {
                    'dry_run' => true, 'title' => plan['title'].to_s, 'steps_total' => steps.length, 'errors' => report['errors'],
                    'warning_count' => report['warnings'], 'checks' => checks, 'applied' => 0,
                    'summary' => "Dry run: #{steps.length} step(s), #{report['errors']} error(s), #{report['warnings']} warning(s). Nothing was changed."
                }
            end

            if report['errors'].positive?
                raise Na__McpOperationsError.new('invalid_params', "The change has #{report['errors']} error(s); nothing was changed.",
                                                 'Fix the steps listed in details (dry_run: true shows them all).',
                                                 { 'checks' => checks.reject { |check| check['level'] == 'ok' } })
            end

            journal = self.Na__ComponentEditorTools__NewJournal(root, plan, steps)
            report_out = self.Na__ComponentEditorTools__Execute(root, journal, steps, params)
            warnings = checks.select { |check| check['level'] == 'warning' }
            report_out['warnings'] = warnings.map { |check| "step #{check['step']}: #{check['notes'].join(' ')}" } unless warnings.empty?
            report_out
        end

        def self.Na__ComponentEditorTools__Continue(root, journal_ref, params)
            journal = self.Na__ComponentEditorTools__LoadJournal(root, journal_ref)
            if %w[complete reverted partly_reverted].include?(journal['status'])
                return { 'journal' => journal['journal_id'], 'status' => journal['status'], 'summary' => 'Nothing left to apply in this journal.' }
            end

            steps = journal['steps']
            done = journal['done'].map { |record| record['step'] }
            pending_save = steps.each_with_index.any? { |step, index| step['op'] == 'save_definition' && !done.include?(index) }
            if pending_save
                raise Na__McpOperationsError.new('invalid_params', 'A save step cannot be continued from a journal.',
                                                 'Run asset_library_edit save again.')
            end

            journal['failed'] = nil
            journal['status'] = 'in_progress'
            self.Na__ComponentEditorTools__Execute(root, journal, steps, params)
        end

        def self.Na__ComponentEditorTools__PlanFromParams(params)
            plan = params['plan']
            plan_file = params['plan_file'].to_s.strip
            if plan.nil? && !plan_file.empty?
                raise Na__McpOperationsError.new('not_found', "No plan file at #{plan_file}.", nil) unless File.file?(plan_file)

                plan = JSON.parse(File.read(plan_file, encoding: 'UTF-8'))
            end
            plan = { 'steps' => plan } if plan.is_a?(Array)
            return plan if plan.is_a?(Hash)

            raise Na__McpOperationsError.new('invalid_params', 'Pass plan {title, steps: [...]}, plan_file, or journal.', nil)
        rescue JSON::ParserError => error
            raise Na__McpOperationsError.new('invalid_params', "The plan file is not valid JSON: #{error.message}", nil)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Normalise Steps
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__NormaliseSteps(root, raw_steps)
            unless raw_steps.is_a?(Array) && !raw_steps.empty?
                raise Na__McpOperationsError.new('invalid_params', 'The plan has no steps.', 'Pass steps: [{op, from, to}, ...].')
            end
            if raw_steps.length > NA_MAX_STEPS
                raise Na__McpOperationsError.new('invalid_params', "A plan holds at most #{NA_MAX_STEPS} steps (got #{raw_steps.length}).", 'Split it.')
            end

            raw_steps.each_with_index.map do |raw, index|
                raise Na__McpOperationsError.new('invalid_params', "steps[#{index}] must be an object.", nil) unless raw.is_a?(Hash)

                op = raw['op'].to_s
                unless NA_OPS.include?(op)
                    raise Na__McpOperationsError.new('invalid_params', "steps[#{index}]: unknown op '#{op}'.", "Use one of: #{NA_OPS.join(', ')}.")
                end

                step = { 'op' => op, 'why' => raw['why'].to_s }
                case op
                when 'create_folder'
                    step['path'] = self.Na__ComponentEditorTools__StepPath(root, raw['path'] || raw['to'], index, 'path')
                when 'update_asset'
                    step['from'] = self.Na__ComponentEditorTools__StepPath(root, raw['path'] || raw['from'], index, 'path')
                    step['to'] = step['from']
                when 'archive_file'
                    step['from'] = self.Na__ComponentEditorTools__StepPath(root, raw['from'] || raw['path'], index, 'from')
                    step['to'] = if raw['to'].to_s.strip.empty?
                                     Na__McpArchive.Na__ComponentEditorTools__DefaultZipPath(root, step['from'])
                                 else
                                     self.Na__ComponentEditorTools__StepPath(root, raw['to'], index, 'to')
                                 end
                when 'save_definition'
                    step['to'] = self.Na__ComponentEditorTools__StepPath(root, raw['to'], index, 'to')
                    step['definition'] = raw['definition']
                    step['definition_name'] = raw['definition'].respond_to?(:name) ? raw['definition'].name.to_s : ''
                    step['overwrite'] = raw['overwrite'] == true
                    step['rename_in_model'] = raw['rename_in_model'] == true
                else
                    step['from'] = self.Na__ComponentEditorTools__StepPath(root, raw['from'], index, 'from')
                    step['to'] = raw['to'].to_s.strip.empty? && op == 'rename_asset' ? step['from'] : self.Na__ComponentEditorTools__StepPath(root, raw['to'], index, 'to')
                end
                self.Na__ComponentEditorTools__AssetOptions(step, raw, index) if NA_ASSET_OPS.include?(op)
                step
            end
        end

        def self.Na__ComponentEditorTools__StepPath(root, path_text, index, key_name)
            if path_text.to_s.strip.empty?
                raise Na__McpOperationsError.new('invalid_params', "steps[#{index}].#{key_name} is required.", nil)
            end

            Na__McpCatalogue.Na__ComponentEditorTools__ResolvePath(root, path_text)
        end

        def self.Na__ComponentEditorTools__AssetOptions(step, raw, index)
            step['def_name'] = raw.key?('def_name') ? raw['def_name'] : 'auto'
            step['allow_in_use'] = raw['allow_in_use'] == true
            step['force'] = raw['force'] == true
            step['description'] = raw['description'].to_s if raw.key?('description') && !raw['description'].nil?

            data = raw['library_data']
            return if data.nil?
            raise Na__McpOperationsError.new('invalid_params', "steps[#{index}].library_data must be an object.", nil) unless data.is_a?(Hash)

            clean = {}
            data.each do |key, value|
                field = key.to_s.strip
                next if field.empty? || value.nil?

                clean[field] = value.to_s
            end
            step['library_data'] = clean
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Simulate (virtual file list)
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Simulate(root, steps, params)
            state = self.Na__ComponentEditorTools__VirtualState(root)
            touched = []
            model = self.Na__ComponentEditorTools__ActiveModel

            checks = steps.each_with_index.map do |step, index|
                notes = []
                case step['op']
                when 'create_folder'
                    if state.key?(self.Na__ComponentEditorTools__Key(step['path']))
                        notes << ['warning', 'The folder already exists; nothing to do.']
                    else
                        self.Na__ComponentEditorTools__AddParents(state, step['path'], notes, root)
                        state[self.Na__ComponentEditorTools__Key(step['path'])] = { 'path' => step['path'], 'dir' => true }
                        self.Na__ComponentEditorTools__LongPathNotes([step['path']], notes, root)
                    end
                when 'rename_folder'
                    self.Na__ComponentEditorTools__CheckMove(state, step, true, notes, root)
                    if notes.none? { |note| note[0] == 'error' }
                        moved = self.Na__ComponentEditorTools__MoveTree(state, step['from'], step['to'])
                        self.Na__ComponentEditorTools__LongPathNotes(moved, notes, root)
                    end
                when 'move_file'
                    self.Na__ComponentEditorTools__CheckMove(state, step, false, notes, root)
                    if notes.none? { |note| note[0] == 'error' }
                        moved = self.Na__ComponentEditorTools__MoveTree(state, step['from'], step['to'])
                        self.Na__ComponentEditorTools__LongPathNotes(moved, notes, root)
                    end
                when 'archive_file'
                    self.Na__ComponentEditorTools__CheckMove(state, step, false, notes, root)
                    notes << ['error', 'An archive must be a .zip file.'] unless step['to'].downcase.end_with?('.zip')
                    if notes.none? { |note| note[0] == 'error' }
                        self.Na__ComponentEditorTools__AddParents(state, step['to'], [], root)
                        moved = self.Na__ComponentEditorTools__MoveTree(state, step['from'], step['to'])
                        self.Na__ComponentEditorTools__LongPathNotes(moved, notes, root)
                    end
                when 'rename_asset', 'update_asset'
                    self.Na__ComponentEditorTools__CheckAssetStep(root, state, step, model, notes)
                    if notes.none? { |note| note[0] == 'error' }
                        moved = self.Na__ComponentEditorTools__MoveTree(state, step['from'], step['to'])
                        self.Na__ComponentEditorTools__LongPathNotes(moved, notes, root)
                        touched << self.Na__ComponentEditorTools__Key(step['to'])
                    end
                when 'save_definition'
                    self.Na__ComponentEditorTools__CheckSaveStep(root, state, step, notes)
                    if notes.none? { |note| note[0] == 'error' }
                        self.Na__ComponentEditorTools__AddParents(state, step['to'], notes, root)
                        state[self.Na__ComponentEditorTools__Key(step['to'])] = { 'path' => step['to'], 'dir' => false }
                        self.Na__ComponentEditorTools__LongPathNotes([step['to']], notes, root)
                        touched << self.Na__ComponentEditorTools__Key(step['to'])
                    end
                end

                level = if notes.any? { |note| note[0] == 'error' } then 'error'
                        elsif notes.any? { |note| note[0] == 'warning' } then 'warning'
                        else 'ok'
                        end
                {
                    'step' => index, 'op' => step['op'],
                    'from' => step['from'] && Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['from']),
                    'to' => Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['to'] || step['path']),
                    'level' => level, 'notes' => notes.map { |note| note[1] }, 'why' => step['why']
                }.reject { |_key, value| value.nil? || value == '' || value == [] }
            end

            unless params['allow_duplicate_codes'] == true
                self.Na__ComponentEditorTools__DuplicateChecks(root, state, touched).each { |check| checks << check }
            end

            {
                'steps'    => checks,
                'errors'   => checks.count { |check| check['level'] == 'error' },
                'warnings' => checks.count { |check| check['level'] == 'warning' }
            }
        end

        def self.Na__ComponentEditorTools__CheckMove(state, step, expect_directory, notes, root)
            from_item = state[self.Na__ComponentEditorTools__Key(step['from'])]
            if from_item.nil?
                notes << ['error', "Not found: #{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['from'])}."]
            elsif from_item['dir'] != expect_directory
                notes << ['error', "#{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['from'])} is #{from_item['dir'] ? 'a folder' : 'a file'}."]
            end
            if self.Na__ComponentEditorTools__TargetTaken?(state, step['from'], step['to'])
                notes << ['error', "#{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['to'])} already exists."]
            end
            self.Na__ComponentEditorTools__AddParents(state, step['to'], notes, root, dry: true)
        end

        def self.Na__ComponentEditorTools__CheckAssetStep(root, state, step, model, notes)
            from_item = state[self.Na__ComponentEditorTools__Key(step['from'])]
            relative_from = Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['from'])
            if from_item.nil? || from_item['dir']
                notes << ['error', "No component file at #{relative_from}."]
                return
            end
            notes << ['error', "#{relative_from} is not a .skp file."] unless step['from'].downcase.end_with?('.skp')
            notes << ['error', 'The new name must end in .skp.'] unless step['to'].downcase.end_with?('.skp')
            if self.Na__ComponentEditorTools__TargetTaken?(state, step['from'], step['to'])
                notes << ['error', "#{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['to'])} already exists."]
            end
            self.Na__ComponentEditorTools__AddParents(state, step['to'], notes, root, dry: true)

            if model && !step['allow_in_use']
                existing = Na__LibrarySafeLoad.Na__ComponentEditorTools__LoadedDefinitionFor(model, step['from'])
                if existing
                    notes << ['error', "#{File.basename(step['from'])} is loaded in the open model as '#{existing.name}' " \
                                       "(#{existing.count_instances} placed). Pass allow_in_use: true, or work from a model that does not use it."]
                end
            end

            self.Na__ComponentEditorTools__NameNotes(root, step, notes) if step['op'] == 'rename_asset'
        end

        def self.Na__ComponentEditorTools__CheckSaveStep(root, state, step, notes)
            definition = step['definition']
            unless definition.respond_to?(:save_as) && (!definition.respond_to?(:valid?) || definition.valid?)
                notes << ['error', 'The component to save was not found in the open model.']
            end
            notes << ['error', 'The file name must end in .skp.'] unless step['to'].downcase.end_with?('.skp')
            if state.key?(self.Na__ComponentEditorTools__Key(step['to'])) && !step['overwrite']
                notes << ['error', "#{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['to'])} already exists. " \
                                   'Pass overwrite: true to replace it (the old file is kept in the journal).']
            end
            self.Na__ComponentEditorTools__NameNotes(root, step, notes)
        end

        # The convention check of the target name and folder.
        def self.Na__ComponentEditorTools__NameNotes(root, step, notes)
            parts = Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, step['to']).split('/')
            folder_in_set = parts.length > 2 ? parts[1..-2].join('/') : ''
            check = Na__McpConvention.Na__ComponentEditorTools__CheckAsset(File.basename(step['to'], '.*'), folder_in_set)
            check['issues'].each do |issue|
                level = issue['level'] == 'error' && !step['force'] ? 'error' : 'warning'
                notes << [level, "#{issue['message']}#{issue['fix'] ? " (#{issue['fix']})" : ''}"]
            end
        end

        # A code used twice after the plan, when at least one of the files is touched by it.
        def self.Na__ComponentEditorTools__DuplicateChecks(root, state, touched)
            blocked = Na__McpCatalogue.Na__ComponentEditorTools__BlockedFolders
            owners = Hash.new { |hash, key| hash[key] = [] }
            state.each do |key, item|
                next if item['dir'] || !key.end_with?('.skp')

                parts = Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, item['path']).split('/')
                next if parts[0..-2].any? { |part| blocked.include?(part) }

                parsed = Na__McpConvention.Na__ComponentEditorTools__ParseName(File.basename(item['path'], '.*'))
                owners[[parts.first, parsed['code']]] << item['path'] if parsed['kind'] == 'filed'
            end

            owners.select { |_code, paths| paths.length > 1 && paths.any? { |path| touched.include?(self.Na__ComponentEditorTools__Key(path)) } }
                  .map do |(set_name, code), paths|
                      { 'step' => nil, 'op' => 'duplicate_code', 'level' => 'error',
                        'notes' => ["#{code} would be used by #{paths.length} files in #{set_name}: " \
                                    "#{paths.map { |path| File.basename(path) }.join(', ')}."] }.compact
                  end
        end

        # Every file and folder under the library root, keyed case-insensitively.
        def self.Na__ComponentEditorTools__VirtualState(root)
            state = { self.Na__ComponentEditorTools__Key(root) => { 'path' => root, 'dir' => true } }
            Dir.glob(File.join(root, '**', '*'), File::FNM_DOTMATCH).each do |path|
                base = File.basename(path)
                next if base == '.' || base == '..'

                clean = path.tr('\\', '/')
                state[self.Na__ComponentEditorTools__Key(clean)] = { 'path' => clean, 'dir' => File.directory?(clean) }
            end
            state
        end

        # Moves a file or a folder and everything in it; returns the new paths.
        def self.Na__ComponentEditorTools__MoveTree(state, from_path, to_path)
            from_key = self.Na__ComponentEditorTools__Key(from_path)
            return [] if from_key == self.Na__ComponentEditorTools__Key(to_path) && from_path == to_path

            moving = state.keys.select { |key| key == from_key || key.start_with?("#{from_key}/") }
            moving.map do |key|
                item = state.delete(key)
                new_path = to_path + item['path'][from_path.length..].to_s
                state[self.Na__ComponentEditorTools__Key(new_path)] = { 'path' => new_path, 'dir' => item['dir'] }
                new_path
            end
        end

        # Every path a step creates must fit Windows' path limit.
        def self.Na__ComponentEditorTools__LongPathNotes(paths, notes, root)
            too_long = paths.select { |path| path.length > NA_MAX_PATH }
            return if too_long.empty?

            longest = too_long.max_by(&:length)
            notes << ['error', "#{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, longest)} would be #{longest.length} characters; " \
                               "Windows allows #{NA_MAX_PATH}. Shorten the name or the folder."]
        end

        def self.Na__ComponentEditorTools__TargetTaken?(state, from_path, to_path)
            to_key = self.Na__ComponentEditorTools__Key(to_path)
            to_key != self.Na__ComponentEditorTools__Key(from_path) && state.key?(to_key)
        end

        # Notes (and, unless dry, records) the folders a step will create.
        def self.Na__ComponentEditorTools__AddParents(state, path, notes, root, dry: false)
            missing = []
            parent = File.dirname(path)
            while parent.length > root.length && !state.key?(self.Na__ComponentEditorTools__Key(parent))
                missing.unshift(parent)
                parent = File.dirname(parent)
            end
            return if missing.empty?

            notes << ['info', "Creates #{missing.map { |folder| Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, folder) }.join(', ')}."]
            return if dry

            missing.each { |folder| state[self.Na__ComponentEditorTools__Key(folder)] = { 'path' => folder, 'dir' => true } }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Execute
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Execute(root, journal, steps, params)
            budget = [[(params['time_budget_s'] || NA_DEFAULT_TIME_BUDGET_S).to_f, 5.0].max, 240.0].min
            started = self.Na__ComponentEditorTools__Clock
            done = journal['done'].map { |record| record['step'] }
            applied = []

            steps.each_with_index do |step, index|
                next if done.include?(index)

                if self.Na__ComponentEditorTools__Clock - started > budget
                    journal['status'] = 'paused'
                    break
                end

                begin
                    record = self.Na__ComponentEditorTools__ExecuteStep(root, journal, step, index)
                    journal['done'] << record
                    applied << record
                rescue StandardError => error
                    journal['failed'] = { 'step' => index, 'op' => step['op'], 'message' => error.message }
                    journal['status'] = 'failed'
                    break
                ensure
                    self.Na__ComponentEditorTools__SaveJournal(journal)
                end
            end

            journal['status'] = 'complete' if journal['done'].length == steps.length
            self.Na__ComponentEditorTools__SaveJournal(journal)
            self.Na__ComponentEditorTools__ForgetLibraryCaches("Library changed on disk (#{journal['journal_id']}). Switch to another tab and back to see it.") unless applied.empty?
            self.Na__ComponentEditorTools__Report(root, journal, steps, applied)
        end

        def self.Na__ComponentEditorTools__Report(root, journal, steps, applied)
            remaining = steps.length - journal['done'].length
            results = applied.map do |record|
                {
                    'step' => record['step'], 'op' => record['op'],
                    'from' => record['from'] && Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, record['from']),
                    'to' => Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, record['to'] || record['path']),
                    'changes' => record['changes'], 'definition_name' => record['definition_name_after'] || record['definition_name'],
                    'note' => record['note']
                }.reject { |_key, value| value.nil? || value == [] || value == '' }
            end
            summary = case journal['status']
                      when 'complete' then "Applied #{applied.length} step(s); #{journal['done'].length} of #{steps.length} done."
                      when 'paused'   then "Applied #{applied.length} step(s); #{remaining} left. Continue with apply_plan journal: #{journal['journal_id']}."
                      else "Stopped at step #{journal['failed'] && journal['failed']['step']}: #{journal['failed'] && journal['failed']['message']}"
                      end
            {
                'dry_run' => false, 'journal' => journal['journal_id'], 'status' => journal['status'], 'applied' => applied.length,
                'done' => journal['done'].length, 'remaining' => remaining, 'failed' => journal['failed'], 'results' => results,
                'revert' => "asset_library_edit revert journal: #{journal['journal_id']}", 'summary' => summary
            }.compact
        end

        def self.Na__ComponentEditorTools__ExecuteStep(root, journal, step, index)
            record = { 'step' => index, 'op' => step['op'], 'at' => self.Na__ComponentEditorTools__Stamp }
            case step['op']
            when 'create_folder'
                record['path'] = step['path']
                record['created'] = !File.directory?(step['path'])
                FileUtils.mkdir_p(step['path'])
            when 'rename_folder', 'move_file'
                self.Na__ComponentEditorTools__MovePath(step['from'], step['to'])
                record.merge!('from' => step['from'], 'to' => step['to'])
            when 'archive_file'
                record.merge!(self.Na__ComponentEditorTools__ArchiveFile(journal, step, index))
            when 'rename_asset', 'update_asset'
                record.merge!(self.Na__ComponentEditorTools__RewriteAsset(journal, step, index))
            when 'save_definition'
                record.merge!(self.Na__ComponentEditorTools__SaveDefinition(journal, step, index))
            end
            record
        end

        def self.Na__ComponentEditorTools__MovePath(from_path, to_path)
            raise "Not found: #{from_path}" unless File.exist?(from_path)
            if File.exist?(to_path) && self.Na__ComponentEditorTools__Key(to_path) != self.Na__ComponentEditorTools__Key(from_path)
                raise "#{to_path} already exists."
            end

            FileUtils.mkdir_p(File.dirname(to_path))
            File.rename(from_path, to_path) unless from_path == to_path
        end

        # Zip the file into its archive, prove the zip, then move the original into
        # the journal (archived/) so the library keeps only the zip.
        def self.Na__ComponentEditorTools__ArchiveFile(journal, step, index)
            from_path = step['from']
            to_path = step['to']
            raise "Not found: #{from_path}" unless File.file?(from_path)
            raise "#{to_path} already exists." if File.exist?(to_path)

            zip = Na__McpArchive.Na__ComponentEditorTools__ZipFile(from_path, to_path)
            directory = File.join(journal['directory'], 'archived')
            FileUtils.mkdir_p(directory)
            kept = self.Na__ComponentEditorTools__JournalFilePath(directory, index, from_path)
            File.rename(from_path, kept)
            { 'from' => from_path, 'to' => to_path, 'kept' => kept, 'crc32' => zip['crc32'],
              'note' => "Zipped (#{zip['bytes']} -> #{zip['zip_bytes']} bytes) and checked; the original is kept in the journal." }
        end

        # Rename and/or rewrite one library .skp: the component inside is renamed
        # (def_name) and its library data / description written, then the file is
        # moved to its new name. The file is backed up before it is rewritten.
        def self.Na__ComponentEditorTools__RewriteAsset(journal, step, index)
            from_path = step['from']
            to_path = step['to']
            raise "Not found: #{from_path}" unless File.file?(from_path)
            if to_path != from_path && File.exist?(to_path) && self.Na__ComponentEditorTools__Key(to_path) != self.Na__ComponentEditorTools__Key(from_path)
                raise "#{to_path} already exists."
            end

            intended = self.Na__ComponentEditorTools__IntendedName(step, to_path)
            data = step['library_data'] || {}
            started = Time.now
            outcome = Na__LibrarySafeLoad.Na__ComponentEditorTools__WithTemporaryDefinition(from_path, 'Library change', allow_in_use: step['allow_in_use']) do |definition, load_info|
                self.Na__ComponentEditorTools__WriteDefinition(journal, index, from_path, definition, load_info, intended, data, step['description'])
            end

            self.Na__ComponentEditorTools__SweepSketchUpBackup(journal, index, from_path, started) if outcome['backup']
            self.Na__ComponentEditorTools__MovePath(from_path, to_path) unless to_path == from_path
            outcome.merge('from' => from_path, 'to' => to_path)
        end

        def self.Na__ComponentEditorTools__WriteDefinition(journal, index, file_path, definition, load_info, intended, data, description)
            model = Sketchup.active_model
            before = definition.name.to_s
            changes = []
            if intended && before != intended
                Na__LibrarySafeLoad.Na__ComponentEditorTools__ApplyName(model, definition, intended, move_clash_aside: true)
                changes << 'definition_name'
            end
            data.each do |field, value|
                next if definition.get_attribute(Na__LibrarySerializer::NA_LIBRARY_DICT, field).to_s == value.to_s
                raise "Could not write #{field}." unless Na__LibrarySerializer.Na__ComponentEditorTools__WriteSingleField(definition, field, value)

                changes << field
            end
            if !description.nil? && definition.description.to_s != description.to_s
                definition.description = description.to_s
                changes << 'description'
            end

            backup = nil
            unless changes.empty?
                backup = self.Na__ComponentEditorTools__BackupFile(journal, index, file_path)
                raise "SketchUp could not save #{File.basename(file_path)}." unless definition.save_as(file_path)
            end

            {
                'definition_name_before' => before, 'name_changed_on_load' => load_info[:name_changed_on_load],
                'definition_name_after' => definition.name.to_s, 'changes' => changes, 'backup' => backup, 'in_use' => load_info[:in_use]
            }
        end

        # A definition from the open model saved as a library file. The rename and
        # data writes happen inside an aborted operation, so the model is only
        # changed when rename_in_model asks for it (one undo step).
        def self.Na__ComponentEditorTools__SaveDefinition(journal, step, index)
            to_path = step['to']
            definition = step['definition']
            raise 'The component to save is no longer in the model.' unless definition && definition.valid?

            existed = File.exist?(to_path)
            raise "#{to_path} already exists." if existed && !step['overwrite']

            backup = existed ? self.Na__ComponentEditorTools__BackupFile(journal, index, to_path) : nil
            intended = self.Na__ComponentEditorTools__IntendedName(step, to_path) || File.basename(to_path, '.*')
            data = step['library_data'] || {}
            model = Sketchup.active_model
            FileUtils.mkdir_p(File.dirname(to_path))

            saved = false
            model.start_operation('Na Library - Save component to library', true)
            begin
                Na__LibrarySafeLoad.Na__ComponentEditorTools__ApplyName(model, definition, intended, move_clash_aside: true)
                data.each { |field, value| Na__LibrarySerializer.Na__ComponentEditorTools__WriteSingleField(definition, field, value) }
                definition.description = step['description'].to_s unless step['description'].nil?
                saved = definition.save_as(to_path)
            ensure
                model.abort_operation
            end
            raise "SketchUp could not save to #{to_path}." unless saved && File.file?(to_path)

            record = { 'to' => to_path, 'created' => !existed, 'backup' => backup, 'definition_name' => intended, 'renamed_in_model' => false }
            self.Na__ComponentEditorTools__RenameInModel(model, definition, intended, data, record) if step['rename_in_model']
            record
        end

        def self.Na__ComponentEditorTools__RenameInModel(model, definition, intended, data, record)
            model.start_operation('MCP: Save to Library', true)
            begin
                Na__LibrarySafeLoad.Na__ComponentEditorTools__ApplyName(model, definition, intended, move_clash_aside: false)
                data.each { |field, value| Na__LibrarySerializer.Na__ComponentEditorTools__WriteSingleField(definition, field, value) }
                model.commit_operation
                record['renamed_in_model'] = true
            rescue StandardError => error
                model.abort_operation
                record['note'] = "Saved, but the component in the model kept its name: #{error.message}"
            end
        end

        def self.Na__ComponentEditorTools__IntendedName(step, to_path)
            wanted = step['def_name']
            return File.basename(to_path, '.*') if wanted.nil? || wanted.to_s.strip.empty? || wanted.to_s == 'auto'
            return nil if wanted.to_s == 'keep'

            wanted.to_s.strip
        end

        # "<dir>/039__<name>" when that fits Windows' path limit, else "<dir>/039.skp";
        # the journal records which file each one is.
        def self.Na__ComponentEditorTools__JournalFilePath(directory, index, file_path)
            long = File.join(directory, format('%03d__%s', index, File.basename(file_path)))
            return long if long.length <= NA_MAX_PATH

            File.join(directory, format('%03d%s', index, File.extname(file_path)))
        end

        def self.Na__ComponentEditorTools__BackupFile(journal, index, file_path)
            directory = File.join(journal['directory'], 'backup')
            FileUtils.mkdir_p(directory)
            target = self.Na__ComponentEditorTools__JournalFilePath(directory, index, file_path)
            FileUtils.cp(file_path, target, preserve: true)
            target
        end

        # If SketchUp wrote a .skb backup beside the file while saving this step,
        # it is moved into the journal so the library does not collect orphans.
        def self.Na__ComponentEditorTools__SweepSketchUpBackup(journal, index, file_path, started)
            skb = "#{Na__McpConvention.Na__ComponentEditorTools__StripSkp(file_path)}.skb"
            return unless File.file?(skb) && File.mtime(skb) >= started - 1

            directory = File.join(journal['directory'], 'skb')
            FileUtils.mkdir_p(directory)
            File.rename(skb, self.Na__ComponentEditorTools__JournalFilePath(directory, index, skb))
        rescue StandardError
            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Revert One Step
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__RevertRecord(root, journal, record)
            case record['op']
            when 'create_folder'
                path = record['path']
                return 'The folder was already there.' unless record['created']
                return 'The folder is not empty; left in place.' unless Dir.exist?(path) && Dir.empty?(path)

                Dir.rmdir(path)
                'Folder removed.'
            when 'rename_folder', 'move_file'
                self.Na__ComponentEditorTools__MovePath(record['to'], record['from'])
                "Moved back to #{Na__McpCatalogue.Na__ComponentEditorTools__Relative(root, record['from'])}."
            when 'archive_file'
                self.Na__ComponentEditorTools__MovePath(record['kept'], record['from'])
                if File.exist?(record['to'])
                    directory = File.join(journal['directory'], 'removed')
                    FileUtils.mkdir_p(directory)
                    File.rename(record['to'], self.Na__ComponentEditorTools__JournalFilePath(directory, record['step'].to_i, record['to']))
                end
                'The original is back in place; the zip moved into the journal (removed/).'
            when 'rename_asset', 'update_asset'
                self.Na__ComponentEditorTools__MovePath(record['to'], record['from']) unless record['to'] == record['from']
                FileUtils.cp(record['backup'], record['from']) if record['backup']
                record['backup'] ? 'Original file restored.' : 'Name restored.'
            when 'save_definition'
                if record['created']
                    directory = File.join(journal['directory'], 'removed')
                    FileUtils.mkdir_p(directory)
                    File.rename(record['to'], self.Na__ComponentEditorTools__JournalFilePath(directory, record['step'].to_i, record['to']))
                    'The saved file was moved into the journal (removed/).'
                else
                    FileUtils.cp(record['backup'], record['to']) if record['backup']
                    'The file it replaced was restored.'
                end
            else
                "Nothing to revert for #{record['op']}."
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Journal Files
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__JournalRoot(root)
            folder = Na__McpConvention.Na__ComponentEditorTools__Config['journal_folder'].to_s
            File.join(root, folder.empty? ? NA_DEFAULT_JOURNAL_DIR : folder)
        end

        def self.Na__ComponentEditorTools__NewJournal(root, plan, steps)
            slug = plan['title'].to_s.gsub(/[^A-Za-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')[0, 32].to_s.sub(/-+\z/, '')
            stamp = Time.now.strftime('%Y%m%d-%H%M%S')
            journal_id = slug.empty? ? stamp : "#{stamp}__#{slug}"
            directory = File.join(self.Na__ComponentEditorTools__JournalRoot(root), journal_id)
            FileUtils.mkdir_p(directory)

            journal = {
                'journal_id' => journal_id, 'directory' => directory, 'title' => plan['title'].to_s, 'library_root' => root,
                'created' => self.Na__ComponentEditorTools__Stamp, 'status' => 'in_progress',
                'steps' => steps.map { |step| step.reject { |key, _value| key == 'definition' } },
                'done' => [], 'failed' => nil
            }
            self.Na__ComponentEditorTools__SaveJournal(journal)
            journal
        end

        def self.Na__ComponentEditorTools__SaveJournal(journal)
            File.write(File.join(journal['directory'], NA_JOURNAL_FILE), JSON.pretty_generate(journal), encoding: 'UTF-8')
        end

        def self.Na__ComponentEditorTools__LoadJournal(root, journal_ref)
            reference = journal_ref.to_s.strip
            raise Na__McpOperationsError.new('invalid_params', 'Pass journal (the id a change returned).', nil) if reference.empty?

            directory = File.directory?(reference) ? reference : File.join(self.Na__ComponentEditorTools__JournalRoot(root), reference)
            path = File.join(directory, NA_JOURNAL_FILE)
            unless File.file?(path)
                raise Na__McpOperationsError.new('not_found', "No journal '#{reference}'.", 'asset_library overview lists the latest journals.')
            end

            journal = JSON.parse(File.read(path, encoding: 'UTF-8'))
            journal['directory'] = directory.tr('\\', '/')
            journal['done'] ||= []
            journal
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Key(path_text)
            Na__LibrarySafeLoad.Na__ComponentEditorTools__PathKey(path_text)
        end

        def self.Na__ComponentEditorTools__ActiveModel
            return nil unless defined?(Sketchup) && Sketchup.respond_to?(:active_model)

            Sketchup.active_model
        end

        def self.Na__ComponentEditorTools__Clock
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def self.Na__ComponentEditorTools__Stamp
            Time.now.strftime('%Y-%m-%d %H:%M:%S')
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
