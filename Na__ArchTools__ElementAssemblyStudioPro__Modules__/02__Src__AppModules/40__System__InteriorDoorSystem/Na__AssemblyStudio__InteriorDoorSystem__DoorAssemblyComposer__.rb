# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR DOOR SYSTEM - DOOR ASSEMBLY COMPOSER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__InteriorDoorSystem__DoorAssemblyComposer__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorDoorSystem
# MODULE     : Na__DoorAssemblyComposer
# AUTHOR     : Noble Architecture
# PURPOSE    : Composes the moving and static parts of the door into the
#              TrueVision-compatible group hierarchy used downstream by
#              the GLB Builder for openable doors.
# CREATED    : 01-May-2026
#
# DESCRIPTION:
# - Hosts the algorithm that wraps the panel, handles, and 2D swing into a
#   movable group named "MOD001__ROT__90-Deg__DoorPanel".
# - Adds an empty marker group "ROT001__RotationPoint__DoorHingeCentre" at
#   the hinge axis so the TrueVision converter can pick up the rotation
#   pivot.
# - Wraps both into "ADR001__InternalDoor" - the outer assembly root.
# - Tags the closed-state assembly with :door_closed.
# - When config[:create_open_state_copy] is true (default), the closed
#   assembly is duplicated, the inner MOD group is rotated 90 degrees
#   about the hinge axis, and the duplicate is tagged :door_open. This
#   matches the user's workflow of toggling between open and closed
#   state visibility tags in SketchUp / Layout.
# - The lining and architraves are NOT enclosed in the MOD/ROT/ADR
#   hierarchy: they are static parts of the assembly and remain at the
#   ComponentDefinition root.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
# - Hierarchy names follow the TrueVision spec exactly.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__DoorAssemblyComposer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools       = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers  = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        GeometryBuilders = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryBuilders
        HandleBuilder3D  = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D
        TagManager       = Na__AssemblyStudio::Na__AppUtils::Na__TagManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Hierarchy Names
