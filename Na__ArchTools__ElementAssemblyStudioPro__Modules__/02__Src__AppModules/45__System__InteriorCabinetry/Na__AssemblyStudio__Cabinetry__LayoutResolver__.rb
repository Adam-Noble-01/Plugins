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
        NA_APPLIANCE_SLOT_MM          = 600.0   # <-- V2.7.6: library appliances are modelled for a 600 slot (595 fascia, 560 body)
        NA_NO_APPLIANCE               = "None".freeze

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
                                na_choice(cfg, "TowerFrontLayout", ["Doors", "SplitDoors", "Housing", "Open"]))
            shelves = is_wall ? na_number(cfg, "WallShelfCount", 0, 20) :
                      (is_base ? na_number(cfg, "BaseShelfCount", 0, 20) : na_number(cfg, "TowerShelfCount", 0, 20))
            # V2.7.5: a floor unit with neither a plinth nor legs stands on the
            # floor. Before, it stood on PlinthHeight_mm whatever the two
            # switches said (SK02 R23, 18-Nov-2026: an open tall unit with both
            # off built at z 150 to 2600, 150 into the slab above). On legs
            # alone it keeps its height: the legs stand in that space.
            raised  = na_flag(cfg, "PlinthEnabled") || na_flag(cfg, "LegsEnabled")

            {
                :type             => type,
                :width            => na_number(cfg, "Width_mm", 50, 3000),
                :height           => height,
                :depth            => depth,
                :z_base           => is_wall ? na_number(cfg, "WallMountHeight_mm", 0, 4000) : (raised ? na_number(cfg, "PlinthHeight_mm", 0, 400) : 0.0),
                :board            => na_number(cfg, "BoardThickness_mm", 6, 50),
                :back             => na_number(cfg, "BackPanelThickness_mm", 0, 40),
                :back_inset       => [na_number(cfg, "BackPanelInset_mm", 0, 200), depth / 2.0].min,
                :top_construction => is_base ? na_choice(cfg, "BaseTopConstruction", ["Rails", "TopPanel"]) : "TopPanel",
                :rail_depth       => na_number(cfg, "TopRailDepth_mm", 20, 400),
                :layout           => layout,
                :style            => na_choice(cfg, "DoorStyle", ["Flat", "Shaker", "Recessed", "Handleless"]),
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
                :plinth_by_run    => [true, "true"].include?(cfg["#{Defaults::NA_CONFIG_KEY_PREFIX}PlinthByRun"]),   # <-- V2.7.6: a run's one kickboard stands in for this unit's own board (only true turns it on)
                :housing_base     => na_number(cfg, "HousingApertureBase_mm", 0, 3000),
                :housing_lower    => na_text(cfg, "HousingLowerAppliance"),
                :housing_lower_ap => na_number(cfg, "HousingLowerAperture_mm", 50, 1500),
                :housing_upper    => na_text(cfg, "HousingUpperAppliance"),
                :housing_upper_ap => na_number(cfg, "HousingUpperAperture_mm", 50, 1500),
                :housing_third    => na_text(cfg, "HousingThirdAppliance"),             # <-- V2.7.8: slots 3 and 4 up the stack
                :housing_third_ap => na_number(cfg, "HousingThirdAperture_mm", 50, 1500),
                :housing_fourth   => na_text(cfg, "HousingFourthAppliance"),
                :housing_fourth_ap=> na_number(cfg, "HousingFourthAperture_mm", 50, 1500),
                :housing_below    => na_choice(cfg, "HousingBelowFront", ["Door", "Filler"]),
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
                :drawer_boxes     => na_flag(cfg, "DrawerBoxesEnabled"),
                # V2.7.8: fronts off the carcass front, and the Handleless style
                :front_standoff   => na_number(cfg, "FrontStandoff_mm", 0, 10),
                :handle_gap       => na_number(cfg, "HandleGap_mm", 5, 80),
                :hl_groove_h      => na_number(cfg, "HandleGrooveHeight_mm", 0, 80),
                :hl_groove_d      => na_number(cfg, "HandleGrooveDepth_mm", 0, 40),
                :hl_groove_r      => na_number(cfg, "HandleGrooveFillet_mm", 0, 20),
                :wall_overhang    => na_number(cfg, "HandleWallOverhang_mm", 0, 80),
                :wall_downstand   => na_flag(cfg, "HandleWallDownstand"),
                :wall_rail_depth  => na_number(cfg, "HandleWallRailDepth_mm", 10, 200),
                :band             => na_number(cfg, "HandleBand_mm", 5, 80),
                :band_downstand   => na_flag(cfg, "HandleBandDownstand"),
                :band_downstand_h => na_number(cfg, "HandleBandDownstandHeight_mm", 10, 300)
            }
        end

        # FUNCTION | Is the Door Style Handleless (V2.7.8)
        # ------------------------------------------------------------
        def self.na_handleless?(v)
            v[:style] == "Handleless"
        end
        # ---------------------------------------------------------------
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

            # V2.7.8: a Handleless wall unit's doors run below its base; its sides
            # come down with them and a rail fills behind the doors' foot, so the
            # unit cannot be seen into and the doors are backed (Adam's
            # approved D1b, SK02, 23-Nov-2026: "there is nothing backing the
            # door at the bottom, so add these").
            drop = na_wall_downstand(v)
            parts << na_box("SidePanel__Left",  "side", 0.0,   t, -d, 0.0, z0 - drop, z1)
            parts << na_box("SidePanel__Right", "side", w - t, w, -d, 0.0, z0 - drop, z1)
            parts << na_box("BasePanel",        "base", t, w - t, -d, ybp, z0, z0 + t)
            if drop > 0
                parts << na_box("Downstand__Front", "downstand", t, w - t, -d, -d + [v[:wall_rail_depth], ybp + d].min, z0 - drop, z0)
            end

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

        # HELPER FUNCTION | How Far a Wall Unit's Sides Come Down Below Its Base (V2.7.8)
        # ------------------------------------------------------------
        # The doors' overhang, on a Handleless wall unit with doors and its
        # downstand on; else 0.
        def self.na_wall_downstand(v)
            return 0.0 unless v[:type] == "Wall" && na_handleless?(v) && v[:layout] != "Open" && v[:wall_downstand]
            v[:wall_overhang]
        end
        private_class_method :na_wall_downstand
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
            # V2.7.8 Handleless: the grip gap above every front and a half gap
            # under the lowest; otherwise half a gap top and bottom, a gap between.
            total = na_handleless?(v) ? v[:height] - n * v[:handle_gap] - v[:gap] / 2.0 : v[:height] - n * v[:gap]
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

        # HELPER FUNCTION | Which Edge a Handleless Front Is Gripped By (V2.7.8)
        # ------------------------------------------------------------
        # The bottom of a wall unit's doors (they hang below its base); the
        # top of everything else: base doors and drawers under the worktop,
        # a tall unit's doors from the gap above each.
        def self.na_handleless_edge(v)
            v[:type] == "Wall" ? "bottom" : "top"
        end
        private_class_method :na_handleless_edge
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Groove in a Handleless Front's Back (Nil When None Fits) (V2.7.8)
        # ------------------------------------------------------------
        # Routed in the BACK of the front along its grip edge: `height` from
        # that edge, `depth` into the front, a `fillet` in its inside corner
        # (Adam's approved D1, SK02, 23-Nov-2026: a 20 x 10 groove with "a
        # slight fillet"). It leaves at least NA_GROOVE_MIN_BACK_MM of front
        # and NA_GROOVE_MIN_LAND_MM below it.
        def self.na_back_groove(v, edge, h)
            depth  = [v[:hl_groove_d], v[:front_thickness] - NA_GROOVE_MIN_BACK_MM].min
            height = [v[:hl_groove_h], h - NA_GROOVE_MIN_LAND_MM].min
            return nil if depth < 1.0 || height < 1.0
            { :edge => edge, :height => height, :depth => depth, :fillet => [v[:hl_groove_r], depth, height].min }
        end
        private_class_method :na_back_groove
        # ---------------------------------------------------------------

        # SUB FUNCTION | Describe One Front and Its Handle
        # ------------------------------------------------------------
        def self.na_add_front(v, layout, name, kind, row, hinge, x0, x1, z0, z1)
            w = x1 - x0
            h = z1 - z0
            return if w < 1 || h < 1
            layout[:warnings] << "#{name.gsub('__', ' ')} is only #{h.round}mm tall." if h < NA_MIN_FRONT_HEIGHT_MM

            back  = v[:depth] + v[:front_standoff]                               # <-- V2.7.8: a hinge gap behind every front (0 before)
            front = {
                :name   => name,
                :kind   => kind,
                :row    => row,
                :hinge  => hinge,
                :x0     => x0, :x1 => x1,
                :y0     => -(back + v[:front_thickness]), :y1 => -back,
                :z0     => z0, :z1 => z1,
                :style  => v[:style],
                :shaker => nil,
                :groove => nil,
                :back_groove => nil
            }
            front[:shaker] = na_shaker_frame(v, w, h) if v[:style] == "Shaker"
            front[:groove] = na_groove(v, na_groove_edge(v, kind, row, hinge), w, h) if v[:style] == "Recessed"
            layout[:warnings] << "#{name.gsub('__', ' ')} is too small for a handle groove." if v[:style] == "Recessed" && front[:groove].nil?
            if na_handleless?(v) && v[:hl_groove_h] > 0 && v[:hl_groove_d] > 0
                front[:back_groove] = na_back_groove(v, na_handleless_edge(v), h)
                layout[:warnings] << "#{name.gsub('__', ' ')} is too small for its finger groove." if front[:back_groove].nil?
            end
            layout[:fronts] << front

            na_add_handle(v, layout, front) unless v[:style] == "Recessed" || na_handleless?(v)
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

        # HELPER FUNCTION | Is a Library Appliance Code Chosen (Not None or Blank)
        # ------------------------------------------------------------
        def self.na_appliance?(code)
            text = code.to_s.strip
            !text.empty? && text.casecmp(NA_NO_APPLIANCE) != 0
        end
        private_class_method :na_appliance?
        # ---------------------------------------------------------------

        # SUB FUNCTION | An Appliance Housing's Stack of Apertures (V2.7.6)
        # ------------------------------------------------------------
        # A tall unit with Housing fronts: a door below, the appliances'
        # apertures (the lower one first, from HousingApertureBase_mm above
        # the floor), a door above. Each aperture holds one library appliance
        # placed in the unit frame at (x offset, carcass front, aperture
        # bottom): the library items are modelled for a 600 slot, so a wider
        # unit centres them. A slot whose code is None takes no aperture.
        # @return [Hash] { :base, :top, :apertures => [{ :slot, :code, :z0, :z1 }] }
        def self.na_housing_stack(v, layout)
            z_low  = v[:z_base]
            z_top  = v[:z_base] + v[:height]
            base   = v[:housing_base]
            slots  = [["Lower", v[:housing_lower], v[:housing_lower_ap]], ["Upper", v[:housing_upper], v[:housing_upper_ap]],
                      ["Third", v[:housing_third], v[:housing_third_ap]], ["Fourth", v[:housing_fourth], v[:housing_fourth_ap]]]   # <-- V2.7.8: four slots, bottom to top
            chosen = slots.select { |slot| na_appliance?(slot[1]) }

            if base < z_low
                layout[:warnings] << "The appliances start #{(z_low - base).round}mm below the carcass, so they start on its base."
                base = z_low
            end
            cursor    = base
            apertures = chosen.map do |slot, code, height|
                aperture = { :slot => slot, :code => code.to_s.strip, :z0 => cursor, :z1 => cursor + height }
                cursor  += height
                aperture
            end
            if cursor > z_top + 0.01
                layout[:warnings] << "The appliances reach #{cursor.round}mm, #{(cursor - z_top).round}mm above the unit's top: raise the unit or lower the aperture base."
            end
            if v[:width] < NA_APPLIANCE_SLOT_MM - 0.01 && !apertures.empty?
                layout[:warnings] << "The unit is #{v[:width].round}mm wide: the library appliances need a 600 slot."
            end
            { :base => base, :top => cursor, :apertures => apertures }
        end
        private_class_method :na_housing_stack
        # ---------------------------------------------------------------

        # SUB FUNCTION | A Fixed Filler Panel in the Door Plane (V2.7.8)
        # ------------------------------------------------------------
        # A housing's front under its appliances when they start high (SK02,
        # Adam 23-Nov-2026: a filler, the warming drawer, two ovens, a door):
        # one panel across the unit in the door finish, with no handle and no
        # grip groove. On a Shaker unit it has the shaker frame, so the fronts
        # read alike.
        def self.na_add_filler(v, layout, name, x0, x1, z0, z1)
            w = x1 - x0
            h = z1 - z0
            return if w < 1 || h < 1
            back   = v[:depth] + v[:front_standoff]
            shaker = v[:style] == "Shaker"
            layout[:fronts] << { :name => name, :kind => "filler", :row => "lower", :hinge => nil,
                                 :x0 => x0, :x1 => x1, :y0 => -(back + v[:front_thickness]), :y1 => -back,
                                 :z0 => z0, :z1 => z1, :style => shaker ? "Shaker" : "Flat",
                                 :shaker => shaker ? na_shaker_frame(v, w, h) : nil, :groove => nil, :back_groove => nil }
        end
        private_class_method :na_add_filler
        # ---------------------------------------------------------------

        # HELPER FUNCTION | How Far a Housing's Band Downstand Hangs Below the Lowest Aperture (V2.7.8)
        # ------------------------------------------------------------
        # Handleless, the downstand on, an appliance in the stack and room for
        # it above the carcass base; else 0.
        def self.na_band_downstand(v, stack)
            return 0.0 unless na_handleless?(v) && v[:band_downstand] && !stack[:apertures].empty?
            return 0.0 unless stack[:base] - v[:band_downstand_h] > v[:z_base] + v[:board]
            v[:band_downstand_h]
        end
        private_class_method :na_band_downstand
        # ---------------------------------------------------------------

        # SUB FUNCTION | Fronts and Appliances of an Appliance Housing (V2.7.6)
        # ------------------------------------------------------------
        def self.na_build_housing_fronts(v, layout)
            g     = v[:gap]
            z_low = v[:z_base]
            z_top = v[:z_base] + v[:height]
            stack = na_housing_stack(v, layout)
            count = na_doors_across(v, layout)
            x_off = (v[:width] - NA_APPLIANCE_SLOT_MM) / 2.0
            hl    = na_handleless?(v)

            # V2.7.8 Handleless (Adam's approved D2, SK02, 23-Nov-2026): the door
            # below stops the band under the lowest appliance, gripped at its top;
            # the door above is gripped at its top, the grip gap under the
            # carcass top. A downstand hung under the appliance's shelf backs
            # the door below and fills the band.
            lower_top = hl && !stack[:apertures].empty? ? stack[:base] - v[:band] : stack[:base] - g / 2.0
            upper_top = hl ? z_top - v[:handle_gap] : z_top - g / 2.0
            if lower_top - (z_low + g / 2.0) >= NA_MIN_FRONT_HEIGHT_MM
                if v[:housing_below] == "Filler"                                 # <-- V2.7.8: a fixed panel, not a door (SK02's stack from 560)
                    na_add_filler(v, layout, "Filler__Lower", g / 2.0, v[:width] - g / 2.0, z_low + g / 2.0, lower_top)
                else
                    na_add_door_row(v, layout, "lower", count, z_low + g / 2.0, lower_top)
                end
            end
            if upper_top - (stack[:top] + g / 2.0) >= NA_MIN_FRONT_HEIGHT_MM
                na_add_door_row(v, layout, "upper", count, stack[:top] + g / 2.0, upper_top)
            end
            drop = na_band_downstand(v, stack)
            if drop > 0
                t = v[:board]
                layout[:parts] << na_box("Downstand__Band", "downstand", t, v[:width] - t, -v[:depth], -v[:depth] + t, stack[:base] - drop, stack[:base])
            end
            layout[:housing]    = stack
            layout[:appliances] = stack[:apertures].map do |aperture|
                aperture.merge(:name => "Appliance__#{aperture[:slot]}", :x0 => x_off, :y => -(v[:depth] + v[:front_standoff]))
            end
        end
        private_class_method :na_build_housing_fronts
        # ---------------------------------------------------------------

        # SUB FUNCTION | Every Front for the Chosen Layout
        # ------------------------------------------------------------
        def self.na_build_fronts(v, layout)
            g     = v[:gap]
            z_low = v[:z_base]
            z_top = v[:z_base] + v[:height]
            w     = v[:width]
            hl    = na_handleless?(v)
            # V2.7.8 Handleless: a front's grip edge stands the grip gap clear of
            # the carcass edge (or the front above); a wall unit's doors run the
            # overhang below its base. Every other edge keeps the half gap.
            top_edge = hl && v[:type] != "Wall" ? z_top - v[:handle_gap] : z_top - g / 2.0
            low_edge = hl && v[:type] == "Wall" ? z_low - v[:wall_overhang] : z_low + g / 2.0
            between  = hl ? v[:handle_gap] : g                                  # <-- From one front's bottom to the next front's top

            case v[:layout]
            when "Open"
                nil
            when "Housing"
                na_build_housing_fronts(v, layout)
            when "Doors"
                na_add_door_row(v, layout, "full", na_doors_across(v, layout), low_edge, top_edge)
            when "SplitDoors"
                split = [v[:split_upper], v[:height] - 100].min
                count = na_doors_across(v, layout)
                na_add_door_row(v, layout, "upper", count, z_top - split + g / 2.0, top_edge)
                na_add_door_row(v, layout, "lower", count, z_low + g / 2.0, hl ? z_top - split - v[:handle_gap] : z_top - split - g / 2.0)
            when "DrawerDoors"
                drawer = [v[:top_drawer], v[:height] - 2 * g - 100].min
                na_add_front(v, layout, "DrawerFront__01", "drawer", "top", nil, g / 2.0, w - g / 2.0, top_edge - drawer, top_edge)
                na_add_door_row(v, layout, "lower", na_doors_across(v, layout), z_low + g / 2.0, top_edge - drawer - between)
            else
                cursor = top_edge
                na_drawer_heights(v, layout).each_with_index do |height, index|
                    na_add_front(v, layout, "DrawerFront__#{na_pad(index + 1)}", "drawer", "drawer", nil, g / 2.0, w - g / 2.0, cursor - height, cursor)
                    cursor -= height + between
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

            zones        = [[z_in0, z_in1]]
            filler_below = false                                                 # <-- V2.7.8: a housing's filler drops the lower cupboard's share
            if v[:layout] == "DrawerDoors"
                drawer = layout[:fronts].find { |front| front[:kind] == "drawer" }
                zones  = [[z_in0, drawer ? drawer[:z0] - v[:gap] / 2.0 - t : z_in1]]
            end
            if v[:type] == "Tower" && v[:layout] == "SplitDoors"
                split = v[:z_base] + v[:height] - [v[:split_upper], v[:height] - 100].min
                shelf.call("FixedShelf", "fixedShelf", split - t / 2.0, -d)
                zones = [[z_in0, split - t / 2.0], [split + t / 2.0, z_in1]]
            end
            # V2.7.6: an appliance housing has a fixed shelf under each
            # aperture (the appliance's body stands on it, its fascia covers
            # the edge) and one over the stack; the two cupboards share the
            # shelves as Split Doors does.
            if v[:type] == "Tower" && v[:layout] == "Housing" && layout[:housing]
                stack = layout[:housing]
                if stack[:apertures].empty?
                    zones = [[z_in0, stack[:base] - t / 2.0], [stack[:base] + t / 2.0, z_in1]]
                    shelf.call("FixedShelf", "fixedShelf", stack[:base] - t / 2.0, -d) if stack[:base] - t / 2.0 > z_in0 && stack[:base] + t / 2.0 < z_in1
                else
                    stack[:apertures].each do |aperture|
                        next unless aperture[:z0] > z_in0 - 0.01 && aperture[:z0] + t < z_in1 + 0.01
                        shelf.call("ApplianceShelf__#{aperture[:slot]}", "fixedShelf", aperture[:z0], -d)
                    end
                    shelf.call("ApplianceShelf__Top", "fixedShelf", stack[:top] - t, -d) if stack[:top] - t > z_in0 && stack[:top] < z_in1 + 0.01
                    zones = [[z_in0, stack[:base] - na_band_downstand(v, stack)], [stack[:top], z_in1]]   # <-- V2.7.8: shelves stay under the band downstand
                    filler_below = v[:housing_below] == "Filler"                         # <-- V2.7.8: behind a filler is no cupboard
                end
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
            done  = filler_below ? 0 : spread.call(zones[0][0], zones[0][1], v[:shelves] - n_up, 1)   # <-- V2.7.8: the top cupboard keeps its usual share
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
            # V2.7.6: in a run with JoinPlinths the run builds ONE kickboard
            # along the units; the unit keeps its raise and its legs, and the
            # legs stand behind where its own board would have been.
            plinth_line = has_plinth
            has_plinth  = false if v[:plinth_by_run]
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

            y_front = plinth_line ? (-d + setback + v[:plinth_thickness] + NA_LEG_BEHIND_PLINTH_MM) : (-d + v[:leg_back_inset])
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
        #                  :rail, :plinth, :legs, :leg_height, :bounds, :warnings,
        #                  :appliances, :housing }
        #   V2.7.6: :appliances lists a housing's library appliances
        #   ({ :name, :slot, :code, :x0, :y, :z0, :z1 }: the item's origin is
        #   (x0, y, z0) in the unit frame); :housing is its stack or nil.
        def self.na_resolve(cfg)
            v = na_effective(cfg)
            layout = {
                :values             => v,
                :y_back_panel_front => -(v[:back_inset] + v[:back]),
                :parts              => [],
                :fronts             => [],
                :handles            => [],
                :drawer_boxes       => [],
                :appliances         => [],
                :housing            => nil,
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

            low = ([v[:z_base]] + layout[:fronts].map { |front| front[:z0] } + layout[:parts].map { |part| part[:z0] }).min   # <-- V2.7.8: a wall unit's doors and downstand run below its base
            layout[:bounds] = {
                :x0 => 0.0,
                :x1 => v[:width],
                :y0 => -(v[:depth] + (layout[:fronts].empty? ? 0.0 : v[:front_standoff] + v[:front_thickness])),
                :y1 => 0.0,
                :z0 => (v[:type] == "Wall") ? low : 0.0,
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
