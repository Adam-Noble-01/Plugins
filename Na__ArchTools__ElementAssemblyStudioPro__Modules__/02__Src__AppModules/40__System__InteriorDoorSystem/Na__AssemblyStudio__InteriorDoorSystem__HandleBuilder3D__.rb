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
#   module applies a +90 deg rotation about the Y axis when inserting
#   into the door, per the user's spec.
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
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__AssetLibrary__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

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

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Variables (Cache)
# -----------------------------------------------------------------------------

        @na_handle_def_cache = {}                                              # <-- AssetKey -> Sketchup::ComponentDefinition

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
            asset_key = config["Na__DoorConfig__HandleAssetKey"]
            asset     = AssetLibrary.na_load_handle_asset(asset_key)

            unless asset
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' could not be loaded - skipping handles")
                return { :interior => nil, :exterior => nil }
            end

            handle_def = na_get_or_build_handle_definition(asset_key, asset, material)
            return { :interior => nil, :exterior => nil } unless handle_def

            interior_inst = na_place_handle_instance(entities, handle_def, asset, config, :interior, material)
            exterior_inst = na_place_handle_instance(entities, handle_def, asset, config, :exterior, material)

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

        # HELPER FUNCTION | Get or Build the Handle ComponentDefinition
        # ------------------------------------------------------------
        # Returns a cached definition if one was built earlier in the
        # session. Otherwise builds a fresh definition from the asset's
        # Na__Asset__Mesh3D block and caches it.
        def self.na_get_or_build_handle_definition(asset_key, asset, material)
            cached = @na_handle_def_cache[asset_key]
            return cached if cached && cached.valid?

            mesh_block = asset["Na__Asset__Mesh3D"]
            unless mesh_block
                DebugTools.na_debug_warn("Handle asset '#{asset_key}' missing Na__Asset__Mesh3D block")
                return nil
            end

            model       = Sketchup.active_model
            return nil unless model

            def_name    = "Na__InteriorDoor__Handle__#{asset_key}"
            existing    = model.definitions[def_name]
            return @na_handle_def_cache[asset_key] = existing if existing && existing.valid?

            definition  = model.definitions.add(def_name)
            na_build_mesh_into_definition(definition, mesh_block, material)
            @na_handle_def_cache[asset_key] = definition
            DebugTools.na_debug_geometry("Built handle definition '#{def_name}'")
            definition
        end
        private_class_method :na_get_or_build_handle_definition
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Populate a ComponentDefinition from Mesh3D Data
        # ------------------------------------------------------------
        # Adds vertices and faces from the asset's Mesh3D block as faces
        # in the definition. Skips faces with fewer than three vertices.
        def self.na_build_mesh_into_definition(definition, mesh_block, material)
            vertices = mesh_block["Na__Geometry__Vertices"] || []
            faces    = mesh_block["Na__Geometry__Faces"]    || []

            return if vertices.empty? || faces.empty?

            point_table = na_build_vertex_point_table(vertices)
            entities    = definition.entities

            faces.each do |frec|
                outer_ids = frec["OuterLoop_VertexIds"] || []
                next if outer_ids.length < 3

                pts       = outer_ids.map { |vid| point_table[vid] }.compact
                next if pts.length < 3

                face = entities.add_face(pts)
                next unless face && face.valid?

                if material
                    face.material      = material
                    face.back_material = material
                end
            end
        end
        private_class_method :na_build_mesh_into_definition
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

        # HELPER FUNCTION | Compute the Insertion Transform for a Handle
        # ------------------------------------------------------------
        # Combines four transformations:
        #   1. +90 deg rotation about Y axis (asset is authored lying on back)
        #   2. Optional X mirror for left-hand handing (ScaleX = -1)
        #   3. Translation to the panel face (interior or exterior side)
        #   4. Translation along X to the hinge offset and along Z to handle height
        def self.na_compute_handle_transform(asset, config, face)
            metadata             = asset["Na__Asset__Metadata"] || {}
            handle_height_mm     = config["Na__DoorConfig__HandleHeight_mm"].to_f
            handle_height_mm     = metadata["Na__PanelPlacement__DefaultHeight_mm"].to_f if handle_height_mm <= 0
            handle_height_mm     = 1050 if handle_height_mm <= 0                          # <-- Final fallback

            opening_w_mm         = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            wall_depth_mm        = config["Na__DoorConfig__WallDepth_mm"].to_f
            lining_t_mm          = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm           = config["Na__DoorConfig__PanelThickness_mm"].to_f
            face_offset_mm       = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            floor_clear_mm       = config["Na__DoorConfig__PanelFloorClearance_mm"].to_f
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

            panel_centre_y_mm    = face_offset_mm + (wall_depth_mm) / 2.0
            handle_y_mm          = if face == :interior
                                       panel_centre_y_mm + (panel_t_mm / 2.0) + offset_y_mm
                                   else
                                       panel_centre_y_mm - (panel_t_mm / 2.0) - offset_y_mm
                                   end

            mm = ->(v) { GeometryHelpers.na_mm_to_inch(v) }

            base_origin   = Geom::Point3d.new(mm.call(handle_x_mm), mm.call(handle_y_mm), mm.call(handle_height_mm))

            t_origin      = Geom::Transformation.new(base_origin)
            t_lay_back    = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees)             # <-- Asset authored on back
            t_face_flip   = (face == :exterior) ? Geom::Transformation.rotation(ORIGIN, Z_AXIS, 180.degrees) : Geom::Transformation.new
            t_handing     = (scale_x < 0) ? Geom::Transformation.scaling(ORIGIN, -1, 1, 1) : Geom::Transformation.new

            t_origin * t_face_flip * t_handing * t_lay_back
        end
        private_class_method :na_compute_handle_transform
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__HandleBuilder3D
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
