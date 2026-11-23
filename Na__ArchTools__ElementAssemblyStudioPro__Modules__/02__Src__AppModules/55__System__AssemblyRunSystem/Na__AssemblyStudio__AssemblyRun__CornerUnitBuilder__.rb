# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - CORNER UNIT BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__CornerUnitBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__CornerUnitBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : The corner type of cabinet: an L-shaped corner base unit where
#              two legs of a cabinet run meet in the corner of a room. Its
#              carcass is drawn here; its two doors, their style and their
#              handles come from the Cabinetry tab's own builders, from the
#              settings of the panel type beside it, so it matches the run.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# THE UNIT (millimetres, its own frame)
# - Origin at the start of arm A on the wall line, at floor level. X along
#   the first leg towards the corner, the wall on y = 0, the room on -y.
#   Each arm is Leg long along its wall and one carcass Depth deep:
#     arm A   x 0 .. Leg,           y -Depth .. 0
#     arm B   x Leg - Depth .. Leg, y -Leg .. 0      (along the second wall)
# - A door on each arm, meeting on a square post at the inside corner; each
#   is hinged at the open end of its arm. Plinth boards under both fronts.
#
#        wall of leg 1 (y = 0)
#     0 +--------------------------+ Leg      x ->
#       |  arm A                   |
#       +---------------+ post     |          y
#         door A        |  arm B   |          |
#                door B |          |          v
#                       +----------+ -Leg
#                              wall of leg 2 (x = Leg)
#
# IT IS THE RUN'S OWN, NOT AN ACB CABINET (V2.7.0)
# - It is rebuilt with the run from the neighbouring type's settings and has
#   no tab of its own: selecting it loads nothing. Making it a full Cabinetry
#   product (its own id, preview and settings) is the next step.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnBuilder__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__CornerUnitBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools    = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        Defaults      = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        ColumnBuilder = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__ColumnBuilder

        NA_CARCASS_GROUP   = "Na__Cabinet__Carcass".freeze
        NA_PART_PREFIX     = "Na__Carcass__".freeze
        NA_PLINTH_PREFIX   = "Na__Cabinet__".freeze
        NA_FRONTS_GROUP    = "Na__CornerUnit__Fronts__%s".freeze
        NA_MIN_DOOR_MM     = 150.0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build the Corner Unit of One Corner
        # ------------------------------------------------------------
        # @param entities       [Sketchup::Entities] the run's corners group
        # @param corner         [Hash] a layout corner of kind CornerUnit
        # @param leg_in         [Hash] the layout leg arriving at the corner
        # @param cabinet_values [Hash, nil] the Na__CabinetConfiguration of
        #                       the panel type beside it (nil = the defaults)
        # @return [Sketchup::Group, nil]
        def self.na_build(entities, corner, leg_in, cabinet_values, name)
            cabinetry = Na__AssemblyStudio::Na__InteriorCabinetrySystem
            cabinetry.na_require_modules
            values    = na_base_values(cabinet_values)
            plan      = na_plan(cabinetry::Na__LayoutResolver.na_effective(values), corner[:size])
            materials = cabinetry::Na__GeometryEngine.send(:na_resolve_materials, values)
            helpers   = cabinetry::Na__GeometryHelpers

            group = helpers.na_add_group(entities, name)
            group.transformation = ColumnBuilder.na_leg_transformation(leg_in, leg_in[:length] - corner[:size])

            carcass = helpers.na_add_group(group.entities, NA_CARCASS_GROUP)
            plan[:parts].each  { |part| helpers.na_add_box_part(carcass.entities, part, NA_PART_PREFIX, materials[:carcass]) }
            plan[:plinth].each { |part| helpers.na_add_box_part(group.entities, part, NA_PLINTH_PREFIX, materials[:plinth]) }
            plan[:doors].each  { |door| na_build_door(group.entities, door, values, materials, cabinetry) }
            DebugTools.na_debug_geometry("Run corner unit #{name}: #{plan[:parts].length} boards, #{plan[:doors].length} doors")
            group
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Unit's Plan (Pure, mm)
# -----------------------------------------------------------------------------

        # FUNCTION | Every Board, Plinth Board and Door of a Corner Unit
        # ------------------------------------------------------------
        # @param v   [Hash] Cabinetry Na__LayoutResolver.na_effective values
        # @param leg [Float] the length of each arm along its wall
        # @return [Hash] { :parts => [box], :plinth => [box], :doors => [{ :arm, :width, :origin, :hinge }] }
        def self.na_plan(v, leg)
            t      = v[:board]
            d      = v[:depth]
            ft     = v[:front_thickness]
            z0     = v[:z_base]
            z1     = v[:z_base] + v[:height]
            back   = v[:back_inset] + v[:back]                                   # <-- Front face of the back panel, in from the wall
            inner  = leg - d                                                     # <-- x of arm B's front, and how far arm A's front runs
            box    = lambda { |name, x0, x1, y0, y1, za, zb| { :name => name, :x0 => x0, :x1 => x1, :y0 => y0, :y1 => y1, :z0 => za, :z1 => zb } }

            parts = [
                box.call("EndPanel__ArmA", 0.0,   t,     -d,       0.0,  z0, z1),
                box.call("EndPanel__ArmB", inner, leg,   -leg,     -leg + t, z0, z1),
                box.call("BasePanel__ArmA", t,    leg,   -d,       -back, z0,     z0 + t),
                box.call("BasePanel__ArmB", inner, leg - back, -leg + t, -d, z0,  z0 + t),
                box.call("TopPanel__ArmA",  t,    leg,   -d,       -back, z1 - t, z1),
                box.call("TopPanel__ArmB",  inner, leg - back, -leg + t, -d, z1 - t, z1),
                box.call("CornerPost",      inner - ft, inner, -d - ft,  -d, z0,     z1)
            ]
            if v[:back] > 0
                parts << box.call("BackPanel__ArmA", t, leg, -back, -v[:back_inset], z0, z1)
                parts << box.call("BackPanel__ArmB", leg - back, leg - v[:back_inset], -leg + t, -back, z0, z1)
            end
            if v[:shelves] > 0
                shelf_z = z0 + (v[:height] - t) / 2.0
                setback = v[:shelf_setback]
                parts << box.call("Shelf__ArmA", t, leg - back, -d + setback, -back, shelf_z, shelf_z + t)
                parts << box.call("Shelf__ArmB", inner + setback, leg - back, -leg + t, -d + setback, shelf_z, shelf_z + t)
            end

            plinth = []
            if v[:plinth_enabled] && z0 >= 20.0
                front = -d + [v[:plinth_setback], d / 2.0].min                   # <-- y of arm A's plinth face
                side  = inner + [v[:plinth_setback], d / 2.0].min                # <-- x of arm B's plinth face
                plinth << box.call("Plinth__ArmA", 0.0, side + v[:plinth_thickness], front, front + v[:plinth_thickness], 0.0, z0)
                plinth << box.call("Plinth__ArmB", side, side + v[:plinth_thickness], -leg, front, 0.0, z0)
            end

            door_width = inner - ft                                              # <-- From the arm's open end to the corner post
            doors = []
            if door_width >= NA_MIN_DOOR_MM
                doors << { :arm => "A", :width => door_width, :hinge => "Left",  :origin => [0.0, 0.0],        :along => [1.0, 0.0] }
                doors << { :arm => "B", :width => door_width, :hinge => "Right", :origin => [leg, -(d + ft)], :along => [0.0, -1.0] }
            end
            { :parts => parts.select { |part| na_box_ok?(part) }, :plinth => plinth.select { |part| na_box_ok?(part) }, :doors => doors }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Box Have Real Volume
        # ------------------------------------------------------------
        def self.na_box_ok?(part)
            (part[:x1] - part[:x0]) > 0.01 && (part[:y1] - part[:y0]) > 0.01 && (part[:z1] - part[:z0]) > 0.01
        end
        private_class_method :na_box_ok?
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Doors (the Cabinetry Tab's Own Fronts and Handles)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Neighbour's Settings as a Plain Base Unit
        # ------------------------------------------------------------
        # Whatever the neighbour is (a drawer pack, a tall unit), the corner
        # unit is a base unit with doors in the neighbour's style.
        def self.na_base_values(cabinet_values)
            defaults = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__Defaults
            values   = Marshal.load(Marshal.dump(defaults::NA_DEFAULT_CABINET_CONFIGURATION)).merge(cabinet_values.is_a?(Hash) ? cabinet_values : {})
            values.merge("Na__CabinetConfig__UnitType" => "Base", "Na__CabinetConfig__BaseFrontLayout" => "Doors")
        end
        private_class_method :na_base_values
        # ---------------------------------------------------------------

        # SUB FUNCTION | One Arm's Door: Resolved and Built as a Base Unit's Is
        # ------------------------------------------------------------
        # The Cabinetry resolver lays out a one-door base unit of the door's
        # width; only its front and handle are built, in a group stood on
        # the arm: X along the arm's wall, the room on -Y.
        def self.na_build_door(entities, door, values, materials, cabinetry)
            door_values = values.merge(
                "Na__CabinetConfig__Width_mm"  => door[:width],
                "Na__CabinetConfig__DoorCount" => "1",
                "Na__CabinetConfig__HingeSide" => door[:hinge],
                "Na__CabinetConfig__FrontStandoff_mm" => 0                       # <-- V2.7.8: the corner unit's doors stay on its own door plane (its post is drawn there)
            )
            layout = cabinetry::Na__LayoutResolver.na_resolve(door_values)
            holder = cabinetry::Na__GeometryHelpers.na_add_group(entities, format(NA_FRONTS_GROUP, door[:arm]))
            along  = Geom::Vector3d.new(door[:along][0], door[:along][1], 0)
            holder.transformation = Geom::Transformation.axes(
                Geom::Point3d.new(door[:origin][0].mm, door[:origin][1].mm, 0),
                along, Geom::Vector3d.new(0, 0, 1) * along, Geom::Vector3d.new(0, 0, 1)
            )
            cabinetry::Na__FrontBuilder.na_build(layout, holder.entities, materials)
            cabinetry::Na__HandleBuilder.na_build(layout, holder.entities, layout[:values][:handle_key], materials)
            holder
        end
        private_class_method :na_build_door
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__CornerUnitBuilder
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
