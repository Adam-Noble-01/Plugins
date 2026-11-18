# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - FRAMEWORK BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__FrameworkBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__FrameworkBuilder
# AUTHOR     : Noble Architecture
# PURPOSE    : Builds what a run makes of its panels' own parts once they are
#              joined: the fused framework (every frame member as ONE solid),
#              one continuous cill and one continuous internal window board,
#              each mitred round every corner of the path.
# CREATED    : 17-Nov-2026 (V2.7.3)
#
# WHY (Adam, 17-Nov-2026, the SK02 bay windows ARN001 and ARN002)
#   "the sill should wrap around all of the sides, and there shouldn't be any
#   join lines" ... "I don't think the fuse parts are working correctly".
#   Measured on ARN002: every window had its own 50 x 50 cill as wide as the
#   window; the run's mullions, corner posts and end blocks stood from the
#   base, so they cut the cill line at every post and corner; each window's
#   board, returned 30 past its sides, overlapped the next by 10 at every
#   mullion and by 90 x 90 at each corner; and the windows' heads and bottom
#   rails met the run's mullions as separate solids, a join line at each.
#
# WHAT IT BUILDS, INSIDE THE RUN'S DEFINITION
#   Na__Run__Framework      Na__RunFramework__Fused        one solid: the head and
#                                                          bottom rail of every
#                                                          frameless window, the
#                                                          mullions and jambs, the
#                                                          infill blocks, the
#                                                          corner posts
#   Na__Run__Cill           Na__RunCill__01                one solid per stretch
#   Na__Run__WindowBoard    Na__RunWindowBoard__01         one solid per stretch
#   Na__Run__Worktop        Na__RunWorktop__01             V2.7.4, Cabinets: one
#                                                          solid per stretch of
#                                                          base and drawer units
#   A group is made only when it has something to hold. Without SketchUp
#   Pro's solid tools the framework's members are left as separate solids,
#   and the run says so.
#
# HOW A CILL OR A BOARD IS MADE (na_sweep)
# - Its section is drawn to the path's LEFT (y) and up (z), as everywhere in a
#   run. Each point of the section runs along the path as a rail, offset by
#   its y and mitred at every corner (Na__RunCills.na_rails), and the faces
#   are laid between the rails. A level side of the section (the cill's top
#   and underside, the board's top) becomes ONE face along the whole stretch,
#   so there is no line where two legs meet. Nothing relies on Follow Me.
#
# WHERE THE SIZES COME FROM
# - The cill: the run's CillHeight_mm and CillProjection_mm; it reaches back
#   to the back of the posts when fused, else to the back of the first
#   panel's frame (as the window's own cill does). Its finish is the
#   window's: Sapele, or the frame's when Paint Cill is on.
# - The board: the first window's own board settings (reveal depth, nosing
#   overhang and type), from the back of the frame or posts. Built only when
#   that window had its board switched on before the run joined it.
# - The framework: each window's own head and bottom thickness (from
#   Na__PanelTypes), the run's mullion and jamb widths and post depth, and
#   the first window's frame finish and frame edge colour.
# - The worktop (V2.7.4): its underside on the units' tops (plinth and
#   carcass), its front the units' fronts plus WorktopOverhang_mm, its back
#   the path (the wall line) plus WorktopBackOverhang_mm, WorktopThickness_mm
#   thick, all read from each unit type's own settings as the Cabinetry tab
#   reads them. Its finish is WorktopMaterialId, else the units' carcass.
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
require_relative 'Na__AssemblyStudio__AssemblyRun__RunCills__'
require_relative 'Na__AssemblyStudio__AssemblyRun__ColumnBuilder__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__FrameworkBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

        DebugTools        = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        EdgeColourManager = Na__AssemblyStudio::Na__AppData::Na__EdgeColourManager
        BoxHelper         = Na__AssemblyStudio::Na__GeometryHelpers::Na__Box
        Defaults          = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        RunCills          = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunCills
        ColumnBuilder     = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__ColumnBuilder

        NA_FRAMEWORK_GROUP   = "Na__Run__Framework".freeze
        NA_FRAMEWORK_FUSED   = "Na__RunFramework__Fused".freeze
        NA_CILL_GROUP        = "Na__Run__Cill".freeze
        NA_BOARD_GROUP       = "Na__Run__WindowBoard".freeze
        NA_WORKTOP_GROUP     = "Na__Run__Worktop".freeze
        NA_SIZE_TOLERANCE_MM = 0.5                                               # <-- Two units further apart than this in height or depth are named
        NA_CUTTER_REACH_MM   = 20.0                                              # <-- V2.7.5: a cut-out reaching the worktop's edge is carried this far past it, and past the top and underside
        NA_CUTTER_PROBE_MM   = 1.0                                               # <-- How far outside a cut-out's side the worktop is looked for
        NA_EDGE_FRAME        = "MTE102__LineColour__SoftBlack__L20".freeze       # <-- The window tab's own frame edge colour
        NA_EDGE_BOARD        = "MTE103__LineColour__MediumDarkGrey__L50".freeze  # <-- The window tab's own board edge colour
        NA_SOFTEN_ANGLE_RAD  = 22.0 * Math::PI / 180.0                           # <-- As the window board: a curved nose reads smooth
        NA_LEVEL_TOLERANCE   = 1.0e-6

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - the Fused Framework
# -----------------------------------------------------------------------------

        # FUNCTION | Every Frame Member of a Fused Run as One Solid
        # ------------------------------------------------------------
        # @param elements [Hash] Na__PanelTypes.na_ensure_elements! result
        #     (:rails per panel type, :values per panel type, :warnings)
        # @return [Integer] members built (fused into one when it could be)
        def self.na_build_framework(entities, layout, elements)
            v       = layout[:settings]
            holder  = entities.add_group
            holder.name = NA_FRAMEWORK_GROUP
            members = 0

            layout[:legs].each do |leg|
                Array(leg[:items]).each do |item|
                    case item[:kind]
                    when Defaults::NA_ITEM_SPAN
                        members += na_build_rails(holder.entities, leg, item, layout, elements[:rails][item[:type]], v)
                    when Defaults::NA_ITEM_COLUMN
                        next unless item[:role] == Defaults::NA_COLUMN_INFILL
                        members += 1 if ColumnBuilder.na_build_leg_box(holder.entities, ColumnBuilder.na_item_name("Na__RunColumn", item), leg, item, nil)
                    else
                        members += 1 if ColumnBuilder.na_build_leg_box(holder.entities, ColumnBuilder.na_item_name("Na__RunPost", item), leg, item, nil)
                    end
                end
            end
            layout[:corners].each do |corner|
                next unless corner[:outline] && corner[:library].nil?
                block = ColumnBuilder.na_build_prism(holder.entities, "Na__RunCorner__C#{corner[:index] + 1}__Post", corner[:outline], v[:height] - corner[:z0].to_f, corner[:z0].to_f)
                members += 1 if block
            end

            if members.zero?
                holder.erase!
                return 0
            end
            look  = na_frame_look(layout, elements)
            fused = na_fuse(holder.entities, elements[:warnings])
            [fused].compact.each { |solid| na_finish(solid, look[:material], look[:edge]) }
            holder.entities.grep(Sketchup::Group).each { |part| na_finish(part, look[:material], look[:edge]) } unless fused
            members
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | The Head and Bottom Rail Over One Frameless Window
        # ------------------------------------------------------------
        # @return [Integer] rails built
        def self.na_build_rails(entities, leg, item, layout, rails, v)
            type = layout[:types][item[:type]] || {}
            return 0 unless type[:frameless] && rails
            band = [v[:post_inset], v[:post_inset] + v[:post_depth]]
            top  = item[:z1].to_f
            base = item[:base_z].to_f
            built = 0
            [["Head", top - rails[:top].to_f, rails[:top].to_f], ["Bottom", base, rails[:bottom].to_f]].each do |role, z0, height|
                next unless height > 0.01
                group = BoxHelper.na_create_grouped_box(
                    entities, format("Na__RunRail__L%d__S%d__%s", item[:leg] + 1, item[:span] + 1, role),
                    item[:s0].mm, band[0].mm, z0.mm, (item[:s1] - item[:s0]).mm, (band[1] - band[0]).mm, height.mm
                )
                next unless group
                group.transformation = ColumnBuilder.na_leg_transformation(leg)
                built += 1
            end
            built
        end
        private_class_method :na_build_rails
        # ---------------------------------------------------------------

        # SUB FUNCTION | Fuse Every Member in a Holder Into One Solid
        # ------------------------------------------------------------
        # Sequential outer shell, as the window tab's Fuse Parts does. Each
        # step replaces the two solids with their outer shell in the same
        # entities. A failure leaves the members as they are.
        # @return [Sketchup::Group, nil] the fused solid, nil when not fused
        def self.na_fuse(entities, warnings)
            parts = entities.grep(Sketchup::Group).to_a
            return parts.first.tap { |solid| solid.name = NA_FRAMEWORK_FUSED } if parts.length == 1
            unless Sketchup.is_pro?
                warnings << "The framework's members were left as separate solids: fusing them needs SketchUp Pro's solid tools."
                return nil
            end

            result = parts.shift
            parts.each_with_index do |part, step|
                shell = result.outer_shell(part)
                unless shell
                    warnings << "The framework could not be fused into one solid (step #{step + 1} of #{parts.length}, #{part.name}): its members were left as separate solids."
                    return nil
                end
                result = shell
            end
            result.name = NA_FRAMEWORK_FUSED
            result
        rescue StandardError => e
            warnings << "The framework could not be fused into one solid: #{e.message}"
            nil
        end
        private_class_method :na_fuse
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - One Cill and One Window Board
# -----------------------------------------------------------------------------

        # FUNCTION | One Cill Along Every Cill Stretch
        # ------------------------------------------------------------
        # @return [Integer] cills built
        def self.na_build_cills(entities, layout, elements, config)
            v = layout[:settings]
            return 0 unless v[:join_cills] && v[:cill_height].to_f > 0 && !Array(layout[:cills]).empty?
            holder = nil
            built  = 0
            layout[:cills].each do |stretch|
                code    = stretch[:types].first
                values  = elements[:values][code] || {}
                back    = na_back_mm(v, values)
                profile = [[-v[:cill_projection].to_f, 0.0], [back, 0.0], [back, v[:cill_height].to_f], [-v[:cill_projection].to_f, v[:cill_height].to_f]]
                holder ||= na_holder(entities, NA_CILL_GROUP)
                solid = na_sweep(holder.entities, format("Na__RunCill__%02d", stretch[:index] + 1), stretch[:centreline], stretch[:closed], profile)
                next unless solid
                na_finish(solid, na_cill_material(values), nil)
                na_check_cill_types(stretch, elements, code)
                built += 1
            end
            built
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Internal Window Board Along Every Board Stretch
        # ------------------------------------------------------------
        # Its section is the window tab's own (the nosing asset at the
        # window's reveal depth and overhang), its top under the frame, on
        # the cill's top.
        # @return [Integer] boards built
        def self.na_build_boards(entities, layout, elements, config)
            v = layout[:settings]
            return 0 unless v[:join_cills] && !Array(layout[:boards]).empty?
            board_builder = Na__AssemblyStudio::Na__WindowSystem::Na__WindowBoardBuilder
            holder = nil
            built  = 0
            layout[:boards].each do |stretch|
                code   = stretch[:types].find { |type_code| (layout[:types][type_code] || {})[:window] }
                row    = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PanelTypes.na_row(config, code) || {}
                values = elements[:values][code] || {}
                next unless na_board_wanted?(row, values)

                profile = na_board_profile(board_builder, values, v)
                unless profile
                    elements[:warnings] << "The window board along #{stretch[:spans].first}...#{stretch[:spans].last} was not built: nosing type #{values['window_board_nosing_type']} has no usable profile."
                    next
                end
                holder ||= na_holder(entities, NA_BOARD_GROUP)
                solid = na_sweep(holder.entities, format("Na__RunWindowBoard__%02d", stretch[:index] + 1), stretch[:centreline], stretch[:closed], profile)
                next unless solid
                na_finish(solid, na_material(values["frame_material_id"]), values["edge_colour_window_board_id"].to_s.empty? ? NA_EDGE_BOARD : values["edge_colour_window_board_id"])
                Na__AssemblyStudio::Na__WindowSystem::Na__SashHornBuilder.na_soften_smooth_edges_below_angle(solid, NA_SOFTEN_ANGLE_RAD)
                built += 1
            end
            built
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API - One Worktop Along the Base Units (V2.7.4)
# -----------------------------------------------------------------------------

        # FUNCTION | One Worktop Along Every Worktop Stretch
        # ------------------------------------------------------------
        # A plain rectangular section swept along the stretch, so it is one
        # solid round every corner with its top and underside one face each.
        # Units of different heights or depths under one stretch: it sits on
        # the highest and overhangs the deepest, and the run says so.
        # @param elements [Hash] Na__PanelTypes.na_ensure_elements! result
        # @return [Array<Hash>] one row per worktop built (string keys, mm):
        #     name, spans, underside_mm, top_mm, front_mm (to the front edge,
        #     from the path), back_mm (behind the path), thickness_mm, solid
        def self.na_build_worktops(entities, layout, elements)
            v = layout[:settings]
            return [] unless v[:worktop] && !Array(layout[:worktops]).empty?
            holder  = nil
            built   = []
            cutouts = Array(layout[:worktop_cutouts])
            used    = []
            layout[:worktops].each do |stretch|
                size = na_worktop_size(stretch, elements)
                next unless size
                front   = -(size[:front] + v[:worktop_overhang].to_f)
                back    = v[:worktop_back].to_f
                z0      = size[:top]
                z1      = z0 + v[:worktop_thickness].to_f
                profile = [[front, z0], [back, z0], [back, z1], [front, z1]]
                name    = format("Na__RunWorktop__%02d", stretch[:index] + 1)
                holder ||= na_holder(entities, NA_WORKTOP_GROUP)
                solid   = na_sweep(holder.entities, name, stretch[:centreline], stretch[:closed], profile)
                unless solid
                    elements[:warnings] << "The worktop over #{stretch[:spans].first}...#{stretch[:spans].last} could not be drawn."
                    next
                end
                material = na_worktop_material(v, size[:values], elements[:warnings])
                na_finish(solid, material, nil)
                band  = RunCills.na_band_outline(stretch[:centreline], front, back, stretch[:closed])
                cuts  = na_cut_worktop!(holder.entities, solid, band, z0, z1, cutouts, elements[:warnings])
                solid = cuts[:solid]
                na_finish(solid, material, nil) unless cuts[:cut].empty?                # <-- The cut faces take the worktop's finish too
                used.concat(cuts[:cut])
                built << { "name" => name, "spans" => stretch[:spans], "underside_mm" => z0.round(1), "top_mm" => z1.round(1),
                           "front_mm" => (-front).round(1), "back_mm" => back.round(1), "thickness_mm" => v[:worktop_thickness].to_f.round(1),
                           "cutouts" => cuts[:cut].empty? ? nil : cuts[:cut], "solid" => solid.manifold? }.compact
            end
            (cutouts.map { |cutout| cutout[:label] } - used).each do |label|
                elements[:warnings] << "Cut-out #{label} lies on no worktop of the run: nothing was cut for it."
            end
            holder.erase! if holder && holder.valid? && holder.entities.length.zero?
            built
        end
        # ---------------------------------------------------------------

        # FUNCTION | Cut a Worktop's Holes and Notches (V2.7.5)
        # ------------------------------------------------------------
        # Each cut-out whose outline overlaps the worktop becomes a cutter:
        # its outline from below the underside to above the top, carried
        # NA_CUTTER_REACH_MM past any side that reaches the worktop's edge (a
        # notch), so no face of the cutter lies on a face of the worktop.
        # SketchUp Pro's cutter.subtract(worktop) gives a new group, the
        # worktop less the cutter, and erases both. The worktop is copied
        # first: a cut that fails or leaves no closed solid is put back, and
        # the run says so.
        # @param band [Hash] the worktop's plan outline (na_band_outline)
        # @return [Hash] { :solid => the worktop now, :cut => [labels cut] }
        def self.na_cut_worktop!(entities, solid, band, z0, z1, cutouts, warnings)
            cut = []
            hits = cutouts.select { |cutout| na_overlaps?(cutout[:outline], band[:outer]) }
            return { :solid => solid, :cut => cut } if hits.empty?
            unless Sketchup.is_pro?
                warnings << "The worktop's cut-outs (#{hits.map { |cutout| cutout[:label] }.join(', ')}) were not made: cutting needs SketchUp Pro's solid tools."
                return { :solid => solid, :cut => cut }
            end

            name = solid.name
            hits.each do |cutout|
                cutter = na_prism(entities, na_reach_edges(cutout[:outline], band), z0 - NA_CUTTER_REACH_MM, z1 + NA_CUTTER_REACH_MM)
                unless cutter
                    warnings << "Cut-out #{cutout[:label]} could not be drawn: the worktop was left whole there."
                    next
                end
                spare  = solid.copy
                result = cutter.subtract(solid)
                if result && result.valid? && result.manifold?
                    spare.erase! if spare.valid?
                    result.name = name
                    solid = result
                    cut << cutout[:label]
                else
                    [result, cutter, solid].each { |left| left.erase! if left && left.valid? }
                    spare.name = name
                    solid = spare
                    warnings << "Cut-out #{cutout[:label]} could not be cut cleanly from #{name}: the worktop was left whole there."
                end
            end
            { :solid => solid, :cut => cut }
        rescue StandardError => e
            warnings << "The worktop's cut-outs stopped: #{e.message}"
            { :solid => solid, :cut => cut }
        end
        private_class_method :na_cut_worktop!
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Carry a Cut-Out Past Any Side That Reaches the Worktop's Edge
        # ------------------------------------------------------------
        # A side whose outside, NA_CUTTER_PROBE_MM away, is not worktop moves
        # out by NA_CUTTER_REACH_MM (both its ends). Exact for a rectangle.
        # @return [Array<Array>] the cutter's outline, anticlockwise
        def self.na_reach_edges(outline, band)
            points = RunCills.na_area(outline) >= 0 ? outline.map(&:dup) : outline.reverse.map(&:dup)
            moves  = Array.new(points.length) { [0.0, 0.0] }
            points.each_index do |i|
                a = points[i]
                b = points[(i + 1) % points.length]
                length = Math.sqrt((b[0] - a[0])**2 + (b[1] - a[1])**2)
                next if length < 1.0e-6
                out   = [(b[1] - a[1]) / length, -(b[0] - a[0]) / length]       # <-- Anticlockwise: outward is the side turned right
                probe = [(a[0] + b[0]) / 2.0 + out[0] * NA_CUTTER_PROBE_MM, (a[1] + b[1]) / 2.0 + out[1] * NA_CUTTER_PROBE_MM]
                next if na_in_band?(probe, band)
                [i, (i + 1) % points.length].each do |j|
                    moves[j][0] += out[0] * NA_CUTTER_REACH_MM
                    moves[j][1] += out[1] * NA_CUTTER_REACH_MM
                end
            end
            points.each_with_index.map { |point, i| [point[0] + moves[i][0], point[1] + moves[i][1]] }
        end
        private_class_method :na_reach_edges
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Vertical Prism (a Cutter) From a Plan Outline, mm
        # ------------------------------------------------------------
        def self.na_prism(entities, outline, z_low, z_high)
            group = entities.add_group
            face  = group.entities.add_face(outline.map { |x, y| Geom::Point3d.new(x.mm, y.mm, z_low.mm) })
            unless face && face.valid?
                group.erase!
                return nil
            end
            face.reverse! if face.normal.z < 0
            face.pushpull((z_high - z_low).mm)
            return group if group.manifold?
            group.erase!
            nil
        end
        private_class_method :na_prism
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Do a Cut-Out and a Worktop's Plan Bounds Overlap
        # ------------------------------------------------------------
        def self.na_overlaps?(outline, other)
            xs, ys = outline.transpose
            ox, oy = other.transpose
            xs.min < ox.max && xs.max > ox.min && ys.min < oy.max && ys.max > oy.min
        end
        private_class_method :na_overlaps?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Is a Plan Point On the Worktop (In Its Outer, Not Its Hole)
        # ------------------------------------------------------------
        def self.na_in_band?(point, band)
            na_in_polygon?(point, band[:outer]) && !(band[:inner] && na_in_polygon?(point, band[:inner]))
        end
        private_class_method :na_in_band?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Point in Polygon (Even-Odd Ray Cast)
        # ------------------------------------------------------------
        def self.na_in_polygon?(point, polygon)
            x, y   = point
            inside = false
            polygon.each_index do |i|
                a = polygon[i]
                b = polygon[(i + 1) % polygon.length]
                next unless (a[1] > y) != (b[1] > y)
                inside = !inside if x < a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            end
            inside
        end
        private_class_method :na_in_polygon?
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | The Sweep (a Section Run Along a Path, Mitred, Level Faces Whole)
# -----------------------------------------------------------------------------

        # FUNCTION | A Section Swept Along a Centreline Into One Solid
        # ------------------------------------------------------------
        # @param profile [Array<Array>] the section, [[y, z], ...] mm, a closed
        #     polygon in either direction: y to the path's left, z up
        # @return [Sketchup::Group, nil]
        def self.na_sweep(entities, name, centreline, closed, profile)
            points = centreline.map { |point| [point[0].to_f, point[1].to_f] }
            return nil if points.length < 2 || profile.length < 3

            rails  = RunCills.na_rails(points, profile, closed)
            group  = entities.add_group
            group.name = name
            spin   = RunCills.na_area(profile) >= 0 ? 1.0 : -1.0                 # <-- Anticlockwise in (y, z): outward is the edge turned right
            legs   = na_leg_vectors(points, closed)
            ends   = closed ? points.length : points.length - 1

            profile.each_index do |j|
                k  = (j + 1) % profile.length
                dy = profile[k][0] - profile[j][0]
                dz = profile[k][1] - profile[j][1]
                length = Math.sqrt(dy * dy + dz * dz)
                next if length < NA_LEVEL_TOLERANCE
                out_y = spin * dz / length
                out_z = -spin * dy / length

                if dz.abs < NA_LEVEL_TOLERANCE
                    na_level_face(group.entities, rails[j], rails[k], closed, out_z)        # <-- One face along the whole stretch
                    next
                end
                (0...ends).each do |segment|
                    following = (segment + 1) % points.length
                    left = legs[segment][:left]
                    na_add_face(group.entities, [rails[j][segment], rails[j][following], rails[k][following], rails[k][segment]],
                                [left[0] * out_y, left[1] * out_y, out_z])
                end
            end

            unless closed
                first = legs.first[:dir]
                last  = legs[ends - 1][:dir]
                na_add_face(group.entities, rails.map(&:first), [-first[0], -first[1], 0.0])
                na_add_face(group.entities, rails.map(&:last), [last[0], last[1], 0.0])
            end
            DebugTools.na_debug_geometry("Run #{name}: #{group.entities.grep(Sketchup::Face).length} faces, solid #{group.manifold?}")
            group
        rescue ArgumentError => e
            DebugTools.na_debug_warn("Run #{name} could not be drawn: #{e.message}")
            group.erase! if group && group.valid?
            nil
        end
        # ---------------------------------------------------------------

        # SUB FUNCTION | A Level Side of the Section as One Face (or a Ring on a Loop)
        # ------------------------------------------------------------
        def self.na_level_face(entities, rail_a, rail_b, closed, out_z)
            outward = [0.0, 0.0, out_z]
            return na_add_face(entities, rail_a + rail_b.reverse, outward) unless closed

            outer, inner = RunCills.na_area(rail_a.map { |p| p[0, 2] }).abs >= RunCills.na_area(rail_b.map { |p| p[0, 2] }).abs ? [rail_a, rail_b] : [rail_b, rail_a]
            face = na_add_face(entities, outer, outward)
            hole = entities.add_face(inner.map { |x, y, z| Geom::Point3d.new(x.mm, y.mm, z.mm) })
            hole.erase! if hole && hole.valid?
            face
        end
        private_class_method :na_level_face
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Add a Face From mm Points, Turned to Face Outward
        # ------------------------------------------------------------
        def self.na_add_face(entities, points_mm, outward)
            face = entities.add_face(points_mm.map { |x, y, z| Geom::Point3d.new(x.mm, y.mm, z.mm) })
            return nil unless face && face.valid?
            face.reverse! if face.normal.dot(Geom::Vector3d.new(*outward)) < 0
            face
        end
        private_class_method :na_add_face
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Each Leg's Direction and Left of a Centreline
        # ------------------------------------------------------------
        def self.na_leg_vectors(points, closed)
            count = closed ? points.length : points.length - 1
            (0...count).map do |index|
                direction = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath.na_direction(points[index], points[(index + 1) % points.length]) || [1.0, 0.0]
                { :dir => direction, :left => Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath.na_left(direction) }
            end
        end
        private_class_method :na_leg_vectors
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Sizes, Finishes and Checks
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | How Far Back a Cill or Board Starts (mm to the Left)
        # ------------------------------------------------------------
        # Fused: the back of the posts (the frames are the run's). Else the
        # back of the panel's own frame, as the window's own cill reaches.
        def self.na_back_mm(v, values)
            return [v[:post_inset], 0.0].max + v[:post_depth] if v[:fuse]
            depth = values["frame_depth_mm"] || Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_FRAME_DEPTH
            values["frame_wall_inset_mm"].to_f + depth.to_f
        end
        private_class_method :na_back_mm
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Board's Section in the Run's Frame ([y, z] mm)
        # ------------------------------------------------------------
        # The window tab's own section (Na__WindowBoardBuilder), with no
        # returns, its top raised to the cill's top.
        def self.na_board_profile(board_builder, values, v)
            section = board_builder.na_resolve_section(values["window_board_nosing_type"] || "1")
            return nil unless section
            back   = na_back_mm(v, values)
            params = {
                :frame_wall_inset             => 0.0,
                :frame_depth                  => back.mm,
                :window_board_reveal_depth    => (values["window_board_reveal_depth_mm"] || Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_WINDOW_BOARD_REVEAL_DEPTH).to_f.mm,
                :window_board_nosing_overhang => (values["window_board_nosing_overhang_mm"] || Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_WINDOW_BOARD_NOSING_OVERHANG).to_f.mm,
                :window_board_returns_enabled => false,
                :width                        => 0.0
            }
            lift = v[:cill_height].to_f
            board_builder.na_straight_section_points(board_builder.na_board_geometry(params, section)).map do |y_in, z_in|
                [y_in.to_mm, z_in.to_mm + lift]
            end
        end
        private_class_method :na_board_profile
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Did the Window Have Its Board On Before the Run Joined It
        # ------------------------------------------------------------
        def self.na_board_wanted?(row, values)
            kept = row["CillBeforeJoin"]
            return kept["window_board_enabled"] == true if kept.is_a?(Hash)
            values["window_board_enabled"] == true
        end
        private_class_method :na_board_wanted?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Framework's Finish: the First Frameless Window's Frame
        # ------------------------------------------------------------
        def self.na_frame_look(layout, elements)
            code   = layout[:types].values.find { |type| type[:frameless] && type[:count].to_i > 0 }&.dig(:code) || layout[:types].keys.first
            values = elements[:values][code] || {}
            edge   = values["edge_colour_frame_id"].to_s.empty? ? NA_EDGE_FRAME : values["edge_colour_frame_id"]
            { :material => na_material(values["frame_material_id"]), :edge => edge }
        end
        private_class_method :na_frame_look
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Cill's Finish, as the Window Tab Gives Its Own
        # ------------------------------------------------------------
        def self.na_cill_material(values)
            return na_material(values["frame_material_id"]) if values["paint_cill"] == true
            na_material(Na__AssemblyStudio::Na__WindowSystem::NA_DEFAULT_CILL_MATERIAL_ID)
        end
        private_class_method :na_cill_material
        # ---------------------------------------------------------------

        # HELPER FUNCTION | How High and How Deep the Units Under a Worktop Stand
        # ------------------------------------------------------------
        # Each unit type's own settings, read as the Cabinetry tab reads them
        # (its resolver's na_effective): the top is the plinth plus the
        # carcass; the front is the carcass depth plus the door, or the
        # carcass alone when the unit is open-fronted.
        # @return [Hash, nil] { :top, :front, :values (the first type's) }
        def self.na_worktop_size(stretch, elements)
            resolver = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__LayoutResolver
            sizes = stretch[:types].filter_map do |code|
                values = elements[:values][code]
                next nil unless values
                unit = resolver.na_effective(values)
                { :code => code, :values => values, :top => unit[:z_base] + unit[:height],
                  :front => unit[:depth] + (unit[:layout] == "Open" ? 0.0 : unit[:front_thickness]) }
            end
            return nil if sizes.empty?

            label = "#{stretch[:spans].first}...#{stretch[:spans].last}"
            { :top => "stand", :front => "have their fronts" }.each do |key, words|
                found = sizes.map { |size| size[key] }
                next unless found.max - found.min > NA_SIZE_TOLERANCE_MM
                listed = sizes.map { |size| "#{size[:code]} #{size[key].round}" }.join(', ')
                elements[:warnings] << "The units under the worktop over #{label} #{words} at different #{key == :top ? 'heights' : 'depths'} (#{listed}): " \
                                       "it #{key == :top ? 'sits on the highest' : 'overhangs the deepest'}."
            end
            { :top => sizes.map { |size| size[:top] }.max, :front => sizes.map { |size| size[:front] }.max, :values => sizes.first[:values] }
        end
        private_class_method :na_worktop_size
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Worktop's Finish: Its Own, Else the Units' Carcass
        # ------------------------------------------------------------
        def self.na_worktop_material(v, values, warnings)
            chosen = v[:worktop_material].to_s
            unless chosen.empty?
                return na_material(chosen) if na_known_material?(chosen)               # <-- nil for the library's own default: SketchUp's default
                warnings << "Worktop material '#{chosen}' is not in the material library: the units' carcass finish is used."
            end
            na_material(values["Na__CabinetConfig__CarcassMaterialId"])
        end
        private_class_method :na_worktop_material
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Is a Material Id in the Library
        # ------------------------------------------------------------
        def self.na_known_material?(material_id)
            Array(Na__AssemblyStudio::Na__AppData::Na__MaterialManager.na_get_all_material_ids).include?(material_id)
        rescue StandardError
            false
        end
        private_class_method :na_known_material?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Library Material by Id (Nil = SketchUp's Default)
        # ------------------------------------------------------------
        def self.na_material(material_id)
            return nil if material_id.to_s.empty?
            Na__AssemblyStudio::Na__AppData::Na__MaterialManager.na_get_material_by_id(material_id.to_s)
        rescue StandardError => e
            DebugTools.na_debug_warn("Run material '#{material_id}' unavailable: #{e.message}")
            nil
        end
        private_class_method :na_material
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Paint a Solid's Faces and Edges
        # ------------------------------------------------------------
        def self.na_finish(group, material, edge_colour_id)
            return unless group && group.valid?
            if material
                group.entities.grep(Sketchup::Face).each do |face|
                    face.material      = material
                    face.back_material = material
                end
            end
            EdgeColourManager.na_apply_edge_colour_to_group(group, edge_colour_id) if edge_colour_id
        rescue StandardError => e
            DebugTools.na_debug_warn("Run #{group.name} finish not applied: #{e.message}")
        end
        private_class_method :na_finish
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Say When the Panels Along a Cill Had Different Finishes
        # ------------------------------------------------------------
        def self.na_check_cill_types(stretch, elements, first_code)
            first = elements[:values][first_code] || {}
            stretch[:types].each do |code|
                other = elements[:values][code] || {}
                next if other["paint_cill"] == first["paint_cill"] && (other["paint_cill"] != true || other["frame_material_id"] == first["frame_material_id"])
                elements[:warnings] << "Panel types #{first_code} and #{code} finish their cills differently: the run's one cill takes #{first_code}'s."
            end
        end
        private_class_method :na_check_cill_types
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Named Holder Group, Made Once
        # ------------------------------------------------------------
        def self.na_holder(entities, name)
            group      = entities.add_group
            group.name = name
            group
        end
        private_class_method :na_holder
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__FrameworkBuilder
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
