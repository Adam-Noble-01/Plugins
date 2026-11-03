# =============================================================================
# NA PAINTERLYNPR ASSETS - MODEL PERSISTENCE - SETTINGS
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ModelPersistence__Settings__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__NprSettings
# PURPOSE    : Model-persistent NPR styles. What the model's NPR settings
#              record holds (the look, the export settings), what a window is
#              given when it opens, every change written back, Reset, Restore,
#              and Undo and Redo of them. The record itself is kept by
#              Na__NprSettingsStore, its second copy by Na__NprSettingsBackup.
# CREATED    : 01-Nov-2026 (v0.3.0)
#
# DESCRIPTION:
# - Adam, 01-Nov-2026: "make sure parameters and options for everything we've
#   got are correctly serialised to a model dictionary ... so we can have
#   model-persistent styles ... This should also serialise and cover things
#   like the export settings".
# - THE LOOK is PainterlyNPR's own settings object, the part that is the
#   drawing (Seed, Sun, Style, Paper, Composition): every control of the NPR
#   Parameters window, its sliders and its menus, lands in one of those. It is
#   given to a window as its engine serialises it, and put back by the engine's
#   own ApplySettingsJson, so a parameter added to PainterlyNPR is kept with
#   nothing changed here. Where it comes from when a window opens: the model's
#   record; else this PC's project cache (what 0.2.0 kept, read only); else
#   nothing, and the engine starts from its own defaults.
# - THE EXPORT SETTINGS are NPR Export's: merged over the defaults in the
#   AppConfig (nprExport.defaults), every key coerced, unknown keys carried.
#   A chosen folder is kept relative to the model's folder where it can be (the
#   model moves between PCs); scenes by their persistent id, the name a hint.
# - THE ART CONTROL POINTS (v0.4.0; Adam: "One set per scene", his rule in
#   ValeVision AURA): as the engine's settings object serialises them
#   (ArtDirectionPoints), so every value of every point type is kept with nothing
#   changed here. One set a SketchUp scene, by its persistent id, and a working
#   set for when no scene is selected. A set with no points is not kept.
# - ONE UNDO STEP A RUN OF CHANGES: a look change after our own look change,
#   with nothing else done to the model in between, joins that step
#   (transparent), so a minute at the sliders is one Ctrl+Z, and any other
#   step (a line drawn, an undo) starts a new one. Reset, Load and Restore are
#   steps of their own. Unchanged data writes nothing.
# - UNDO AND REDO: while an NPR window is open the model is watched; an undo
#   that moved the record is re-read and handed to the windows (the look goes
#   back in the drawing), and the live sync is told it need not check the
#   model's geometry. Observers only read and schedule.
#
# =============================================================================

require 'json'

