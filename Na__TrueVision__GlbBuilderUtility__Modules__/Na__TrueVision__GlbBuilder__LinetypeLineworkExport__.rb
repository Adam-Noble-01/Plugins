# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - LINETYPE LINEWORK EXPORT MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__LinetypeLineworkExport__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Linetype Linework Export
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Writes one linework GLB per LINETYPE tag - the tags a person uses
#              in SketchUp to say "this line is dashed", "this is a centre line",
#              "this is coming out" - so the downstream drawing editors can draw
#              them with their own line style instead of losing them at export.
# CREATED    : 18-Sep-2026
#
# DESCRIPTION:
# - A linetype tag is a Tags SSOT entry carrying Glb__LineworkOnly. It carries no
#   mesh into any GLB: the model export already skips these tags, either as a fully
#   excluded tag or as a linework-hidden one, and that does not change here.
# - The whole model is walked once. Every edge belongs to the nearest linetype tag
#   on itself or on a group or component above it, at any nesting depth, so a
#   dashed line drawn inside a door component reaches the drawing.
# - Tag visibility is ignored (LinetypeExportConfig.ExportIgnoresTagVisibility):
#   linetype tags are drawing data, so a model tidied for a render still carries
#   its linework. Hidden entities, and hidden, soft and smooth edges, are skipped.
# - One file per tag that holds geometry: {prefix}{Stem}__LineworkModel__.glb, a
#   single non-indexed LINES primitive (POSITION + COLOR_0) in world metres, Y up -
#   the model GLBs' own frame, so the lines land on the model.
# - The files are written into the model export folder, so the standard multi-model
#   loader discovers them by filename and gives each one its own category. No
#   manifest: the filename IS the contract.
#
# DEPENDENCIES:
# - Main__ (INCHES_TO_METERS, GLB_FILE_EXTENSION), EngineCore__GeometryHandling__
#   (Z_UP_TO_Y_UP_MATRIX), EngineCore__ (Na__GlbEngine__WriteGlbFile),
#   EngineCore__LineworkModelHandling__ (Na__LineworkEngine__BuildGltfFromEdgeData),
#   Logging__, Na__DataLib__CacheData.
#
# DEVELOPMENT LOG:
# 18-Sep-2026 - Version 1.0.0
# - First version (GLB Builder 2.7.3).
#
# =============================================================================

