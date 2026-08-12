# =============================================================================
# NA COMPONENT EDITOR TOOLS - EXPORT TOOLS
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__ExportTools__Main__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__ExportTools
# PURPOSE    : Generate multi-view 2D projections plus full 3D mesh data for the
#              selected component and export one unified Na__ asset JSON file.
# CREATED    : 05-Aug-2026
#
# DESCRIPTION:
# - Works on the currently selected component instance or group (same capture
#   flow as Overview / Attributes / Thumbnail via Monitor Selection).
# - All geometry is read from the definition entities in definition space, so
#   the export is independent of where the instance sits in the model.
# - Local 0,0,0 comes from a nested group/component named or tagged
#   "00__OriginPoint" when present, otherwise the bounding box bottom centre
#   is used and a warning is recorded.
# - 2D views are fixed axis orthographic edge projections matching the
#   AssetBuildingEnvironment scene exporter:
#     * Front Elevation : view direction +Y | screen X=+X, screen Y=+Z
#     * Right Elevation : view direction -X | screen X=+Y, screen Y=+Z
#     * Top Plan        : view direction -Z | screen X=+X, screen Y=+Y
# - Edge keep rules: silhouette edges always; hard or border edges while any
#   adjacent face is camera facing; loose edges always.
# - Hidden-edge cull: every kept edge is raytest-sampled along the view
#   direction against the selected instance in the model, so detail buried
#   behind faces (lathe rings under a ball, back corners) drops out and each
#   view matches what SketchUp displays. Samples are taken at 25/50/75% along
#   the edge rather than at its endpoints: a revolve's seam vertices sit
#   exactly on the plane where its faces meet, where raytest is unreliable and
#   buried rings leaked through as stragglers. Interior samples sit clear of
#   that plane, and a partially buried edge still exports whole because one
#   interior sample reaching the camera keeps it.
# - Circle recovery: chains of tessellated segments that lie on a common
#   circle (lathe rings, exploded circles) are refitted and exported as true
#   Circle / Arc paths instead of chord runs. Faceted shapes are excluded -
#   octagons, hexagons and coarse "circles" are all ArcCurves whose vertices
#   lie on the circumcircle, so both the arc path and the chain refit would
#   otherwise round them off. The test is tessellation density normalised to a
#   full turn (NA_ARC_MIN_SEGMENTS_PER_TURN), not Curve#is_polygon?, which only
#   records how a curve was created and reports false for an 8-sided circle.
# - 3D capture mirrors the Element Assembly Studio unified exporter: per-vertex
#   normals via face.mesh(7), real edge records with soft/smooth flags, and a
#   full object hierarchy block with local and world matrices.
#
# EDGE STYLE CAPTURE (schema 1.2.0)
# - Every exported edge carries the authored SketchUp style so downstream
#   consumers never have to guess with an angle-based softening filter:
#     Na__Edge__IsSoft      edge not drawn AND adjacent faces merge into a
#                           Surface entity. Does not itself change shading.
#     Na__Edge__IsSmooth    adjacent face shading blends across the edge.
#                           On its own the edge STAYS VISIBLE - SketchUp hides
#                           it only because Soften/Smooth sets both together.
#     Na__Edge__IsHidden    Edit > Hide. Not drawn, no surface merge, shading
#                           unchanged.
#     Na__Edge__IsDisplayed resolved "does SketchUp draw this line" answer:
#                           !soft && !hidden && tag visible.
#     Na__Edge__ColorHex    colour of a material painted on the edge itself,
#                           with HasOwnMaterial distinguishing an authored
#                           colour from the black default.
#   Faces gain the matching Na__Face__IsHidden / IsDisplayed / TagName /
#   BackMaterial, and hierarchy nodes gain Na__Object__IsHidden / TagVisible.
# - Because the flags now have to survive, the Mesh3D traversal no longer
#   culls hidden geometry (NA_CAPTURE_HIDDEN_GEOMETRY). Before 1.2.0 hidden
#   edges and faces were dropped during collection, so IsHidden could never
#   be anything but false. The 2D projection views are unchanged - those are
#   a display projection and still exclude hidden / invisible-tag linework.
# - Loose edges (no adjacent face) now export. Previously only face-loop
#   vertex positions were indexed, so unfaced linework failed the vertex
#   lookup and was silently discarded.
# - Vertex normals are averaged across smoothed edges by face.mesh(7), so
#   smooth shading is baked into the exported normals already.
# - Export filename mirrors the component name (illegal filesystem characters
#   stripped, trailing underscores normalised to the Na__ double underscore
#   suffix). The product code is the leading digit block of the component name
#   (for example 50_1001 from 50_1001__Finial__Ball_) and is written to both
#   Na__Asset__Metadata__Id and Na__Asset__ValeSpec__ProductCode.
#
# =============================================================================

require 'sketchup.rb'
require 'json'

module Na__ComponentEditorTools
    module Na__ExportTools

# -----------------------------------------------------------------------------
# REGION | Module Constants
# -----------------------------------------------------------------------------

        NA_INCH_TO_MM                  = 25.4
        NA_ORIGIN_NAME                 = '00__OriginPoint'.freeze

        # MODULE CONSTANT | Capture Hidden / Invisible-Tag Geometry in Mesh3D
        # ------------------------------------------------------------
        # When true the Mesh3D + ObjectHierarchy3D capture records hidden
        # edges, hidden faces and geometry on invisible tags and flags them
        # (Na__Edge__IsHidden / Na__Face__IsHidden / Na__Object__IsHidden)
        # instead of dropping them. This is what lets an authored component
        # round-trip: the Lantern Importer can re-hide exactly what the
        # author hid rather than guessing from a softening angle threshold.
        #
        # The 2D projection views are deliberately NOT affected - those are a
        # display projection, so hidden and invisible-tag linework stays out.
        #
        # Flip to false to restore the pre-1.2.0 "visible geometry only" mesh.
        NA_CAPTURE_HIDDEN_GEOMETRY     = true

        # MODULE CONSTANT | Fallback Edge Colour (SketchUp draws untinted edges black)
        # ------------------------------------------------------------
        NA_DEFAULT_EDGE_RGB            = [0, 0, 0].freeze

        NA_EXPORT_DIR_REGISTRY_SECTION = 'Na__ComponentEditorTools__ExportTools'.freeze
        NA_EXPORT_DIR_REGISTRY_KEY     = 'na_last_export_directory'.freeze

        NA_MIN_SEG_MM                  = 0.05                                  # <-- Drop projected fragments shorter than this
        NA_JOIN_GAP_MM                 = 0.05                                  # <-- Merge collinear intervals with gaps up to this
        NA_FACING_EPS                  = 1.0e-4                                # <-- Dot-product band treated as edge-on to camera
        NA_AXIS_PARALLEL_EPS           = 0.999                                 # <-- Min |dot| for an arc plane to face the camera
        NA_CIRCLE_FIT_TOL_MM           = 0.02                                  # <-- Max radial residual for a chain to count as a circle
        NA_CIRCLE_FIT_MIN_POINTS       = 10                                    # <-- Min chain points before circle fitting is attempted
        NA_CHAIN_NODE_ROUND_DP         = 2                                     # <-- Endpoint rounding (0.01mm) for chain adjacency

        NA_OCCLUSION_TOL_IN            = 0.15 / 25.4                           # <-- Depth slack before a nearer hit counts as an occluder
        NA_OCCLUSION_STEP_IN           = 0.04                                  # <-- Recast advance past ignorable hits (about 1mm)
        NA_OCCLUSION_MAX_CASTS         = 16                                    # <-- Max recasts per sample ray (origin marker / foreign hits only)
        NA_OCCLUSION_MAX_EDGES         = 20000                                 # <-- Above this the hidden-edge cull is skipped for speed
        NA_OCCLUSION_SAMPLE_FRACTIONS  = [0.25, 0.5, 0.75].freeze              # <-- Interior sample positions along each edge
        NA_OCCLUSION_MIN_SPAN_IN       = 0.5 / 25.4                            # <-- Below this an edge falls back to endpoint sampling
        NA_ARC_MIN_SEGMENTS_PER_TURN   = 16                                    # <-- Coarser than this and a curve is faceted, not round

        NA_VIEW_DEFINITIONS = [
            {
                :key   => 'Na__Asset__Elevation2D__Front'.freeze,
                :label => 'Front Elevation'.freeze,
                :dir   => [0.0, 1.0, 0.0].freeze,
                :right => [1.0, 0.0, 0.0].freeze,
                :up    => [0.0, 0.0, 1.0].freeze,
                :axes  => 'X=world +X, Y=world +Z | view direction +Y'.freeze
            },
            {
                :key   => 'Na__Asset__Elevation2D__Right'.freeze,
                :label => 'Right Elevation'.freeze,
                :dir   => [-1.0, 0.0, 0.0].freeze,
                :right => [0.0, 1.0, 0.0].freeze,
                :up    => [0.0, 0.0, 1.0].freeze,
                :axes  => 'X=world +Y, Y=world +Z | view direction -X'.freeze
            },
            {
                :key   => 'Na__Asset__Plan2D__Top'.freeze,
                :label => 'Top Plan'.freeze,
                :dir   => [0.0, 0.0, -1.0].freeze,
                :right => [1.0, 0.0, 0.0].freeze,
                :up    => [0.0, 1.0, 0.0].freeze,
                :axes  => 'X=world +X, Y=world +Y | view direction -Z'.freeze
            }
        ].freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module State