# -----------------------------------------------------------------------------

        # CONSTANTS | TrueVision Hierarchy Names
        # ------------------------------------------------------------
        NA_GROUP_NAME_ADR_OUTER     = "ADR001__InternalDoor".freeze            # <-- Assembly root
        NA_GROUP_NAME_MOD_PANEL     = "MOD001__ROT__90-Deg__DoorPanel".freeze  # <-- Movable subassembly
        NA_GROUP_NAME_ROT_HINGE     = "ROT001__RotationPoint__DoorHingeCentre".freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Compose the Closed Door Assembly
        # ------------------------------------------------------------
        # Builds the panel + handles + swing inside a MOD group, attaches
        # a ROT marker, and wraps everything in the ADR outer assembly.
        # The caller supplies the door's component-definition entities
        # (the assembly is added at the root of the definition).
        #
        # @param config [Hash] Door configuration block
        # @param entities [Sketchup::Entities] Definition-level entities
        # @param panel_material [Sketchup::Material, nil]
        # @param handle_material [Sketchup::Material, nil]
        # @return [Hash] { :adr => Group, :mod => Group, :rot => Group }
        def self.na_compose_closed_assembly(config, entities, panel_material, handle_material)
            adr_group       = entities.add_group
            adr_group.name  = NA_GROUP_NAME_ADR_OUTER
            adr_ents        = adr_group.entities

            mod_group       = adr_ents.add_group
            mod_group.name  = NA_GROUP_NAME_MOD_PANEL
            mod_ents        = mod_group.entities

            GeometryBuilders.na_build_panel(config, mod_ents, panel_material)
            HandleBuilder3D.na_build_handles(config, mod_ents, handle_material)
            GeometryBuilders.na_build_swing(config, mod_ents)

            rot_group       = adr_ents.add_group
            rot_group.name  = NA_GROUP_NAME_ROT_HINGE
            na_translate_rot_marker_to_hinge(rot_group, config)

            TagManager.na_apply_tag_to_entity(adr_group, :door_closed)
            DebugTools.na_debug_geometry("Composed closed assembly: ADR + MOD + ROT")

            { :adr => adr_group, :mod => mod_group, :rot => rot_group }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compose the Open-State Copy of the Closed Assembly
        # ------------------------------------------------------------
        # Duplicates the closed ADR group and rotates the inner MOD group
        # 90 degrees about the hinge axis so the door reads as open. The
        # outer ADR copy is tagged :door_open. The lining and architraves
        # remain shared (they sit at the definition root, not inside ADR).
        #
        # @param config [Hash] Door configuration
        # @param closed_assembly [Hash] Result of na_compose_closed_assembly
        # @param entities [Sketchup::Entities] Same definition entities used above
        # @return [Sketchup::Group, nil] The open-state ADR group
        def self.na_compose_open_state_copy(config, closed_assembly, entities)
            return nil unless closed_assembly[:adr] && closed_assembly[:adr].valid?

            adr_open                  = na_duplicate_group(closed_assembly[:adr], entities)
            return nil unless adr_open

            mod_open                  = na_find_child_group_by_name(adr_open, NA_GROUP_NAME_MOD_PANEL)
            if mod_open
                rotation_transform    = na_compute_open_rotation_transform(config)
                mod_open.transform!(rotation_transform)
            else
                DebugTools.na_debug_warn("Open-state copy missing MOD group; skipping rotation")
            end

            TagManager.na_apply_tag_to_entity(adr_open, :door_open)
            DebugTools.na_debug_geometry("Composed open-state copy with 90deg rotation")
            adr_open
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Move the Empty ROT Marker Group to the Hinge Axis
        # ------------------------------------------------------------
        # The ROT marker is an empty group whose origin matches the hinge
        # axis of the door panel. The TrueVision GLB Builder reads the
        # group's transformation to derive the rotation pivot.
        def self.na_translate_rot_marker_to_hinge(rot_group, config)
            opening_w_mm    = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            wall_depth_mm   = config["Na__DoorConfig__WallDepth_mm"].to_f
            lining_t_mm     = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm      = config["Na__DoorConfig__PanelThickness_mm"].to_f
            face_offset_mm  = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            swing_side      = (config["Na__DoorConfig__SwingSide"] || "Left").downcase

            hinge_x_mm      = (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
            hinge_y_mm      = face_offset_mm + (wall_depth_mm - panel_t_mm) / 2.0

            translation     = Geom::Transformation.new(Geom::Point3d.new(
                GeometryHelpers.na_mm_to_inch(hinge_x_mm),
                GeometryHelpers.na_mm_to_inch(hinge_y_mm),
                0
            ))
            rot_group.transform!(translation)
        end
        private_class_method :na_translate_rot_marker_to_hinge
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compute the Open-State Rotation Transformation
        # ------------------------------------------------------------
        # Right-hand doors swing CW in plan when viewed from above; left-
        # hand doors swing CCW. Inward swings rotate one way, outward
        # swings rotate the other.
        def self.na_compute_open_rotation_transform(config)
            opening_w_mm    = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            wall_depth_mm   = config["Na__DoorConfig__WallDepth_mm"].to_f
            lining_t_mm     = config["Na__DoorConfig__LiningThickness_mm"].to_f
            panel_t_mm      = config["Na__DoorConfig__PanelThickness_mm"].to_f
            face_offset_mm  = config["Na__DoorConfig__LiningFaceOffset_mm"].to_f
            swing_side      = (config["Na__DoorConfig__SwingSide"]      || "Left").downcase
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").downcase

            hinge_x_mm      = (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
            hinge_y_mm      = face_offset_mm + (wall_depth_mm - panel_t_mm) / 2.0

            pivot           = Geom::Point3d.new(
                GeometryHelpers.na_mm_to_inch(hinge_x_mm),
                GeometryHelpers.na_mm_to_inch(hinge_y_mm),
                0
            )

            base_angle      = (swing_side == "left") ? 90.degrees : -90.degrees
            sign            = (swing_direction == "inward") ? 1.0 : -1.0
            angle           = base_angle * sign

            Geom::Transformation.rotation(pivot, Z_AXIS, angle)
        end
        private_class_method :na_compute_open_rotation_transform
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Find the First Child Group Matching a Name
        # ------------------------------------------------------------
        def self.na_find_child_group_by_name(parent_group, child_name)
            return nil unless parent_group && parent_group.valid?
            parent_group.entities.grep(Sketchup::Group).find { |g| g.name == child_name }
        end
        private_class_method :na_find_child_group_by_name
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Duplicate a Group at the Same Position
        # ------------------------------------------------------------
        # Uses Sketchup::Group#copy to clone the group inside the parent
        # entities collection. The copy preserves child geometry and
        # nested group hierarchy.
        def self.na_duplicate_group(source_group, target_entities)
            return nil unless source_group && source_group.valid?

            copy = source_group.copy
            return nil unless copy && copy.valid?
            copy.name = source_group.name
            copy
        end
        private_class_method :na_duplicate_group
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__DoorAssemblyComposer
end # module Na__InteriorDoorSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
