# =============================================================================
# NA PAINTERLYNPR ASSETS - PROJECT CACHE - STORE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ProjectCache__Store__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__CacheStore
# PURPOSE    : Where a model's local NPR cache lives and what it holds: one
#              folder per project in 92__UserProjects__ProjectCache (git-ignored)
#              with the GLBs the GLB builder wrote, the manifest (each file's
#              fingerprint, hash and version), the scene file the NPR Viewport
#              reads, and the engine's look for that project.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - A PROJECT'S KEY is its model's title (12 characters) and a hash of its
#   path, so two models with one name in different folders never share a
#   cache, and an unsaved model gets one from its GUID until it is saved.
# - PATHS STAY UNDER 260: SketchUp's Ruby (and the GLB builder inside it)
#   cannot open a longer one, and the Plugins folder is already deep. The key
#   is short and the GLBs sit straight in the project folder; Na__Cache__TooLong
#   names any file that would still pass the limit.
# - THE CACHE IS MANAGED, NOT GROWN: an index at the cache root records when
#   each project was last opened; the oldest beyond keepProjects are deleted
#   (never the one in use), and the GLB builder's export logs are trimmed.
# - Nothing here touches the model.
#
# =============================================================================

require 'digest'

module Na__PainterlyAssets
    module Na__CacheStore

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_MANIFEST_FILE  = 'Na__PainterlyAssets__ProjectCache__Manifest__.json'.freeze unless defined?(NA_MANIFEST_FILE)
        NA_SCENE_FILE     = 'Na__PainterlyAssets__ProjectCache__Scene__.json'.freeze    unless defined?(NA_SCENE_FILE)
        NA_SETTINGS_FILE  = 'Na__PainterlyAssets__ProjectCache__Settings__.json'.freeze unless defined?(NA_SETTINGS_FILE)
        NA_INDEX_FILE     = 'Na__PainterlyAssets__ProjectCache__Index__.json'.freeze    unless defined?(NA_INDEX_FILE)
        NA_MANIFEST_SCHEMA = 'Na__PainterlyAssets__ProjectCache__Manifest'.freeze       unless defined?(NA_MANIFEST_SCHEMA)
        NA_EXPORT_LOG_GLOB = 'GlbBuilder__ExportLog__*.txt'.freeze                      unless defined?(NA_EXPORT_LOG_GLOB)

        @na_untitled_keys = {} unless defined?(@na_untitled_keys)                       # <-- An unsaved model's key, by GUID, for this session

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Where a Project's Cache Is
    # -------------------------------------------------------------------------

        def self.Na__Cache__Root
            FileUtils.mkdir_p(Na__PainterlyAssets::NA_PROJECT_CACHE_DIR)
            Na__PainterlyAssets::NA_PROJECT_CACHE_DIR
        end

        # FUNCTION | A Model's Project Key: <title, 12 characters>__<8 hex of its path>
        # ------------------------------------------------------------
        def self.Na__Cache__Key(model)
            chars = Na__ConfigLoader.Na__Config__GetOr(12, 'nprViewport', 'projectCache', 'folderNameChars').to_i
            path  = model.path.to_s
            if path.empty?
                guid = model.guid.to_s
                return @na_untitled_keys[guid] ||= "Untitled__#{Digest::SHA1.hexdigest(guid)[0, 8]}"
            end
            title = File.basename(path, '.*').gsub(/[^A-Za-z0-9_-]/, '_').gsub(/_+\z/, '')[0, [chars, 4].max]
            "#{title}__#{Digest::SHA1.hexdigest(path.tr('\\', '/').downcase)[0, 8]}"
        end
        # ---------------------------------------------------------------

        def self.Na__Cache__Folder(model)
            folder = File.join(self.Na__Cache__Root, self.Na__Cache__Key(model))
            FileUtils.mkdir_p(folder)
            folder
        end

        # The longest path SketchUp's Ruby opens (the library's pathLimit, 259)
        def self.Na__Cache__TooLong(folder, file_names)
            limit = Na__PathResolver.Na__Paths__Limit
            Array(file_names).select { |name| File.join(folder, name).length > limit }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Manifest, the Scene and the Look
    # -------------------------------------------------------------------------

        # FUNCTION | The Manifest: { 'Units' => { key => {...} }, 'Files' => { name => {...} }, ... }
        # ------------------------------------------------------------
        def self.Na__Cache__ReadManifest(folder)
            raw = Na__SafeFileWriter.Na__SafeFile__ReadJson(File.join(folder, NA_MANIFEST_FILE))
            fresh = { 'Schema' => NA_MANIFEST_SCHEMA, 'SchemaVersion' => 1, 'Revision' => 0, 'Units' => {}, 'Files' => {} }
            return fresh unless raw.is_a?(Hash) && raw['Schema'] == NA_MANIFEST_SCHEMA
            raw['Units'] = {} unless raw['Units'].is_a?(Hash)
            raw['Files'] = {} unless raw['Files'].is_a?(Hash)
            raw
        end
        # ---------------------------------------------------------------

        def self.Na__Cache__WriteManifest(folder, manifest)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(File.join(folder, NA_MANIFEST_FILE), manifest, 4)
        end

        def self.Na__Cache__ReadScene(folder)
            Na__SafeFileWriter.Na__SafeFile__ReadJson(File.join(folder, NA_SCENE_FILE))
        end

        def self.Na__Cache__WriteScene(folder, scene)
            Na__SafeFileWriter.Na__SafeFile__WriteJson(File.join(folder, NA_SCENE_FILE), scene, 4)
        end

        # FUNCTION | The Engine's Look for This Project (what the NPR Parameters window set), or nil
        # ------------------------------------------------------------
        def self.Na__Cache__ReadSettings(folder)
            raw = Na__SafeFileWriter.Na__SafeFile__ReadJson(File.join(folder, NA_SETTINGS_FILE))
            raw.is_a?(Hash) && raw['Settings'].is_a?(Hash) ? raw['Settings'] : nil
        end

        def self.Na__Cache__WriteSettings(folder, settings)
            record = { 'Schema' => 'Na__PainterlyAssets__ProjectCache__Settings', 'SavedIso' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'), 'Settings' => settings }
            Na__SafeFileWriter.Na__SafeFile__WriteJson(File.join(folder, NA_SETTINGS_FILE), record, 4)
        end
        # ---------------------------------------------------------------

        # SHA-256 of a file's bytes: a file rewritten the same keeps its version
        def self.Na__Cache__Sha256(path)
            Digest::SHA256.file(path).hexdigest
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Keeping the Cache Managed
    # -------------------------------------------------------------------------

        # FUNCTION | Record a Project as Used, Then Trim the Cache
        # ------------------------------------------------------------
        # The oldest projects past keepProjects go, never the one in use; the
        # GLB builder's export logs in a project keep their newest few.
        def self.Na__Cache__Touch(model)
            key   = self.Na__Cache__Key(model)
            index_path = File.join(self.Na__Cache__Root, NA_INDEX_FILE)
            index = Na__SafeFileWriter.Na__SafeFile__ReadJson(index_path) || {}
            projects = index['Projects'].is_a?(Hash) ? index['Projects'] : {}
            projects[key] = { 'ModelPath' => model.path.to_s, 'Title' => model.title.to_s, 'UsedIso' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ') }

            keep  = Na__ConfigLoader.Na__Config__GetOr(12, 'nprViewport', 'projectCache', 'keepProjects').to_i
            stale = projects.keys.reject { |k| k == key }.sort_by { |k| projects[k]['UsedIso'].to_s }.reverse.drop([keep - 1, 0].max)
            stale.each do |old|
                folder = File.join(self.Na__Cache__Root, old)
                FileUtils.rm_rf(folder) if File.directory?(folder) && File.dirname(folder) == self.Na__Cache__Root
                projects.delete(old)
            end
            Na__SafeFileWriter.Na__SafeFile__WriteJson(index_path, { 'Schema' => 'Na__PainterlyAssets__ProjectCache__Index', 'Projects' => projects }, 4)
            self.na_trim_logs(File.join(self.Na__Cache__Root, key))
            stale
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The project cache index could not be kept: #{error.message}")
            []
        end
        # ---------------------------------------------------------------

        def self.na_trim_logs(folder)
            keep = Na__ConfigLoader.Na__Config__GetOr(3, 'nprViewport', 'projectCache', 'keepExportLogs').to_i
            logs = Dir.glob(File.join(folder.tr('\\', '/'), NA_EXPORT_LOG_GLOB)).sort_by { |f| File.mtime(f) }.reverse
            logs.drop(keep).each { |f| File.delete(f) rescue nil }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
