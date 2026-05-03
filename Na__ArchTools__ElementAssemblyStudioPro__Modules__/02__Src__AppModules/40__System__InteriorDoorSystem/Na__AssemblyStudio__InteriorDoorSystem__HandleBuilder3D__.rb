# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - 3D HANDLE BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__HandleBuilder3D
# AUTHOR     : Noble Architecture
# PURPOSE    : Loads a unified handle asset JSON (2D + 3D + metadata) and
#              instantiates the 3D mesh on both faces of the door panel.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Reads the 3D handle mesh from the Na__Asset__Mesh3D block of a
#   unified handle asset JSON loaded via Na__AssetLibrary.
# - Builds a SketchUp ComponentDefinition for the handle once per asset
#   key per session (cached in @na_handle_def_cache) and reuses it for
#   both the interior and exterior instances.
# - The asset is authored lying on its back (Z+ = front face) so this
#   module applies a three-step lay-back rotation (Z axis -90 deg, then
#   X axis -90 deg, then another X axis -90 deg, all around the
#   00__OriginPoint reference) to stand the handle up with the lever
#   pointing out of the door panel's interior face.
# - Reads RH/LH offsets and ScaleX from the asset metadata's
#   Na__PanelPlacement__RightHand / Na__PanelPlacement__LeftHand blocks
#   so a single asset works for either hand of door.
# - Handle instances are added to the entities collection passed in
#   (typically the door's MOD movable group) and tagged :door_handle.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require 'set'
require 'digest'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__HandleBuilder3D

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools      = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        AssetLibrary    = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__AssetLibrary
        TagManager      = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables (Cache)
