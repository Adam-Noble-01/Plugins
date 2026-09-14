# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - SITE PLAN EXPORT MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__SitePlanExport__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Site Plan Export
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Writes the 2D site plan data read by TrueVision3D Site Plan drawings:
#              one linework GLB per site plan tag (71-75), a fill GLB for fill tags,
#              and a manifest, into the project's SitePlan__DrawingData folder.
# CREATED    : 14-Sep-2026
#
# DESCRIPTION:
# - Site plan layers are the Tags SSOT entries that carry SitePlan__ExportFileNameStem
#   (section 71_75__SitePlanTags__). The model export never writes them.
# - The whole model is walked. Every edge and face belongs to the nearest site plan
#   tag on itself or on a group or component above it. Tag visibility is ignored
#   (SitePlanExportConfig.ExportIgnoresTagVisibility); hidden objects, soft, smooth
#   and hidden edges, and fully excluded reference tags are skipped. Skipped edges and
#   hidden objects are counted per layer: the summary, the log and the manifest say so.
# - Linework GLB: one non-indexed LINES primitive (POSITION + COLOR_0), world metres,
#   Y up - the same frame as the model GLBs, so the site plan lines up with the model.
# - Fill GLB (fill tags only): one LINE_LOOP primitive per face ring, with the extras
#   Na__SitePlanFace (face index) and Na__SitePlanRing (outer / inner).
# - The manifest is written last. Older site plan GLBs in the folder that this export
#   did not write are offered for deletion, so the pipeline stops publishing them.
#
# DEPENDENCIES:
# - Main__ (INCHES_TO_METERS, logging config), EngineCore__GeometryHandling__
#   (Z_UP_TO_Y_UP_MATRIX, Na__GltfHelpers__AddAccessor), EngineCore__ (WriteGlbFile),
#   EngineCore__LineworkModelHandling__ (BuildGltfFromEdgeData), Logging__, CoreExport__.
#
# DEVELOPMENT LOG:
# 14-Sep-2026 - Version 1.1.1
# - The checks are no longer only in the summary shown before export. Every one is
#   written to the export log, and the completion message lists them (up to eight)
#   instead of pointing at a summary that has already closed (GLB Builder 2.7.2).
#
# 14-Sep-2026 - Version 1.1.0
# - Hidden, soft and smooth edges, and hidden groups or components, are counted against
#   the layer they would have drawn on, and reported in the summary, the log and the
#   manifest warnings (GLB Builder 2.7.1). What exports is unchanged.
#
# 14-Sep-2026 - Version 1.0.0
# - First version (GLB Builder 2.7.0).
#
# =============================================================================

