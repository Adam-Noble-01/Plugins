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
# - Builds the moving door panel as a top-level group at the
#   ComponentDefinition root. The group name is chosen per swing
#   direction so TrueVision3D's click-to-open animation rotates each
#   door the correct way (the JS scanner parses the signed degree
#   token from the group name via Na__DoorAnim__DEG_REGEX):
#     * Outward swing -> "MOD001__ROT__-90-Deg__DoorPanel" (clockwise from above)
#     * Inward  swing -> "MOD001__ROT__90-Deg__DoorPanel"  (counterclockwise from above)
#   The MOD group holds the panel solid, the handles, and the panel
#   design linework.
# - There is NO inner ADR wrapper group. The outer ComponentDefinition
#   itself (e.g. ADR013__InteriorDoor__) is the ADR for TrueVision3D's
#   scanner, and MOD/ROT sit as direct siblings inside it. This avoids
#   the GLB Builder collapsing a redundant single-child ADR layer and
#   stripping the MOD prefix that the click-to-open animation needs.
# - Adds the marker group "ROT001__RotationPoint__DoorHingeCentre" at
#   the ComponentDefinition root level (sibling of MOD) so the SketchUp
#   author can grab the pivot helper without drilling into the door
#   panel. The group's origin is the hinge axis - downstream tools read
#   its transformation/origin to derive the rotation pivot. The group is
#   then populated with red pivot helper linework (vertical hinge axis
#   line + crosshairs at both ends + swing-direction arrow) by
#   Na__RotationPivotBuilder. The helpers live on the dedicated tag
#   `02__DoorHelpers__RotationPivots`, are painted with the
#   `MTE201__LineColour__Red` edge material, and are stripped from GLB
#   export by the `02__` numeric prefix + `Glb__FullyExcluded: true`.
# - Tags the closed-state MOD with :door_closed.
# - When config[:create_open_state_copy] is true (default), the MOD
#   group is duplicated and the duplicate is rotated 90 degrees about
#   the hinge axis, then tagged :door_open. This matches the user's
#   workflow of toggling between open and closed state visibility tags
#   in SketchUp / Layout. Both MODs share the single ROT marker.
# - The lining, architraves, and the single 2D swing arc remain at the
#   ComponentDefinition root and are NOT duplicated for the open state.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
# - Hierarchy names follow the TrueVision3D animation spec.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryHelpers__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__GeometryBuilders__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__HandleBuilder3D__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__PanelDesignBuilder__'
require_relative 'Na__AssemblyStudio__InteriorDoorSystem__RotationPivotBuilder__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'