# -----------------------------------------------------------------------------

        @na_last_document       = nil
        @na_last_file_name      = nil
        @na_last_component_name = nil

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - Preview Generation
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__GeneratePreview
            model = Sketchup.active_model
            selected_instance = Na__SelectionInspector.Na__ComponentEditorTools__SelectedInstance

            unless model && selected_instance
                return self.Na__ComponentEditorTools__Result(false, 'Select one component instance or group, then generate the preview.')
            end

            definition = selected_instance.definition
            unless definition
                return self.Na__ComponentEditorTools__Result(false, 'Selected entity has no definition to export.')
            end

            warnings = []
            component_name = selected_instance.name.to_s.strip
            component_name = definition.name.to_s.strip if component_name.empty?
            component_name = 'UntitledComponent' if component_name.empty?

            origin_point, origin_warning = self.Na__ComponentEditorTools__ResolveOrigin(definition)
            warnings << origin_warning if origin_warning

            edge_records = self.Na__ComponentEditorTools__CollectEdgeRecords(definition.entities, Geom::Transformation.new, [], {})

            occlusion_context = {
                :model              => model,
                :instance           => selected_instance,
                :instance_transform => selected_instance.transformation,
                :ray_offset         => model.bounds.diagonal.to_f * 1.5 + 100.0,
                :warnings           => warnings
            }

            view_blocks = {}
            view_stats  = []
            NA_VIEW_DEFINITIONS.each do |view_def|
                block, stats = self.Na__ComponentEditorTools__CaptureView(edge_records, origin_point, view_def, occlusion_context)
                if block
                    view_blocks[view_def[:key]] = block
                    view_stats << stats
                else
                    warnings << "#{view_def[:label]} produced no linework."
                end
            end

            mesh_block, hierarchy_block, mesh_stats = self.Na__ComponentEditorTools__CaptureMesh(definition, origin_point)
            warnings << 'No 3D faces found - Na__Asset__Mesh3D is null.' unless mesh_block
            view_stats << mesh_stats if mesh_stats

            if view_blocks.empty? && mesh_block.nil?
                return self.Na__ComponentEditorTools__Result(false, 'No exportable geometry found in the selected component.')
            end

            product_code = self.Na__ComponentEditorTools__ExtractProductCode(component_name)
            warnings << 'No leading product code found in the component name.' if product_code.empty?

            document = self.Na__ComponentEditorTools__BuildDocument(
                model, component_name, product_code, view_blocks, mesh_block, hierarchy_block, warnings
            )

            file_name = self.Na__ComponentEditorTools__OutputFileName(component_name)

            @na_last_document       = document
            @na_last_file_name      = file_name
            @na_last_component_name = component_name

            self.Na__ComponentEditorTools__Result(true, "Preview generated for #{component_name}.", {
                :component_name   => component_name,
                :product_code     => product_code,
                :file_name        => file_name,
                :warnings         => warnings,
                :stats            => view_stats,
                :preview_document => self.Na__ComponentEditorTools__PreviewDocumentCopy(document)
            })
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "Preview failed: #{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - JSON Export
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__ExportJson
            unless @na_last_document
                return self.Na__ComponentEditorTools__Result(false, 'Generate a preview first, then export.')
            end

            start_dir   = self.Na__ComponentEditorTools__ResolveExportDirectory
            output_path = UI.savepanel('Export Na Asset JSON', start_dir, @na_last_file_name.to_s)

            unless output_path
                return self.Na__ComponentEditorTools__Result(false, 'Export cancelled - no file was saved.')
            end

            output_path += '.json' unless output_path.downcase.end_with?('.json')
            json_string = self.Na__ComponentEditorTools__SerializeRoot(@na_last_document)

            File.open(output_path, 'w') { |file| file.write(json_string) }
            self.Na__ComponentEditorTools__RememberExportDirectory(output_path)

            self.Na__ComponentEditorTools__Result(true, "Exported: #{File.basename(output_path)}", { :path => output_path })
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "Export failed: #{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result and Naming Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Result(success_flag, message_text, extra_hash = {})
            { :success => !!success_flag, :message => message_text.to_s }.merge(extra_hash)
        end

        # HELPER | Leading digit block of the component name (unique bank code)
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__ExtractProductCode(component_name)
            match = component_name.to_s.strip.match(/\A(\d+(?:_\d+)?)/)
            match ? match[1] : ''
        end

        # HELPER | Output filename mirrors the component name
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__OutputFileName(component_name)
            base = component_name.to_s.strip.gsub(/[<>:"\/\\|?*]/, '').gsub(/\s+/, '_')
            base = base.sub(/_+\z/, '')
            base = 'UntitledComponent' if base.empty?
            "#{base}__.json"
        end

        def self.Na__ComponentEditorTools__ResolveExportDirectory
            remembered = Sketchup.read_default(NA_EXPORT_DIR_REGISTRY_SECTION, NA_EXPORT_DIR_REGISTRY_KEY, '')
            return remembered if remembered && !remembered.to_s.empty? && File.directory?(remembered)

            documents_dir = File.join(Dir.home, 'Documents')
            return documents_dir if File.directory?(documents_dir)
            return Dir.home if Dir.home && File.directory?(Dir.home)

            Sketchup.temp_dir
        rescue StandardError
            Sketchup.temp_dir
        end

        def self.Na__ComponentEditorTools__RememberExportDirectory(saved_file_path)
            return if saved_file_path.nil? || saved_file_path.to_s.empty?
            Sketchup.write_default(NA_EXPORT_DIR_REGISTRY_SECTION, NA_EXPORT_DIR_REGISTRY_KEY, File.dirname(saved_file_path))
        rescue StandardError
            nil
        end

        # HELPER | Preview copy with mesh faces stripped (JS wireframe only
        # needs vertices and edges; the export itself uses the full document)
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__PreviewDocumentCopy(document)
            preview = {}
            document.each { |key, value| preview[key] = value }

            mesh_block = document['Na__Asset__Mesh3D']
            if mesh_block.is_a?(Hash)
                reduced = {}
                mesh_block.each { |key, value| reduced[key] = value }
                reduced['Na__Geometry__Faces'] = []
                preview['Na__Asset__Mesh3D'] = reduced
            end

            preview
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Origin Resolution
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve local 0,0,0 for the definition
        # ------------------------------------------------------------
        # Returns [Geom::Point3d, warning_or_nil] in definition space.
        def self.Na__ComponentEditorTools__ResolveOrigin(definition)
            found = self.Na__ComponentEditorTools__FindNamedContainer(
                definition.entities, NA_ORIGIN_NAME, Geom::Transformation.new, {}
            )

            if found
                entity = found[:entity]
                local_centre = if entity.respond_to?(:definition) && entity.definition
                                   entity.definition.bounds.center
                               else
                                   entity.bounds.center
                               end
                return [local_centre.transform(found[:world_transform]), nil]
            end

            bounds = definition.bounds
            fallback = Geom::Point3d.new(bounds.center.x, bounds.center.y, bounds.min.z)
            [fallback, "No #{NA_ORIGIN_NAME} group found - bounding box bottom centre used as local 0,0,0."]
        end

        def self.Na__ComponentEditorTools__FindNamedContainer(entities, target_name, parent_world, definition_guard)
            entities.each do |entity|
                case entity
                when Sketchup::Group
                    world = parent_world * entity.transformation
                    return { :entity => entity, :world_transform => world } if self.Na__ComponentEditorTools__EntityNameMatches(entity, target_name)
                    result = self.Na__ComponentEditorTools__FindNamedContainer(entity.entities, target_name, world, definition_guard)
                    return result if result
                when Sketchup::ComponentInstance
                    world = parent_world * entity.transformation
                    return { :entity => entity, :world_transform => world } if self.Na__ComponentEditorTools__EntityNameMatches(entity, target_name)
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    result = self.Na__ComponentEditorTools__FindNamedContainer(entity.definition.entities, target_name, world, definition_guard)
                    definition_guard.delete(definition_id)
                    return result if result
                end
            end
            nil
        end

        def self.Na__ComponentEditorTools__EntityNameMatches(entity, target_name)
            entity_name = entity.respond_to?(:name) ? entity.name.to_s : ''
            tag_name    = (entity.respond_to?(:layer) && entity.layer) ? entity.layer.name.to_s : ''
            self.Na__ComponentEditorTools__NamesMatch(entity_name, target_name) ||
                self.Na__ComponentEditorTools__NamesMatch(tag_name, target_name)
        end

        def self.Na__ComponentEditorTools__NamesMatch(candidate_name, target_name)
            candidate = candidate_name.to_s.strip
            target    = target_name.to_s.strip
            return false if candidate.empty? || target.empty?
            return true  if candidate == target

            candidate_norm = candidate.downcase.gsub(/[^a-z0-9]/, '')
            target_norm    = target.downcase.gsub(/[^a-z0-9]/, '')
            return false if candidate_norm.empty? || target_norm.empty?
            candidate_norm == target_norm || candidate_norm.include?(target_norm)
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Geometry Collection
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__EntityExcluded(entity)
            return true unless entity
            return true if entity.respond_to?(:hidden?) && entity.hidden?
            if entity.respond_to?(:layer) && entity.layer && entity.layer.respond_to?(:visible?) && !entity.layer.visible?
                return true
            end
            false
        end

        def self.Na__ComponentEditorTools__OriginEntity(entity)
            if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                return true if self.Na__ComponentEditorTools__EntityNameMatches(entity, NA_ORIGIN_NAME)
            end
            if entity.respond_to?(:layer) && entity.layer
                return true if self.Na__ComponentEditorTools__NamesMatch(entity.layer.name.to_s, NA_ORIGIN_NAME)
            end
            false
        end

        def self.Na__ComponentEditorTools__CollectEdgeRecords(entities, world_transform, edge_records, definition_guard)
            entities.each do |entity|
                next if self.Na__ComponentEditorTools__EntityExcluded(entity)
                next if self.Na__ComponentEditorTools__OriginEntity(entity)

                case entity
                when Sketchup::Edge
                    edge_records << { :edge => entity, :world_transform => world_transform }
                when Sketchup::Group
                    child_world = world_transform * entity.transformation
                    self.Na__ComponentEditorTools__CollectEdgeRecords(entity.entities, child_world, edge_records, definition_guard)
                when Sketchup::ComponentInstance
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    child_world = world_transform * entity.transformation
                    self.Na__ComponentEditorTools__CollectEdgeRecords(entity.definition.entities, child_world, edge_records, definition_guard)
                    definition_guard.delete(definition_id)
                end
            end
            edge_records
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Transform and Normal Math
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Determinant3x3(transform)
            m = transform.to_a
            m[0] * (m[5] * m[10] - m[6] * m[9]) -
            m[4] * (m[1] * m[10] - m[2] * m[9]) +
            m[8] * (m[1] * m[6]  - m[2] * m[5])
        end

        def self.Na__ComponentEditorTools__NormalMatrix(transform)
            m = transform.to_a
            [
                 (m[5] * m[10] - m[9] * m[6]),  -(m[1] * m[10] - m[9] * m[2]),   (m[1] * m[6] - m[5] * m[2]),
                -(m[4] * m[10] - m[8] * m[6]),   (m[0] * m[10] - m[8] * m[2]),  -(m[0] * m[6] - m[4] * m[2]),
                 (m[4] * m[9]  - m[8] * m[5]),  -(m[0] * m[9]  - m[8] * m[1]),   (m[0] * m[5] - m[4] * m[1])
            ]
        end

        def self.Na__ComponentEditorTools__TransformNormal(normal_matrix, nx, ny, nz)
            c  = normal_matrix
            rx = c[0] * nx + c[1] * ny + c[2] * nz
            ry = c[3] * nx + c[4] * ny + c[5] * nz
            rz = c[6] * nx + c[7] * ny + c[8] * nz
            len = Math.sqrt(rx * rx + ry * ry + rz * rz)
            return [0.0, 0.0, 1.0] if len <= 1.0e-10
            [rx / len, ry / len, rz / len]
        end

        def self.Na__ComponentEditorTools__TransformKey(transform)
            transform.to_a.map { |value| value.round(6) }.join('|')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Classification
# -----------------------------------------------------------------------------

        # FUNCTION | Keep silhouette, camera-facing hard, border and loose edges
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__ClassifyKeptEdges(edge_records, view_dir)
            transform_cache = {}
            kept            = []

            edge_records.each do |record|
                edge = record[:edge]
                next unless edge && edge.valid?

                transform = record[:world_transform]
                cache_key = self.Na__ComponentEditorTools__TransformKey(transform)
                entry     = transform_cache[cache_key] ||= {
                    :normal_matrix => self.Na__ComponentEditorTools__NormalMatrix(transform),
                    :mirrored      => self.Na__ComponentEditorTools__Determinant3x3(transform) < 0.0
                }

                adjacent_faces = edge.faces.reject { |face| self.Na__ComponentEditorTools__EntityExcluded(face) }

                if adjacent_faces.empty?
                    kept << record
                    next
                end

                front_any = false
                back_any  = false
                adjacent_faces.each do |face|
                    normal = face.normal
                    wx, wy, wz = self.Na__ComponentEditorTools__TransformNormal(entry[:normal_matrix], normal.x.to_f, normal.y.to_f, normal.z.to_f)
                    if entry[:mirrored]
                        wx = -wx
                        wy = -wy
                        wz = -wz
                    end
                    dot = wx * view_dir[0] + wy * view_dir[1] + wz * view_dir[2]
                    front_any = true if dot < NA_FACING_EPS
                    back_any  = true if dot > NA_FACING_EPS
                end

                is_silhouette = front_any && back_any
                is_hard       = !edge.soft? && !edge.smooth?
                is_border     = adjacent_faces.length == 1

                kept << record if is_silhouette || ((is_hard || is_border) && front_any)
            end

            kept
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Hidden-Edge Occlusion Cull (Raytest Sampling)
# -----------------------------------------------------------------------------

        # FUNCTION | Drop edges hidden behind faces for this view direction
        # ------------------------------------------------------------
        # Samples every kept edge with model raytest casts along the view
        # direction from outside the model. An edge survives while any sample
        # is the first surface met (within tolerance), so lathe rings under a
        # ball, back corners and buried detail drop out and the view matches
        # what SketchUp itself displays.
        # Origin-marker hits and hits outside the selected instance are
        # recast past; any other nearer hit occludes, faces and edges alike.
        # Edge hits must occlude because revolved parts share seam planes:
        # a ray descending exactly along a shared seam meets every surface
        # crossing as an edge hit, and stepping past those let hidden
        # fragments leak through as straggler linework.
        #
        # SAMPLING IS INTERIOR, NOT PER ENDPOINT. Endpoint-only sampling leaked
        # buried lathe rings: a revolve's seam vertices sit exactly on the
        # plane where its faces meet, raytest is unreliable along that plane,
        # and the seam vertex read back as visible. The result was a scatter of
        # 1-6mm stragglers in plan, all with an endpoint at exactly y=0.
        # Sampling at 25/50/75% along the span puts every sample clear of the
        # seam, so those fragments now cull correctly, while a genuinely
        # half-buried silhouette edge still has a visible interior sample and
        # survives whole. Edges shorter than NA_OCCLUSION_MIN_SPAN_IN cannot
        # carry meaningful interior samples and fall back to the endpoint test.
        def self.Na__ComponentEditorTools__OcclusionCullEdges(kept_records, view_def, context)
            return kept_records unless context && context[:model]

            if kept_records.length > NA_OCCLUSION_MAX_EDGES
                if context[:warnings]
                    context[:warnings] << "#{view_def[:label]}: #{kept_records.length} edges exceed the occlusion limit - hidden-edge cull skipped for this view."
                end
                return kept_records
            end

            model              = context[:model]
            instance_transform = context[:instance_transform] || Geom::Transformation.new
            ray_offset         = context[:ray_offset] || 1000.0

            dir_local = view_def[:dir]
            dir_world = Geom::Vector3d.new(dir_local[0], dir_local[1], dir_local[2]).transform(instance_transform)
            return kept_records if dir_world.length == 0
            dir_world.normalize!

            kept_records.select do |record|
                edge      = record[:edge]
                transform = record[:world_transform]
                start_world = edge.start.position.transform(transform).transform(instance_transform)
                end_world   = edge.end.position.transform(transform).transform(instance_transform)

                self.Na__ComponentEditorTools__EdgeSurvivesOcclusion(
                    model, start_world, end_world, dir_world, ray_offset, context
                )
            end
        rescue StandardError => error
            if context && context[:warnings]
                context[:warnings] << "#{view_def[:label]}: occlusion cull failed (#{error.message}) - all classified edges kept."
            end
            kept_records
        end

        # HELPER | Does any sample along this edge reach the camera?
        # ------------------------------------------------------------
        # Interior samples first (they sit clear of revolve seam planes, where
        # raytest is unreliable). Short edges fall back to endpoint sampling.
        def self.Na__ComponentEditorTools__EdgeSurvivesOcclusion(model, start_world, end_world, dir_world, ray_offset, context)
            span_x = end_world.x.to_f - start_world.x.to_f
            span_y = end_world.y.to_f - start_world.y.to_f
            span_z = end_world.z.to_f - start_world.z.to_f
            span   = Math.sqrt(span_x * span_x + span_y * span_y + span_z * span_z)

            if span < NA_OCCLUSION_MIN_SPAN_IN
                return self.Na__ComponentEditorTools__SamplePointVisible(model, start_world, dir_world, ray_offset, context) ||
                       self.Na__ComponentEditorTools__SamplePointVisible(model, end_world, dir_world, ray_offset, context)
            end

            NA_OCCLUSION_SAMPLE_FRACTIONS.each do |fraction|
                sample_point = Geom::Point3d.new(
                    start_world.x.to_f + span_x * fraction,
                    start_world.y.to_f + span_y * fraction,
                    start_world.z.to_f + span_z * fraction
                )
                return true if self.Na__ComponentEditorTools__SamplePointVisible(model, sample_point, dir_world, ray_offset, context)
            end

            false
        end

        # HELPER | Is this world-space sample the first surface along the ray?
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__SamplePointVisible(model, sample_world, dir_world, ray_offset, context)
            ray_origin     = sample_world.offset(dir_world.reverse, ray_offset)
            sample_depth   = ray_origin.distance(sample_world)
            current_origin = ray_origin
            instance       = context[:instance]

            NA_OCCLUSION_MAX_CASTS.times do
                hit = model.raytest([current_origin, dir_world], true)
                return true unless hit

                hit_point, hit_path = hit
                hit_depth = ray_origin.distance(hit_point)
                return true if hit_depth >= sample_depth - NA_OCCLUSION_TOL_IN

                origin_marker = hit_path.is_a?(Array) && hit_path.any? { |entity| self.Na__ComponentEditorTools__OriginEntity(entity) }
                inside_target = instance.nil? || (hit_path.is_a?(Array) && hit_path.include?(instance))

                return false if !origin_marker && inside_target

                current_origin = hit_point.offset(dir_world, NA_OCCLUSION_STEP_IN)
            end
            true
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | View Capture Pipeline
# -----------------------------------------------------------------------------

        # FUNCTION | Capture one fixed-axis 2D view block
        # ------------------------------------------------------------
        # Returns [block_hash, stats_hash] or [nil, nil] when empty.
        def self.Na__ComponentEditorTools__CaptureView(edge_records, origin_pt, view_def, occlusion_context = nil)
            kept_records = self.Na__ComponentEditorTools__ClassifyKeptEdges(edge_records, view_def[:dir])
            return [nil, nil] if kept_records.empty?

            kept_records = self.Na__ComponentEditorTools__OcclusionCullEdges(kept_records, view_def, occlusion_context)
            return [nil, nil] if kept_records.empty?

            arcs, lines = self.Na__ComponentEditorTools__BuildViewPaths(kept_records, origin_pt, view_def)
            return [nil, nil] if arcs.empty? && lines.empty?

            bbox         = self.Na__ComponentEditorTools__CalcBbox2d(arcs, lines)
            circle_count = arcs.count { |arc| arc['IsCircle'] == true }

            block = {
                'Na__View__SourceSceneName'  => "FixedAxis__#{view_def[:label].gsub(' ', '')}",
                'Na__View__ProjectionType'   => 'OrthographicEdgeProjection | silhouette + camera-facing hard edges | raytest hidden-edge cull | circle refit',
                'Na__View__ViewDirection'    => view_def[:axes].split('view direction').last.to_s.strip,
                'Na__Geometry__OriginNote'   => "Local 0,0 = #{NA_ORIGIN_NAME} centre projected into this view. #{view_def[:label]} of asset.",
                'Na__Geometry__CoordSystem'  => "View plane | #{view_def[:axes]} | Units=mm | depth discarded",
                'Na__Geometry__BoundingBox'  => bbox,
                'Na__Geometry__Counts'       => {
                    'Na__Geometry__EdgeCount'    => kept_records.length,
                    'Na__Geometry__ArcCount'     => arcs.length,
                    'Na__Geometry__LineCount'    => lines.length,
                    'Na__Geometry__PolygonCount' => 0,
                    'Na__Geometry__CircleCount'  => circle_count
                },
                'Na__Geometry__Paths'        => arcs + lines
            }

            stats = {
                :label   => view_def[:label],
                :kept    => kept_records.length,
                :arcs    => arcs.length,
                :circles => circle_count,
                :lines   => lines.length,
                :width   => bbox.empty? ? 0.0 : bbox['Na__Geometry__Width_mm'],
                :height  => bbox.empty? ? 0.0 : bbox['Na__Geometry__Height_mm']
            }

            [block, stats]
        end

        # HELPER | Project a definition-space point into view millimetres
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__ProjectUv(point, origin_pt, view_def)
            rx = point.x - origin_pt.x
            ry = point.y - origin_pt.y
            rz = point.z - origin_pt.z
            right = view_def[:right]
            up    = view_def[:up]
            [
                (rx * right[0] + ry * right[1] + rz * right[2]) * NA_INCH_TO_MM,
                (rx * up[0]    + ry * up[1]    + rz * up[2])    * NA_INCH_TO_MM
            ]
        end

        # FUNCTION | Build arc and line paths for one view
        # ------------------------------------------------------------
        # Pipeline: exact ArcCurve paths where the arc plane faces the camera,
        # then dedupe raw segments, then chain-based circle refitting, then
        # collinear merge of whatever remains.
        #
        # FACETED CURVES ARE NOT ARCS. Octagons, hexagons and coarse "circles"
        # are all Sketchup::ArcCurve, with the radius being the circumradius
        # and every vertex sitting exactly on the circumcircle. Emitting one
        # through the arc path bulges each straight side out to that
        # circumcircle, which drew the octagonal ridge block as a circle in
        # plan (8 sides x 45 degrees = a full 360). CurveIsFaceted routes any
        # curve coarser than NA_ARC_MIN_SEGMENTS_PER_TURN to the straight
        # segment path instead.
        #
        # The same vertices-on-a-circle property also fools the chain circle
        # refit - a 12-sided shape fits a circle with zero residual - so
        # faceted segments are tagged :no_circle_fit and excluded from it.
        # Tagging rather than raising NA_CIRCLE_FIT_MIN_POINTS keeps genuine
        # part-circle chains (a partly occluded fine circle) refittable.
        def self.Na__ComponentEditorTools__BuildViewPaths(kept_records, origin_pt, view_def)
            arcs             = []
            segment_records  = []
            faceted_records  = []
            curve_groups     = {}

            kept_records.each do |record|
                curve = record[:edge].curve
                if !curve.is_a?(Sketchup::ArcCurve)
                    segment_records << record
                elsif self.Na__ComponentEditorTools__CurveIsFaceted(curve)
                    faceted_records << record
                else
                    key = "#{curve.object_id}|#{self.Na__ComponentEditorTools__TransformKey(record[:world_transform])}"
                    group = curve_groups[key] ||= { :curve => curve, :transform => record[:world_transform], :records => [] }
                    group[:records] << record
                end
            end

            curve_groups.each_value do |group|
                curve     = group[:curve]
                transform = group[:transform]
                if self.Na__ComponentEditorTools__ArcFacesCamera(curve, transform, view_def) && group[:records].length == curve.edges.length
                    arcs << self.Na__ComponentEditorTools__ArcPath(curve, transform, origin_pt, view_def)
                else
                    segment_records.concat(group[:records])
                end
            end

            raw_segments = []
            [[segment_records, false], [faceted_records, true]].each do |records, is_faceted|
                records.each do |record|
                    edge      = record[:edge]
                    transform = record[:world_transform]
                    raw_segments << {
                        :p1            => self.Na__ComponentEditorTools__ProjectUv(edge.start.position.transform(transform), origin_pt, view_def),
                        :p2            => self.Na__ComponentEditorTools__ProjectUv(edge.end.position.transform(transform), origin_pt, view_def),
                        :no_circle_fit => is_faceted
                    }
                end
            end

            deduped_segments        = self.Na__ComponentEditorTools__DedupeSegments(raw_segments)
            fitted_paths, leftovers = self.Na__ComponentEditorTools__FitChainsToCircles(deduped_segments)

            arcs  = self.Na__ComponentEditorTools__DedupeArcs(arcs + fitted_paths)
            lines = self.Na__ComponentEditorTools__MergeSegments(leftovers)

            [arcs, lines]
        end

        # HELPER | Is this ArcCurve visually faceted rather than round?
        # ------------------------------------------------------------
        # Curve#is_polygon? alone is NOT sufficient: it records how the curve
        # was created, not how it looks. A "circle" drawn with 8 sides, or an
        # exploded/copied polygon, reports is_polygon? == false yet is plainly
        # an octagon - which is exactly how the ridge block's octagonal shaft
        # ended up drawn as a circle in plan.
        #
        # The reliable measure is tessellation density normalised to a full
        # turn, since that is what decides whether the chords read as a curve:
        #     segments_per_turn = edge_count * 2PI / sweep
        # Below NA_ARC_MIN_SEGMENTS_PER_TURN each chord departs its arc by more
        # than about 2% of the radius, so the shape is faceted and must export
        # as straight segments. This works whichever way the curve was built,
        # and whether the group holds one 8-edge curve or eight 1-edge curves.
        #
        # is_polygon? is still honoured as an additional trigger when present.
        def self.Na__ComponentEditorTools__CurveIsFaceted(curve)
            return true if curve.respond_to?(:is_polygon?) && curve.is_polygon?

            edge_count = curve.edges.length
            return true if edge_count < 3

            sweep = (curve.end_angle.to_f - curve.start_angle.to_f).abs
            sweep = 2.0 * Math::PI if sweep <= 1.0e-9                           # <-- Full circles can report a zero span
            segments_per_turn = edge_count * (2.0 * Math::PI / sweep)

            segments_per_turn < NA_ARC_MIN_SEGMENTS_PER_TURN
        rescue StandardError
            false
        end

        def self.Na__ComponentEditorTools__ArcFacesCamera(curve, transform, view_def)
            normal = curve.normal
            wx, wy, wz = self.Na__ComponentEditorTools__TransformNormal(
                self.Na__ComponentEditorTools__NormalMatrix(transform), normal.x.to_f, normal.y.to_f, normal.z.to_f
            )
            dir = view_def[:dir]
            dot = wx * dir[0] + wy * dir[1] + wz * dir[2]
            dot.abs >= NA_AXIS_PARALLEL_EPS
        end

        def self.Na__ComponentEditorTools__ArcPath(curve, transform, origin_pt, view_def)
            center   = self.Na__ComponentEditorTools__ProjectUv(curve.center.transform(transform), origin_pt, view_def)
            start_pt = self.Na__ComponentEditorTools__ProjectUv(curve.edges.first.start.position.transform(transform), origin_pt, view_def)
            end_pt   = self.Na__ComponentEditorTools__ProjectUv(curve.edges.last.end.position.transform(transform), origin_pt, view_def)

            radius = Math.sqrt((start_pt[0] - center[0]) ** 2 + (start_pt[1] - center[1]) ** 2)

            start_deg = (Math.atan2(start_pt[1] - center[1], start_pt[0] - center[0]) * 180.0 / Math::PI).round(3)
            end_deg   = (Math.atan2(end_pt[1]   - center[1], end_pt[0]   - center[0]) * 180.0 / Math::PI).round(3)
            is_circle = curve.circular?

            end_deg = (start_deg + 360.0).round(3) if is_circle
            sweep_deg = (end_deg - start_deg).round(3)
            sweep_deg += 360.0 if !is_circle && sweep_deg <= 0.0

            self.Na__ComponentEditorTools__ArcPathHash(center, radius, start_deg, end_deg, sweep_deg, start_pt, end_pt, is_circle)
        end

        def self.Na__ComponentEditorTools__ArcPathHash(center, radius, start_deg, end_deg, sweep_deg, start_pt, end_pt, is_circle)
            {
                'PathType'       => is_circle ? 'Circle' : 'Arc',
                'VertexName'     => '',
                'Center_mm'      => { 'X' => center[0].round(3),   'Y' => center[1].round(3) },
                'Radius_mm'      => radius.round(3),
                'StartAngle_deg' => start_deg,
                'EndAngle_deg'   => end_deg,
                'Sweep_deg'      => sweep_deg.round(3),
                'StartPoint_mm'  => { 'X' => start_pt[0].round(3), 'Y' => start_pt[1].round(3) },
                'EndPoint_mm'    => { 'X' => end_pt[0].round(3),   'Y' => end_pt[1].round(3) },
                'IsCircle'       => !!is_circle
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Segment Dedupe, Chain Circle Fitting and Collinear Merge
# -----------------------------------------------------------------------------

        # HELPER | Remove exact duplicate segments (front/back coincident edges)
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__DedupeSegments(raw_segments)
            seen = {}
            out  = []
            raw_segments.each do |segment|
                a = [segment[:p1][0].round(NA_CHAIN_NODE_ROUND_DP), segment[:p1][1].round(NA_CHAIN_NODE_ROUND_DP)]
                b = [segment[:p2][0].round(NA_CHAIN_NODE_ROUND_DP), segment[:p2][1].round(NA_CHAIN_NODE_ROUND_DP)]
                next if a == b
                key = (a <=> b) <= 0 ? [a, b] : [b, a]

                # A coincident duplicate must not launder away the polygon tag,
                # or the survivor could still be circle-refitted.
                if seen[key]
                    seen[key][:no_circle_fit] = true if segment[:no_circle_fit]
                    next
                end

                seen[key] = segment
                out << segment
            end
            out
        end

        # FUNCTION | Refit chains of segments as circles and arcs
        # ------------------------------------------------------------
        # Builds endpoint adjacency on deduped segments, walks degree-2 chains,
        # then fits each long chain with a least squares circle. Chains that
        # fit within tolerance are emitted as Circle (closed) or Arc (open)
        # paths; everything else is returned for the collinear merge pass.
        # Recovers lathe rings and exploded circles that carry no ArcCurve.
        def self.Na__ComponentEditorTools__FitChainsToCircles(segments)
            return [[], segments] if segments.length < 3

            node_key = lambda do |point|
                "#{point[0].round(NA_CHAIN_NODE_ROUND_DP)}|#{point[1].round(NA_CHAIN_NODE_ROUND_DP)}"
            end

            adjacency = Hash.new { |hash, key| hash[key] = [] }
            segments.each_with_index do |segment, index|
                adjacency[node_key.call(segment[:p1])] << index
                adjacency[node_key.call(segment[:p2])] << index
            end

            visited      = {}
            fitted_paths = []
            leftovers    = []

            segments.each_with_index do |segment, index|
                next if visited[index]

                chain_indices = [index]
                visited[index] = true

                start_key = node_key.call(segment[:p1])
                end_key   = node_key.call(segment[:p2])

                # Walk forward from the segment end, then backward from the start
                [[end_key, :forward], [start_key, :backward]].each do |walk_key, direction|
                    current_key  = walk_key
                    current_seg  = index
                    loop do
                        neighbours = adjacency[current_key].reject { |seg_index| seg_index == current_seg || visited[seg_index] }
                        break unless adjacency[current_key].length == 2 && neighbours.length == 1

                        next_index = neighbours[0]
                        visited[next_index] = true
                        if direction == :forward
                            chain_indices << next_index
                        else
                            chain_indices.unshift(next_index)
                        end

                        next_segment = segments[next_index]
                        next_a = node_key.call(next_segment[:p1])
                        next_b = node_key.call(next_segment[:p2])
                        current_key = (next_a == current_key) ? next_b : next_a
                        current_seg = next_index
                    end
                end

                chain_points, is_closed = self.Na__ComponentEditorTools__OrderedChainPoints(segments, chain_indices, node_key)

                # A faceted shape's vertices all sit exactly on its
                # circumcircle, so a chain containing any faceted segment would
                # fit a circle with zero residual and round it off. Never
                # refit those.
                chain_is_faceted = chain_indices.any? { |seg_index| segments[seg_index][:no_circle_fit] }

                fitted = nil
                if !chain_is_faceted && chain_points && chain_points.length >= NA_CIRCLE_FIT_MIN_POINTS
                    fitted = self.Na__ComponentEditorTools__CircleFitPath(chain_points, is_closed)
                end

                if fitted
                    fitted_paths << fitted
                else
                    chain_indices.each { |seg_index| leftovers << segments[seg_index] }
                end
            end

            [fitted_paths, leftovers]
        end

        # HELPER | Ordered point list for a chain of segment indices
        # ------------------------------------------------------------
        # Returns [points_array, closed_flag] or [nil, false] when the chain
        # cannot be ordered cleanly (junctions, forks).
        def self.Na__ComponentEditorTools__OrderedChainPoints(segments, chain_indices, node_key)
            return [nil, false] if chain_indices.empty?

            remaining = {}
            chain_indices.each { |seg_index| remaining[seg_index] = true }

            first_segment = segments[chain_indices[0]]
            points        = [first_segment[:p1], first_segment[:p2]]
            remaining.delete(chain_indices[0])

            extended = true
            while extended && !remaining.empty?
                extended = false
                tail_key = node_key.call(points.last)
                head_key = node_key.call(points.first)

                remaining.each_key do |seg_index|
                    segment = segments[seg_index]
                    a_key = node_key.call(segment[:p1])
                    b_key = node_key.call(segment[:p2])

                    if a_key == tail_key
                        points << segment[:p2]
                    elsif b_key == tail_key
                        points << segment[:p1]
                    elsif a_key == head_key
                        points.unshift(segment[:p2])
                    elsif b_key == head_key
                        points.unshift(segment[:p1])
                    else
                        next
                    end

                    remaining.delete(seg_index)
                    extended = true
                    break
                end
            end

            return [nil, false] unless remaining.empty?

            closed = node_key.call(points.first) == node_key.call(points.last) && points.length > 3
            points = points[0...-1] if closed
            [points, closed]
        end

        # HELPER | Least squares circle fit (Kasa method) with residual check
        # ------------------------------------------------------------
        # Returns an Arc/Circle path hash, or nil when the chain is not a
        # clean circular run.
        def self.Na__ComponentEditorTools__CircleFitPath(chain_points, is_closed)
            n = chain_points.length.to_f
            suu = 0.0; suv = 0.0; svv = 0.0
            su  = 0.0; sv  = 0.0
            b1  = 0.0; b2  = 0.0; b3  = 0.0

            chain_points.each do |point|
                u = point[0]
                v = point[1]
                q = u * u + v * v
                suu += u * u
                suv += u * v
                svv += v * v
                su  += u
                sv  += v
                b1  -= q * u
                b2  -= q * v
                b3  -= q
            end

            det = suu * (svv * n - sv * sv) - suv * (suv * n - sv * su) + su * (suv * sv - svv * su)
            return nil if det.abs < 1.0e-9

            d_coef = (b1 * (svv * n - sv * sv) - suv * (b2 * n - sv * b3) + su * (b2 * sv - svv * b3)) / det
            e_coef = (suu * (b2 * n - sv * b3) - b1 * (suv * n - sv * su) + su * (suv * b3 - b2 * su)) / det
            f_coef = (suu * (svv * b3 - b2 * sv) - suv * (suv * b3 - b2 * su) + b1 * (suv * sv - svv * su)) / det

            cx = -d_coef / 2.0
            cy = -e_coef / 2.0
            r_squared = cx * cx + cy * cy - f_coef
            return nil if r_squared <= 0.0

            radius = Math.sqrt(r_squared)
            return nil if radius > 100_000.0

            chain_points.each do |point|
                distance = Math.sqrt((point[0] - cx) ** 2 + (point[1] - cy) ** 2)
                return nil if (distance - radius).abs > NA_CIRCLE_FIT_TOL_MM
            end

            center = [cx, cy]

            if is_closed
                start_pt  = chain_points.first
                start_deg = (Math.atan2(start_pt[1] - cy, start_pt[0] - cx) * 180.0 / Math::PI).round(3)
                end_deg   = (start_deg + 360.0).round(3)
                return self.Na__ComponentEditorTools__ArcPathHash(center, radius, start_deg, end_deg, 360.0, start_pt, start_pt, true)
            end

            start_pt = chain_points.first
            end_pt   = chain_points.last
            mid_pt   = chain_points[chain_points.length / 2]

            start_deg = Math.atan2(start_pt[1] - cy, start_pt[0] - cx) * 180.0 / Math::PI
            end_deg   = Math.atan2(end_pt[1]   - cy, end_pt[0]   - cx) * 180.0 / Math::PI
            mid_deg   = Math.atan2(mid_pt[1]   - cy, mid_pt[0]   - cx) * 180.0 / Math::PI

            ccw_sweep_end = (end_deg - start_deg) % 360.0
            ccw_sweep_mid = (mid_deg - start_deg) % 360.0

            if ccw_sweep_mid <= ccw_sweep_end
                sweep = ccw_sweep_end
                self.Na__ComponentEditorTools__ArcPathHash(
                    center, radius, start_deg.round(3), (start_deg + sweep).round(3), sweep.round(3), start_pt, end_pt, false
                )
            else
                sweep = (start_deg - end_deg) % 360.0
                self.Na__ComponentEditorTools__ArcPathHash(
                    center, radius, end_deg.round(3), (end_deg + sweep).round(3), sweep.round(3), end_pt, start_pt, false
                )
            end
        end

        # HELPER | Remove coincident duplicate arc paths
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__DedupeArcs(arcs)
            seen = {}
            out  = []
            arcs.each do |arc|
                key = if arc['IsCircle']
                          ['C', arc['Center_mm']['X'].round(2), arc['Center_mm']['Y'].round(2), arc['Radius_mm'].round(2)]
                      else
                          ['A', arc['Center_mm']['X'].round(2), arc['Center_mm']['Y'].round(2), arc['Radius_mm'].round(2),
                           arc['StartAngle_deg'].round(1), arc['EndAngle_deg'].round(1)]
                      end
                next if seen[key]
                seen[key] = true
                out << arc
            end
            out
        end

        # FUNCTION | Merge collinear overlapping segments into clean lines
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__MergeSegments(raw_segments)
            line_groups = {}

            raw_segments.each do |segment|
                dx = segment[:p2][0] - segment[:p1][0]
                dy = segment[:p2][1] - segment[:p1][1]
                length = Math.sqrt(dx * dx + dy * dy)
                next if length < NA_MIN_SEG_MM

                dx /= length
                dy /= length
                if dx < -1.0e-9 || (dx.abs <= 1.0e-9 && dy < 0.0)
                    dx = -dx
                    dy = -dy
                end

                offset = segment[:p1][0] * dy - segment[:p1][1] * dx
                key    = [dx.round(4), dy.round(4), offset.round(2)]

                t1 = segment[:p1][0] * dx + segment[:p1][1] * dy
                t2 = segment[:p2][0] * dx + segment[:p2][1] * dy
                t1, t2 = t2, t1 if t1 > t2

                group = line_groups[key] ||= { :dx => dx, :dy => dy, :offset => offset, :intervals => [] }
                group[:intervals] << [t1, t2]
            end

            lines = []
            line_groups.each_value do |group|
                group[:intervals].sort_by! { |interval| interval[0] }
                merged = []
                group[:intervals].each do |interval|
                    if merged.empty? || interval[0] > merged.last[1] + NA_JOIN_GAP_MM
                        merged << [interval[0], interval[1]]
                    elsif interval[1] > merged.last[1]
                        merged.last[1] = interval[1]
                    end
                end

                merged.each do |t1, t2|
                    next if (t2 - t1) < NA_MIN_SEG_MM
                    lines << {
                        'PathType'   => 'Line',
                        'VertexName' => '',
                        'Start_mm'   => {
                            'X' => (t1 * group[:dx] + group[:offset] * group[:dy]).round(3),
                            'Y' => (t1 * group[:dy] - group[:offset] * group[:dx]).round(3)
                        },
                        'End_mm'     => {
                            'X' => (t2 * group[:dx] + group[:offset] * group[:dy]).round(3),
                            'Y' => (t2 * group[:dy] - group[:offset] * group[:dx]).round(3)
                        }
                    }
                end
            end

            lines
        end

        def self.Na__ComponentEditorTools__CalcBbox2d(arcs, lines)
            xs = []
            ys = []
            lines.each do |line|
                xs << line['Start_mm']['X'] << line['End_mm']['X']
                ys << line['Start_mm']['Y'] << line['End_mm']['Y']
            end
            arcs.each do |arc|
                cx = arc['Center_mm']['X']
                cy = arc['Center_mm']['Y']
                r  = arc['Radius_mm']
                xs << (cx - r) << (cx + r)
                ys << (cy - r) << (cy + r)
            end
            return {} if xs.empty?
            {
                'Na__Geometry__MinX_mm'   => xs.min.round(3),
                'Na__Geometry__MaxX_mm'   => xs.max.round(3),
                'Na__Geometry__MinY_mm'   => ys.min.round(3),
                'Na__Geometry__MaxY_mm'   => ys.max.round(3),
                'Na__Geometry__Width_mm'  => (xs.max - xs.min).round(3),
                'Na__Geometry__Height_mm' => (ys.max - ys.min).round(3)
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | 3D Mesh and Hierarchy Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Mesh3D + ObjectHierarchy3D from the definition
        # ------------------------------------------------------------
        # Returns [mesh_block, hierarchy_block, stats_hash] (nils when empty).
        def self.Na__ComponentEditorTools__CaptureMesh(definition, origin_pt)
            hierarchy_nodes = []
            face_records    = []
            edge_records    = []
            node_seq        = 0

            root_node_id = self.Na__ComponentEditorTools__NodeId(node_seq)
            node_seq += 1
            hierarchy_nodes << {
                'Na__Object__NodeId'                    => root_node_id,
                'Na__Object__ParentNodeId'              => nil,
                'Na__Object__EntityType'                => 'ComponentDefinition',
                'Na__Object__Name'                      => definition.name.to_s,
                'Na__Object__DefinitionName'            => definition.name.to_s,
                'Na__Object__TagName'                   => '',
                'Na__Object__TagVisible'                => true,
                'Na__Object__IsHidden'                  => false,
                'Na__Object__MaterialName'              => '',
                'Na__Object__LocalTransform__Matrix4x4' => self.Na__ComponentEditorTools__TransformToMatrix(Geom::Transformation.new),
                'Na__Object__WorldTransform__Matrix4x4' => self.Na__ComponentEditorTools__TransformToMatrix(Geom::Transformation.new),
                'Na__Object__DirectFaceCount'           => 0
            }

            node_seq = self.Na__ComponentEditorTools__CollectMeshTree(
                definition.entities, Geom::Transformation.new, root_node_id,
                hierarchy_nodes, face_records, node_seq, {}, edge_records
            )

            # Linework-only components are valid now that loose edges export,
            # so only bail when there is genuinely nothing to capture.
            return [nil, nil, nil] if face_records.empty? && edge_records.empty?

            mesh_block      = self.Na__ComponentEditorTools__BuildMeshBlock(face_records, origin_pt, edge_records)
            hierarchy_block = self.Na__ComponentEditorTools__BuildHierarchyBlock(hierarchy_nodes, face_records)

            counts = mesh_block['Na__Geometry__Counts']
            stats  = {
                :label     => '3D Mesh',
                :vertices  => counts['Na__Geometry__VertexCount'],
                :faces     => counts['Na__Geometry__FaceCount'],
                :edges     => counts['Na__Geometry__EdgeCount'],
                :objects   => hierarchy_nodes.length,
                :hard      => counts['Na__Geometry__HardEdgeCount'],
                :soft      => counts['Na__Geometry__SoftEdgeCount'],
                :smooth    => counts['Na__Geometry__SmoothEdgeCount'],
                :hidden    => counts['Na__Geometry__HiddenEdgeCount'],
                :displayed => counts['Na__Geometry__DisplayedEdgeCount'],
                :coloured  => counts['Na__Geometry__ColouredEdgeCount']
            }

            [mesh_block, hierarchy_block, stats]
        end

        def self.Na__ComponentEditorTools__NodeId(node_index)
            'OBJ%04d' % (node_index + 1)
        end

        # FUNCTION | Walk the definition tree collecting faces, edges and nodes
        # ------------------------------------------------------------
        # With NA_CAPTURE_HIDDEN_GEOMETRY enabled this traversal no longer
        # culls hidden entities or entities on invisible tags. Their state is
        # recorded on the emitted record instead, so soften / smooth / hide /
        # edge-colour authored in SketchUp survives the round trip. Only the
        # 00__OriginPoint construction marker is still skipped outright.
        def self.Na__ComponentEditorTools__CollectMeshTree(entities, parent_world, parent_node_id, hierarchy_nodes, face_records, node_seq, definition_guard, edge_records)
            entities.each do |entity|
                next if !NA_CAPTURE_HIDDEN_GEOMETRY && self.Na__ComponentEditorTools__EntityExcluded(entity)
                next if self.Na__ComponentEditorTools__OriginEntity(entity)

                case entity
                when Sketchup::Face
                    face_records << { :face => entity, :world_transform => parent_world, :node_id => parent_node_id }
                when Sketchup::Edge
                    edge_records << { :edge => entity, :world_transform => parent_world, :node_id => parent_node_id }
                when Sketchup::Group
                    local_transform = entity.transformation
                    world_transform = parent_world * local_transform
                    node_id         = self.Na__ComponentEditorTools__NodeId(node_seq)
                    node_seq       += 1
                    hierarchy_nodes << self.Na__ComponentEditorTools__HierarchyNodeHash(node_id, parent_node_id, entity, local_transform, world_transform)
                    node_seq = self.Na__ComponentEditorTools__CollectMeshTree(
                        entity.entities, world_transform, node_id, hierarchy_nodes, face_records, node_seq, definition_guard, edge_records
                    )
                when Sketchup::ComponentInstance
                    definition_id = entity.definition.object_id
                    next if definition_guard[definition_id]
                    definition_guard[definition_id] = true
                    local_transform = entity.transformation
                    world_transform = parent_world * local_transform
                    node_id         = self.Na__ComponentEditorTools__NodeId(node_seq)
                    node_seq       += 1
                    hierarchy_nodes << self.Na__ComponentEditorTools__HierarchyNodeHash(node_id, parent_node_id, entity, local_transform, world_transform)
                    node_seq = self.Na__ComponentEditorTools__CollectMeshTree(
                        entity.definition.entities, world_transform, node_id, hierarchy_nodes, face_records, node_seq, definition_guard, edge_records
                    )
                    definition_guard.delete(definition_id)
                end
            end
            node_seq
        end

        def self.Na__ComponentEditorTools__HierarchyNodeHash(node_id, parent_node_id, entity, local_transform, world_transform)
            {
                'Na__Object__NodeId'                    => node_id,
                'Na__Object__ParentNodeId'              => parent_node_id,
                'Na__Object__EntityType'                => entity.class.name.split('::').last,
                'Na__Object__Name'                      => entity.respond_to?(:name) ? entity.name.to_s : '',
                'Na__Object__DefinitionName'            => entity.respond_to?(:definition) ? entity.definition.name.to_s : '',
                'Na__Object__TagName'                   => self.Na__ComponentEditorTools__TagName(entity),
                'Na__Object__TagVisible'                => self.Na__ComponentEditorTools__TagVisible(entity),
                'Na__Object__IsHidden'                  => self.Na__ComponentEditorTools__IsHidden(entity),
                'Na__Object__MaterialName'              => (entity.respond_to?(:material) && entity.material) ? entity.material.display_name.to_s : '',
                'Na__Object__LocalTransform__Matrix4x4' => self.Na__ComponentEditorTools__TransformToMatrix(local_transform),
                'Na__Object__WorldTransform__Matrix4x4' => self.Na__ComponentEditorTools__TransformToMatrix(world_transform),
                'Na__Object__DirectFaceCount'           => 0
            }
        end

        # HELPER | Tag (layer) name of a drawing element, '' when unassigned
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__TagName(entity)
            (entity.respond_to?(:layer) && entity.layer) ? entity.layer.name.to_s : ''
        rescue StandardError
            ''
        end

        # HELPER | Is this element's tag currently visible in the model?
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__TagVisible(entity)
            return true unless entity.respond_to?(:layer) && entity.layer
            return true unless entity.layer.respond_to?(:visible?)
            !!entity.layer.visible?
        rescue StandardError
            true
        end

        # HELPER | Explicit per-entity hide flag (Edit > Hide), not tag state
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__IsHidden(entity)
            entity.respond_to?(:hidden?) ? !!entity.hidden? : false
        rescue StandardError
            false
        end

        def self.Na__ComponentEditorTools__TransformToMatrix(transform)
            arr = transform.to_a.map { |value| value.to_f.round(6) }
            [
                [arr[0],  arr[1],  arr[2],  arr[3]],
                [arr[4],  arr[5],  arr[6],  arr[7]],
                [arr[8],  arr[9],  arr[10], arr[11]],
                [arr[12], arr[13], arr[14], arr[15]]
            ]
        end

        # FUNCTION | Build the Mesh3D block with per-vertex normals
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__BuildMeshBlock(face_records, origin_pt, edge_records)
            vertex_id_lookup      = {}
            position_to_vertex_id = {}
            vertices_out          = []
            faces_out             = []

            face_records.each_with_index do |face_record, index|
                face      = face_record[:face]
                transform = face_record[:world_transform]
                node_id   = face_record[:node_id]

                determinant   = self.Na__ComponentEditorTools__Determinant3x3(transform)
                is_mirrored   = determinant < 0
                normal_matrix = self.Na__ComponentEditorTools__NormalMatrix(transform)

                polygon_mesh = self.Na__ComponentEditorTools__FacePolygonMesh(face)

                outer_ids = self.Na__ComponentEditorTools__LoopVertexIds(
                    face, face.outer_loop.vertices, transform, origin_pt, polygon_mesh, normal_matrix,
                    is_mirrored, vertex_id_lookup, position_to_vertex_id, vertices_out
                )
                next if outer_ids.length < 3

                inner_loops = face.loops.reject(&:outer?).map do |face_loop|
                    self.Na__ComponentEditorTools__LoopVertexIds(
                        face, face_loop.vertices, transform, origin_pt, polygon_mesh, normal_matrix,
                        is_mirrored, vertex_id_lookup, position_to_vertex_id, vertices_out
                    )
                end

                normal_vec = face.normal.transform(transform)
                normal_vec.length = 1.0 if normal_vec.respond_to?(:length=) && normal_vec.length > 0.0

                area_mm2 = begin
                    (face.area(transform).to_f * NA_INCH_TO_MM * NA_INCH_TO_MM).round(3)
                rescue StandardError
                    nil
                end
                material_name = face.material ? face.material.display_name.to_s : ''
                back_material = face.back_material ? face.back_material.display_name.to_s : ''
                face_hidden   = self.Na__ComponentEditorTools__IsHidden(face)
                face_tag_vis  = self.Na__ComponentEditorTools__TagVisible(face)

                face_id = 'F%03d' % (index + 1)
                faces_out << {
                    'FaceId'                 => face_id,
                    'FaceName'               => "Na__Mesh__Face__#{face_id}",
                    'OuterLoop_VertexIds'    => outer_ids,
                    'InnerLoops'             => inner_loops,
                    'Normal'                 => [
                        normal_vec.x.to_f.round(6),
                        normal_vec.y.to_f.round(6),
                        normal_vec.z.to_f.round(6)
                    ],
                    'Area_mm2'               => area_mm2,
                    'MaterialName'           => material_name,
                    'Na__Face__BackMaterial' => back_material,
                    'Na__Face__IsHidden'     => face_hidden,
                    'Na__Face__IsDisplayed'  => (!face_hidden && face_tag_vis),
                    'Na__Face__TagName'      => self.Na__ComponentEditorTools__TagName(face),
                    'Na__Face__TagVisible'   => face_tag_vis,
                    'Na__Object__NodeId'     => node_id
                }
            end

            loose_vertex_count = self.Na__ComponentEditorTools__RegisterLooseEdgeVertices(
                edge_records, position_to_vertex_id, vertices_out, origin_pt
            )

            edges_out = self.Na__ComponentEditorTools__EdgesFromRealEdges(edge_records, position_to_vertex_id, origin_pt)
            bbox      = self.Na__ComponentEditorTools__CalcBboxXyz(vertices_out)

            soft_edge_count      = edges_out.count { |record| record['Na__Edge__IsSoft'] }
            smooth_edge_count    = edges_out.count { |record| record['Na__Edge__IsSmooth'] }
            hard_edge_count      = edges_out.count { |record| !record['Na__Edge__IsSoft'] && !record['Na__Edge__IsSmooth'] }
            hidden_edge_count    = edges_out.count { |record| record['Na__Edge__IsHidden'] }
            displayed_edge_count = edges_out.count { |record| record['Na__Edge__IsDisplayed'] }
            coloured_edge_count  = edges_out.count { |record| record['Na__Edge__HasOwnMaterial'] }
            hidden_face_count    = faces_out.count { |record| record['Na__Face__IsHidden'] }

            {
                'Na__Geometry__OriginNote'      => "Local 0,0,0 = centre of #{NA_ORIGIN_NAME} group.",
                'Na__Geometry__CoordSystem'     => 'Right-handed | X=right, Y=front, Z=up | Units=mm',
                'Na__Geometry__EdgeStyleLegend' => self.Na__ComponentEditorTools__EdgeStyleLegend,
                'Na__Geometry__BoundingBox'     => bbox,
                'Na__Geometry__Counts'          => {
                    'Na__Geometry__VertexCount'         => vertices_out.length,
                    'Na__Geometry__LineworkVertexCount' => loose_vertex_count,
                    'Na__Geometry__FaceCount'           => faces_out.length,
                    'Na__Geometry__HiddenFaceCount'     => hidden_face_count,
                    'Na__Geometry__EdgeCount'           => edges_out.length,
                    'Na__Geometry__HardEdgeCount'       => hard_edge_count,
                    'Na__Geometry__SoftEdgeCount'       => soft_edge_count,
                    'Na__Geometry__SmoothEdgeCount'     => smooth_edge_count,
                    'Na__Geometry__HiddenEdgeCount'     => hidden_edge_count,
                    'Na__Geometry__DisplayedEdgeCount'  => displayed_edge_count,
                    'Na__Geometry__ColouredEdgeCount'   => coloured_edge_count
                },
                'Na__Geometry__Vertices'        => vertices_out,
                'Na__Geometry__Faces'           => faces_out,
                'Na__Geometry__Edges'           => edges_out
            }
        end

        # FUNCTION | Inline contract for the edge style flags
        # ------------------------------------------------------------
        # Written into every export so the Lantern Designer loader and the
        # SketchUp re-importer share one authoritative statement of what the
        # flags mean, rather than each re-deriving SketchUp's rules.
        def self.Na__ComponentEditorTools__EdgeStyleLegend
            {
                'Na__Edge__IsSoft'      => 'SketchUp soft: edge is not drawn AND its adjacent faces merge into a Surface entity. Does not by itself change shading.',
                'Na__Edge__IsSmooth'    => 'SketchUp smooth: adjacent face shading blends across the edge (averaged vertex normals). On its own the edge REMAINS VISIBLE; SketchUp hides it only because Soften/Smooth sets soft and smooth together.',
                'Na__Edge__IsHidden'    => 'SketchUp Edit > Hide: edge is not drawn. Faces are NOT merged into a surface and shading is unchanged.',
                'Na__Edge__IsDisplayed' => 'Resolved draw test: true when NOT soft AND NOT hidden AND the edge tag is visible. Smooth alone does not suppress the line. Consume this directly instead of re-deriving the rules or applying an angle-based softening filter.',
                'Na__Edge__ColorHex'    => 'Colour of the material painted on the edge itself. When Na__Edge__HasOwnMaterial is false this is the SketchUp default edge colour (#000000) and the edge should be left unpainted on re-import.',
                'ShadingNote'           => 'Vertex normals in Na__Geometry__Vertices are already averaged across smoothed edges via face.mesh(7) / normal_at, so smooth shading is baked into the exported normals and needs no downstream recomputation.'
            }
        end

        def self.Na__ComponentEditorTools__BuildHierarchyBlock(hierarchy_nodes, face_records)
            per_node_count = Hash.new(0)
            face_records.each { |record| per_node_count[record[:node_id]] += 1 }
            hierarchy_nodes.each do |node|
                node['Na__Object__DirectFaceCount'] = per_node_count[node['Na__Object__NodeId']] || 0
            end
            {
                'Na__Hierarchy__OriginNote'  => 'Hierarchy captured from the component definition with nested groups/components preserved.',
                'Na__Hierarchy__CoordSystem' => 'Right-handed | X=right, Y=front, Z=up | Units=mm',
                'Na__Hierarchy__Objects'     => hierarchy_nodes
            }
        end

        def self.Na__ComponentEditorTools__FacePolygonMesh(face)
            return nil unless face && face.valid?
            face.mesh(7)
        rescue StandardError
            nil
        end

        def self.Na__ComponentEditorTools__LocalNormalAtVertex(face, polygon_mesh, vertex_position)
            if polygon_mesh
                begin
                    index = polygon_mesh.add_point(vertex_position)
                    local_normal = polygon_mesh.normal_at(index) if index && index > 0
                    return local_normal if local_normal
                rescue StandardError
                    # fall through to face normal fallback
                end
            end
            face ? face.normal : Geom::Vector3d.new(0, 0, 1)
        end

        def self.Na__ComponentEditorTools__LoopVertexIds(face, loop_vertices, transform, origin_pt, polygon_mesh, normal_matrix, is_mirrored, vertex_id_lookup, position_to_vertex_id, vertices_out)
            loop_vertices.map do |vertex|
                world_point = vertex.position.transform(transform)
                pos_x_mm = ((world_point.x - origin_pt.x) * NA_INCH_TO_MM).round(3)
                pos_y_mm = ((world_point.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
                pos_z_mm = ((world_point.z - origin_pt.z) * NA_INCH_TO_MM).round(3)

                local_normal = self.Na__ComponentEditorTools__LocalNormalAtVertex(face, polygon_mesh, vertex.position)
                nx, ny, nz = self.Na__ComponentEditorTools__TransformNormal(
                    normal_matrix, local_normal.x.to_f, local_normal.y.to_f, local_normal.z.to_f
                )
                if is_mirrored
                    nx = -nx
                    ny = -ny
                    nz = -nz
                end

                normal_x = nx.round(6)
                normal_y = ny.round(6)
                normal_z = nz.round(6)

                position_key = "#{pos_x_mm}|#{pos_y_mm}|#{pos_z_mm}"
                combined_key = "#{position_key}|#{normal_x}|#{normal_y}|#{normal_z}"

                unless vertex_id_lookup[combined_key]
                    vertex_id = 'V%03d' % (vertices_out.length + 1)
                    vertex_id_lookup[combined_key] = vertex_id
                    position_to_vertex_id[position_key] ||= vertex_id
                    vertices_out << {
                        'VertexId'   => vertex_id,
                        'VertexName' => "Na__Mesh__Vertex__#{vertex_id}",
                        'PosX_mm'    => pos_x_mm,
                        'PosY_mm'    => pos_y_mm,
                        'PosZ_mm'    => pos_z_mm,
                        'Normal_X'   => normal_x,
                        'Normal_Y'   => normal_y,
                        'Normal_Z'   => normal_z
                    }
                end
                vertex_id_lookup[combined_key]
            end
        end

        # FUNCTION | Convert real Sketchup::Edge records into JSON edge records
        # ------------------------------------------------------------
        # Every edge carries the full authored style bundle so both the web
        # renderer and the SketchUp re-importer can restore parity:
        #
        #   Na__Edge__IsSoft       edge hidden AND adjacent faces merged into
        #                          a Surface entity (SketchUp: soft)
        #   Na__Edge__IsSmooth     adjacent face shading blended across the
        #                          edge via averaged vertex normals. On its own
        #                          the edge STAYS VISIBLE - SketchUp only hides
        #                          it because the Soften/Smooth slider sets soft
        #                          and smooth together.
        #   Na__Edge__IsHidden     Edit > Hide. Edge not drawn, faces NOT merged
        #                          into a surface and shading unchanged.
        #   Na__Edge__IsDisplayed  resolved answer to "does SketchUp draw this
        #                          line". Precomputed here so downstream never
        #                          has to re-derive the soft/smooth/hidden/tag
        #                          precedence rules (and so a dumb angle-based
        #                          softening filter is never needed).
        #
        # Vertex ids come from the position index built during the face pass,
        # topped up by RegisterLooseEdgeVertices so loose linework with no
        # adjacent face still exports instead of being silently dropped.
        #
        # Uniqueness is per (node, undirected vertex pair) so coincident edges
        # living in different nested groups both survive and can be rebuilt
        # into their own containers.
        def self.Na__ComponentEditorTools__EdgesFromRealEdges(edge_records, position_to_vertex_id, origin_pt)
            seen  = {}
            edges = []

            edge_records.each do |record|
                edge = record[:edge]
                next unless edge && edge.valid?
                transform = record[:world_transform]
                node_id   = record[:node_id]

                start_world = edge.start.position.transform(transform)
                end_world   = edge.end.position.transform(transform)

                start_vid = position_to_vertex_id[self.Na__ComponentEditorTools__PositionKeyMm(start_world, origin_pt)]
                end_vid   = position_to_vertex_id[self.Na__ComponentEditorTools__PositionKeyMm(end_world, origin_pt)]
                next unless start_vid && end_vid
                next if start_vid == end_vid

                pair_key = "#{node_id}|#{[start_vid, end_vid].sort.join('|')}"
                next if seen[pair_key]
                seen[pair_key] = true

                edge_id      = 'E%03d' % (edges.length + 1)
                edge_record  = {
                    'EdgeId'      => edge_id,
                    'StartVertex' => start_vid,
                    'EndVertex'   => end_vid
                }
                edge_record.merge!(self.Na__ComponentEditorTools__EdgeStyleRecord(edge))
                edge_record['Na__Object__NodeId'] = node_id
                edges << edge_record
            end

            edges
        end

        # FUNCTION | Authored style bundle for one edge
        # ------------------------------------------------------------
        def self.Na__ComponentEditorTools__EdgeStyleRecord(edge)
            is_soft     = edge.respond_to?(:soft?)   ? !!edge.soft?   : false
            is_smooth   = edge.respond_to?(:smooth?) ? !!edge.smooth? : false
            is_hidden   = self.Na__ComponentEditorTools__IsHidden(edge)
            tag_visible = self.Na__ComponentEditorTools__TagVisible(edge)
            colour      = self.Na__ComponentEditorTools__EdgeColour(edge)

            {
                'Na__Edge__IsSoft'          => is_soft,
                'Na__Edge__IsSmooth'        => is_smooth,
                'Na__Edge__IsHidden'        => is_hidden,
                'Na__Edge__IsDisplayed'     => (!is_soft && !is_hidden && tag_visible),
                'Na__Edge__CastsShadows'    => edge.respond_to?(:casts_shadows?) ? !!edge.casts_shadows? : true,
                'Na__Edge__TagName'         => self.Na__ComponentEditorTools__TagName(edge),
                'Na__Edge__TagVisible'      => tag_visible,
                'Na__Edge__MaterialName'    => colour[:material_name],
                'Na__Edge__HasOwnMaterial'  => colour[:has_own_material],
                'Na__Edge__ColorHex'        => colour[:hex],
                'Na__Edge__ColorRgba'       => colour[:rgba],

                # Legacy 1.1.0 aliases - kept so existing readers of these
                # exports keep working while consumers migrate to Na__Edge__*.
                'IsSoft'                    => is_soft,
                'IsSmooth'                  => is_smooth,
                'IsHidden'                  => is_hidden,
                'CastsShadows'              => edge.respond_to?(:casts_shadows?) ? !!edge.casts_shadows? : true
            }
        end

        # HELPER | Resolve an edge's authored colour
        # ------------------------------------------------------------
        # SketchUp only tints an edge when a material has been painted onto
        # the edge itself. Untinted edges fall back to the model's edge colour
        # (black by default), so that is what we report with
        # HasOwnMaterial=false - the importer then knows to leave the edge
        # unpainted rather than force it black.
        def self.Na__ComponentEditorTools__EdgeColour(edge)
            material = edge.respond_to?(:material) ? edge.material : nil

            unless material
                return {
                    :material_name    => '',
                    :has_own_material => false,
                    :hex              => self.Na__ComponentEditorTools__RgbToHex(NA_DEFAULT_EDGE_RGB),
                    :rgba             => [NA_DEFAULT_EDGE_RGB[0], NA_DEFAULT_EDGE_RGB[1], NA_DEFAULT_EDGE_RGB[2], 255]
                }
            end

            colour = material.color
            rgb    = colour ? [colour.red.to_i, colour.green.to_i, colour.blue.to_i] : NA_DEFAULT_EDGE_RGB
            alpha  = (colour && colour.respond_to?(:alpha)) ? colour.alpha.to_i : 255

            {
                :material_name    => material.display_name.to_s,
                :has_own_material => true,
                :hex              => self.Na__ComponentEditorTools__RgbToHex(rgb),
                :rgba             => [rgb[0], rgb[1], rgb[2], alpha]
            }
        rescue StandardError
            {
                :material_name    => '',
                :has_own_material => false,
                :hex              => self.Na__ComponentEditorTools__RgbToHex(NA_DEFAULT_EDGE_RGB),
                :rgba             => [NA_DEFAULT_EDGE_RGB[0], NA_DEFAULT_EDGE_RGB[1], NA_DEFAULT_EDGE_RGB[2], 255]
            }
        end

        def self.Na__ComponentEditorTools__RgbToHex(rgb)
            '#%02X%02X%02X' % [rgb[0].to_i, rgb[1].to_i, rgb[2].to_i]
        end

        # FUNCTION | Give loose edges real vertex ids
        # ------------------------------------------------------------
        # The face pass only indexes positions that belong to a face loop, so
        # linework with no adjacent face (construction lines, authored guide
        # edges, the ridge lighting block's detail lines) previously failed the
        # "next unless start_vid && end_vid" guard and vanished from Mesh3D.
        # This pass registers those endpoints as linework-only vertices.
        #
        # They carry a placeholder +Z normal and IsLineworkOnly=true. Nothing
        # in Na__Geometry__Faces ever references them, so the placeholder can
        # never leak into face shading.
        def self.Na__ComponentEditorTools__RegisterLooseEdgeVertices(edge_records, position_to_vertex_id, vertices_out, origin_pt)
            loose_count = 0

            edge_records.each do |record|
                edge = record[:edge]
                next unless edge && edge.valid?
                transform = record[:world_transform]

                [edge.start, edge.end].each do |vertex|
                    world_point  = vertex.position.transform(transform)
                    pos_x_mm     = ((world_point.x - origin_pt.x) * NA_INCH_TO_MM).round(3)
                    pos_y_mm     = ((world_point.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
                    pos_z_mm     = ((world_point.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
                    position_key = "#{pos_x_mm}|#{pos_y_mm}|#{pos_z_mm}"
                    next if position_to_vertex_id[position_key]

                    vertex_id = 'V%03d' % (vertices_out.length + 1)
                    position_to_vertex_id[position_key] = vertex_id
                    loose_count += 1
                    vertices_out << {
                        'VertexId'       => vertex_id,
                        'VertexName'     => "Na__Mesh__Vertex__#{vertex_id}",
                        'PosX_mm'        => pos_x_mm,
                        'PosY_mm'        => pos_y_mm,
                        'PosZ_mm'        => pos_z_mm,
                        'Normal_X'       => 0.0,
                        'Normal_Y'       => 0.0,
                        'Normal_Z'       => 1.0,
                        'IsLineworkOnly' => true
                    }
                end
            end

            loose_count
        end

        def self.Na__ComponentEditorTools__PositionKeyMm(world_point, origin_pt)
            x = ((world_point.x - origin_pt.x) * NA_INCH_TO_MM).round(3)
            y = ((world_point.y - origin_pt.y) * NA_INCH_TO_MM).round(3)
            z = ((world_point.z - origin_pt.z) * NA_INCH_TO_MM).round(3)
            "#{x}|#{y}|#{z}"
        end

        def self.Na__ComponentEditorTools__CalcBboxXyz(vertices)
            return {} if vertices.empty?
            xs = vertices.map { |vertex| vertex['PosX_mm'] }
            ys = vertices.map { |vertex| vertex['PosY_mm'] }
            zs = vertices.map { |vertex| vertex['PosZ_mm'] }
            {
                'Na__Geometry__MinX_mm' => xs.min.round(3),
                'Na__Geometry__MaxX_mm' => xs.max.round(3),
                'Na__Geometry__MinY_mm' => ys.min.round(3),
                'Na__Geometry__MaxY_mm' => ys.max.round(3),
                'Na__Geometry__MinZ_mm' => zs.min.round(3),
                'Na__Geometry__MaxZ_mm' => zs.max.round(3)
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Document Assembly
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__BuildDocument(model, component_name, product_code, view_blocks, mesh_block, hierarchy_block, warnings)
            has_plan      = view_blocks.key?('Na__Asset__Plan2D__Top')
            has_elevation = view_blocks.key?('Na__Asset__Elevation2D__Front') || view_blocks.key?('Na__Asset__Elevation2D__Right')
            has_3d        = !mesh_block.nil?

            front_block    = view_blocks['Na__Asset__Elevation2D__Front']
            overall_height = nil
            if front_block && !front_block['Na__Geometry__BoundingBox'].empty?
                overall_height = front_block['Na__Geometry__BoundingBox']['Na__Geometry__Height_mm']
            end

            exported_views = []
            NA_VIEW_DEFINITIONS.each do |view_def|
                next unless view_blocks.key?(view_def[:key])
                exported_views << { 'sceneName' => "FixedAxis__#{view_def[:label].gsub(' ', '')}", 'viewKey' => view_def[:key] }
            end
            exported_views << { 'sceneName' => 'DefinitionEntities', 'viewKey' => 'Na__Asset__Mesh3D' } if has_3d

            source_model = model.path.to_s.empty? ? model.title.to_s : File.basename(model.path.to_s)

            document = {
                'meta' => {
                    'schema'           => 'Na__Asset__UnifiedComponentSchema',
                    'schemaVersion'    => '1.2.0',
                    'generator'        => 'Na__ComponentEditorTools::Na__ExportTools - Export tab multi-view exporter',
                    'generatedDate'    => Time.now.strftime('%d-%b-%Y'),
                    'sourceModel'      => source_model,
                    'sourceAsset'      => component_name,
                    'exportedScenes'   => exported_views,
                    'exportWarnings'   => warnings.dup,
                    'namingConvention' => 'All custom keys prefixed Na__. Three-stage form Na__Section__SubSection__FieldName.',
                    'fieldPrefixes'    => {
                        'Na__Asset__'     => 'Top-level asset metadata and content blocks',
                        'Na__Geometry__'  => 'Geometry sub-fields (BoundingBox, Counts, OriginNote, CoordSystem, Paths, EdgeStyleLegend)',
                        'Na__View__'      => '2D projection provenance (source view, camera axes, projection type)',
                        'Na__Object__'    => '3D hierarchy nodes (ids, names, tags, transforms, visibility)',
                        'Na__Hierarchy__' => '3D object hierarchy block metadata',
                        'Na__Edge__'      => 'Authored edge style (soft, smooth, hidden, resolved display, tag, colour)',
                        'Na__Face__'      => 'Authored face state (hidden, resolved display, tag, back material)'
                    }
                },
                'Na__Asset__Metadata' => {
                    'Na__Asset__Metadata__Id'           => product_code,
                    'Na__Asset__Metadata__Name'         => component_name,
                    'Na__Asset__Metadata__CategoryId'   => '',
                    'Na__Asset__Metadata__CategoryName' => '',
                    'Na__Asset__Metadata__Description'  => '',
                    'Na__Asset__Metadata__Revision'     => 'A',
                    'Na__Asset__Metadata__Author'       => '',
                    'Na__Asset__Metadata__CreatedDate'  => Time.now.strftime('%d-%b-%Y'),
                    'Na__Asset__Metadata__DataStatus'   => 'Draft - auto-captured by Component Editor Export tab, awaiting audit',
                    'Na__Asset__Metadata__Material'     => '',
                    'Na__Asset__Metadata__Tags'         => []
                },
                'Na__Asset__ValeSpecification' => {
                    'Na__Asset__ValeSpec__ProductCode' => product_code,
                    'Na__Asset__ValeSpec__ProductName' => '',
                    'Na__Asset__ValeSpec__Supplier'    => '',
                    'Na__Asset__ValeSpec__Material'    => '',
                    'Na__Asset__ValeSpec__Finish'      => '',
                    'Na__Asset__ValeSpec__Notes'       => ''
                }
            }

            NA_VIEW_DEFINITIONS.each do |view_def|
                block = view_blocks[view_def[:key]]
                document[view_def[:key]] = block if block
            end

            document['Na__Asset__Mesh3D']            = mesh_block
            document['Na__Asset__ObjectHierarchy3D'] = hierarchy_block
            document['Na__Asset__Glb3D__Url']        = nil
            document['Na__Asset__Has2dPlan']         = has_plan
            document['Na__Asset__Has2dElevation']    = has_elevation
            document['Na__Asset__Has2dProfile']      = false
            document['Na__Asset__Has3d']             = has_3d
            document['Na__Asset__PlacementBehaviour'] = {
                'Na__Asset__PlacementBehaviour__ApplicableRoles' => [],
                'Na__Asset__PlacementBehaviour__AnchorPoint'     => 'seatingCentre',
                'Na__Asset__PlacementBehaviour__AlignToVertical' => true,
                'Na__Asset__PlacementBehaviour__RequiresBase'    => nil,
                'Na__Asset__PlacementBehaviour__OverallHeightMm' => overall_height,
                'Na__Asset__PlacementBehaviour__SeatingWidthMm'  => nil
            }

            document
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Column-Aligned JSON Serializer (Na__ 3-Stage Style)
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__Indent(depth)
            return ''   if depth < 1
            return '  ' if depth == 1
            ' ' * (4 * (depth - 1))
        end

        def self.Na__ComponentEditorTools__Scalar(value)
            case value
            when NilClass    then 'null'
            when TrueClass   then 'true'
            when FalseClass  then 'false'
            when Float
                value.nan? || value.infinite? ? 'null' : value.to_json
            else
                value.to_json
            end
        end

        def self.Na__ComponentEditorTools__PaddedKey(key, column_width)
            key_json = key.to_json
            pad      = [0, column_width - key_json.length].max
            "#{key_json}#{' ' * pad} : "
        end

        def self.Na__ComponentEditorTools__FormatPair(key, value, depth, column_width)
            indent  = self.Na__ComponentEditorTools__Indent(depth)
            key_col = self.Na__ComponentEditorTools__PaddedKey(key, column_width)
            case value
            when Hash
                return "#{indent}#{key_col}{}" if value.empty?
                body  = self.Na__ComponentEditorTools__FormatObjectBody(value, depth + 1)
                close = self.Na__ComponentEditorTools__Indent(depth)
                "#{indent}#{key_col}{\n#{body}\n#{close}}"
            when Array
                return "#{indent}#{key_col}[]" if value.empty?
                inner = self.Na__ComponentEditorTools__FormatArrayBody(value, depth)
                "#{indent}#{key_col}[\n#{inner}\n#{indent}]"
            else
                "#{indent}#{key_col}#{self.Na__ComponentEditorTools__Scalar(value)}"
            end
        end

        def self.Na__ComponentEditorTools__FormatObjectBody(hash, depth)
            return '' if hash.empty?
            width = hash.keys.map { |key| key.to_json.length }.max
            hash.map { |key, value| self.Na__ComponentEditorTools__FormatPair(key, value, depth, width) }.join(",\n")
        end

        def self.Na__ComponentEditorTools__FormatArrayBody(array, parent_depth)
            element_depth = parent_depth + 1
            array.map { |element| self.Na__ComponentEditorTools__FormatArrayElement(element, element_depth) }.join(",\n")
        end

        def self.Na__ComponentEditorTools__FormatArrayElement(element, depth)
            case element
            when Hash
                return "#{self.Na__ComponentEditorTools__Indent(depth)}{}" if element.empty?
                body = self.Na__ComponentEditorTools__FormatObjectBody(element, depth + 1)
                open = self.Na__ComponentEditorTools__Indent(depth)
                "#{open}{\n#{body}\n#{open}}"
            when Array
                inner = element.map { |value| self.Na__ComponentEditorTools__Scalar(value) }.join(', ')
                "#{self.Na__ComponentEditorTools__Indent(depth)}[#{inner}]"
            else
                "#{self.Na__ComponentEditorTools__Indent(depth)}#{self.Na__ComponentEditorTools__Scalar(element)}"
            end
        end

        def self.Na__ComponentEditorTools__SerializeRoot(root_hash)
            width = root_hash.keys.map { |key| key.to_json.length }.max
            parts = root_hash.map { |key, value| self.Na__ComponentEditorTools__FormatPair(key, value, 1, width) }
            "{\n#{parts.join(",\n")}\n}\n"
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
