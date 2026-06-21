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
#   ComponentDefinition root. The group name encodes the EXACT rotation
#   angle so TrueVision3D's click-to-open animation swings each door
#   in the correct direction. The angle is computed from both swing
#   direction AND hinge side (mirroring na_compute_open_rotation_transform):
#     * Left  + Inward  -> "MOD001__ROT__-90-Deg__DoorPanel"
#     * Right + Inward  -> "MOD001__ROT__90-Deg__DoorPanel"
#     * Left  + Outward -> "MOD001__ROT__90-Deg__DoorPanel"
#     * Right + Outward -> "MOD001__ROT__-90-Deg__DoorPanel"
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
        # MOD group name encodes the exact signed rotation angle so
        # TrueVision3D's Na__DoorAnim__DEG_REGEX (`/(-?\d+)-Deg/i`)
        # can derive the correct direction for every door instance.
        # na_resolve_mod_panel_name(config) computes the angle dynamically
        # from both SwingSide and SwingDirection using the same formula as
        # na_compute_open_rotation_transform — so the GLB animation always
        # matches the SketchUp open-state preview.
        #
        # Reference values (right-handed defaults):
        NA_GROUP_NAME_MOD_PANEL_OUTWARD = "MOD001__ROT__-90-Deg__DoorPanel".freeze   # <-- right+outward
        NA_GROUP_NAME_MOD_PANEL_INWARD  = "MOD001__ROT__90-Deg__DoorPanel".freeze    # <-- right+inward
        NA_GROUP_NAME_MOD_PANEL         = NA_GROUP_NAME_MOD_PANEL_OUTWARD             # <-- legacy alias
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
        # For a single door this builds one MOD + one ROT. For a double
        # door it builds TWO MOD + TWO ROT pairs (one per leaf) in leaf
        # order - MOD001/ROT001 then MOD002/ROT002 - so the downstream
        # TrueVision3D scanner pairs each rotating MOD with its own hinge
        # pivot by sibling index (mirrors the bifold multi-panel contract).
        #
        # @param config [Hash] Door configuration block
        # @param entities [Sketchup::Entities] Definition-level entities
        # @param panel_material [Sketchup::Material, nil]
        # @param handle_material [Sketchup::Material, nil]
        # @return [Hash] { :leaves => [{:mod, :rot, :leaf}, ...],
        #                   :mod => Group, :rot => Group, :adr => Group }
        #                (`:mod`/`:rot`/`:adr` alias the FIRST leaf for
        #                legacy callers; the door no longer has a separate
        #                ADR wrapper group)
        def self.na_compose_closed_assembly(config, entities, panel_material, handle_material)
            leaves = GeometryHelpers.na_compute_leaves(config)
            built  = leaves.map do |leaf|
                na_compose_closed_leaf(config, entities, panel_material, handle_material, leaf)
            end

            DebugTools.na_debug_geometry("Composed closed assembly: #{built.length} leaf MOD+ROT pair(s) at definition root")

            first = built.first || {}
            {
                :leaves => built,
                :mod    => first[:mod],
                :rot    => first[:rot],
                :adr    => first[:mod]
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Compose a Single Closed Leaf (MOD + ROT Pair)
        # ------------------------------------------------------------
        # Builds one moving MOD group (panel + handles + panel design) and
        # its sibling ROT pivot marker for the supplied leaf. Both are added
        # as direct children of the definition entities, MOD first then ROT,
        # so positional index pairing holds for the GLB animation scanner.
        #
        # @param config [Hash] Door configuration block
        # @param entities [Sketchup::Entities] Definition-level entities
        # @param panel_material [Sketchup::Material, nil]
        # @param handle_material [Sketchup::Material, nil]
        # @param leaf [Hash] Leaf descriptor (GeometryHelpers.na_compute_leaves)
        # @return [Hash] { :mod => Group, :rot => Group, :leaf => Hash }
        def self.na_compose_closed_leaf(config, entities, panel_material, handle_material, leaf)
            mod_group       = entities.add_group
            mod_group.name  = na_resolve_mod_panel_name(config, leaf)
            mod_ents        = mod_group.entities

            GeometryBuilders.na_build_panel(config, mod_ents, panel_material, leaf)
            HandleBuilder3D.na_build_handles(config, mod_ents, handle_material, leaf)
            PanelDesignBuilder.na_build_panel_design(config, mod_ents, leaf)

            # ROT lives at the ComponentDefinition root level (sibling of
            # the MOD group) so the SketchUp author can grab the pivot
            # helper without drilling into the door panel hierarchy. One ROT
            # per leaf is shared between that leaf's closed and open copies.
            rot_group       = entities.add_group
            rot_group.name  = na_resolve_rot_marker_name(leaf)
            na_translate_rot_marker_to_hinge(rot_group, config, leaf)
            RotationPivotBuilder.na_build_pivot_helper(rot_group, config, leaf)

            TagManager.na_apply_tag_to_entity(mod_group, :door_closed)
            DebugTools.na_debug_geometry("Composed closed leaf #{leaf[:index]}: #{mod_group.name} + #{rot_group.name}")

            { :mod => mod_group, :rot => rot_group, :leaf => leaf }
        end
        private_class_method :na_compose_closed_leaf
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
        # Each leaf MOD is duplicated and rotated about ITS OWN hinge so a
        # double door reads as both leaves swung open. The matching ROT
        # markers never move or duplicate, so every MOD copy pivots around
        # the same authored hinge centre as its closed counterpart.
        #
        # @param config [Hash] Door configuration
        # @param closed_assembly [Hash] Result of na_compose_closed_assembly
        # @param entities [Sketchup::Entities] Same definition entities used above
        # @return [Array<Sketchup::Group>] The open-state MOD group(s)
        def self.na_compose_open_state_copy(config, closed_assembly, entities)
            built = closed_assembly[:leaves] || []
            opened = built.map do |leaf_record|
                mod_closed = leaf_record[:mod]
                next nil unless mod_closed && mod_closed.valid?

                mod_open = na_duplicate_group(mod_closed, entities)
                next nil unless mod_open

                rotation_transform = na_compute_open_rotation_transform(config, leaf_record[:leaf])
                mod_open.transform!(rotation_transform)

                TagManager.na_apply_tag_to_entity(mod_open, :door_open)
                DebugTools.na_debug_geometry("Composed open-state MOD copy for leaf #{leaf_record[:leaf][:index]} (90deg rotation around its hinge)")
                mod_open
            end
            opened.compact
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers - Geometry
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Resolve the MOD Panel Group Name (Hinge Side + Swing Direction)
        # ------------------------------------------------------------
        # TrueVision3D's Na__DoorAnim__DEG_REGEX parses the signed
        # degree token from the MOD group name and rotates the door
        # panel about the Y axis (GLB Y-up = SketchUp Z-up) through
        # the ROT pivot.
        #
        # The CORRECT angle depends on BOTH swing direction AND hinge
        # side. This mirrors the same formula used by
        # na_compute_open_rotation_transform so the animation angle in
        # the GLB always matches SketchUp's open-state preview:
        #
        #   base_angle = left-hinge → +90°,  right-hinge → -90°
        #   sign       = inward     → -1,     outward     → +1
        #   angle      = base_angle × sign
        #
        # Result table:
        #   Left  + Inward  → -90   ← panel swings into room on left hinge
        #   Right + Inward  → +90   ← panel swings into room on right hinge
        #   Left  + Outward → +90   ← panel swings toward exterior on left hinge
        #   Right + Outward → -90   ← panel swings toward exterior on right hinge
        def self.na_resolve_mod_panel_name(config, leaf = nil)
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").to_s.downcase
            swing_side      = na_leaf_swing_side(config, leaf)

            base_angle = (swing_side == "left") ? 90 : -90
            sign       = (swing_direction == "inward") ? -1 : 1
            angle      = base_angle * sign

            index      = leaf ? leaf[:index].to_i : 1
            "MOD%03d__ROT__%d-Deg__DoorPanel" % [index, angle]
        end
        private_class_method :na_resolve_mod_panel_name
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the ROT Marker Group Name for a Leaf
        # ------------------------------------------------------------
        # Index-matched to the MOD panel name so the GLB animation scanner
        # pairs MOD001<->ROT001, MOD002<->ROT002 by sibling position. A
        # nil/single leaf resolves to ROT001 (unchanged single-door name).
        def self.na_resolve_rot_marker_name(leaf = nil)
            index = leaf ? leaf[:index].to_i : 1
            "ROT%03d__RotationPoint__DoorHingeCentre" % index
        end
        private_class_method :na_resolve_rot_marker_name
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Effective Hinge Side for a Leaf
        # ------------------------------------------------------------
        # A leaf descriptor carries its own forced hinge side (left leaf of
        # a double door is always "left", right leaf always "right"). When
        # no leaf is supplied the single-door config SwingSide is used.
        def self.na_leaf_swing_side(config, leaf)
            return leaf[:swing_side].to_s.downcase if leaf && leaf[:swing_side]
            (config["Na__DoorConfig__SwingSide"] || "Left").to_s.downcase
        end
        private_class_method :na_leaf_swing_side
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Resolve the Hinge Pivot X (mm) for a Leaf
        # ------------------------------------------------------------
        def self.na_leaf_hinge_x_mm(config, leaf)
            return leaf[:hinge_x_mm].to_f if leaf && leaf[:hinge_x_mm]

            opening_w_mm = config["Na__DoorConfig__OpeningWidth_mm"].to_f
            lining_t_mm  = config["Na__DoorConfig__LiningThickness_mm"].to_f
            swing_side   = na_leaf_swing_side(config, leaf)
            (swing_side == "left") ? lining_t_mm : (opening_w_mm - lining_t_mm)
        end
        private_class_method :na_leaf_hinge_x_mm
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Move the Empty ROT Marker Group to the Hinge Axis
        # ------------------------------------------------------------
        # The ROT marker is an empty group whose origin matches the hinge
        # axis of the door panel. The TrueVision GLB Builder reads the
        # group's transformation to derive the rotation pivot.
        def self.na_translate_rot_marker_to_hinge(rot_group, config, leaf = nil)
            hinge_x_mm      = na_leaf_hinge_x_mm(config, leaf)
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
        def self.na_compute_open_rotation_transform(config, leaf = nil)
            swing_side      = na_leaf_swing_side(config, leaf)
            swing_direction = (config["Na__DoorConfig__SwingDirection"] || "Inward").downcase

            hinge_x_mm      = na_leaf_hinge_x_mm(config, leaf)
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