module Na__PainterlyAssets
    module Na__NprSettings

    # -------------------------------------------------------------------------
    # REGION | Observers (they only read and schedule)
    # -------------------------------------------------------------------------

        class Na__NprSettings__ModelWatch < Sketchup::ModelObserver
            def onTransactionCommit(model);  Na__PainterlyAssets::Na__NprSettings.na_on_commit(model); end
            def onTransactionUndo(model);    Na__PainterlyAssets::Na__NprSettings.na_on_undo(model);   end
            def onTransactionRedo(model);    Na__PainterlyAssets::Na__NprSettings.na_on_undo(model);   end
            def onTransactionAbort(model);   Na__PainterlyAssets::Na__NprSettings.na_on_break(model);  end
        end

        class Na__NprSettings__AppWatch < Sketchup::AppObserver
            def onNewModel(model);           Na__PainterlyAssets::Na__NprSettings.na_on_model(model);  end
            def onOpenModel(model);          Na__PainterlyAssets::Na__NprSettings.na_on_model(model);  end
            def onActivateModel(model);      Na__PainterlyAssets::Na__NprSettings.na_on_model(model);  end
            def expectsStartupModelNotifications; false; end                          # <-- Attached when a window opens, never at start-up
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Constants and State
    # -------------------------------------------------------------------------

        NA_LOOK_KEYS = %w[Seed Sun Style Paper Composition].freeze unless defined?(NA_LOOK_KEYS)
        NA_OPERATION = {
            'look'          => 'PainterlyNPR Assets: NPR Look',
            'lookReset'     => 'PainterlyNPR Assets: Reset NPR Look',
            'lookLoad'      => 'PainterlyNPR Assets: Load NPR Look',
            'export'        => 'PainterlyNPR Assets: NPR Export Settings',
            'exportReset'   => 'PainterlyNPR Assets: Reset NPR Export Settings',
            'restore'       => 'PainterlyNPR Assets: Restore NPR Settings',
            'points'        => 'PainterlyNPR Assets: NPR Art Control Points'
        }.freeze unless defined?(NA_OPERATION)
        NA_WORKING_SET  = 'working'.freeze unless defined?(NA_WORKING_SET)                  # <-- The art control points with no scene selected
        NA_EXPORT_FALLBACK = {
            'views'       => 'current',
            'scenes'      => [],
            'format'      => 'png',
            'dpi'         => 300,
            'jpegQuality' => 92,
            'folderMode'  => 'besideModel',
            'subfolder'   => 'PainterlyNPR__Exports',
            'folder'      => '',
            'fileName'    => '{model}__{view}__PainterlyNPR__{dpi}dpi__',
            'ifExists'    => 'number',
            'openFolder'  => true,
            'openFile'    => false
        }.freeze unless defined?(NA_EXPORT_FALLBACK)
        NA_EXPORT_CHOICES = {
            'views'      => %w[current scenes],
            'format'     => %w[png jpeg pdf],
            'folderMode' => %w[besideModel chosen],
            'ifExists'   => %w[number replace]
        }.freeze unless defined?(NA_EXPORT_CHOICES)
        NA_MAX_SCENES   = 500     unless defined?(NA_MAX_SCENES)
        NA_MAX_LOOK     = 200_000 unless defined?(NA_MAX_LOOK)                          # <-- Characters: a look is a few thousand

        @na_session    = nil   unless defined?(@na_session)                              # <-- { 'model', 'loaded' }: the active model's record as last read
        @na_watch      = nil   unless defined?(@na_watch)                                # <-- { 'model', 'observer' }
        @na_app_watch  = nil   unless defined?(@na_app_watch)
        @na_writing    = false unless defined?(@na_writing)
        @na_chain      = nil   unless defined?(@na_chain)                                # <-- { 'model', 'block' }: the last step was our own write of this block
        @na_announcing = nil   unless defined?(@na_announcing)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Reading
    # -------------------------------------------------------------------------

        # FUNCTION | The Model's Record as Last Read (read once, then after each change)
        # ------------------------------------------------------------
        def self.Na__Settings__Loaded(model)
            return Na__NprSettingsStore.na_empty('') unless model
            unless @na_session && @na_session['model'].equal?(model)
                @na_session = { 'model' => model, 'loaded' => Na__NprSettingsStore.Na__Store__Load(model) }
            end
            @na_session['loaded']
        end
        # ---------------------------------------------------------------

        def self.Na__Settings__Reload(model)
            @na_session = nil
            self.Na__Settings__Loaded(model)
        end

        # FUNCTION | The Look a Window Is Given: { 'settings' (or nil), 'source' }
        # ------------------------------------------------------------
        # source: 'model' (the record), 'cache' (this PC's 0.2.0 project cache),
        # or 'engine' (nothing kept: the engine's own defaults stand).
        def self.Na__Settings__Look(model)
            loaded = self.Na__Settings__Loaded(model)
            block = loaded['blocks']['look']
            return { 'settings' => block['settings'], 'source' => 'model' } if block.is_a?(Hash) && block['settings'].is_a?(Hash)
            cached = model ? Na__CacheStore.Na__Cache__ReadSettings(Na__CacheStore.Na__Cache__Folder(model)) : nil
            return { 'settings' => self.na_look_only(cached), 'source' => 'cache' } if cached.is_a?(Hash) && !self.na_look_only(cached).empty?
            { 'settings' => nil, 'source' => 'engine' }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR look could not be read.', error)
            { 'settings' => nil, 'source' => 'engine' }
        end
        # ---------------------------------------------------------------

        # FUNCTION | NPR Export's Settings for This Model (the defaults where it holds none)
        # ------------------------------------------------------------
        def self.Na__Settings__Export(model)
            block = self.Na__Settings__Loaded(model)['blocks']['export']
            self.Na__Settings__NormaliseExport(block.is_a?(Hash) ? block : {})
        end
        # ---------------------------------------------------------------

        # FUNCTION | Which Set of Art Control Points the Model's View Is On: a Scene's Persistent Id, or the Working Set
        # ------------------------------------------------------------
        def self.Na__Settings__PointsKey(model)
            page = model ? model.pages.selected_page : nil
            page ? page.persistent_id.to_s : NA_WORKING_SET
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Set of Art Control Points: { 'Key', 'Name', 'Points', 'Sheet' }
        # ------------------------------------------------------------
        # @param key [String, nil] none: the set the model's view is on
        def self.Na__Settings__Points(model, key = nil)
            key   = (key || self.Na__Settings__PointsKey(model)).to_s
            block = self.Na__Settings__Loaded(model)['blocks']['points']
            block = {} unless block.is_a?(Hash)
            sets  = block['sets'].is_a?(Hash) ? block['sets'] : {}
            set   = sets[key].is_a?(Hash) ? sets[key] : {}
            { 'Key' => key, 'Name' => set['name'].to_s, 'Points' => set['points'].is_a?(Array) ? set['points'] : [], 'Sheet' => block['sheet'] }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The art control points could not be read.', error)
            { 'Key' => key.to_s, 'Name' => '', 'Points' => [], 'Sheet' => nil }
        end
        # ---------------------------------------------------------------

        def self.Na__Settings__ExportDefaults
            configured = Na__ConfigLoader.Na__Config__GetOr({}, 'nprExport', 'defaults')
            JSON.parse(JSON.generate(NA_EXPORT_FALLBACK.merge(configured.is_a?(Hash) ? configured.reject { |key, _| key.start_with?('_') } : {})))
        end

        # FUNCTION | What the Windows Show About the Record
        # ------------------------------------------------------------
        def self.Na__Settings__Status(model)
            loaded = self.Na__Settings__Loaded(model)
            meta   = loaded['meta'] || {}
            epoch  = meta['updatedEpoch'].to_f
            {
                'State'     => loaded['state'],
                'Problem'   => loaded['problem'],
                'Revision'  => meta['revision'].to_i,
                'SavedText' => epoch > 0 ? Time.at(epoch).strftime('%d %b %Y %H:%M') : '',
                'HasLook'   => loaded['blocks'].key?('look'),
                'HasExport' => loaded['blocks'].key?('export'),
                'HasPoints' => loaded['blocks'].key?('points'),
                'Backup'    => Na__NprSettingsBackup.Na__Backup__Offer(model, loaded),
                'Model'     => self.na_title(model)
            }
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR settings status could not be made.', error)
            { 'State' => 'readOnly', 'Problem' => error.message, 'Backup' => { 'offer' => false } }
        end
        # ---------------------------------------------------------------

        def self.Na__Settings__Writing?
            @na_writing ? true : false
        end

        # The windows told what the model's settings now are (after a Load, a Restore, a model change)
        def self.Na__Settings__Announce(model)
            self.na_announce(model)
        end

        # The model's name as the windows show it
        def self.Na__Settings__Title(model)
            self.na_title(model)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Writing
    # -------------------------------------------------------------------------

        # FUNCTION | Keep a Look in the Model
        # ------------------------------------------------------------
        # @param kind [String] 'look' (a change: joins a run of them), 'lookReset' or 'lookLoad'
        # @return [String, nil] why nothing was written, or nil (written, or unchanged)
        def self.Na__Settings__SaveLook(model, settings, kind = 'look')
            return 'There is no model.' unless model
            look = self.na_look_only(settings)
            return 'That is not a PainterlyNPR look: it holds none of Seed, Sun, Style, Paper or Composition.' if look.empty?
            return 'That look is too large to keep in the model.' if JSON.generate(look).length > NA_MAX_LOOK
            loaded = self.Na__Settings__Reload(model)
            block  = loaded['blocks']['look'].is_a?(Hash) ? loaded['blocks']['look'] : {}
            return nil if self.na_same?(block['settings'], look)
            engine = Na__RemoteEngine.Na__Remote__Current || {}
            changed = block.merge('settings' => look, 'engineVersion' => engine['appVersion'].to_s, 'engineCommit' => engine['commit'].to_s)
            self.na_write(model, loaded, { 'look' => changed }, kind, kind == 'look' ? 'look' : nil)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep NPR Export's Settings in the Model
        # ------------------------------------------------------------
        # @param kind [String] 'export' (a change) or 'exportReset'
        def self.Na__Settings__SaveExport(model, settings, kind = 'export')
            return 'There is no model.' unless model
            clean  = self.Na__Settings__NormaliseExport(settings.is_a?(Hash) ? settings : {})
            loaded = self.Na__Settings__Reload(model)
            block  = loaded['blocks']['export']
            current = self.Na__Settings__NormaliseExport(block.is_a?(Hash) ? block : {})
            return nil if self.na_same?(current, clean)                                    # <-- Unchanged (and the defaults, unchanged, are never written)
            self.na_write(model, loaded, { 'export' => clean }, kind, kind == 'export' ? 'export' : nil)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Keep One Set of Art Control Points in the Model
        # ------------------------------------------------------------
        # A run of changes is one undo step, as the look's is. No points: the
        # set is dropped from the record.
        # @param key [String] the set the page is showing (the view may have moved on since)
        # @param points [Array<Hash>] the engine's ArtDirectionPoints
        # @return [String, nil] why nothing was written, or nil (written, or unchanged)
        def self.Na__Settings__SavePoints(model, key, points, sheet)
            return 'There is no model.' unless model
            key  = key.to_s.empty? ? NA_WORKING_SET : key.to_s
            list = Array(points).select { |point| point.is_a?(Hash) }
            return 'Those art control points are too large to keep in the model.' if JSON.generate(list).length > NA_MAX_LOOK
            loaded  = self.Na__Settings__Reload(model)
            block   = loaded['blocks']['points'].is_a?(Hash) ? loaded['blocks']['points'] : {}
            sets    = block['sets'].is_a?(Hash) ? block['sets'].dup : {}
            current = sets[key].is_a?(Hash) ? sets[key] : {}
            return nil if self.na_same?(current['points'].is_a?(Array) ? current['points'] : [], list)
            if list.empty?
                sets.delete(key)
            else
                page = key == NA_WORKING_SET ? nil : model.pages.to_a.find { |candidate| candidate.persistent_id.to_s == key }
                sets[key] = current.merge('name' => page ? page.name.to_s : current['name'].to_s, 'points' => list)
            end
            engine  = Na__RemoteEngine.Na__Remote__Current || {}
            changed = block.merge('sets' => sets, 'sheet' => sheet.is_a?(Hash) ? sheet : block['sheet'], 'engineVersion' => engine['appVersion'].to_s, 'engineCommit' => engine['commit'].to_s)
            self.na_write(model, loaded, { 'points' => changed }, 'points', 'points')
        end
        # ---------------------------------------------------------------

        # FUNCTION | Restore This PC's Backup Into the Model (only when the windows offered it)
        # ------------------------------------------------------------
        def self.Na__Settings__Restore(model)
            return 'There is no model.' unless model
            loaded = self.Na__Settings__Reload(model)
            offer  = Na__NprSettingsBackup.Na__Backup__Offer(model, loaded)
            return 'There is nothing on this PC to restore for this model.' unless offer['offer']
            backup = Na__NprSettingsBackup.Na__Backup__Find(model, loaded)
            @na_writing = true
            begin
                problem, now = Na__NprSettingsStore.Na__Store__SaveRecord(model, loaded, backup['record'], NA_OPERATION['restore'])
            ensure
                @na_writing = false
            end
            @na_chain = nil
            return problem if problem
            @na_session = { 'model' => model, 'loaded' => now }
            Na__NprSettingsBackup.Na__Backup__Write(model, now)
            self.na_announce(model)
            nil
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Export Settings' Shape
    # -------------------------------------------------------------------------

        # FUNCTION | Every Key Coerced, Over the Defaults; Keys This Version Does Not Know Carried
        # ------------------------------------------------------------
        def self.Na__Settings__NormaliseExport(raw)
            defaults = self.Na__Settings__ExportDefaults
            given    = raw.is_a?(Hash) ? raw : {}
            out      = defaults.merge(given)
            NA_EXPORT_CHOICES.each { |key, choices| out[key] = choices.include?(out[key].to_s) ? out[key].to_s : defaults[key] }
            limits = Array(Na__ConfigLoader.Na__Config__GetOr([50, 1200], 'nprExport', 'dpiLimits')).map(&:to_i)
            out['dpi']         = self.na_whole(out['dpi'], defaults['dpi']).clamp(limits[0] || 50, limits[1] || 1200)
            out['jpegQuality'] = self.na_whole(out['jpegQuality'], defaults['jpegQuality']).clamp(50, 100)
            out['scenes']      = self.na_scenes(out['scenes'])
            out['subfolder']   = self.na_folder_name(out['subfolder'])
            out['folder']      = out['folder'].to_s.strip.tr('\\', '/')
            name = out['fileName'].to_s.strip
            out['fileName']    = name.empty? ? defaults['fileName'] : name[0, 160]
            out['openFolder']  = out['openFolder'] == true
            out['openFile']    = out['openFile'] == true
            out
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Watching the Model (while an NPR window is open)
    # -------------------------------------------------------------------------

        # FUNCTION | Watch the Active Model's Transactions and the Model Changing
        # ------------------------------------------------------------
        def self.Na__Settings__Watch(model)
            return unless model
            self.na_unwatch_model if @na_watch && !@na_watch['model'].equal?(model)
            unless @na_watch
                observer = Na__NprSettings__ModelWatch.new
                model.add_observer(observer)
                @na_watch = { 'model' => model, 'observer' => observer }
                @na_chain = nil                                                            # <-- What happened before we watched is not known
            end
            unless @na_app_watch
                @na_app_watch = Na__NprSettings__AppWatch.new
                Sketchup.add_observer(@na_app_watch)
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The model could not be watched for NPR settings.', error)
        end
        # ---------------------------------------------------------------

        def self.Na__Settings__Unwatch
            self.na_unwatch_model
            if @na_app_watch
                Sketchup.remove_observer(@na_app_watch) rescue nil
                @na_app_watch = nil
            end
            @na_chain = nil
        end

        # The NPR windows opened or closed: watch while any is open
        def self.Na__Settings__WindowsChanged
            open = Na__NprWindows::NA_ROLES.any? { |role| Na__NprWindows.Na__Windows__Visible?(role) } ||
                   (defined?(Na__NprExport) && Na__NprExport.Na__Export__WindowVisible?)
            open ? self.Na__Settings__Watch(Sketchup.active_model) : self.Na__Settings__Unwatch
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Observer Callbacks (read, then schedule)
    # -------------------------------------------------------------------------

        def self.na_on_commit(model)
            @na_chain = nil unless @na_writing                                             # <-- Someone else's step: the next look change starts a new one
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR settings watch failed on a commit.', error)
        end

        def self.na_on_break(_model)
            @na_chain = nil unless @na_writing
        rescue StandardError
            nil
        end

        # An Undo or Redo: did it move our record? Then the windows get it back,
        # and the live sync need not check the geometry.
        def self.na_on_undo(model)
            @na_chain = nil
            changed = false
            if @na_session && @na_session['model'].equal?(model)
                raw = Na__NprSettingsStore.Na__Store__Raw(model)
                changed = raw.to_s != @na_session['loaded']['raw'].to_s
                self.na_schedule_reload(model) if changed
            end
            Na__LiveSync.Na__Live__ModelUndone(model, changed) if defined?(Na__LiveSync)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR settings watch failed on an undo.', error)
        end

        # Another model came to the front (a new file, an opened one, a 2027 tab)
        def self.na_on_model(model)
            @na_chain = nil
            @na_session = nil
            self.Na__Settings__Watch(model) if @na_watch
            fired = false
            UI.start_timer(0.3, false) do
                next if fired
                fired = true
                Na__PainterlyAssets::Na__NprSettings.na_announce(Sketchup.active_model)
            end
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR settings could not follow the model change.', error)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # One write: a step of its own, or (chain_block) joined to our last step of that block
        def self.na_write(model, loaded, changes, kind, chain_block)
            transparent = chain_block && @na_chain && @na_chain['block'] == chain_block &&
                          @na_chain['model'].equal?(model) && @na_watch && @na_watch['model'].equal?(model)
            @na_writing = true
            begin
                problem, now = Na__NprSettingsStore.Na__Store__Save(model, loaded, changes, NA_OPERATION[kind], transparent: transparent ? true : false)
            ensure
                @na_writing = false
            end
            @na_session = { 'model' => model, 'loaded' => now }
            if problem
                @na_chain = nil
                return problem
            end
            @na_chain = chain_block ? { 'model' => model, 'block' => chain_block } : nil
            Na__NprSettingsBackup.Na__Backup__Write(model, now)
            nil
        end

        def self.na_schedule_reload(model)
            fired = false
            UI.start_timer(0, false) do
                next if fired
                fired = true
                begin
                    next if model.respond_to?(:valid?) && !model.valid?                       # <-- Closed since (a Mac window, a 2027 tab)
                    loaded = Na__PainterlyAssets::Na__NprSettings.Na__Settings__Reload(model)
                    Na__PainterlyAssets::Na__NprSettingsBackup.Na__Backup__Write(model, loaded)    # <-- The record really changed: this PC's copy follows
                    Na__PainterlyAssets::Na__NprSettings.na_announce(model)
                rescue StandardError => error
                    Na__PainterlyAssets::Na__DebugTools.Na__Debug__Error('The NPR settings could not be read again after an undo.', error)
                end
            end
        end

        # The windows are told: the look to both NPR windows, the export
        # settings and the record's status to NPR Export
        def self.na_announce(model)
            return unless model
            Na__LiveSync.Na__Live__LookChanged(model) if defined?(Na__LiveSync)
            Na__NprWindows.Na__Windows__SendAll('record', self.Na__Settings__Status(model)) if defined?(Na__NprWindows)
            Na__NprExport.Na__Export__PushState if defined?(Na__NprExport)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The NPR windows could not be told about the settings.', error)
        end

        def self.na_unwatch_model
            watch = @na_watch
            @na_watch = nil
            return unless watch
            watch['model'].remove_observer(watch['observer'])
        rescue StandardError
            nil                                                                            # <-- A closed model takes its observers with it
        end

        def self.na_look_only(settings)
            return {} unless settings.is_a?(Hash)
            settings.select { |key, value| NA_LOOK_KEYS.include?(key) && !value.nil? }
        end

        # Equal as data, whatever the order of the keys
        def self.na_same?(a, b)
            self.na_canonical(a) == self.na_canonical(b)
        end

        def self.na_canonical(value)
            case value
            when Hash  then '{' + value.keys.map(&:to_s).sort.map { |key| "#{key.to_json}:#{self.na_canonical(value[key])}" }.join(',') + '}'
            when Array then '[' + value.map { |item| self.na_canonical(item) }.join(',') + ']'
            when Float then value == value.round ? value.round.to_s : value.to_s                # <-- 1.0 from JSON and 1 from JavaScript are one value
            else value.to_json
            end
        end

        def self.na_whole(value, fallback)
            number = Float(value)
            number.finite? ? number.round : fallback.to_i
        rescue ArgumentError, TypeError
            fallback.to_i
        end

        # [{ 'pid' => Integer, 'name' => String }], each scene once
        def self.na_scenes(list)
            seen = {}
            Array(list).first(NA_MAX_SCENES).each_with_object([]) do |entry, out|
                next unless entry.is_a?(Hash)
                pid = entry['pid'].to_i
                next unless pid > 0 && !seen[pid]
                seen[pid] = true
                out << { 'pid' => pid, 'name' => entry['name'].to_s[0, 120] }
            end
        end

        # One folder's name: no separators, nothing Windows refuses ('' is the model's own folder)
        def self.na_folder_name(name)
            clean = name.to_s.strip.gsub(%r{[<>:"/\\|?*\x00-\x1f]}, '_').gsub(/\A\.+|[. ]+\z/, '')
            clean[0, 80]
        end

        def self.na_title(model)
            return '' unless model
            title = model.title.to_s
            title.empty? ? 'Untitled' : title
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