module Na__AssemblyStudio
module Na__InteriorDoorSystem
    module Na__DoorAssemblyComposer

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools           = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers      = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryHelpers
        GeometryBuilders     = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__GeometryBuilders
        HandleBuilder3D      = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__HandleBuilder3D
        PanelDesignBuilder   = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__PanelDesignBuilder
        RotationPivotBuilder = Na__AssemblyStudio::Na__InteriorDoorSystem::Na__RotationPivotBuilder
        TagManager           = Na__AssemblyStudio::Na__AppUtils::Na__TagManager

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Module Constants - Hierarchy Names
# -----------------------------------------------------------------------------

        # CONSTANTS | TrueVision Hierarchy Names
        # ------------------------------------------------------------
        # The OUTER ADR is the door's ComponentDefinition itself
        # (e.g. ADR013__InteriorDoor__) - we do NOT wrap an inner ADR
        # group around the MOD because the GLB Builder flattens a
        # redundant single-child group, which would strip the MOD
        # prefix that TrueVision3D's animation scanner relies on.
        #
        # The MOD group name encodes the rotation direction in its
        # degree token. TrueVision3D's Na__DoorAnim__DEG_REGEX
        # (`/(-?\d+)-Deg/i`) parses the signed integer and rotates
        # the door panel about the Y axis through the ROT pivot.
        # The sign is chosen per swing direction so each door type
        # opens in the correct direction (verified empirically):
        #   * Outward swing  ->  -90-Deg   (correct for outward in TV3D)
        #   * Inward  swing  ->  +90-Deg   (flips so the panel swings into the room)
        # The static legacy alias NA_GROUP_NAME_MOD_PANEL preserves
        # the previous default (outward) for any code that imports
        # the constant directly; the composer routes through
        # na_resolve_mod_panel_name(config) at build time.
        NA_GROUP_NAME_MOD_PANEL_OUTWARD = "MOD001__ROT__-90-Deg__DoorPanel".freeze
        NA_GROUP_NAME_MOD_PANEL_INWARD  = "MOD001__ROT__90-Deg__DoorPanel".freeze
        NA_GROUP_NAME_MOD_PANEL         = NA_GROUP_NAME_MOD_PANEL_OUTWARD                   # <-- legacy alias
        NA_GROUP_NAME_ROT_HINGE         = "ROT001__RotationPoint__DoorHingeCentre".freeze
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Compose the Closed Door Assembly
        # ------------------------------------------------------------
        # Builds the moving door panel (panel + handles + panel design)
        # directly inside a top-level MOD group, then drops the ROT pivot
        # marker as a sibling. The OUTER ADR is the door's
        # ComponentDefinition itself (the caller's `entities` is the
        # definition's entities), so MOD and ROT end up as direct
        # children of the GLB ADR node where TrueVision3D's animation
        # scanner expects them.
        #
        # The 2D swing arc and lining/architraves live at the same
        # definition root level but are tag-controlled and remain shared
        # between the closed MOD and the open-state MOD duplicate.
        #
        # @param config [Hash] Door configuration block
        # @param entities [Sketchup::Entities] Definition-level entities
        # @param panel_material [Sketchup::Material, nil]
        # @param handle_material [Sketchup::Material, nil]
        # @return [Hash] { :mod => Group, :rot => Group, :adr => Group }
        #                (`:adr` aliases `:mod` for legacy callers; the
        #                door no longer has a separate ADR wrapper group)
        def self.na_compose_closed_assembly(config, entities, panel_material, handle_material)
            mod_group       = entities.add_group
            mod_group.name  = na_resolve_mod_panel_name(config)
            mod_ents        = mod_group.entities

            GeometryBuilders.na_build_panel(config, mod_ents, panel_material)
            HandleBuilder3D.na_build_handles(config, mod_ents, handle_material)
            PanelDesignBuilder.na_build_panel_design(config, mod_ents)

            # ROT lives at the ComponentDefinition root level (sibling of
            # the MOD group) so the SketchUp author can grab the pivot
            # helper without drilling into the door panel hierarchy. A
            # single ROT is shared between the closed and open MOD copies.
            rot_group       = entities.add_group
            rot_group.name  = NA_GROUP_NAME_ROT_HINGE
            na_translate_rot_marker_to_hinge(rot_group, config)
            RotationPivotBuilder.na_build_pivot_helper(rot_group, config)

            TagManager.na_apply_tag_to_entity(mod_group, :door_closed)
            DebugTools.na_debug_geometry("Composed closed assembly: MOD + ROT at definition root (no inner ADR wrapper)")

            { :mod => mod_group, :rot => rot_group, :adr => mod_group }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compose the Open-State Copy of the Closed MOD
        # ------------------------------------------------------------
        # Duplicates the closed MOD group at the ComponentDefinition root
        # level and rotates the duplicate 90 degrees about the hinge axis
        # so it reads as the door in its open position. The duplicate is
        # tagged :door_open so the SketchUp author can toggle between the
        # closed and open visual via tag visibility. The single ROT
        # marker is shared - it never moves and never duplicates, so both
        # MODs rotate around the same authored hinge centre.
        #
        # @param config [Hash] Door configuration
        # @param closed_assembly [Hash] Result of na_compose_closed_assembly
        # @param entities [Sketchup::Entities] Same definition entities used above
        # @return [Sketchup::Group, nil] The open-state MOD group
        def self.na_compose_open_state_copy(config, closed_assembly, entities)
            return nil unless closed_assembly[:mod] && closed_assembly[:mod].valid?

            mod_open                  = na_duplicate_group(closed_assembly[:mod], entities)
            return nil unless mod_open

            rotation_transform        = na_compute_open_rotation_transform(config)
            mod_open.transform!(rotation_transform)

            TagManager.na_apply_tag_to_entity(mod_open, :door_open)
            DebugTools.na_debug_geometry("Composed open-state MOD copy with 90deg rotation around hinge")
            mod_open
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve the MOD Panel Group Name for the Door's Swing Direction
        # ------------------------------------------------------------
        # TrueVision3D's Na__DoorAnim__DEG_REGEX parses the signed
        # degree token from the MOD group name and rotates the door
        # panel about the Y axis through the ROT pivot. We pick the
        # sign per swing direction so each door type opens in the
        # correct direction in the click-to-open animation:
        #   * Outward swing -> "-90-Deg" (clockwise from above in TV3D)
        #   * Inward  swing -> "90-Deg"  (counterclockwise from above)
        # Defaults to inward when the configuration omits the field
        # (matches the Na__DoorConfiguration default).
        def self.na_resolve_mod_panel_name(config)
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").to_s.downcase
            case swing_direction
            when "inward"  then NA_GROUP_NAME_MOD_PANEL_INWARD
            when "outward" then NA_GROUP_NAME_MOD_PANEL_OUTWARD
            else                NA_GROUP_NAME_MOD_PANEL_INWARD
            end
        end
        private_class_method :na_resolve_mod_panel_name
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Move the Empty ROT Marker Group to the Hinge Axis
        # ------------------------------------------------------------
        # The ROT marker is an empty group whose origin matches the hinge
        # axis of the door panel. The TrueVision GLB Builder reads the
        # group's transformation to derive the rotation pivot.
        def self.na_translate_rot_marker_to_hinge(rot_group, config)
            opening_w_mm    = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            lining_t_mm     = config["Na__DoorConfig__LiningThickness_mm"].to_f
            swing_side      = (config["Na__DoorConfig__SwingSide"] || "Left").downcase

            hinge_x_mm      = (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
            hinge_y_mm      = GeometryHelpers.na_hinge_y_origin_mm(config)    # <-- Hinge-face wall (near for inward, far for outward)

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
        # Door-local coords have +X along the wall, +Y through the wall
        # depth (front face at Y=0). The room sits on the -Y side of the
        # wall, so an Inward swing must rotate the closed hinge->latch
        # vector to -Y, and an Outward swing must rotate it to +Y. This
        # matches the dialog's JS plan view, which always draws the open
        # latch on the room side.
        def self.na_compute_open_rotation_transform(config)
            opening_w_mm    = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            lining_t_mm     = config["Na__DoorConfig__LiningThickness_mm"].to_f
            swing_side      = (config["Na__DoorConfig__SwingSide"]      || "Left").downcase
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").downcase

            hinge_x_mm      = (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
            hinge_y_mm      = GeometryHelpers.na_hinge_y_origin_mm(config)    # <-- Hinge-face wall (near for inward, far for outward)

            pivot           = Geom::Point3d.new(
                GeometryHelpers.na_mm_to_inch(hinge_x_mm),
                GeometryHelpers.na_mm_to_inch(hinge_y_mm),
                0
            )

            base_angle      = (swing_side == "left") ? 90.degrees : -90.degrees
            sign            = (swing_direction == "inward") ? -1.0 : 1.0
            angle           = base_angle * sign

            Geom::Transformation.rotation(pivot, Z_AXIS, angle)
        end
        private_class_method :na_compute_open_rotation_transform
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
