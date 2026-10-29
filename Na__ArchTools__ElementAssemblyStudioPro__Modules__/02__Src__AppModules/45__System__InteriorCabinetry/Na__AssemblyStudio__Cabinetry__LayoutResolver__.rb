# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - INTERIOR CABINETRY SYSTEM - LAYOUT RESOLVER (RUBY)
# =============================================================================
#
# FILE       : Na__AssemblyStudio__Cabinetry__LayoutResolver__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__InteriorCabinetrySystem
# MODULE     : Na__LayoutResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : Turns one cabinet configuration into the position and size of
#              every part, in millimetres. Pure maths: no SketchUp API, so it
#              runs (and is tested) outside SketchUp.
# CREATED    : 29-Oct-2026
#
# ONE SET OF RULES, TWO LANGUAGES
# - This is the Ruby twin of
#   Na__AssemblyStudio__Cabinetry__Viewport__LayoutResolver__.js, which the
#   dialog previews draw from. The geometry builders build from this one.
#   The CabinetLayout parity check runs both over the same configurations and
#   compares every number, so a rule changed in one must change in the other.
#
# UNIT FRAME (millimetres)
# - Origin : BACK-LEFT corner of the carcass, at FLOOR level, on the wall line.
# - X      : along the run (left to right seen from the front)
# - Y      : depth; the carcass fills -depth..0 and the fronts sit in front of
#            it, so the unit faces -Y like SketchUp's Front view.
# - Z      : up from the floor (a wall unit is built at its mounting height).
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__Cabinetry__Defaults__'