require 'json'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Linetype Linework Export - Constants
    # -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Defaults (each overridden by LinetypeExportConfig in the Tags SSOT)
        # ------------------------------------------------------------
        NA__LINETYPE__CONFIG_DEFAULTS = {
            'LineworkFileSuffix'         => '__LineworkModel__',
            'ExportIgnoresTagVisibility' => true
        }.freeze
        NA__LINETYPE__EXPORTER_VERSION = '1.0.0'.freeze                           # <-- Written into the GLB asset generator string
        NA__LINETYPE__MAX_DEPTH        = 64                                       # <-- Nesting guard for the walk
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Linetype Linework Export - Standards Data
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Load the Tags SSOT, Local Copy First
        # ---------------------------------------------------------------
        # The local plugins-folder copy wins, so an SSOT edit that has not
        # reached GitHub yet still exports. The DataLib cache is the fallback.
        # ---------------------------------------------------------------
        def self.Na__Linetype__LoadTagsData
            local_path = File.expand_path(
                File.join('..', 'Na__Common__DataLib__CoreSuEntityStandards', 'Na__DataLib__CoreIndex__Tags__.json'),
                __dir__
            )

            if File.exist?(local_path)
                begin
                    return JSON.parse(File.read(local_path, encoding: 'UTF-8'))
                rescue => e
                    Na__Log__Warn "  [Linetype] Local Tags SSOT unreadable, using the DataLib cache: #{e.message}"
                end
            end

            Na__DataLib__CacheData.Na__Cache__LoadData(:tags)
        rescue => e
            Na__Log__Warn "  [Linetype] Tags SSOT could not be loaded: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read LinetypeExportConfig Over the Defaults
        # ---------------------------------------------------------------
        def self.Na__Linetype__Config(tags_data)
            config = NA__LINETYPE__CONFIG_DEFAULTS.dup
            block  = tags_data.is_a?(Hash) ? tags_data['LinetypeExportConfig'] : nil
            return config unless block.is_a?(Hash)

            block.each { |key, value| config[key] = value if config.key?(key) }
            config
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Linetype Definitions
        # ---------------------------------------------------------------
        # A linetype tag is any entry carrying Glb__LineworkOnly with an export
        # file name stem. An entry missing the stem is reported and skipped
        # rather than exported under a guessed filename.
        #
        # Returns [ by_tag, by_stem ]. by_tag holds every SketchUp name that
        # means this linetype - the canonical one and any Glb__LineworkLegacyTagNames
        # alias - so a model tagged up before a rename still exports. by_stem holds
        # each definition once: the EXPORT is per stem, which is why the buckets
        # are keyed by stem and two names can never write the same file twice.
        # ---------------------------------------------------------------
        def self.Na__Linetype__BuildDefinitions(tags_data)
            by_tag  = {}
            by_stem = {}
            library = tags_data.is_a?(Hash) ? tags_data['Na__DataLib__CoreIndex__Tags'] : nil
            return [by_tag, by_stem] unless library.is_a?(Hash)

            library.each_value do |section|
                next unless section.is_a?(Hash)

                section.each_value do |entry|
                    next unless entry.is_a?(Hash)
                    next unless entry['Glb__LineworkOnly'] == true

                    tag_name = entry['Tag__SketchUpName']
                    next unless tag_name.is_a?(String) && !tag_name.empty?

                    stem = entry['Glb__ExportFileNameStem']
                    unless stem.is_a?(String) && !stem.empty?
                        Na__Log__Warn "  [Linetype] '#{tag_name}' is marked Glb__LineworkOnly but has no Glb__ExportFileNameStem - skipped"
                        next
                    end

                    definition = {
                        tag_name:  tag_name,
                        stem:      stem,
                        label:     (entry['Glb__LineworkLabel'].is_a?(String)    ? entry['Glb__LineworkLabel']    : stem),
                        line_type: (entry['Glb__LineworkLineType'].is_a?(String) ? entry['Glb__LineworkLineType'] : 'solid')
                    }

                    by_stem[stem]    = definition
                    by_tag[tag_name] = definition

                    Array(entry['Glb__LineworkLegacyTagNames']).each do |legacy_name|
                        next unless legacy_name.is_a?(String) && !legacy_name.empty?
                        by_tag[legacy_name] = definition                             # <-- Same file, older name
                    end
                end
            end

            [by_tag, by_stem]
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Linetype Linework Export - Geometry Collection
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | New Collection Bucket for One Linetype Tag
        # ---------------------------------------------------------------
        def self.Na__Linetype__NewBucket(definition)
            {
                defn:      definition,
                positions: [],                                                    # <-- Flat [x,y,z, x,y,z, ...], two points per edge
                colors:    [],                                                    # <-- Flat [r,g,b,a, ...], two per edge
                skipped:   0                                                      # <-- Hidden / soft / smooth entities left out
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add One Edge to a Bucket (World Metres, Y Up)
        # ---------------------------------------------------------------
        def self.Na__Linetype__AddEdge(bucket, edge, transform)
            p0 = transform * edge.start.position
            p1 = transform * edge.end.position

            bucket[:positions].push(
                p0.x.to_f * INCHES_TO_METERS, p0.y.to_f * INCHES_TO_METERS, p0.z.to_f * INCHES_TO_METERS,
                p1.x.to_f * INCHES_TO_METERS, p1.y.to_f * INCHES_TO_METERS, p1.z.to_f * INCHES_TO_METERS
            )

            colour = edge.material ? edge.material.color : nil
            if colour
                r = colour.red   / 255.0
                g = colour.green / 255.0
                b = colour.blue  / 255.0
                a = (colour.respond_to?(:alpha) ? colour.alpha : 255) / 255.0
            else
                r = 0.0
                g = 0.0
                b = 0.0
                a = 1.0
            end
            2.times { bucket[:colors].push(r, g, b, a) }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Count an Entity Left Out of a Tag's Linework
        # ---------------------------------------------------------------
        def self.Na__Linetype__CountSkipped(ctx, owner)
            return if owner.nil?
            bucket = (ctx[:buckets][owner] ||= self.Na__Linetype__NewBucket(ctx[:stems][owner]))
            bucket[:skipped] += 1
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk Entities, Collecting Edges by Nearest Linetype Tag
        # ---------------------------------------------------------------
        # @param entities    [Sketchup::Entities]     Children to walk
        # @param transform   [Geom::Transformation]   Accumulated transform (Z up to Y up at the root)
        # @param current_tag [String|nil]             Export stem of the nearest linetype tag above, nil when none
        # @param ctx         [Hash]                   :defs, :stems, :buckets, :excluded, :exclusion_pattern, :ignore_visibility
        # ---------------------------------------------------------------
        def self.Na__Linetype__Collect(entities, transform, current_tag, ctx, depth = 0)
            return if depth > NA__LINETYPE__MAX_DEPTH

            entities.each do |entity|
                next unless entity.respond_to?(:layer)

                layer    = entity.layer
                tag_name = layer ? layer.name : 'Layer0'
                next if ctx[:excluded].include?(tag_name)
                next if ctx[:exclusion_pattern] && tag_name =~ ctx[:exclusion_pattern]
                next if !ctx[:ignore_visibility] && layer && !layer.visible?

                owner = ctx[:defs].key?(tag_name) ? ctx[:defs][tag_name][:stem] : current_tag   # <-- Buckets are keyed by stem, so a legacy name joins the same file

                if entity.respond_to?(:hidden?) && entity.hidden?
                    self.Na__Linetype__CountSkipped(ctx, owner)                     # <-- Counted, so a gap in the linework shows in the log
                    next
                end

                if entity.is_a?(Sketchup::Edge)
                    next if owner.nil?
                    if entity.soft? || entity.smooth?
                        self.Na__Linetype__CountSkipped(ctx, owner)
                        next
                    end
                    bucket = (ctx[:buckets][owner] ||= self.Na__Linetype__NewBucket(ctx[:stems][owner]))
                    self.Na__Linetype__AddEdge(bucket, entity, transform)
                elsif entity.is_a?(Sketchup::Group)
                    self.Na__Linetype__Collect(entity.entities, transform * entity.transformation, owner, ctx, depth + 1)
                elsif entity.is_a?(Sketchup::ComponentInstance)
                    self.Na__Linetype__Collect(entity.definition.entities, transform * entity.transformation, owner, ctx, depth + 1)
                end
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Close Every Open Group or Component Edit Context
        # ---------------------------------------------------------------
        # Inside an open drawing context SketchUp reports vertex positions and
        # the context's own transforms in WORLD space, so a walk from the model
        # root through an open group would apply that group's transform to points
        # that already carry it. Closing back to the root makes every coordinate
        # local again, which is what this walk accumulates.
        # ---------------------------------------------------------------
        def self.Na__Linetype__CloseOpenContexts(model)
            return unless model.respond_to?(:active_path)
            return if model.active_path.nil? || model.active_path.empty?

            Na__Log__Warn "  [Linetype] A group or component was open for editing - closing it so the walk reads local coordinates"
            guard = 0
            while model.active_path && !model.active_path.empty? && guard < NA__LINETYPE__MAX_DEPTH
                model.close_active
                guard += 1
            end
        rescue => e
            Na__Log__Warn "  [Linetype] Could not close the open editing context: #{e.message}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Scan the Model for Linetype Linework (No Files Written)
        # ---------------------------------------------------------------
        # Returns { config:, defs:, stems:, buckets: }. defs is keyed by every
        # SketchUp name a linetype answers to, stems by export stem, and buckets
        # by stem - existing only for the linetypes the model holds geometry on.
        #
        # close_contexts closes any open group or component first, which the
        # walk needs to read local coordinates (see CloseOpenContexts). Only an
        # EXPORT asks for it: opening the export dialog must not close the group
        # a person is working in, so a plan settles for warning that its counts
        # are off until the group is closed.
        # ---------------------------------------------------------------
        def self.Na__Linetype__Scan(model, close_contexts = false)
            tags_data    = self.Na__Linetype__LoadTagsData
            defs, stems  = self.Na__Linetype__BuildDefinitions(tags_data)
            config       = self.Na__Linetype__Config(tags_data)

            return { config: config, defs: defs, stems: stems, buckets: {} } if stems.empty?

            exclusions  = tags_data.is_a?(Hash) ? tags_data['ExportExclusions'] : nil
            excluded    = exclusions.is_a?(Hash) ? Array(exclusions['FullyExcludedTagNames']) : []
            pattern_str = exclusions.is_a?(Hash) ? exclusions['PatternExclusionRegex'] : nil

            ctx = {
                defs:              defs,
                stems:             stems,
                buckets:           {},
                excluded:          excluded.reject { |name| defs.key?(name) },      # <-- A linetype tag is never excluded from its OWN export
                exclusion_pattern: (pattern_str.is_a?(String) ? Regexp.new(pattern_str) : nil),
                ignore_visibility: config['ExportIgnoresTagVisibility'] != false
            }

            if close_contexts
                self.Na__Linetype__CloseOpenContexts(model)
            elsif model.respond_to?(:active_path) && model.active_path && !model.active_path.empty?
                Na__Log__Warn "  [Linetype] A group or component is open for editing - these counts are provisional; the export closes it first"
            end

            self.Na__Linetype__Collect(model.entities, Z_UP_TO_Y_UP_MATRIX, nil, ctx)

            { config: config, defs: defs, stems: stems, buckets: ctx[:buckets] }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Linetype Linework Export - Writing
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Write One Linetype Linework GLB
        # ---------------------------------------------------------------
        def self.Na__Linetype__WriteBucket(bucket, path)
            defn             = bucket[:defn]
            gltf, bin_buffer = Na__LineworkEngine__BuildGltfFromEdgeData(bucket[:positions], bucket[:colors])

            gltf['asset']['generator'] = "TrueVision3D GLB Builder Linetype Linework Export v#{NA__LINETYPE__EXPORTER_VERSION}"
            gltf['asset']['extras']    = {
                'Na__LinetypeTag'      => defn[:tag_name],
                'Na__LinetypeStem'     => defn[:stem],
                'Na__LinetypeLabel'    => defn[:label],
                'Na__LinetypeLineType' => defn[:line_type]
            }
            gltf['meshes'][0]['name'] = defn[:stem] if gltf['meshes'][0]

            Na__GlbEngine__WriteGlbFile(path, gltf, bin_buffer)
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Export Every Linetype Tag That Holds Geometry
        # ---------------------------------------------------------------
        # Writes into the model export folder so the multi-model loader finds
        # the files beside the mesh and category linework GLBs.
        #
        # @param model          [Sketchup::Model] Model to walk
        # @param export_dir     [String]          Folder the model GLBs were written to
        # @param project_prefix [String]          "PS01__" style prefix, or ""
        # @return               [Hash]            { written:, files:, empty_tags:, edge_count: }
        # ---------------------------------------------------------------
        def self.Na__Linetype__ExportAll(model, export_dir, project_prefix = "")
            result = { written: 0, files: [], empty_tags: [], edge_count: 0 }

            scan    = self.Na__Linetype__Scan(model, true)                          # <-- An export closes any open group first
            stems   = scan[:stems]
            buckets = scan[:buckets]

            if stems.empty?
                Na__Log__Puts "  No linetype tags defined in the Tags SSOT - nothing to export"
                return result
            end

            suffix = scan[:config]['LineworkFileSuffix'] || NA__LINETYPE__CONFIG_DEFAULTS['LineworkFileSuffix']

            stems.each do |stem_key, defn|
                bucket = buckets[stem_key]

                if bucket.nil? || bucket[:positions].empty?
                    skipped = bucket ? bucket[:skipped] : 0
                    note    = skipped > 0 ? " (#{skipped} hidden/soft/smooth entities skipped)" : ""
                    Na__Log__Puts "    #{defn[:tag_name]}: no linework#{note}"
                    result[:empty_tags] << defn[:tag_name]
                    next
                end

                filename = "#{project_prefix}#{defn[:stem]}#{suffix}#{GLB_FILE_EXTENSION}"
                path     = File.join(export_dir, filename)
                edges    = bucket[:positions].length / 6

                begin
                    self.Na__Linetype__WriteBucket(bucket, path)
                    result[:written]    += 1
                    result[:edge_count] += edges
                    result[:files]      << filename
                    skipped_note = bucket[:skipped] > 0 ? ", #{bucket[:skipped]} skipped" : ""
                    Na__Log__Puts "    OK #{filename} - #{edges} edges, line type '#{defn[:line_type]}'#{skipped_note}"
                rescue => e
                    Na__Log__Warn "    ERROR: Failed to write #{filename} - #{e.message}"
                end
            end

            result
        rescue => e
            Na__Log__Warn "  ERROR: Linetype linework export failed - #{e.message}"
            Na__Log__Warn "  #{e.backtrace.first(5).join("\n  ")}"
            result
        end
        # ---------------------------------------------------------------

        # FUNCTION | Plan the Linetype Export (Filenames Only, Nothing Written)
        # ---------------------------------------------------------------
        # Used by the export dialog and the export plan so the file list shown
        # before an export is the list the export actually writes.
        #
        # @return [Array<Hash>] [{ filename:, tag_name:, label:, line_type:, edge_count: }]
        # ---------------------------------------------------------------
        def self.Na__Linetype__PlanExport(model, project_prefix = "")
            scan   = self.Na__Linetype__Scan(model)
            suffix = scan[:config]['LineworkFileSuffix'] || NA__LINETYPE__CONFIG_DEFAULTS['LineworkFileSuffix']
            plan   = []

            scan[:stems].each do |stem_key, defn|
                bucket = scan[:buckets][stem_key]
                next if bucket.nil? || bucket[:positions].empty?

                plan << {
                    filename:   "#{project_prefix}#{defn[:stem]}#{suffix}#{GLB_FILE_EXTENSION}",
                    tag_name:   defn[:tag_name],
                    label:      defn[:label],
                    line_type:  defn[:line_type],
                    edge_count: bucket[:positions].length / 6
                }
            end

            plan
        rescue => e
            Na__Log__Warn "  [Linetype] Export plan failed: #{e.message}"
            []
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