# -----------------------------------------------------------------------------

        @na_handle_def_cache = {}                                              # <-- AssetKey -> Sketchup::ComponentDefinition
        NA_HANDLE_DEF_SIGNATURE_DICT = "Na__InteriorDoor__HandleBuilder3D".freeze
        NA_HANDLE_DEF_SIGNATURE_KEY  = "Na__MeshSignature".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build Both Interior and Exterior Handle Instances
        # ------------------------------------------------------------
        # @param config [Hash] Door configuration block
        # @param entities [Sketchup::Entities] Target entities (e.g. MOD group)
        # @param material [Sketchup::Material, nil] Optional handle material
        # @return [Hash] { :interior => ComponentInstance, :exterior => ComponentInstance }
        def self.na_build_handles(config, entities, material = nil)
            asset_key = na_resolve_handle_asset_key(config)
            asset     = AssetLibrary.na_load_handle_asset(asset_key)

            unless asset
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' could not be loaded - skipping handles")
                return { :interior => nil, :exterior => nil }
            end

            validation = na_validate_handle_asset_for_3d(asset_key, asset)
            unless validation[:valid]
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' failed 3D contract validation - skipping handles")
                return { :interior => nil, :exterior => nil }
            end

            handle_def = na_get_or_build_handle_definition(asset_key, validation[:mesh_block])
            return { :interior => nil, :exterior => nil } unless handle_def

            interior_inst = na_place_handle_instance(entities, handle_def, asset, config, :interior, material)
            exterior_inst = na_place_handle_instance(entities, handle_def, asset, config, :exterior, material)
            na_apply_standard_dark_grey_edge_colour(interior_inst || exterior_inst)

            { :interior => interior_inst, :exterior => exterior_inst }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Clear the In-Memory Definition Cache (Developer Reload)
        # ------------------------------------------------------------
        def self.na_clear_definition_cache
            @na_handle_def_cache = {}
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Definition Builder
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve Handle Asset Key with Safe Default
        # ------------------------------------------------------------
        def self.na_resolve_handle_asset_key(config)
            candidate = config && config["Na__DoorConfig__HandleAssetKey"]
            key = candidate.to_s.strip
            return key unless key.empty?

            if AssetLibrary.const_defined?(:NA_DEFAULT_HANDLE_KEY)
                AssetLibrary::NA_DEFAULT_HANDLE_KEY.to_s
            else
                "Na__InteriorDoor__Handle__Default"
            end
        end
        private_class_method :na_resolve_handle_asset_key
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate Handle Asset Mesh Contract
        # ------------------------------------------------------------
        # Performs strict contract checks so malformed JSON fails loudly
        # before any SketchUp geometry mutation begins.
        def self.na_validate_handle_asset_for_3d(asset_key, asset)
            unless asset.is_a?(Hash)
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' is not a JSON object")
                return { :valid => false, :mesh_block => nil }
            end

            mesh_block = asset["Na__Asset__Mesh3D"]
            unless mesh_block.is_a?(Hash)
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' missing Hash block 'Na__Asset__Mesh3D'")
                return { :valid => false, :mesh_block => nil }
            end

            vertices = mesh_block["Na__Geometry__Vertices"]
            faces    = mesh_block["Na__Geometry__Faces"]
            unless vertices.is_a?(Array) && !vertices.empty?
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' has no valid 'Na__Geometry__Vertices' array")
                return { :valid => false, :mesh_block => nil }
            end
            unless faces.is_a?(Array) && !faces.empty?
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' has no valid 'Na__Geometry__Faces' array")
                return { :valid => false, :mesh_block => nil }
            end

            valid, reason = na_validate_vertex_records(vertices)
            unless valid
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' vertex contract error: #{reason}")
                return { :valid => false, :mesh_block => nil }
            end

            valid, reason = na_validate_face_records(faces)
            unless valid
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' face contract error: #{reason}")
                return { :valid => false, :mesh_block => nil }
            end

            valid, reason = na_validate_face_vertex_references(vertices, faces)
            unless valid
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' face->vertex reference error: #{reason}")
                return { :valid => false, :mesh_block => nil }
            end

            { :valid => true, :mesh_block => mesh_block }
        end
        private_class_method :na_validate_handle_asset_for_3d
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate Vertex Records
        # ------------------------------------------------------------
        def self.na_validate_vertex_records(vertices)
            vertices.each_with_index do |record, index|
                return [false, "record #{index} is not an object"] unless record.is_a?(Hash)
                return [false, "record #{index} missing VertexId"] if record["VertexId"].to_s.strip.empty?

                %w[PosX_mm PosY_mm PosZ_mm].each do |field_name|
                    return [false, "record #{index} missing #{field_name}"] unless record.key?(field_name)
                    return [false, "record #{index} invalid #{field_name} value"] unless na_numeric_value?(record[field_name])
                end
            end
            [true, nil]
        end
        private_class_method :na_validate_vertex_records
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate Face Records
        # ------------------------------------------------------------
        def self.na_validate_face_records(faces)
            faces.each_with_index do |record, index|
                return [false, "record #{index} is not an object"] unless record.is_a?(Hash)
                loop_ids = record["OuterLoop_VertexIds"]
                return [false, "record #{index} missing OuterLoop_VertexIds"] unless loop_ids.is_a?(Array)
                return [false, "record #{index} needs at least 3 OuterLoop_VertexIds"] if loop_ids.length < 3
                return [false, "record #{index} has blank vertex id"] if loop_ids.any? { |value| value.to_s.strip.empty? }
            end
            [true, nil]
        end
        private_class_method :na_validate_face_records
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate Face Vertex ID References
        # ------------------------------------------------------------
        def self.na_validate_face_vertex_references(vertices, faces)
            vertex_ids = vertices.map { |record| record["VertexId"].to_s }.to_set
            faces.each_with_index do |record, index|
                loop_ids = record["OuterLoop_VertexIds"] || []
                loop_ids.each do |vertex_id|
                    return [false, "record #{index} references unknown VertexId '#{vertex_id}'"] unless vertex_ids.include?(vertex_id.to_s)
                end
            end
            [true, nil]
        end
        private_class_method :na_validate_face_vertex_references
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Numeric Coercion Guard
        # ------------------------------------------------------------
        def self.na_numeric_value?(value)
            Float(value)
            true
        rescue StandardError
            false
        end
        private_class_method :na_numeric_value?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Get or Build the Handle ComponentDefinition
        # ------------------------------------------------------------
        # Returns a cached definition if one was built earlier in the
        # session. Otherwise builds a fresh definition from the asset's
        # Na__Asset__Mesh3D block and caches it.
        def self.na_get_or_build_handle_definition(asset_key, mesh_block)
            mesh_signature = na_build_mesh_signature(mesh_block)
            cached = @na_handle_def_cache[asset_key]
            if cached && cached.valid?
                if na_definition_has_mesh_faces?(cached) && na_definition_matches_mesh_signature?(cached, mesh_signature)
                    return cached
                end
                DebugTools.na_debug_warn("Handle definition cache for '#{asset_key}' is stale or empty - rebuilding from JSON mesh")
                @na_handle_def_cache.delete(asset_key)
            end

            model       = Sketchup.active_model
            return nil unless model

            def_name    = "Na__InteriorDoor__Handle__#{asset_key}"
            existing    = model.definitions[def_name]
            if existing && existing.valid? &&
               na_definition_has_mesh_faces?(existing) &&
               na_definition_matches_mesh_signature?(existing, mesh_signature)
                @na_handle_def_cache[asset_key] = existing
                return existing
            end

            definition = if existing && existing.valid?
                             existing
                         else
                             model.definitions.add(def_name)
                         end
            definition.entities.clear!

            built_faces = na_build_mesh_into_definition(definition, mesh_block)
            if built_faces <= 0
                DebugTools.na_debug_warn("Handle definition '#{def_name}' built zero faces - skipping handle instances")
                return nil
            end

            applied_edges = na_apply_edge_flags_to_definition(definition, mesh_block)

            na_write_definition_mesh_signature(definition, mesh_signature)
            @na_handle_def_cache[asset_key] = definition
            DebugTools.na_debug_geometry("Built handle definition '#{def_name}' with #{built_faces} faces, applied edge flags to #{applied_edges} edges")
            definition
        end
        private_class_method :na_get_or_build_handle_definition
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Populate a ComponentDefinition from Mesh3D Data
        # ------------------------------------------------------------
        # Adds vertices and faces from the asset's Mesh3D block as faces
        # in the definition. Skips faces with fewer than three vertices.
        def self.na_build_mesh_into_definition(definition, mesh_block)
            vertices = mesh_block["Na__Geometry__Vertices"] || []
            faces    = mesh_block["Na__Geometry__Faces"]    || []

            return 0 if vertices.empty? || faces.empty?

            point_table = na_build_vertex_point_table(vertices)
            entities    = definition.entities
            return 0 if point_table.empty?
            built_count = 0

            faces.each do |frec|
                outer_ids = frec["OuterLoop_VertexIds"] || []
                next if outer_ids.length < 3

                pts       = outer_ids.map { |vid| point_table[vid] }.compact
                next if pts.length < 3

                face = entities.add_face(pts)
                next unless face && face.valid?
                built_count += 1

            end
            built_count
        end
        private_class_method :na_build_mesh_into_definition
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Apply IsSoft / IsSmooth / IsHidden / CastsShadows to Edges
        # ------------------------------------------------------------
        # The JSON mesh carries per-edge flags sourced from the original
        # Sketchup::Edge objects at export time (see
        # Na__AssemblyStudio__DevTools__JsonExporter3D__.rb :: na_edges_from_real_edges).
        # We reapply those flags to the newly-built handle definition so
        # softened / smoothed edges disappear in the SketchUp viewport
        # (the downstream GLB builder also respects them).
        #
        # Matching strategy: position-pair key (unordered) built from the
        # JSON-declared world positions. JSON can have multiple vertex
        # records at one physical position (per-vertex-normal dedupe)
        # but SketchUp auto-merges them, so several JSON edge records
        # may map to the same SketchUp::Edge - we OR the soft/smooth/
        # hidden flags so any JSON record indicating soft/smooth wins.
        #
        # @param definition [Sketchup::ComponentDefinition]
        # @param mesh_block [Hash] Na__Asset__Mesh3D block
        # @return [Integer] Number of SketchUp edges that received flags
        def self.na_apply_edge_flags_to_definition(definition, mesh_block)
            edge_records = mesh_block["Na__Geometry__Edges"] || []
            return 0 if edge_records.empty?

            vertices = mesh_block["Na__Geometry__Vertices"] || []
            point_table = na_build_vertex_point_table(vertices)
            return 0 if point_table.empty?

            flag_by_key = {}
            edge_records.each do |record|
                next unless record.is_a?(Hash)
                start_pt = point_table[record["StartVertex"]]
                end_pt   = point_table[record["EndVertex"]]
                next unless start_pt && end_pt

                key = na_edge_position_key(start_pt, end_pt)
                bucket = flag_by_key[key] || { :soft => false, :smooth => false, :hidden => false, :casts_shadows => true }
                bucket[:soft]   = true if record["IsSoft"]
                bucket[:smooth] = true if record["IsSmooth"]
                bucket[:hidden] = true if record["IsHidden"]
                bucket[:casts_shadows] = false if record.key?("CastsShadows") && !record["CastsShadows"]
                flag_by_key[key] = bucket
            end

            applied = 0
            definition.entities.grep(Sketchup::Edge).each do |edge|
                next unless edge && edge.valid?
                key = na_edge_position_key(edge.start.position, edge.end.position)
                flags = flag_by_key[key]
                next unless flags

                edge.soft   = flags[:soft]
                edge.smooth = flags[:smooth]
                edge.hidden = flags[:hidden] if flags[:hidden]
                if edge.respond_to?(:casts_shadows=)
                    edge.casts_shadows = flags[:casts_shadows]
                end
                applied += 1
            end
            applied
        end
        private_class_method :na_apply_edge_flags_to_definition
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Stable Edge Position Key (Unordered Endpoints)
        # ------------------------------------------------------------
        # Rounds to 6 decimal places so that micro-jitter from vertex
        # transformations cannot separate a matching pair.
        def self.na_edge_position_key(pt_a, pt_b)
            key_a = na_point_key(pt_a)
            key_b = na_point_key(pt_b)
            [key_a, key_b].sort.join("||")
        end
        private_class_method :na_edge_position_key
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Stable Point Key Rounded to 6 Decimal Places
        # ------------------------------------------------------------
        def self.na_point_key(pt)
            "%.6f|%.6f|%.6f" % [pt.x.to_f, pt.y.to_f, pt.z.to_f]
        end
        private_class_method :na_point_key
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build VertexId -> Geom::Point3d Table (mm -> inches)
        # ------------------------------------------------------------
        def self.na_build_vertex_point_table(vertex_records)
            table = {}
            vertex_records.each do |vrec|
                next unless vrec.is_a?(Hash)
                vid = vrec["VertexId"]
                x   = vrec["PosX_mm"]
                y   = vrec["PosY_mm"]
                z   = vrec["PosZ_mm"]
                next unless vid && x && y && z

                table[vid] = Geom::Point3d.new(
                    GeometryHelpers.na_mm_to_inch(x),
                    GeometryHelpers.na_mm_to_inch(y),
                    GeometryHelpers.na_mm_to_inch(z)
                )
            end
            table
        end
        private_class_method :na_build_vertex_point_table
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Detect Whether a Definition Already Has Faces
        # ------------------------------------------------------------
        def self.na_definition_has_mesh_faces?(definition)
            return false unless definition && definition.valid?
            !definition.entities.grep(Sketchup::Face).empty?
        end
        private_class_method :na_definition_has_mesh_faces?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Build Stable Mesh Signature for Definition Reuse
        # ------------------------------------------------------------
        # Signature prefix "v3|" marks the material-neutral definition
        # generation change. Earlier cached definitions may contain baked
        # face materials from the first swatch chosen, so bumping this token
        # forces a one-time rebuild where handle finish is driven only by
        # instance material assignment.
        def self.na_build_mesh_signature(mesh_block)
            Digest::SHA256.hexdigest("v3|#{JSON.generate(mesh_block || {})}")
        rescue StandardError
            nil
        end
        private_class_method :na_build_mesh_signature
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compare Definition Signature to Mesh Signature
        # ------------------------------------------------------------
        def self.na_definition_matches_mesh_signature?(definition, mesh_signature)
            return false if mesh_signature.to_s.empty?
            stored = definition.get_attribute(NA_HANDLE_DEF_SIGNATURE_DICT, NA_HANDLE_DEF_SIGNATURE_KEY, "").to_s
            return false if stored.empty?
            stored == mesh_signature.to_s
        rescue StandardError
            false
        end
        private_class_method :na_definition_matches_mesh_signature?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Persist Mesh Signature onto ComponentDefinition
        # ------------------------------------------------------------
        def self.na_write_definition_mesh_signature(definition, mesh_signature)
            return if mesh_signature.to_s.empty?
            definition.set_attribute(NA_HANDLE_DEF_SIGNATURE_DICT, NA_HANDLE_DEF_SIGNATURE_KEY, mesh_signature.to_s)
        rescue StandardError => e
            DebugTools.na_debug_warn("Failed to write handle mesh signature: #{e.message}")
        end
        private_class_method :na_write_definition_mesh_signature
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Instance Placement
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Place a Single Handle Instance on the Door
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Where to add the instance
        # @param definition [Sketchup::ComponentDefinition]
        # @param asset [Hash] Parsed handle asset JSON
        # @param config [Hash] Door configuration
        # @param face [Symbol] :interior or :exterior
        # @param material [Sketchup::Material, nil]
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_place_handle_instance(entities, definition, asset, config, face, material)
            transform = na_compute_handle_transform(asset, config, face)
            instance  = entities.add_instance(definition, transform)
            return nil unless instance && instance.valid?

            instance.name = (face == :interior) ? "Na__DoorHandle__Interior" : "Na__DoorHandle__Exterior"
            TagManager.na_apply_tag_to_entity(instance, :door_handle)

            if material
                instance.material = material
            end

            DebugTools.na_debug_geometry("Placed #{face} handle instance")
            instance
        end
        private_class_method :na_place_handle_instance
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Apply Standard Dark-Grey Edge Colour to Handle Mesh
        # ------------------------------------------------------------
        # Final generation step for handles. Reuses the same DataLib-backed
        # EdgeColourManager path used by the panel design subsystem so all
        # handle edges are always rendered with the canonical dark grey MTE.
        #
        # @param handle_instance [Sketchup::ComponentInstance, nil]
        # @return [Integer] Number of edges painted
        def self.na_apply_standard_dark_grey_edge_colour(handle_instance)
            return 0 unless handle_instance && handle_instance.valid?

            edge_colour_id = EdgeColourManager::NA_DEFAULT_DARK_GREY_KEY
            EdgeColourManager.na_apply_edge_colour_to_group(handle_instance, edge_colour_id)
        rescue StandardError => e
            DebugTools.na_debug_error("Failed to apply standard dark-grey edge colour to handle", e)
            0
        end
        private_class_method :na_apply_standard_dark_grey_edge_colour
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compute the Insertion Transform for a Handle
        # ------------------------------------------------------------
        # Combines four transformations:
        #   1. Handle lay-back rotation (Z -90, X -90, X -90 around
        #      ORIGIN / 00__OriginPoint) - see na_compute_handle_lay_back_rotation
        #   2. Optional X mirror for left-hand handing (ScaleX = -1)
        #   3. Translation to the panel face (interior or exterior side)
        #   4. Translation along X to the hinge offset and along Z to handle height
        def self.na_compute_handle_transform(asset, config, face)
            metadata             = asset["Na__Asset__Metadata"] || {}
            handle_height_mm     = config["Na__DoorConfig__HandleHeight_mm"].to_f
            handle_height_mm     = metadata["Na__PanelPlacement__DefaultHeight_mm"].to_f if handle_height_mm <= 0
            handle_height_mm     = 900 if handle_height_mm <= 0                          # <-- Final fallback

            opening_w_mm         = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            lining_t_mm          = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm           = config["Na__DoorConfig__PanelThickness_mm"].to_f
            swing_side           = (config["Na__DoorConfig__SwingSide"] || "Left").downcase

            placement_block      = (swing_side == "left") ? "Na__PanelPlacement__LeftHand" : "Na__PanelPlacement__RightHand"
            placement            = metadata[placement_block] || {}
            offset_x_mm          = placement["Na__PanelPlacement__OffsetX_mm"].to_f
            offset_y_mm          = placement["Na__PanelPlacement__OffsetY_mm"].to_f
            scale_x              = placement["Na__PanelPlacement__ScaleX"]
            scale_x              = (swing_side == "left") ? -1.0 : 1.0 if scale_x.nil?

            inner_w_mm           = opening_w_mm - 2 * lining_t_mm
            hinge_x_mm           = (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
            handle_x_mm          = (swing_side == "left") ?
                                       (hinge_x_mm + inner_w_mm + offset_x_mm) :
                                       (hinge_x_mm - inner_w_mm + offset_x_mm * scale_x)

            panel_centre_y_mm    = GeometryHelpers.na_panel_centre_y_mm(config)        # <-- Swing-direction-aware panel centre
            handle_y_mm          = if face == :interior
                                       panel_centre_y_mm + (panel_t_mm / 2.0) + offset_y_mm
                                   else
                                       panel_centre_y_mm - (panel_t_mm / 2.0) - offset_y_mm
                                   end

            mm = ->(v) { GeometryHelpers.na_mm_to_inch(v) }

            base_origin   = Geom::Point3d.new(mm.call(handle_x_mm), mm.call(handle_y_mm), mm.call(handle_height_mm))

            t_origin      = Geom::Transformation.new(base_origin)
            t_lay_back    = na_compute_handle_lay_back_rotation                                  # <-- Handle lay-back correction (Z -180 then X -90)
            t_face_flip   = na_compute_handle_face_flip(face)                                    # <-- Mirror across panel XZ plane for exterior face
            t_handing     = (scale_x < 0) ? Geom::Transformation.scaling(ORIGIN, -1, 1, 1) : Geom::Transformation.new

            t_origin * t_face_flip * t_handing * t_lay_back
        end
        private_class_method :na_compute_handle_transform
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compose Face Flip for Interior / Exterior Handle
        # ------------------------------------------------------------
        # After lay-back the handle sits with its "out-of-face" axis
        # along local +Y and the lever along local -X. Placing the
        # exterior copy needs the handle mirrored across the panel's
        # own XZ plane so the lever's "out-of-face" direction flips
        # while the lever stays on the same (latch) side of the panel.
        #
        # A pure Y-axis mirror (scaling 1, -1, 1 around ORIGIN) is the
        # only transformation that achieves this cleanly; no rotation
        # of the laid-back handle produces a "Y-only" flip. The mirror
        # has determinant = -1, which inverts face normals inside the
        # instance; finish is applied at instance level in
        # na_place_handle_instance, so the mirrored copy remains visually
        # consistent with the interior copy.
        #
        # Interior handle receives an identity transformation so the
        # authored orientation survives to the interior face.
        #
        # @param face [Symbol] :interior or :exterior
        # @return [Geom::Transformation]
        def self.na_compute_handle_face_flip(face)
            return Geom::Transformation.new unless face == :exterior
            Geom::Transformation.scaling(ORIGIN, 1, -1, 1)
        end
        private_class_method :na_compute_handle_face_flip
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compose Handle Lay-Back Rotation (X -90)
        # ------------------------------------------------------------
        # The unified handle assets are authored lying on their back so
        # that the exporter's 00__OriginPoint sits at the handle spindle
        # with Z+ pointing up so a correction is required to orientate the handle
        # Rotation around model X axis -90Deg fixes this.
        def self.na_compute_handle_lay_back_rotation
            rotateHandleX = Geom::Transformation.rotation(ORIGIN, X_AXIS, -90.degrees)
          end
        private_class_method :na_compute_handle_lay_back_rotation
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__HandleBuilder3D
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