require 'json'
require 'fileutils'

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Site Plan Export - Constants
    # -----------------------------------------------------------------------------

        # MODULE CONSTANTS | Defaults (each overridden by SitePlanExportConfig in the Tags SSOT)
        # ------------------------------------------------------------
        NA__SITEPLAN__CONFIG_DEFAULTS = {
            'ExportFolderName'           => 'SitePlan__DrawingData',
            'ManifestFileName'           => 'TrueVision__SitePlanData__Manifest__.json',
            'LineworkFileSuffix'         => '__LineworkModel__',
            'FillFileSuffix'             => '__FillModel__',
            'ExportIgnoresTagVisibility' => true
        }.freeze
        NA__SITEPLAN__EXPORTER_VERSION  = '1.1.1'.freeze                          # <-- Written into the manifest and GLB asset
        NA__SITEPLAN__SCHEMA_VERSION    = 1                                        # <-- Manifest schema version
        NA__SITEPLAN__MAX_DEPTH         = 64                                       # <-- Nesting guard for the walk
        NA__SITEPLAN__FLAT_TOLERANCE_M  = 0.5                                      # <-- Height span above which a layer is flagged
        NA__SITEPLAN__FAR_WARNING_M     = 2000.0                                   # <-- Distance from the origin flagged for precision
        NA__SITEPLAN__OLD_FILE_PATTERN  = /\A(?:.*?__)?TrueVision__SitePlan__[A-Za-z0-9]+__(?:LineworkModel|FillModel)__\.glb\z/i
        NA__SITEPLAN__PREFS_SECTION     = 'TrueVision3D_GlbBuilder'.freeze        # <-- Sketchup defaults section
        NA__SITEPLAN__PREFS_KEY_DIR     = 'SitePlanExportDir'.freeze              # <-- Last folder exported to
        NA__SITEPLAN__TV_CONTENT_FOLDER = '30__TrueVision__AppContent'.freeze     # <-- Picking this folder exports into its site plan folder
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Site Plan Export - Standards Data
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Load a DataLib JSON File, Local Copy First
        # ---------------------------------------------------------------
        # The local plugins-folder copy wins, so an SSOT edit that has not reached
        # GitHub yet still exports. The DataLib cache is the fallback.
        # ---------------------------------------------------------------
        def self.Na__SitePlan__LoadDataLibFile(file_name, file_key)
            local_path = File.expand_path(File.join('..', 'Na__Common__DataLib__CoreSuEntityStandards', file_name), __dir__)
            if File.exist?(local_path)
                begin
                    return JSON.parse(File.read(local_path, encoding: 'UTF-8'))
                rescue => e
                    Na__Log__Warn "  [SitePlan] Local #{file_name} unreadable, using the DataLib cache: #{e.message}"
                end
            end
            Na__DataLib__CacheData.Na__Cache__LoadData(file_key)
        rescue => e
            Na__Log__Warn "  [SitePlan] #{file_name} could not be loaded: #{e.message}"
            nil
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Index the Edge Materials SSOT as { MTE id => hex }
        # ---------------------------------------------------------------
        def self.Na__SitePlan__EdgeHexIndex(edge_data)
            index   = {}
            library = edge_data.is_a?(Hash) ? edge_data['Na__DataLib__CoreIndex__EdgeMaterials'] : nil
            return index unless library.is_a?(Hash)

            library.each_value do |series|
                next unless series.is_a?(Hash)
                series.each do |key, entry|
                    next unless entry.is_a?(Hash) && entry['HexValue'].is_a?(String)
                    index[key] = entry['HexValue']
                end
            end
            index
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build the Site Plan Layer Definitions { tag name => definition }
        # ---------------------------------------------------------------
        def self.Na__SitePlan__BuildLayerDefinitions(tags_data, edge_data)
            layers  = {}
            library = tags_data.is_a?(Hash) ? tags_data['Na__DataLib__CoreIndex__Tags'] : nil
            return layers unless library.is_a?(Hash)

            hex_by_id = self.Na__SitePlan__EdgeHexIndex(edge_data)

            library.each_value do |section|
                next unless section.is_a?(Hash)
                section.each_value do |entry|
                    next unless entry.is_a?(Hash)
                    stem = entry['SitePlan__ExportFileNameStem']
                    name = entry['Tag__SketchUpName']
                    next unless stem.is_a?(String) && name.is_a?(String)

                    line_id = entry['SitePlan__LineColourId']
                    fill_id = entry['SitePlan__FillColourId']

                    layers[name] = {
                        tag_name:   name,
                        stem:       stem,
                        label:      entry['SitePlan__LayerLabel'] || stem.sub('TrueVision__SitePlan__', ''),
                        group:      entry['SitePlan__LayerGroup'],
                        draw_order: entry['SitePlan__DrawOrder'],
                        fills:      entry['SitePlan__ExportFills'] == true,
                        scales:     entry['SitePlan__VisibleAtScales'].is_a?(Array) ? entry['SitePlan__VisibleAtScales'] : [],
                        style:      {
                            'LineColourId' => line_id,
                            'LineHex'      => line_id ? hex_by_id[line_id] : nil,
                            'LineType'     => entry['SitePlan__LineType'],
                            'LineWeightMm' => entry['SitePlan__LineWeightMm'],
                            'FillColourId' => fill_id,
                            'FillHex'      => fill_id ? hex_by_id[fill_id] : nil,
                            'FillOpacity'  => entry['SitePlan__FillOpacity']
                        }
                    }
                end
            end
            layers
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Merge SitePlanExportConfig Over the Defaults
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Config(tags_data)
            config = NA__SITEPLAN__CONFIG_DEFAULTS.dup
            block  = tags_data.is_a?(Hash) ? tags_data['SitePlanExportConfig'] : nil
            if block.is_a?(Hash)
                NA__SITEPLAN__CONFIG_DEFAULTS.each_key { |key| config[key] = block[key] unless block[key].nil? }
            end
            config
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Site Plan Export - Geometry Collection
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | New Collection Bucket for One Site Plan Layer
        # ---------------------------------------------------------------
        def self.Na__SitePlan__NewBucket(definition)
            {
                defn:          definition,
                positions:     [],                                                # <-- Flat [x,y,z, x,y,z, ...], two points per edge
                colors:        [],                                                # <-- Flat [r,g,b,a, ...], two per edge
                rings:         [],                                                # <-- [{ face:, outer:, points: [x,y,z, ...] }]
                face_count:    0,
                faces_ignored: 0,
                min:           [Float::INFINITY, Float::INFINITY, Float::INFINITY],
                max:           [-Float::INFINITY, -Float::INFINITY, -Float::INFINITY]
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Grow a Bucket's Bounds
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Grow(bucket, x, y, z)
            min = bucket[:min]
            max = bucket[:max]
            min[0] = x if x < min[0]
            min[1] = y if y < min[1]
            min[2] = z if z < min[2]
            max[0] = x if x > max[0]
            max[1] = y if y > max[1]
            max[2] = z if z > max[2]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add One Edge (World Metres, Y Up)
        # ---------------------------------------------------------------
        def self.Na__SitePlan__AddEdge(bucket, edge, transform)
            p0 = transform * edge.start.position
            p1 = transform * edge.end.position

            x0 = p0.x.to_f * INCHES_TO_METERS
            y0 = p0.y.to_f * INCHES_TO_METERS
            z0 = p0.z.to_f * INCHES_TO_METERS
            x1 = p1.x.to_f * INCHES_TO_METERS
            y1 = p1.y.to_f * INCHES_TO_METERS
            z1 = p1.z.to_f * INCHES_TO_METERS

            bucket[:positions].push(x0, y0, z0, x1, y1, z1)

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

            self.Na__SitePlan__Grow(bucket, x0, y0, z0)
            self.Na__SitePlan__Grow(bucket, x1, y1, z1)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add One Face as Rings (Outer Loop and Holes)
        # ---------------------------------------------------------------
        def self.Na__SitePlan__AddFace(bucket, face, transform)
            face_index = bucket[:face_count]
            bucket[:face_count] += 1

            face.loops.each do |face_loop|
                points = []
                face_loop.vertices.each do |vertex|
                    point = transform * vertex.position
                    x = point.x.to_f * INCHES_TO_METERS
                    y = point.y.to_f * INCHES_TO_METERS
                    z = point.z.to_f * INCHES_TO_METERS
                    points.push(x, y, z)
                    self.Na__SitePlan__Grow(bucket, x, y, z)
                end
                next if points.length < 9                                         # <-- A ring needs three corners
                bucket[:rings] << { face: face_index, outer: face_loop.outer?, points: points }
            end
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Count a Skipped Edge or Hidden Object Against Its Site Plan Layer
        # ---------------------------------------------------------------
        def self.Na__SitePlan__CountSkipped(ctx, owner, entity)
            return if owner.nil?
            counts = (ctx[:skipped][owner] ||= { edges: 0, objects: 0 })
            if entity.is_a?(Sketchup::Edge)
                counts[:edges] += 1
            elsif entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                counts[:objects] += 1
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Walk Entities, Collecting Site Plan Geometry by Nearest Site Plan Tag
        # ---------------------------------------------------------------
        # @param entities    [Sketchup::Entities]     Children to walk
        # @param transform   [Geom::Transformation]   Accumulated transform (Z up to Y up at the root)
        # @param current_tag [String|nil]             Nearest site plan tag above, nil when none
        # @param ctx         [Hash]                   :layers, :buckets, :skipped, :excluded, :exclusion_pattern, :ignore_visibility
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Collect(entities, transform, current_tag, ctx, depth = 0)
            return if depth > NA__SITEPLAN__MAX_DEPTH

            entities.each do |entity|
                next unless entity.respond_to?(:layer)

                layer    = entity.layer
                tag_name = layer ? layer.name : 'Layer0'
                next if ctx[:excluded].include?(tag_name)
                next if ctx[:exclusion_pattern] && tag_name =~ ctx[:exclusion_pattern]
                next if !ctx[:ignore_visibility] && layer && !layer.visible?

                owner = ctx[:layers].key?(tag_name) ? tag_name : current_tag

                if entity.respond_to?(:hidden?) && entity.hidden?
                    self.Na__SitePlan__CountSkipped(ctx, owner, entity)              # <-- Counted, so a gap in the linework shows in the summary
                    next
                end

                if entity.is_a?(Sketchup::Edge)
                    next if owner.nil?
                    if entity.soft? || entity.smooth?
                        self.Na__SitePlan__CountSkipped(ctx, owner, entity)
                        next
                    end
                    bucket = (ctx[:buckets][owner] ||= self.Na__SitePlan__NewBucket(ctx[:layers][owner]))
                    self.Na__SitePlan__AddEdge(bucket, entity, transform)
                elsif entity.is_a?(Sketchup::Face)
                    next if owner.nil?
                    bucket = (ctx[:buckets][owner] ||= self.Na__SitePlan__NewBucket(ctx[:layers][owner]))
                    if bucket[:defn][:fills]
                        self.Na__SitePlan__AddFace(bucket, entity, transform)
                    else
                        bucket[:faces_ignored] += 1
                    end
                elsif entity.is_a?(Sketchup::Group)
                    self.Na__SitePlan__Collect(entity.entities, transform * entity.transformation, owner, ctx, depth + 1)
                elsif entity.is_a?(Sketchup::ComponentInstance)
                    self.Na__SitePlan__Collect(entity.definition.entities, transform * entity.transformation, owner, ctx, depth + 1)
                end
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Scan the Model (No Files Written)
        # ---------------------------------------------------------------
        # Returns { config:, layers:, buckets:, skipped:, ssot_version: }. Buckets exist only
        # for site plan layers that hold geometry.
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Scan(model)
            tags_data  = self.Na__SitePlan__LoadDataLibFile('Na__DataLib__CoreIndex__Tags__.json', :tags)
            edge_data  = self.Na__SitePlan__LoadDataLibFile('Na__DataLib__CoreIndex__EdgeMaterials__.json', :edge_materials)
            layer_defs = self.Na__SitePlan__BuildLayerDefinitions(tags_data, edge_data)
            config     = self.Na__SitePlan__Config(tags_data)

            exclusions  = tags_data.is_a?(Hash) ? tags_data['ExportExclusions'] : nil
            excluded    = exclusions.is_a?(Hash) ? Array(exclusions['FullyExcludedTagNames']) : []
            pattern_str = exclusions.is_a?(Hash) ? exclusions['PatternExclusionRegex'] : nil

            ctx = {
                layers:            layer_defs,
                buckets:           {},
                skipped:           {},                                                # <-- { tag name => { edges:, objects: } } left out of the export
                excluded:          excluded.reject { |name| layer_defs.key?(name) },
                exclusion_pattern: (pattern_str.is_a?(String) ? Regexp.new(pattern_str) : nil),
                ignore_visibility: config['ExportIgnoresTagVisibility'] != false
            }

            self.Na__SitePlan__Collect(model.entities, Z_UP_TO_Y_UP_MATRIX, nil, ctx) unless layer_defs.empty?

            meta = tags_data.is_a?(Hash) ? tags_data['meta'] : nil
            {
                config:       config,
                layers:       layer_defs,
                buckets:      ctx[:buckets],
                skipped:      ctx[:skipped],
                ssot_version: (meta.is_a?(Hash) ? meta['version'] : nil)
            }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Site Plan Export - Checks and Summary
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Warnings per Layer { tag name => [text, ...] }
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Warnings(buckets, skipped = {})
            warnings = {}
            buckets.each do |tag_name, bucket|
                list = []

                height = bucket[:max][1] - bucket[:min][1]
                if height.finite? && height > NA__SITEPLAN__FLAT_TOLERANCE_M
                    list << "spans #{height.round(2)} m in height; site plan layers should be flat"
                end

                if bucket[:faces_ignored] > 0
                    list << "#{bucket[:faces_ignored]} face(s) ignored; this tag exports lines only"
                end

                if bucket[:defn][:fills] && bucket[:rings].empty? && !bucket[:positions].empty?
                    list << "no faces, so no fill; draw the outline as a closed face"
                end

                if bucket[:positions].empty? && !bucket[:rings].empty?
                    list << "faces but no visible edges, so nothing to outline; the layer is skipped"
                end

                reach = [bucket[:min][0].abs, bucket[:max][0].abs, bucket[:min][2].abs, bucket[:max][2].abs].max
                if reach.finite? && reach > NA__SITEPLAN__FAR_WARNING_M
                    list << "reaches #{reach.round} m from the origin; keep the model near the origin"
                end

                counts = skipped[tag_name]
                if counts && counts[:edges] > 0
                    list << "#{counts[:edges]} hidden, soft or smooth edge(s) skipped; unhide or unsoften any that belong on the drawing"
                end
                if counts && counts[:objects] > 0
                    list << "#{counts[:objects]} hidden group(s) or component(s) skipped"
                end

                warnings[tag_name] = list unless list.empty?
            end

            skipped.each do |tag_name, counts|
                next if buckets.key?(tag_name)
                list = []
                list << "all #{counts[:edges]} edge(s) are hidden, soft or smooth, so nothing was exported" if counts[:edges] > 0
                list << "#{counts[:objects]} hidden group(s) or component(s) skipped" if counts[:objects] > 0
                warnings[tag_name] = list unless list.empty?
            end
            warnings
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Bounds in Drawing Millimetres (X, Z)
        # ---------------------------------------------------------------
        def self.Na__SitePlan__BoundsMm(min, max)
            return nil unless min[0].finite? && max[0].finite? && min[2].finite? && max[2].finite?
            {
                'MinX' => (min[0] * 1000.0).round(1),
                'MinZ' => (min[2] * 1000.0).round(1),
                'MaxX' => (max[0] * 1000.0).round(1),
                'MaxZ' => (max[2] * 1000.0).round(1)
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Project Prefix for File Names
        # ---------------------------------------------------------------
        # "PS01_M10__SitePlanModel.skp" and "PS01__Model.skp" both give "PS01__".
        # Falls back to the model export's own prefix rule.
        # ---------------------------------------------------------------
        def self.Na__SitePlan__ProjectPrefix(model)
            path = model.path.to_s
            return '' if path.empty?

            match = File.basename(path).match(/\A([A-Za-z]{2}\d{2})(?=_)/)
            return "#{match[1].upcase}__" if match

            self.Na__Helpers__ExtractProjectPrefix(model)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Summary Shown Before Anything Is Written
        # ---------------------------------------------------------------
        def self.Na__SitePlan__SummaryText(scan, prefix)
            buckets = scan[:buckets]
            lines   = ['Site plan layers with geometry:']

            buckets.keys.sort.each do |tag_name|
                bucket = buckets[tag_name]
                text   = "  #{tag_name} - #{bucket[:positions].length / 6} line(s)"
                text  += ", #{bucket[:face_count]} face(s)" if bucket[:defn][:fills] && bucket[:face_count] > 0
                lines << text
            end

            unused = scan[:layers].keys - buckets.keys - (scan[:skipped] || {}).keys
            lines << ''
            lines << "Site plan tags with nothing on them: #{unused.length}" unless unused.empty?

            warnings = self.Na__SitePlan__Warnings(buckets, scan[:skipped] || {})
            unless warnings.empty?
                lines << ''
                lines << 'Check:'
                warnings.keys.sort.each do |tag_name|
                    warnings[tag_name].each { |text| lines << "  #{tag_name}: #{text}" }
                end
            end

            lines << ''
            lines << "Files are named #{prefix}TrueVision__SitePlan__{Layer}__LineworkModel__.glb"
            lines.join("\n")
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Site Plan Export - Writing
    # -----------------------------------------------------------------------------

        # HELPER FUNCTION | Choose the Export Folder
        # ---------------------------------------------------------------
        # Picking 30__TrueVision__AppContent exports into its site plan folder
        # (created if missing). Any other folder name asks first, because the
        # pipeline only publishes site plan data from SitePlan__DrawingData.
        # ---------------------------------------------------------------
        def self.Na__SitePlan__ChooseFolder(config)
            folder_name = config['ExportFolderName']
            last_dir    = Sketchup.read_default(NA__SITEPLAN__PREFS_SECTION, NA__SITEPLAN__PREFS_KEY_DIR, nil)

            options = { title: "Select the project's #{folder_name} folder" }
            options[:directory] = last_dir if last_dir.is_a?(String) && Dir.exist?(last_dir)

            dir = UI.select_directory(options)
            return nil unless dir

            if File.basename(dir) == NA__SITEPLAN__TV_CONTENT_FOLDER
                dir = File.join(dir, folder_name)
                FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
            end

            unless File.basename(dir) == folder_name
                answer = UI.messagebox(
                    "The pipeline only publishes site plan data from a folder named #{folder_name}.\n\n" \
                    "Export into \"#{File.basename(dir)}\" anyway?",
                    MB_YESNO
                )
                return nil unless answer == IDYES
            end

            Sketchup.write_default(NA__SITEPLAN__PREFS_SECTION, NA__SITEPLAN__PREFS_KEY_DIR, dir)
            dir
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Write One Linework GLB
        # ---------------------------------------------------------------
        def self.Na__SitePlan__WriteLinework(bucket, path)
            gltf, bin_buffer = Na__LineworkEngine__BuildGltfFromEdgeData(bucket[:positions], bucket[:colors])
            gltf['asset']['generator'] = "TrueVision3D GLB Builder Site Plan Export v#{NA__SITEPLAN__EXPORTER_VERSION}"
            gltf['asset']['extras']    = {
                'Na__SitePlanTag'  => bucket[:defn][:tag_name],
                'Na__SitePlanStem' => bucket[:defn][:stem]
            }
            gltf['meshes'][0]['name'] = bucket[:defn][:stem] if gltf['meshes'][0]
            Na__GlbEngine__WriteGlbFile(path, gltf, bin_buffer)
            true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Write One Fill GLB (One LINE_LOOP per Ring)
        # ---------------------------------------------------------------
        def self.Na__SitePlan__WriteFill(bucket, path)
            stem = bucket[:defn][:stem]
            gltf = {
                'asset'       => {
                    'version'   => '2.0',
                    'generator' => "TrueVision3D GLB Builder Site Plan Export v#{NA__SITEPLAN__EXPORTER_VERSION}",
                    'extras'    => { 'Na__SitePlanTag' => bucket[:defn][:tag_name], 'Na__SitePlanStem' => stem }
                },
                'scene'       => 0,
                'scenes'      => [{ 'nodes' => [0] }],
                'nodes'       => [{ 'mesh' => 0, 'name' => stem }],
                'meshes'      => [{ 'name' => "#{stem}__FillRings", 'primitives' => [] }],
                'accessors'   => [],
                'bufferViews' => [],
                'buffers'     => []
            }
            bin_buffer = String.new('', encoding: Encoding::ASCII_8BIT)

            bucket[:rings].each do |ring|
                accessor = Na__GltfHelpers__AddAccessor(gltf, bin_buffer, ring[:points], 5126, 'VEC3', 34962)
                next if accessor.nil?
                gltf['meshes'][0]['primitives'] << {
                    'attributes' => { 'POSITION' => accessor },
                    'mode'       => 2,                                                # <-- LINE_LOOP
                    'extras'     => {
                        'Na__SitePlanFace' => ring[:face],
                        'Na__SitePlanRing' => (ring[:outer] ? 'outer' : 'inner')
                    }
                }
            end

            return false if gltf['meshes'][0]['primitives'].empty?
            Na__GlbEngine__WriteGlbFile(path, gltf, bin_buffer)
            true
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Model North Angle in Degrees (0 when unset)
        # ---------------------------------------------------------------
        def self.Na__SitePlan__NorthAngleDeg(model)
            value = model.shadow_info['NorthAngle']
            value.nil? ? 0.0 : value.to_f
        rescue
            0.0
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write Every Layer, the Manifest, and Offer to Remove Old Files
        # ---------------------------------------------------------------
        # Returns { layers:, files:, removed:, warnings:, log_path: }.
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Write(model, scan, prefix, export_dir)
            config   = scan[:config]
            written  = []
            records  = []
            removed  = 0
            warnings = self.Na__SitePlan__Warnings(scan[:buckets], scan[:skipped] || {})
            overall  = self.Na__SitePlan__NewBucket(nil)

            self.Na__Log__OpenSession(export_dir)
            Na__Log__Puts "Site Plan Export v#{NA__SITEPLAN__EXPORTER_VERSION} - #{scan[:buckets].length} layer(s) with geometry"
            warnings.keys.sort.each do |tag_name|
                warnings[tag_name].each { |text| Na__Log__Warn "  [SitePlan] Check #{tag_name}: #{text}" }
            end

            begin
                scan[:buckets].keys.sort.each do |tag_name|
                    bucket = scan[:buckets][tag_name]
                    defn   = bucket[:defn]
                    base   = "#{prefix}#{defn[:stem]}"

                    if bucket[:positions].empty?
                        Na__Log__Warn "  [SitePlan] #{tag_name}: no visible edges - skipped"
                        next
                    end

                    linework_file = "#{base}#{config['LineworkFileSuffix']}.glb"
                    self.Na__SitePlan__WriteLinework(bucket, File.join(export_dir, linework_file))
                    written << linework_file
                    Na__Log__Puts "  [SitePlan] #{linework_file} - #{bucket[:positions].length / 6} line(s)"

                    fill_file = nil
                    if defn[:fills] && !bucket[:rings].empty?
                        candidate = "#{base}#{config['FillFileSuffix']}.glb"
                        if self.Na__SitePlan__WriteFill(bucket, File.join(export_dir, candidate))
                            fill_file = candidate
                            written << fill_file
                            Na__Log__Puts "  [SitePlan] #{fill_file} - #{bucket[:rings].length} ring(s) from #{bucket[:face_count]} face(s)"
                        end
                    end

                    self.Na__SitePlan__Grow(overall, bucket[:min][0], bucket[:min][1], bucket[:min][2])
                    self.Na__SitePlan__Grow(overall, bucket[:max][0], bucket[:max][1], bucket[:max][2])

                    records << {
                        'Layer__TagName'         => defn[:tag_name],
                        'Layer__CategoryKey'     => defn[:stem],
                        'Layer__Label'           => defn[:label],
                        'Layer__Group'           => defn[:group],
                        'Layer__DrawOrder'       => defn[:draw_order],
                        'Layer__LineworkFile'    => linework_file,
                        'Layer__FillFile'        => fill_file,
                        'Layer__SegmentCount'    => bucket[:positions].length / 6,
                        'Layer__RingCount'       => bucket[:rings].length,
                        'Layer__BoundsMm'        => self.Na__SitePlan__BoundsMm(bucket[:min], bucket[:max]),
                        'Layer__Style'           => defn[:style],
                        'Layer__VisibleAtScales' => defn[:scales],
                        'Layer__Warnings'        => warnings[tag_name] || []
                    }
                end

                records.sort_by! { |record| [record['Layer__DrawOrder'] || 0, record['Layer__TagName']] }

                manifest = {
                    'SitePlanData__Description'     => 'Site plan drawing data exported by the TrueVision3D GLB Builder. One linework GLB per site plan tag, plus a fill GLB for fill tags. Read by the ProjectVision build script and TrueVision3D site plan drawings.',
                    'SitePlanData__SchemaVersion'   => NA__SITEPLAN__SCHEMA_VERSION,
                    'SitePlanData__ProjectPrefix'   => prefix.sub(/__\z/, ''),
                    'SitePlanData__SourceModelFile' => (model.path.to_s.empty? ? nil : File.basename(model.path)),
                    'SitePlanData__ExportedIso'     => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),
                    'SitePlanData__ExporterVersion' => NA__SITEPLAN__EXPORTER_VERSION,
                    'SitePlanData__TagsSsotVersion' => scan[:ssot_version],
                    'SitePlanData__Units'           => 'metres',
                    'SitePlanData__UpAxis'          => 'Y',
                    'SitePlanData__NorthAngleDeg'   => self.Na__SitePlan__NorthAngleDeg(model),
                    'SitePlanData__BoundsMm'        => self.Na__SitePlan__BoundsMm(overall[:min], overall[:max]),
                    'SitePlanData__Layers'          => records
                }

                manifest_file = config['ManifestFileName']
                File.write(File.join(export_dir, manifest_file), JSON.pretty_generate(manifest) + "\n", mode: 'w:UTF-8')
                Na__Log__Puts "  [SitePlan] #{manifest_file} - #{records.length} layer(s)"

                stale = Dir.children(export_dir).select do |file_name|
                    file_name =~ NA__SITEPLAN__OLD_FILE_PATTERN && !written.include?(file_name)
                end

                unless stale.empty?
                    listing = stale.first(12).map { |file_name| "  #{file_name}" }.join("\n")
                    listing += "\n  ...and #{stale.length - 12} more" if stale.length > 12
                    answer = UI.messagebox(
                        "#{stale.length} older site plan GLB(s) in this folder were not written by this export:\n\n" \
                        "#{listing}\n\nDelete them, so the pipeline stops publishing them?",
                        MB_YESNO
                    )
                    if answer == IDYES
                        stale.each do |file_name|
                            begin
                                File.delete(File.join(export_dir, file_name))
                                removed += 1
                                Na__Log__Puts "  [SitePlan] Removed old #{file_name}"
                            rescue => e
                                Na__Log__Warn "  [SitePlan] Could not remove #{file_name}: #{e.message}"
                            end
                        end
                    end
                end
            ensure
                log_path = self.Na__Log__CloseSession
            end

            { layers: records.length, files: written.length, removed: removed, warnings: warnings, log_path: log_path }
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------



    # -----------------------------------------------------------------------------
    # REGION | Site Plan Export - Entry Point
    # -----------------------------------------------------------------------------

        # FUNCTION | Run the Site Plan Export (Scan, Confirm, Choose Folder, Write)
        # ---------------------------------------------------------------
        def self.Na__SitePlan__Run(model = Sketchup.active_model)
            return false unless model

            if model.active_path
                UI.messagebox('Close the group or component you are editing, then export the site plan again.')
                return false
            end

            scan = self.Na__SitePlan__Scan(model)

            if scan[:layers].empty?
                UI.messagebox(
                    "The Tags SSOT has no site plan tags.\n\n" \
                    'Na__DataLib__CoreIndex__Tags__.json v2.3.0 or later carries them (section 71_75__SitePlanTags__).'
                )
                return false
            end

            if scan[:buckets].empty?
                skipped_edges = (scan[:skipped] || {}).values.sum { |counts| counts[:edges] }
                skipped_note  = skipped_edges > 0 ? "\n\n#{skipped_edges} edge(s) on site plan tags are hidden, soft or smooth, so they were skipped." : ''
                UI.messagebox(
                    "Nothing to export: no geometry sits on a site plan tag (71-75).\n\n" \
                    'Tag the site plan groups (or their edges and faces), then try again.' + skipped_note
                )
                return false
            end

            prefix  = self.Na__SitePlan__ProjectPrefix(model)
            summary = self.Na__SitePlan__SummaryText(scan, prefix)
            return false unless UI.messagebox("#{summary}\n\nChoose the export folder next. Continue?", MB_YESNO) == IDYES

            export_dir = self.Na__SitePlan__ChooseFolder(scan[:config])
            return false unless export_dir

            result = self.Na__SitePlan__Write(model, scan, prefix, export_dir)

            message  = "Site plan export complete.\n\n"
            message += "#{result[:layers]} layer(s): #{result[:files]} GLB file(s) and the manifest, written to:\n#{export_dir}"
            message += "\n\nRemoved #{result[:removed]} older file(s)." if result[:removed] > 0
            unless result[:warnings].empty?
                checks = []
                result[:warnings].keys.sort.each { |tag_name| result[:warnings][tag_name].each { |text| checks << "  #{tag_name}: #{text}" } }
                listed = checks.first(8)
                listed << "  ...and #{checks.length - 8} more in the export log" if checks.length > 8
                message += "\n\nWritten, with these to check:\n#{listed.join("\n")}"
            end
            message += "\n\nExport log: #{File.basename(result[:log_path])}" if result[:log_path]
            message += "\n\nNext: run the ProjectVision build pipeline (option 3) to publish it."

            self.Na__Helpers__OpenFolder(export_dir)
            UI.messagebox(message)
            true
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D

# =============================================================================
# END OF FILE
# =============================================================================
