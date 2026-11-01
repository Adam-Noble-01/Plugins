# =============================================================================
# NA PAINTERLYNPR ASSETS - PROJECT CACHE - GLB BRIDGE
# =============================================================================
#
# FILE       : Na__PainterlyAssets__ProjectCache__GlbBridge__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__GlbBridge
# PURPOSE    : The model to GLBs for the local NPR cache, by the same route
#              ValeVision Cloud Sync's web exporter takes (its GlbExportBridge,
#              Sync Aura): TrueVision's GLB builder, whitecard plus MAT000E__
#              exempt materials, the builder's previous mode put back after.
#              Only into a folder on this PC, and only the files a change made
#              stale.
# CREATED    : 01-Nov-2026
#
# DESCRIPTION:
# - THIS PLUGIN CALLS THE GLB BUILDER; it never reimplements it (Cloud Sync's
#   rule). The plan is the builder's own: its excluded tags, its tag groups,
#   its storey containers and their elements, the file names it writes. The
#   export is its own Na__PublicApi__PerformExport(dir, quiet: true).
# - ONLY THE STALE FILES ARE WRITTEN: for the length of one export the
#   builder's per-file selection (Na__ExportSelection__DeselectedSet, which its
#   export loop and its linetype export both consult) answers "deselected"
#   for every file this sync does not need. The model's own stored selection
#   is never read or written, and the builder's method is put back in an
#   ensure. A builder that one day offers its own export-only call is used
#   instead (Na__PublicApi__WithExportOnly).
# - THE ACTIVE CONTEXT MUST BE THE MODEL: the builder plans from
#   model.active_entities, and an open group reports world coordinates, so
#   the sync waits until no group is open (Cloud Sync refuses the same way).
# - LINETYPE LINEWORK IS NOT EXPORTED: those files have no mesh twin, so the
#   engine's scene never reads them.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__GlbBridge

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_BUILDER_LOADER   = 'Na__TrueVision__GlbBuilderUtility__Loader__.rb'.freeze unless defined?(NA_BUILDER_LOADER)
        NA_MESH_SUFFIX      = '__MeshModel__'.freeze                                  unless defined?(NA_MESH_SUFFIX)       # <-- The builder's own constants are read first
        NA_LINEWORK_SUFFIX  = '__LineworkModel__'.freeze                              unless defined?(NA_LINEWORK_SUFFIX)
        NA_MESH_ONLY_GROUPS = ['01__OrbitHelperCube'].freeze                          unless defined?(NA_MESH_ONLY_GROUPS)  # <-- The builder writes no linework for these

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Builder
    # -------------------------------------------------------------------------

        # FUNCTION | The GLB Builder's Module, Loaded If It Was Not (nil when it is not installed)
        # ------------------------------------------------------------
        def self.Na__GlbBridge__Builder
            return TrueVision3D::GlbBuilderUtility if self.na_builder_ready?
            loader = File.join(File.dirname(Na__PainterlyAssets::NA_MODULES_ROOT), NA_BUILDER_LOADER)
            return nil unless File.file?(loader)
            load loader
            self.na_builder_ready? ? TrueVision3D::GlbBuilderUtility : nil
        rescue ScriptError, StandardError => error
            Na__DebugTools.Na__Debug__Error('The TrueVision GLB builder could not be loaded.', error)
            nil
        end
        # ---------------------------------------------------------------

        def self.na_builder_ready?
            defined?(TrueVision3D::GlbBuilderUtility) &&
                TrueVision3D::GlbBuilderUtility.respond_to?(:Na__PublicApi__PerformExport) &&
                TrueVision3D::GlbBuilderUtility.respond_to?(:Na__ExportCore__OrganizeEntitiesByTags)
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Plan: the Builder's Units and Their Files
    # -------------------------------------------------------------------------

        # FUNCTION | What the Builder Would Write: { 'Prefix', 'Units' => [...] }
        # ------------------------------------------------------------
        # Each unit: { 'Key', 'Kind' ('Flat' | 'Storey'), 'Files' (mesh, then
        # linework), 'Entities', 'Transform' (a merged storey's, else nil) }.
        # The builder's own sequence, as its model status and its export run it.
        def self.Na__GlbBridge__Plan(model)
            builder = self.Na__GlbBridge__Builder
            raise 'The TrueVision GLB builder is not installed or did not load (Na__TrueVision__GlbBuilderUtility).' unless builder
            raise 'Close the open group or component first: the GLB builder exports the model, not an open context.' if model.active_path

            builder.Na__ExportCore__IdentifyExcludedLayers(model)
            prefix     = builder.Na__Helpers__ExtractProjectPrefix(model).to_s
            mesh_sfx   = defined?(TrueVision3D::GlbBuilderUtility::MESH_MODEL_SUFFIX) ? TrueVision3D::GlbBuilderUtility::MESH_MODEL_SUFFIX : NA_MESH_SUFFIX
            line_sfx   = defined?(TrueVision3D::GlbBuilderUtility::LINEWORK_MODEL_SUFFIX) ? TrueVision3D::GlbBuilderUtility::LINEWORK_MODEL_SUFFIX : NA_LINEWORK_SUFFIX
            tag_groups = builder.Na__ExportCore__OrganizeEntitiesByTags(model)
            storeys    = builder.Na__ExportCore__DetectStoreyContainers(model)
            unless storeys.empty?                                                       # <-- Storey containers export per element, so they leave the flat groups (the builder's own step)
                storeys.each_value { |containers| Array(containers).each { |c| tag_groups.each_value { |list| list.delete(c) } } }
                tag_groups.delete_if { |_name, list| list.empty? }
            end

            units = tag_groups.map do |base, entities|
                files = ["#{prefix}#{base}#{mesh_sfx}.glb"]
                files << "#{prefix}#{base}#{line_sfx}.glb" unless NA_MESH_ONLY_GROUPS.include?(base)
                { 'Key' => base, 'Kind' => 'Flat', 'Files' => files, 'Entities' => entities, 'Transform' => nil }
            end
            storeys.each do |storey_name, containers|
                transform = builder.Na__ExportCore__ResolveMergedStoreyTransform(containers, storey_name)
                builder.Na__ExportCore__OrganizeStoreyChildrenByTags(containers, storey_name).each do |element, entities|
                    base = "#{storey_name}__#{element}"
                    units << { 'Key' => base, 'Kind' => 'Storey', 'Files' => ["#{prefix}#{base}#{mesh_sfx}.glb", "#{prefix}#{base}#{line_sfx}.glb"],
                               'Entities' => entities, 'Transform' => transform }
                end
            end
            { 'Prefix' => prefix, 'Units' => units }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | The Export: Only the Named Files
    # -------------------------------------------------------------------------

        # FUNCTION | Write the Named Files Into a Folder: { 'ok', 'written', 'missing', 'message', 'mode', 'log' }
        # ------------------------------------------------------------
        def self.Na__GlbBridge__Export(model, folder, file_names)
            builder = self.Na__GlbBridge__Builder
            return self.na_result(false, [], file_names, 'The TrueVision GLB builder is not installed or did not load.') unless builder
            return self.na_result(false, [], file_names, 'Close the open group first: the GLB builder exports the model.') if model.active_path

            wanted   = Array(file_names).map(&:to_s)
            before   = wanted.each_with_object({}) { |name, h| path = File.join(folder, name); h[name] = File.file?(path) ? File.mtime(path) : nil }   # <-- Written means changed since now: a 2 s window (Cloud Sync's) would count the last sync's file when two run back to back
            mode     = self.na_material_mode(model)
            previous = self.na_set_mode(builder, mode)
            begin
                self.na_with_export_only(builder, wanted) do
                    builder.Na__PublicApi__PerformExport(folder, quiet: true)          # <-- No Explorer window, no message box mid-sync
                end
            ensure
                self.na_set_mode(builder, previous) if previous                        # <-- Leave TrueVision's own session as it was
            end

            written = wanted.select do |name|
                path = File.join(folder, name)
                File.file?(path) && (before[name].nil? || File.mtime(path) != before[name])
            end
            missing = wanted - written
            log     = Dir.glob(File.join(folder.tr('\\', '/'), Na__CacheStore::NA_EXPORT_LOG_GLOB)).max_by { |f| File.mtime(f) }
            message = missing.empty? ? "#{written.length} GLB file(s) written (#{mode == :indexed_only ? 'SSOT materials' : 'whitecard'} + MAT000E__ exempt)." :
                                       "#{written.length} of #{wanted.length} GLB file(s) written; #{missing.length} not: #{missing.first(3).join(', ')}."
            self.na_result(missing.empty?, written, missing, message, mode, log)
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Error('The GLB export failed.', error)
            self.na_result(false, [], Array(file_names), "The GLB export raised #{error.class}: #{error.message}")
        end
        # ---------------------------------------------------------------

        # The builder's per-file selection answers "deselected" for every file
        # but the wanted ones, for this block only, then is put back.
        def self.na_with_export_only(builder, wanted)
            if builder.respond_to?(:Na__PublicApi__WithExportOnly)
                return builder.Na__PublicApi__WithExportOnly(wanted) { yield }
            end
            return yield unless builder.respond_to?(:Na__ExportSelection__DeselectedSet)   # <-- An older builder: it writes every file (slower, still right)

            keep     = wanted.each_with_object({}) { |name, set| set[name] = true }
            only     = Hash.new { |_set, name| !keep[name.to_s] }
            original = builder.method(:Na__ExportSelection__DeselectedSet)
            builder.define_singleton_method(:Na__ExportSelection__DeselectedSet) { |*_args| only }
            begin
                yield
            ensure
                builder.define_singleton_method(:Na__ExportSelection__DeselectedSet, original)
            end
        end

        # Whitecard (every material Default, MAT000E__ exempt ones kept) unless
        # the config says auto and the model sits in a __MaxModel project
        # (Cloud Sync's rule: those keep their SSOT MAT###__ materials).
        def self.na_material_mode(model)
            setting = Na__ConfigLoader.Na__Config__GetOr('whitecard', 'nprViewport', 'projectCache', 'materialMode').to_s
            return :no_materials unless setting == 'auto'
            dir = File.dirname(model.path.to_s)
            6.times do
                return :indexed_only if File.basename(dir) =~ /__MaxModel\z/i
                parent = File.dirname(dir)
                break if parent == dir
                dir = parent
            end
            :no_materials
        end

        def self.na_set_mode(builder, mode)
            return nil unless mode && builder.respond_to?(:Na__MaterialEngine__SetExportMode) && builder.respond_to?(:Na__MaterialEngine__GetExportMode)
            previous = builder.Na__MaterialEngine__GetExportMode
            builder.Na__MaterialEngine__SetExportMode(mode)
            previous
        rescue StandardError => error
            Na__DebugTools.Na__Debug__Warn("The GLB builder's material mode could not be set: #{error.message}")
            nil
        end

        def self.na_result(ok, written, missing, message, mode = nil, log = nil)
            { 'ok' => ok, 'written' => written, 'missing' => missing, 'message' => message, 'mode' => mode.to_s, 'log' => log }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
