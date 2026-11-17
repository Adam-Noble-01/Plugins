# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - COLUMN BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__ColumnBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__ColumnBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds everything on a run that is the run's own: the fused
#              mullions and jambs, infill blocks, library columns on their
#              backing blocks, and the block or library column in each corner.
#              Spans (the elements) and cabinet corner units are built
#              elsewhere.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# WHAT IT BUILDS, INSIDE THE RUN'S DEFINITION
#   Na__Run__Posts      Na__RunPost__L1__02__Mullion      one box each
#   Na__Run__Columns    Na__RunColumn__L1__03__Infill     a block
#                       Na__RunColumn__L1__03__Backing    behind a library column
#                       Na__RunColumn__L1__03__Vale260    the library column
#   Na__Run__Corners    Na__RunCorner__C1__Post / __Backing / __Vale260
#   A group is made only when it has something to hold.
#
# COORDINATES
# - Everything is built in the run definition's own frame (a closed
#   context), from the layout's millimetres. Each leg has a frame: X along
#   the leg, Y to its left, Z up; a box is drawn in that frame and the
#   group is given the leg's transformation.
#
# EDGE COLOURS (the whitecard hierarchy of the DataLib)
# - Posts are frame members: Dark Grey L40. Blocks are mass: Soft Black L20.
#   A library column keeps its own greys.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__EdgeColourManager__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__GeometryHelpers__Box__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnLibrary__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__ColumnBuilder

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        BoxHelper         = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box
        Defaults          = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        ColumnLibrary     = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__ColumnLibrary

        NA_POSTS_GROUP        = "Na__Run__Posts".freeze
        NA_COLUMNS_GROUP      = "Na__Run__Columns".freeze
        NA_CORNERS_GROUP      = "Na__Run__Corners".freeze
        NA_EDGE_FRAME_MEMBER  = "MTE103__LineColour__DarkGrey__L40".freeze
        NA_EDGE_MASS          = "MTE102__LineColour__SoftBlack__L20".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frames (the Run's Own Plan to SketchUp)
# -----------------------------------------------------------------------------

        # FUNCTION | A Plan Point in mm as a Point3d at a Height
        # ------------------------------------------------------------
        def self.na_point(plan_point, z_mm = 0.0)
            Geom::Point3d.new(plan_point[0].to_f.mm, plan_point[1].to_f.mm, z_mm.to_f.mm)
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Leg's Frame: X Along It, Y to Its Left, Z Up
        # ------------------------------------------------------------
        # A span's element, a post and a library column all stand in this
        # frame, moved along X to their station.
        # @param station_mm [Float] distance along the leg from its first point
        # @param z_mm       [Float] height above the run's base
        def self.na_leg_transformation(leg, station_mm = 0.0, z_mm = 0.0)
            origin = na_point([leg[:p0][0] + leg[:dir][0] * station_mm, leg[:p0][1] + leg[:dir][1] * station_mm], z_mm)
            Geom::Transformation.axes(origin,
                                      Geom::Vector3d.new(leg[:dir][0], leg[:dir][1], 0),
                                      Geom::Vector3d.new(leg[:left][0], leg[:left][1], 0),
                                      Geom::Vector3d.new(0, 0, 1))
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Build Every Post, Column and Corner Block of a Layout
        # ------------------------------------------------------------
        # @param layout   [Hash] Na__LayoutResolver.na_resolve result
        # @param entities [Sketchup::Entities] the run definition's
        # @param framework [Boolean] the run is fused: its posts, infill
        #     blocks and corner posts are frame members, built and fused by
        #     Na__FrameworkBuilder (V2.7.3), and only counted here
        # @return [Hash] { :posts, :columns, :corners } counts
        def self.na_build(layout, entities, model, framework: false)
            holders = {}
            holder  = lambda do |name|
                holders[name] ||= begin
                    group      = entities.add_group
                    group.name = name
                    group
                end
            end
            counts = { :posts => 0, :columns => 0, :corners => 0 }
            height = layout[:settings][:height]

            layout[:legs].each do |leg|
                Array(leg[:items]).each do |item|
                    case item[:kind]
                    when "Post"
                        na_build_leg_box(holder.call(NA_POSTS_GROUP).entities, na_item_name("Na__RunPost", item), leg, item, NA_EDGE_FRAME_MEMBER) unless framework
                        counts[:posts] += 1
                    when Defaults::NA_ITEM_COLUMN
                        next if item[:role] == Defaults::NA_COLUMN_GAP
                        counts[:columns] += 1
                        next if framework && item[:role] == Defaults::NA_COLUMN_INFILL
                        na_build_column(holder.call(NA_COLUMNS_GROUP).entities, leg, item, height, model)
                    end
                end
            end

            layout[:corners].each do |corner|
                next unless corner[:outline]
                counts[:corners] += 1
                next if framework && corner[:library].nil?                                          # <-- A corner post is a frame member
                na_build_corner(holder.call(NA_CORNERS_GROUP).entities, corner, layout, model)
            end
            DebugTools.na_debug_geometry("Run parts: #{counts[:posts]} posts, #{counts[:columns]} columns, #{counts[:corners]} corner blocks")
            counts
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Posts and Columns Along a Leg
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | A Part Name: Na__RunPost__L1__02__Mullion
        # ------------------------------------------------------------
        def self.na_item_name(head, item, role = item[:role])
            format("%s__L%d__%02d__%s", head, item[:leg] + 1, item[:seq] + 1, role)
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | One Box in a Leg's Frame, From an Item's Extents
        # ------------------------------------------------------------
        # Also builds the fused framework's members (Na__FrameworkBuilder),
        # which are painted once fused: edge_colour nil paints nothing.
        # @return [Sketchup::Group, nil]
        def self.na_build_leg_box(entities, name, leg, item, edge_colour)
            return nil unless item[:y0] && item[:z1] && item[:width].to_f > 0.01 && item[:z1].to_f - item[:z0].to_f > 0.01
            group = BoxHelper.na_create_grouped_box(
                entities, name,
                item[:s0].mm, item[:y0].mm, item[:z0].mm,
                (item[:s1] - item[:s0]).mm, (item[:y1] - item[:y0]).mm, (item[:z1] - item[:z0]).mm
            )
            return nil unless group
            group.transformation = na_leg_transformation(leg)
            na_paint_edges(group, edge_colour) if edge_colour
            group
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | An Infill Block, or a Library Column on Its Backing
        # ------------------------------------------------------------
        def self.na_build_column(entities, leg, item, height_mm, model)
            unless Defaults::NA_LIBRARY_COLUMNS.key?(item[:role])
                na_build_leg_box(entities, na_item_name("Na__RunColumn", item), leg, item, NA_EDGE_MASS)
                return
            end
            na_build_leg_box(entities, na_item_name("Na__RunColumn", item, "Backing"), leg, item, NA_EDGE_MASS)
            definition    = ColumnLibrary.na_variant(model, item[:role], :inline, height_mm)
            instance      = entities.add_instance(definition, na_leg_transformation(leg, item[:s0]))
            instance.name = na_item_name("Na__RunColumn", item)
        end
        private_class_method :na_build_column
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Corners
# -----------------------------------------------------------------------------

        # SUB FUNCTION | A Corner Block, With Its Library Column When It Has One
        # ------------------------------------------------------------
        # The library corner column stands on the corner of the two framework
        # faces: its own X runs along the leg leaving the corner, its own Y
        # back along the leg arriving, so its body is proud of both faces.
        def self.na_build_corner(entities, corner, layout, model)
            v      = layout[:settings]
            label  = "Na__RunCorner__C#{corner[:index] + 1}"
            height = v[:frames] ? v[:height] : v[:filler_height]
            base   = corner[:z0].to_f                                                               # <-- On the run's cill when one runs through the corner (V2.7.3)
            block  = na_build_prism(entities, "#{label}__#{corner[:library] ? 'Backing' : 'Post'}", corner[:outline], height - base, base)
            na_paint_edges(block, NA_EDGE_MASS) if block
            return unless corner[:library]

            definition = ColumnLibrary.na_variant(model, corner[:library], :corner, height)
            transform  = Geom::Transformation.axes(
                na_point(corner[:point]),
                Geom::Vector3d.new(corner[:dir_out][0], corner[:dir_out][1], 0),
                Geom::Vector3d.new(-corner[:dir_in][0], -corner[:dir_in][1], 0),
                Geom::Vector3d.new(0, 0, 1)
            )
            instance      = entities.add_instance(definition, transform)
            instance.name = "#{label}__#{corner[:library]}"
        end
        private_class_method :na_build_corner
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Plan Outline Raised Into a Solid Block
        # ------------------------------------------------------------
        # The face is drawn at its base and turned to face up before it is
        # pushed, so the block always rises (SketchUp turns a face drawn on
        # z = 0 to face down).
        # @param base_mm [Float] height of its underside above the run's base
        # @return [Sketchup::Group, nil]
        def self.na_build_prism(entities, name, outline, height_mm, base_mm = 0.0)
            points = outline.map { |plan_point| na_point(plan_point, base_mm) }
            return nil if points.length < 3 || height_mm <= 0
            group      = entities.add_group
            group.name = name
            face       = group.entities.add_face(points)
            face.reverse! if face.normal.z < 0
            face.pushpull(height_mm.mm)
            group
        rescue ArgumentError => e
            DebugTools.na_debug_warn("Run corner block '#{name}' could not be drawn: #{e.message}")
            group.erase! if group && group.valid?
            nil
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edge Colours
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Paint a Group's Edges With a DataLib Edge Colour
        # ------------------------------------------------------------
        # Never fatal: an unpainted block is still a block.
        def self.na_paint_edges(group, edge_colour_id)
            return unless group && group.valid?
            EdgeColourManager.na_apply_edge_colour_to_group(group, edge_colour_id)
        rescue StandardError => e
            DebugTools.na_debug_warn("Run edge colour '#{edge_colour_id}' not applied: #{e.message}")
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__ColumnBuilder
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