module Na__AssemblyStudio
module Na__InteriorCabinetrySystem
    module Na__LayoutResolver

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        Defaults = Na__AssemblyStudio::Na__InteriorCabinetrySystem::Na__Defaults

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Construction Allowances (not user settings - mirror the JS)
# -----------------------------------------------------------------------------

        NA_AUTO_PAIR_OVER_MM          = 600.0   # <-- UK single doors stop at 600; wider units take a pair
        NA_MIN_DOOR_WIDTH_MM          = 100.0
        NA_MIN_FRONT_HEIGHT_MM        = 60.0
        NA_SHAKER_MIN_PANEL_MM        = 30.0
        NA_SHAKER_MIN_FRAME_MM        = 15.0
        NA_GROOVE_MIN_LAND_MM         = 20.0
        NA_GROOVE_MIN_BACK_MM         = 3.0
        NA_SHELF_MIN_GAP_MM           = 40.0
        NA_RUNNER_CLEARANCE_MM        = 13.0    # <-- Side-mount runner space each side (UK 12.5)
        NA_DRAWER_SIDE_MM             = 15.0
        NA_DRAWER_BASE_MM             = 6.0
        NA_DRAWER_BELOW_FRONT_TOP_MM  = 30.0
        NA_DRAWER_ABOVE_FRONT_BASE_MM = 15.0
        NA_DRAWER_CARCASS_CLEAR_MM    = 5.0
        NA_DRAWER_LENGTH_STEP_MM      = 50.0    # <-- 500 long in a 560 carcass
        NA_DRAWER_REAR_CLEAR_MM       = 10.0
        NA_DRAWER_MIN_WIDTH_MM        = 100.0
        NA_DRAWER_HANDLE_DROP_MM      = 70.0
        NA_TALL_HANDLE_HEIGHT_MM      = 1050.0  # <-- Handle centre above the floor on a full height tall door
        NA_TALL_HANDLE_HALF_MM        = 100.0
        NA_LEG_MIN_HEIGHT_MM          = 80.0
        NA_LEG_BEHIND_PLINTH_MM       = 35.0
        NA_LEG_BEHIND_BACK_MM         = 35.0
        NA_LEG_MIN_ROW_GAP_MM         = 40.0
        NA_MIDDLE_LEGS_OVER_MM        = 900.0   # <-- 1000 units get a middle pair of legs
        NA_PLINTH_MIN_HEIGHT_MM       = 20.0
        NA_RAIL_DIAMETER_MM           = 25.0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Config Readers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read a Number, Falling Back to the Default, Clamped
        # ------------------------------------------------------------
        def self.na_number(cfg, key, min, max)
            value = na_to_float(cfg["#{Defaults::NA_CONFIG_KEY_PREFIX}#{key}"])
            value = na_to_float(Defaults.na_default_of(key)) if value.nil?
            value = min.to_f if value.nil?
            [[value, min.to_f].max, max.to_f].min
        end
        private_class_method :na_number
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Float From Anything, Nil When Unreadable or Blank
        # ------------------------------------------------------------
        def self.na_to_float(raw)
            return nil if raw.nil? || raw == true || raw == false
            return nil if raw.is_a?(String) && raw.strip.empty?
            value = Float(raw)
            value.finite? ? value : nil
        rescue ArgumentError, TypeError
            nil
        end
        private_class_method :na_to_float
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read One of a Set of Strings, Falling Back to the Default
        # ------------------------------------------------------------
        def self.na_choice(cfg, key, allowed)
            raw = cfg["#{Defaults::NA_CONFIG_KEY_PREFIX}#{key}"]
            return raw.to_s if !raw.nil? && allowed.include?(raw.to_s)
            fallback = Defaults.na_default_of(key).to_s
            allowed.include?(fallback) ? fallback : allowed.first
        end
        private_class_method :na_choice
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read a Boolean (Anything But false Is On), With Default
        # ------------------------------------------------------------
        def self.na_flag(cfg, key)
            raw = cfg["#{Defaults::NA_CONFIG_KEY_PREFIX}#{key}"]
            return Defaults.na_default_of(key) != false if raw.nil?
            raw != false && raw != "false"
        end
        private_class_method :na_flag
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Read a Free Text Value, With Default
        # ------------------------------------------------------------
        def self.na_text(cfg, key)
            raw = cfg["#{Defaults::NA_CONFIG_KEY_PREFIX}#{key}"]
            return Defaults.na_default_of(key).to_s if raw.nil? || raw.to_s.strip.empty?
            raw.to_s.strip
        end
        private_class_method :na_text
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Every Value the Layout Uses, Defaulted and Clamped
        # ------------------------------------------------------------
        # @param cfg [Hash] A Na__CabinetConfiguration block (string keys)
        # @return [Hash] Plain values in mm (symbol keys), plus the options
        def self.na_effective(cfg)
            cfg     = {} unless cfg.is_a?(Hash)
            type    = na_choice(cfg, "UnitType", ["Base", "Wall", "Tower"])
            is_base = (type == "Base")
            is_wall = (type == "Wall")

            height = is_wall ? na_number(cfg, "WallHeight_mm", 100, 3500) :
                     (is_base ? na_number(cfg, "BaseHeight_mm", 100, 3500) : na_number(cfg, "TowerHeight_mm", 100, 3500))
            depth  = is_wall ? na_number(cfg, "WallDepth_mm", 100, 1200) :
                     (is_base ? na_number(cfg, "BaseDepth_mm", 100, 1200) : na_number(cfg, "TowerDepth_mm", 100, 1200))
            layout = is_wall ? na_choice(cfg, "WallFrontLayout", ["Doors", "Open"]) :
                     (is_base ? na_choice(cfg, "BaseFrontLayout", ["Doors", "DrawerDoors", "Drawers", "Open"]) :
                                na_choice(cfg, "TowerFrontLayout", ["Doors", "SplitDoors", "Open"]))
            shelves = is_wall ? na_number(cfg, "WallShelfCount", 0, 20) :
                      (is_base ? na_number(cfg, "BaseShelfCount", 0, 20) : na_number(cfg, "TowerShelfCount", 0, 20))

            {
                :type             => type,
                :width            => na_number(cfg, "Width_mm", 50, 3000),
                :height           => height,
                :depth            => depth,
                :z_base           => is_wall ? na_number(cfg, "WallMountHeight_mm", 0, 4000) : na_number(cfg, "PlinthHeight_mm", 0, 400),
                :board            => na_number(cfg, "BoardThickness_mm", 6, 50),
                :back             => na_number(cfg, "BackPanelThickness_mm", 0, 40),
                :back_inset       => [na_number(cfg, "BackPanelInset_mm", 0, 200), depth / 2.0].min,
                :top_construction => is_base ? na_choice(cfg, "BaseTopConstruction", ["Rails", "TopPanel"]) : "TopPanel",
                :rail_depth       => na_number(cfg, "TopRailDepth_mm", 20, 400),
                :layout           => layout,
                :style            => na_choice(cfg, "DoorStyle", ["Flat", "Shaker", "Recessed"]),
                :door_count       => na_choice(cfg, "DoorCount", ["Auto", "1", "2"]),
                :hinge            => na_choice(cfg, "HingeSide", ["Left", "Right"]),
                :drawer_count     => na_number(cfg, "DrawerCount", 1, 8).round,
                :drawer_layout    => na_choice(cfg, "DrawerLayout", ["Graduated", "Equal"]),
                :top_drawer       => na_number(cfg, "TopDrawerHeight_mm", 40, 600),
                :split_upper      => na_number(cfg, "SplitUpperHeight_mm", 100, 3000),
                :front_thickness  => na_number(cfg, "DoorThickness_mm", 6, 50),
                :gap              => na_number(cfg, "DoorGap_mm", 0, 20),
                :shaker_frame     => na_number(cfg, "ShakerFrameWidth_mm", 10, 300),
                :shaker_recess    => na_number(cfg, "ShakerPanelRecess_mm", 1, 30),
                :groove_width     => na_number(cfg, "GrooveWidth_mm", 4, 80),
                :groove_depth     => na_number(cfg, "GrooveDepth_mm", 2, 40),
                :groove_offset    => na_number(cfg, "GrooveOffset_mm", 0, 200),
                :shelves          => shelves.round,
                :tower_interior   => (type == "Tower") ? na_choice(cfg, "TowerInterior", ["Shelves", "Hanging"]) : "Shelves",
                :hat_shelf_drop   => na_number(cfg, "HatShelfDrop_mm", 0, 1500),
                :rail_drop        => na_number(cfg, "RailDropBelowShelf_mm", 0, 500),
                :shelf_setback    => na_number(cfg, "ShelfSetback_mm", 0, 300),
                :plinth_enabled   => na_flag(cfg, "PlinthEnabled"),
                :plinth_setback   => na_number(cfg, "PlinthSetback_mm", 0, 400),
                :plinth_thickness => na_number(cfg, "PlinthThickness_mm", 3, 60),
                :legs_enabled     => na_flag(cfg, "LegsEnabled"),
                :leg_side_inset   => na_number(cfg, "LegSideInset_mm", 0, 500),
                :leg_back_inset   => na_number(cfg, "LegBackInset_mm", 0, 500),
                :leg_key          => na_text(cfg, "LegAssetKey"),
                :handle_key       => na_text(cfg, "HandleAssetKey"),
                :handle_direction => na_choice(cfg, "HandleOrientation", ["Auto", "Vertical", "Horizontal"]),
                :handle_edge_inset=> na_number(cfg, "HandleEdgeInset_mm", 0, 500),
                :handle_end_inset => na_number(cfg, "HandleEndInset_mm", 0, 1000),
                :drawer_boxes     => na_flag(cfg, "DrawerBoxesEnabled")
            }
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Builders
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | One Board as an Axis-Aligned Box (mm)
        # ------------------------------------------------------------
        def self.na_box(name, role, x0, x1, y0, y1, z0, z1)
            { :name => name, :role => role, :x0 => x0, :x1 => x1, :y0 => y0, :y1 => y1, :z0 => z0, :z1 => z1 }
        end
        private_class_method :na_box
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Does a Box Have Real Volume
        # ------------------------------------------------------------
        def self.na_box_ok?(box)
            (box[:x1] - box[:x0]) > 0.01 && (box[:y1] - box[:y0]) > 0.01 && (box[:z1] - box[:z0]) > 0.01
        end
        private_class_method :na_box_ok?
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Spread n Shelves Evenly Through a Height Range
        # ------------------------------------------------------------
        # Bottom face of each shelf, lowest first. Drops shelves until each
        # opening is at least NA_SHELF_MIN_GAP_MM tall.
        def self.na_shelf_levels(z_bottom, z_top, count, thickness)
            n = [count, 0].max
            n -= 1 while n > 0 && ((z_top - z_bottom) - n * thickness) / (n + 1) < NA_SHELF_MIN_GAP_MM
            gap = ((z_top - z_bottom) - n * thickness) / (n + 1)
            (1..n).map { |k| z_bottom + k * gap + (k - 1) * thickness }
        end
        private_class_method :na_shelf_levels
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Two-Digit Part Number
        # ------------------------------------------------------------
        def self.na_pad(index)
            format("%02d", index)
        end
        private_class_method :na_pad
        # ---------------------------------------------------------------

        # FUNCTION | Is the Chosen Handle a Knob (Placed by Its Centre)
        # ------------------------------------------------------------
        def self.na_knob?(handle_key)
            !!(handle_key.to_s =~ /__Knob__/i)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Carcass
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Sides, Base, Top (Rails or Panel) and Back
        # ------------------------------------------------------------
        # The back panel is set in 20 from the sides' back edges: the scribe,
        # planed to an uneven wall, with a void behind the back for pipes and
        # the wall unit hanging rail. The base, top and shelves stop at it.
        def self.na_build_carcass(v, layout)
            t   = v[:board]
            w   = v[:width]
            d   = v[:depth]
            z0  = v[:z_base]
            z1  = v[:z_base] + v[:height]
            ybp = layout[:y_back_panel_front]
            parts = layout[:parts]

            parts << na_box("SidePanel__Left",  "side", 0.0,   t, -d, 0.0, z0, z1)
            parts << na_box("SidePanel__Right", "side", w - t, w, -d, 0.0, z0, z1)
            parts << na_box("BasePanel",        "base", t, w - t, -d, ybp, z0, z0 + t)

            rails_fit = (ybp + d) >= (2 * v[:rail_depth] + 10)
            if v[:top_construction] == "Rails" && rails_fit
                parts << na_box("TopRail__Front", "rail", t, w - t, -d, -d + v[:rail_depth], z1 - t, z1)
                parts << na_box("TopRail__Rear",  "rail", t, w - t, ybp - v[:rail_depth], ybp, z1 - t, z1)
            else
                layout[:warnings] << "The carcass is too shallow for two top rails, so it has a top panel." if v[:top_construction] == "Rails"
                parts << na_box("TopPanel", "top", t, w - t, -d, ybp, z1 - t, z1)
            end

            if v[:back] > 0
                parts << na_box("BackPanel", "back", t, w - t, -(v[:back_inset] + v[:back]), -v[:back_inset], z0, z1)
            end
        end
        private_class_method :na_build_carcass
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Fronts
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | How Many Doors Across
        # ------------------------------------------------------------
        def self.na_doors_across(v, layout)
            count = (v[:door_count] == "Auto") ? (v[:width] > NA_AUTO_PAIR_OVER_MM ? 2 : 1) : v[:door_count].to_i
            if count == 2 && (v[:width] / 2.0 - v[:gap]) < NA_MIN_DOOR_WIDTH_MM
                layout[:warnings] << "Too narrow for a pair of doors, so it has one."
                count = 1
            end
            count
        end
        private_class_method :na_doors_across
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Front Heights for a Drawer Pack (Top Drawer First)
        # ------------------------------------------------------------
        def self.na_drawer_heights(v, layout)
            n     = v[:drawer_count]
            total = v[:height] - n * v[:gap]
            return [total] if n == 1
            if v[:drawer_layout] == "Graduated"
                top  = [v[:top_drawer], total - (n - 1) * NA_MIN_FRONT_HEIGHT_MM].min
                rest = (total - top) / (n - 1)
                return [top] + Array.new(n - 1, rest) if rest >= top
                layout[:warnings] << "The lower drawers would be shallower than the top one, so all #{n} are equal."
            end
            Array.new(n, total / n)
        end
        private_class_method :na_drawer_heights
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Which Edge a Recessed Handle Groove Runs Along
        # ------------------------------------------------------------
        def self.na_groove_edge(v, kind, row, hinge)
            return "top"    if kind == "drawer"
            return "bottom" if v[:type] == "Wall"
            if v[:type] == "Tower"
                return "bottom" if row == "upper"
                return "top"    if row == "lower"
                return hinge == "Right" ? "left" : "right"
            end
            "top"
        end
        private_class_method :na_groove_edge
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Shaker Frame for One Front (Nil When Too Small)
        # ------------------------------------------------------------
        def self.na_shaker_frame(v, w, h)
            stile = [v[:shaker_frame], (w - NA_SHAKER_MIN_PANEL_MM) / 2.0].min
            rail  = [v[:shaker_frame], (h - NA_SHAKER_MIN_PANEL_MM) / 2.0].min
            return nil if stile < NA_SHAKER_MIN_FRAME_MM || rail < NA_SHAKER_MIN_FRAME_MM
            { :stile => stile, :rail => rail, :recess => [v[:shaker_recess], v[:front_thickness] - 4].min }
        end
        private_class_method :na_shaker_frame
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Handle Groove for One Front (Nil When It Will Not Fit)
        # ------------------------------------------------------------
        def self.na_groove(v, edge, w, h)
            span  = (edge == "left" || edge == "right") ? w : h
            depth = [v[:groove_depth], v[:front_thickness] - NA_GROOVE_MIN_BACK_MM].min
            width = [v[:groove_width], 2 * depth].min
            return nil if depth <= 0 || span < v[:groove_offset] + width + NA_GROOVE_MIN_LAND_MM
            { :edge => edge, :offset => v[:groove_offset], :width => width, :depth => depth }
        end
        private_class_method :na_groove
        # ---------------------------------------------------------------

        # SUB FUNCTION | Describe One Front and Its Handle
        # ------------------------------------------------------------
        def self.na_add_front(v, layout, name, kind, row, hinge, x0, x1, z0, z1)
            w = x1 - x0
            h = z1 - z0
            return if w < 1 || h < 1
            layout[:warnings] << "#{name.gsub('__', ' ')} is only #{h.round}mm tall." if h < NA_MIN_FRONT_HEIGHT_MM

            front = {
                :name   => name,
                :kind   => kind,
                :row    => row,
                :hinge  => hinge,
                :x0     => x0, :x1 => x1,
                :y0     => -(v[:depth] + v[:front_thickness]), :y1 => -v[:depth],
                :z0     => z0, :z1 => z1,
                :style  => v[:style],
                :shaker => nil,
                :groove => nil
            }
            front[:shaker] = na_shaker_frame(v, w, h) if v[:style] == "Shaker"
            front[:groove] = na_groove(v, na_groove_edge(v, kind, row, hinge), w, h) if v[:style] == "Recessed"
            layout[:warnings] << "#{name.gsub('__', ' ')} is too small for a handle groove." if v[:style] == "Recessed" && front[:groove].nil?
            layout[:fronts] << front

            na_add_handle(v, layout, front) unless v[:style] == "Recessed"
        end
        private_class_method :na_add_front
        # ---------------------------------------------------------------

        # SUB FUNCTION | Anchor the Handle on One Front
        # ------------------------------------------------------------
        def self.na_add_handle(v, layout, front)
            key = v[:handle_key]
            return if key.empty? || key == Defaults::NA_NO_HANDLE_KEY
            knob     = na_knob?(key)
            vertical = (v[:handle_direction] == "Auto") ? (front[:kind] == "door") : (v[:handle_direction] == "Vertical")
            handle   = { :front => front[:name], :orientation => vertical ? "vertical" : "horizontal",
                         :x => 0.0, :z => 0.0, :anchor => "centre", :y => front[:y0] }

            if front[:kind] == "drawer"
                handle[:x] = (front[:x0] + front[:x1]) / 2.0
                handle[:z] = vertical ? (front[:z0] + front[:z1]) / 2.0 : na_drawer_handle_z(v, front)
                layout[:handles] << handle
                return
            end

            open_right = front[:hinge] != "Right"
            near_top   = (v[:type] == "Base") || front[:row] == "lower"
            near_base  = (v[:type] == "Wall") || front[:row] == "upper"

            if vertical || knob
                handle[:x] = open_right ? front[:x1] - v[:handle_edge_inset] : front[:x0] + v[:handle_edge_inset]
                if near_top
                    handle[:z]      = front[:z1] - v[:handle_end_inset]
                    handle[:anchor] = knob ? "centre" : "top"
                elsif near_base
                    handle[:z]      = front[:z0] + v[:handle_end_inset]
                    handle[:anchor] = knob ? "centre" : "bottom"
                else
                    low  = front[:z0] + v[:handle_end_inset] + NA_TALL_HANDLE_HALF_MM
                    high = front[:z1] - v[:handle_end_inset] - NA_TALL_HANDLE_HALF_MM
                    handle[:z] = (low > high) ? (front[:z0] + front[:z1]) / 2.0 : [high, [low, NA_TALL_HANDLE_HEIGHT_MM].max].min
                end
            else
                handle[:x]      = open_right ? front[:x1] - v[:handle_edge_inset] : front[:x0] + v[:handle_edge_inset]
                handle[:anchor] = open_right ? "right" : "left"
                handle[:z]      = if near_base
                                      front[:z0] + v[:handle_end_inset]
                                  elsif near_top
                                      front[:z1] - v[:handle_end_inset]
                                  else
                                      [front[:z1] - v[:handle_end_inset], [front[:z0] + v[:handle_end_inset], NA_TALL_HANDLE_HEIGHT_MM].max].min
                                  end
            end
            layout[:handles] << handle
        end
        private_class_method :na_add_handle
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Height of a Horizontal Drawer Handle
        # ------------------------------------------------------------
        # A shaker front with its full frame carries the handle on its top rail,
        # clear of the panel joint. A slim front (rails cut down to fit) and the
        # other styles centre it, at most 70 below the top on a deep front.
        def self.na_drawer_handle_z(v, front)
            shaker = front[:shaker]
            return front[:z1] - shaker[:rail] / 2.0 if shaker && shaker[:rail] >= v[:shaker_frame] - 1e-6
            front[:z1] - [(front[:z1] - front[:z0]) / 2.0, NA_DRAWER_HANDLE_DROP_MM].min
        end
        private_class_method :na_drawer_handle_z
        # ---------------------------------------------------------------

        # SUB FUNCTION | One Row of Doors Across the Unit
        # ------------------------------------------------------------
        def self.na_add_door_row(v, layout, row, count, z0, z1)
            w     = v[:width]
            g     = v[:gap]
            label = (row == "upper") ? "__Upper" : ((row == "lower") ? "__Lower" : "")
            count.times do |j|
                hinge = (count == 1) ? v[:hinge] : (j.zero? ? "Left" : "Right")
                side  = (count == 1) ? "" : (j.zero? ? "__Left" : "__Right")
                na_add_front(v, layout, "Door#{label}#{side}", "door", row, hinge,
                             j * w / count + g / 2.0, (j + 1) * w / count - g / 2.0, z0, z1)
            end
        end
        private_class_method :na_add_door_row
        # ---------------------------------------------------------------

        # SUB FUNCTION | Every Front for the Chosen Layout
        # ------------------------------------------------------------
        def self.na_build_fronts(v, layout)
            g     = v[:gap]
            z_low = v[:z_base]
            z_top = v[:z_base] + v[:height]
            w     = v[:width]

            case v[:layout]
            when "Open"
                nil
            when "Doors"
                na_add_door_row(v, layout, "full", na_doors_across(v, layout), z_low + g / 2.0, z_top - g / 2.0)
            when "SplitDoors"
                split = [v[:split_upper], v[:height] - 100].min
                count = na_doors_across(v, layout)
                na_add_door_row(v, layout, "upper", count, z_top - split + g / 2.0, z_top - g / 2.0)
                na_add_door_row(v, layout, "lower", count, z_low + g / 2.0, z_top - split - g / 2.0)
            when "DrawerDoors"
                drawer = [v[:top_drawer], v[:height] - 2 * g - 100].min
                na_add_front(v, layout, "DrawerFront__01", "drawer", "top", nil, g / 2.0, w - g / 2.0, z_top - g / 2.0 - drawer, z_top - g / 2.0)
                na_add_door_row(v, layout, "lower", na_doors_across(v, layout), z_low + g / 2.0, z_top - 1.5 * g - drawer)
            else
                cursor = z_top - g / 2.0
                na_drawer_heights(v, layout).each_with_index do |height, index|
                    na_add_front(v, layout, "DrawerFront__#{na_pad(index + 1)}", "drawer", "drawer", nil, g / 2.0, w - g / 2.0, cursor - height, cursor)
                    cursor -= height + g
                end
            end
        end
        private_class_method :na_build_fronts
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Interior
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Shelves (Adjustable, Fixed Split Shelf, Wardrobe Top Shelf)
        # ------------------------------------------------------------
        def self.na_build_shelves(v, layout)
            t       = v[:board]
            w       = v[:width]
            d       = v[:depth]
            ybp     = layout[:y_back_panel_front]
            z_in0   = v[:z_base] + t
            z_in1   = v[:z_base] + v[:height] - t
            y_front = -d + [v[:shelf_setback], (ybp + d) - 50].min
            parts   = layout[:parts]

            shelf  = lambda { |name, role, z, front| parts << na_box(name, role, t, w - t, front, ybp, z, z + t) }
            spread = lambda do |z_bottom, z_top, count, first|
                levels = na_shelf_levels(z_bottom, z_top, count, t)
                levels.each_with_index { |z, index| shelf.call("Shelf__#{na_pad(first + index)}", "shelf", z, y_front) }
                levels.length
            end

            return if v[:layout] == "Drawers"

            zones = [[z_in0, z_in1]]
            if v[:layout] == "DrawerDoors"
                drawer = layout[:fronts].find { |front| front[:kind] == "drawer" }
                zones  = [[z_in0, drawer ? drawer[:z0] - v[:gap] / 2.0 - t : z_in1]]
            end
            if v[:type] == "Tower" && v[:layout] == "SplitDoors"
                split = v[:z_base] + v[:height] - [v[:split_upper], v[:height] - 100].min
                shelf.call("FixedShelf", "fixedShelf", split - t / 2.0, -d)
                zones = [[z_in0, split - t / 2.0], [split + t / 2.0, z_in1]]
            end

            if v[:type] == "Tower" && v[:tower_interior] == "Hanging"
                top = z_in1 - v[:hat_shelf_drop]
                if top - t > z_in0 + 100
                    shelf.call("HatShelf", "hatShelf", top - t, y_front)
                    rail_z = top - t - v[:rail_drop] - NA_RAIL_DIAMETER_MM / 2.0
                    if rail_z - NA_RAIL_DIAMETER_MM / 2.0 > z_in0
                        layout[:rail] = { :name => "HangingRail", :x0 => t, :x1 => w - t, :y => (-d + ybp) / 2.0,
                                          :z => rail_z, :diameter => NA_RAIL_DIAMETER_MM }
                    end
                else
                    layout[:warnings] << "The unit is too short for a wardrobe top shelf and rail."
                end
                return
            end

            if zones.length == 1
                spread.call(zones[0][0], zones[0][1], v[:shelves], 1)
                return
            end
            lower = zones[0][1] - zones[0][0]
            upper = zones[1][1] - zones[1][0]
            n_up  = (v[:shelves] * upper / [1.0, lower + upper].max).round
            done  = spread.call(zones[0][0], zones[0][1], v[:shelves] - n_up, 1)
            spread.call(zones[1][0], zones[1][1], n_up, 1 + done)
        end
        private_class_method :na_build_shelves
        # ---------------------------------------------------------------

        # SUB FUNCTION | A Drawer Box Behind Every Drawer Front
        # ------------------------------------------------------------
        def self.na_build_drawer_boxes(v, layout)
            return unless v[:drawer_boxes] && v[:type] == "Base"
            t      = v[:board]
            s      = NA_DRAWER_SIDE_MM
            z_in0  = v[:z_base] + t
            z_in1  = v[:z_base] + v[:height] - t
            bx0    = t + NA_RUNNER_CLEARANCE_MM
            bx1    = v[:width] - t - NA_RUNNER_CLEARANCE_MM
            inside = layout[:y_back_panel_front] + v[:depth]
            length = ((inside - NA_DRAWER_REAR_CLEAR_MM) / NA_DRAWER_LENGTH_STEP_MM).floor * NA_DRAWER_LENGTH_STEP_MM
            return if bx1 - bx0 < NA_DRAWER_MIN_WIDTH_MM || length < NA_DRAWER_LENGTH_STEP_MM

            y0 = -v[:depth]
            y1 = y0 + length
            layout[:fronts].select { |front| front[:kind] == "drawer" }.each_with_index do |front, index|
                z0  = [front[:z0] + NA_DRAWER_ABOVE_FRONT_BASE_MM, z_in0 + NA_DRAWER_CARCASS_CLEAR_MM].max
                top = [front[:z1] - NA_DRAWER_BELOW_FRONT_TOP_MM, z_in1 - NA_DRAWER_CARCASS_CLEAR_MM].min
                next if top - z0 < NA_MIN_FRONT_HEIGHT_MM
                base = "DrawerBox__#{na_pad(index + 1)}"
                layout[:drawer_boxes] << {
                    :name  => base,
                    :parts => [
                        na_box("#{base}__Side__Left",  "drawerSide",  bx0, bx0 + s, y0, y1, z0, top),
                        na_box("#{base}__Side__Right", "drawerSide",  bx1 - s, bx1, y0, y1, z0, top),
                        na_box("#{base}__Front",       "drawerFront", bx0 + s, bx1 - s, y0, y0 + s, z0, top),
                        na_box("#{base}__Back",        "drawerBack",  bx0 + s, bx1 - s, y1 - s, y1, z0, top),
                        na_box("#{base}__Base",        "drawerBase",  bx0 + s, bx1 - s, y0 + s, y1 - s, z0, z0 + NA_DRAWER_BASE_MM)
                    ]
                }
            end
        end
        private_class_method :na_build_drawer_boxes
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plinth and Legs
# -----------------------------------------------------------------------------

        # SUB FUNCTION | Plinth Board and Leg Points (Floor Standing Units Only)
        # ------------------------------------------------------------
        def self.na_build_plinth_and_legs(v, layout)
            return if v[:type] == "Wall" || v[:z_base] <= 0
            w = v[:width]
            d = v[:depth]

            setback    = [0.0, [v[:plinth_setback], d / 2.0 - v[:plinth_thickness]].min].max
            has_plinth = v[:plinth_enabled] && v[:z_base] >= NA_PLINTH_MIN_HEIGHT_MM
            if has_plinth
                layout[:plinth] = na_box("Plinth", "plinth", 0.0, w, -d + setback, -d + setback + v[:plinth_thickness], 0.0, v[:z_base])
            end

            return unless v[:legs_enabled]
            if v[:z_base] < NA_LEG_MIN_HEIGHT_MM
                layout[:warnings] << "Legs need a plinth height of at least #{NA_LEG_MIN_HEIGHT_MM.round}mm."
                return
            end

            xs = (w < 2 * v[:leg_side_inset] + NA_LEG_MIN_ROW_GAP_MM) ? [w / 2.0] : [v[:leg_side_inset], w - v[:leg_side_inset]]
            xs = [xs[0], w / 2.0, xs[1]] if xs.length == 2 && w > NA_MIDDLE_LEGS_OVER_MM

            y_front = has_plinth ? (-d + setback + v[:plinth_thickness] + NA_LEG_BEHIND_PLINTH_MM) : (-d + v[:leg_back_inset])
            y_back  = -[v[:leg_back_inset], v[:back_inset] + v[:back] + NA_LEG_BEHIND_BACK_MM].max
            ys      = (y_back - y_front >= NA_LEG_MIN_ROW_GAP_MM) ? [y_front, y_back] : [(y_front + y_back) / 2.0]

            layout[:leg_height] = v[:z_base]
            ys.each { |y| xs.each { |x| layout[:legs] << { :x => x, :y => y } } }
        end
        private_class_method :na_build_plinth_and_legs
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve a Configuration Into Its Parts
        # ------------------------------------------------------------
        # @param cfg [Hash] Na__CabinetConfiguration block (string keys)
        # @return [Hash] { :values, :parts, :fronts, :handles, :drawer_boxes,
        #                  :rail, :plinth, :legs, :leg_height, :bounds, :warnings }
        def self.na_resolve(cfg)
            v = na_effective(cfg)
            layout = {
                :values             => v,
                :y_back_panel_front => -(v[:back_inset] + v[:back]),
                :parts              => [],
                :fronts             => [],
                :handles            => [],
                :drawer_boxes       => [],
                :rail               => nil,
                :plinth             => nil,
                :legs               => [],
                :leg_height         => 0.0,
                :warnings           => []
            }

            na_build_carcass(v, layout)
            na_build_fronts(v, layout)
            na_build_shelves(v, layout)
            na_build_drawer_boxes(v, layout)
            na_build_plinth_and_legs(v, layout)
            layout[:parts] = layout[:parts].select { |box| na_box_ok?(box) }

            layout[:bounds] = {
                :x0 => 0.0,
                :x1 => v[:width],
                :y0 => -(v[:depth] + (layout[:fronts].empty? ? 0.0 : v[:front_thickness])),
                :y1 => 0.0,
                :z0 => (v[:type] == "Wall") ? v[:z_base] : 0.0,
                :z1 => v[:z_base] + v[:height]
            }
            layout
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__LayoutResolver
end # module Na__InteriorCabinetrySystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
