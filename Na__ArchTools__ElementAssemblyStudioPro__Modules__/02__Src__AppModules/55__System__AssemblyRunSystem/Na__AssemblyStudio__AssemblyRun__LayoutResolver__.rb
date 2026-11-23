# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - LAYOUT RESOLVER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__LayoutResolver__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__LayoutResolver
# AUTHOR     : Noble Architecture
# PURPOSE    : Turns a run's configuration into the exact place of every span,
#              column, post and corner along its path. The builders draw only
#              what this returns; the dialog's previews and the MCP's dry run
#              show the same result.
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# ONE RESOLVER, NO JAVASCRIPT TWIN
# - The other tabs keep a JS copy of their layout rules for the preview and a
#   spec to catch the two drifting apart. A run's layout is resolved here only:
#   the dialog sends its configuration and draws the layout sent back
#   (Na__DialogRouter.na_send_layout). There is nothing to keep in step.
#
# WHAT IT WORKS OUT, IN ORDER
#   1. The settings, each checked against its limits (refused, never clamped).
#   2. The panel types: code, product, width, height.
#   3. The legs of the path and the corner at each vertex: which way it turns,
#      whether that is towards the side the elements stand on, what stands in
#      it, and how far each leg stops short of it (the setback).
#   4. Each leg's sequence: its own Items, or its Fill rule expanded; a joint
#      column between spans that follow each other; end columns; and, with
#      Fuse Framework on, the mullions and jambs.
#   5. Widths: columns and posts are fixed; a span takes its panel type's
#      width, or an equal share of what the leg has left.
#   6. Each panel type's one width, checked across every leg it is used on.
#   7. Frames (V2.7.3): where one cill and one window board run (stretches,
#      Na__RunCills), what stands on the cill, and what each panel type
#      gives up to the run: its cill and board (:cill_joined,
#      :board_joined) and, fused, its whole frame (:frameless).
#   8. Cabinets (V2.7.4): where one worktop runs over the base and drawer
#      units (Na__RunCills.na_worktop_stretches). Its depth and height are
#      the units' own, so the builder sizes it once the elements exist.
#
# THE LEG FRAME (millimetres, the run's own plan)
#   s : along the leg from its first point. +y (left of the leg) is the side
#       an element's own +Y lies on. Frames stand on the left (the building
#       side); cabinets on the right (the room side). See Na__Defaults.
#
# PURE RUBY: no Sketchup or Geom calls, so the offline suite can run it.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'
require_relative 'Na__AssemblyStudio__AssemblyRun__RunCills__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem
    module Na__LayoutResolver

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        Defaults = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        PathMath = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath
        RunCills = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunCills

        NA_SPAN   = Defaults::NA_ITEM_SPAN
        NA_COLUMN = Defaults::NA_ITEM_COLUMN
        NA_POST   = "Post".freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Config Readers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | A Setting, or Its Default When Absent
        # ------------------------------------------------------------
        def self.na_get(config, short)
            key = Defaults.na_key(short)
            config.key?(key) && !config[key].nil? ? config[key] : Defaults::NA_DEFAULT_RUN_CONFIGURATION[key]
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Number Inside Its Limits (an Error When Outside)
        # ------------------------------------------------------------
        def self.na_number(config, short, errors)
            raw   = na_get(config, short)
            value = na_to_float(raw)
            if value.nil?
                errors << "#{short} must be a number, not #{raw.inspect}."
                return na_to_float(Defaults::NA_DEFAULT_RUN_CONFIGURATION[Defaults.na_key(short)]) || 0.0
            end
            low, high = Defaults::NA_LIMITS[short]
            errors << "#{short} is #{na_trim(value)}; it must be between #{na_trim(low)} and #{na_trim(high)}." if low && (value < low || value > high)
            value
        end
        private_class_method :na_number
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Value as a Float (Nil When It Is No Number)
        # ------------------------------------------------------------
        def self.na_to_float(raw)
            return raw.to_f if raw.is_a?(Numeric)
            return nil unless raw.is_a?(String) && raw.strip.match?(/\A-?\d+(\.\d+)?\z/)
            raw.strip.to_f
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | One of a Set of Options (an Error When It Is Not)
        # ------------------------------------------------------------
        def self.na_choice(config, short, allowed, errors)
            value = na_get(config, short).to_s
            return value if allowed.include?(value)
            errors << "#{short} is '#{value}'; it must be one of #{allowed.join(', ')}."
            allowed.first
        end
        private_class_method :na_choice
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Number Without a Trailing .0
        # ------------------------------------------------------------
        def self.na_trim(value)
            number = value.to_f.round(1)
            number == number.round ? number.round.to_s : number.to_s
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Settings
# -----------------------------------------------------------------------------

        # FUNCTION | Every Run-Level Setting, Checked
        # ------------------------------------------------------------
        # @return [Hash] symbol-keyed values in mm
        def self.na_settings(config, errors)
            mode   = Defaults::NA_MODES.include?(na_get(config, "Mode").to_s) ? na_get(config, "Mode").to_s : nil
            errors << "Mode is '#{na_get(config, 'Mode')}'; it must be #{Defaults::NA_MODES.join(' or ')}." unless mode
            mode ||= Defaults::NA_MODE_FRAMES
            frames = (mode == Defaults::NA_MODE_FRAMES)
            fuse   = frames && na_get(config, "FuseFramework") == true
            {
                :mode            => mode,
                :frames          => frames,
                :band_left       => frames,                                      # <-- Frames stand left of the path, cabinets right
                :height          => na_number(config, "Height_mm", errors),
                :fuse            => fuse,
                :join_cills      => frames && (fuse || na_get(config, "JoinCills") == true),   # <-- A fused framework always sits on one cill
                :cill_height     => na_number(config, "CillHeight_mm", errors),
                :cill_projection => na_number(config, "CillProjection_mm", errors),
                :mullion         => na_number(config, "MullionWidth_mm", errors),
                :jamb            => na_number(config, "JambWidth_mm", errors),
                :post_depth      => na_number(config, "PostDepth_mm", errors),
                :post_inset      => na_number(config, "PostInset_mm", errors),
                :joint           => na_choice(config, "JointColumn", Defaults::NA_COLUMN_KINDS_BY_MODE[mode], errors),
                :joint_width     => na_number(config, "JointWidth_mm", errors),
                :end_column      => na_choice(config, "EndColumn", Defaults::NA_COLUMN_KINDS_BY_MODE[mode], errors),
                :end_width       => na_number(config, "EndWidth_mm", errors),
                :corner          => na_choice(config, "CornerColumn", Defaults::NA_CORNER_KINDS_BY_MODE[mode], errors),
                :corner_post     => na_number(config, "CornerPostSize_mm", errors),
                :unit_depth      => na_number(config, "UnitDepth_mm", errors),
                :front_allowance => na_number(config, "FrontAllowance_mm", errors),
                :corner_unit_leg => na_number(config, "CornerUnitLeg_mm", errors),
                :filler_height   => na_number(config, "FillerHeight_mm", errors),
                :worktop           => !frames && na_get(config, "Worktop") == true,   # <-- Cabinets only (V2.7.4)
                :worktop_thickness => na_number(config, "WorktopThickness_mm", errors),
                :worktop_overhang  => na_number(config, "WorktopOverhang_mm", errors),
                :worktop_back      => na_number(config, "WorktopBackOverhang_mm", errors),
                :worktop_end       => na_number(config, "WorktopEndOverhang_mm", errors),
                :worktop_material  => na_get(config, "WorktopMaterialId").to_s.strip,
                # V2.7.6: only a value the run has STORED turns it on. A new run
                # stores true (its start, Na__Defaults.na_default_config); a run
                # built before 2.7.6 has none, so an unrelated rebuild never
                # swaps its units' plinths for a kickboard (MANAGER, 23-Nov-2026).
                :join_plinths      => !frames && config[Defaults.na_key("JoinPlinths")] == true,
                :soffit_height     => frames ? 0.0 : na_number(config, "SoffitHeight_mm", errors)
            }
        end
        private_class_method :na_settings
        # ---------------------------------------------------------------

        # HELPER FUNCTION | How Deep the Elements Stand From the Path
        # ------------------------------------------------------------
        # Frames: the posts' far face. Cabinets: the carcass depth.
        def self.na_band_depth(v)
            v[:frames] ? [v[:post_inset], 0.0].max + v[:post_depth] : v[:unit_depth]
        end
        private_class_method :na_band_depth
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Panel Types
# -----------------------------------------------------------------------------

        # FUNCTION | The Panel Type Table, Checked
        # ------------------------------------------------------------
        # @return [Hash{String=>Hash}] code => { :code, :product, :system,
        #     :width (nil = share the leg), :height (nil = to the run's
        #     height), :sill, :element_id, :auto, :derived_from, :label }
        def self.na_panel_types(config, v, errors)
            types    = {}
            products = Defaults::NA_MODE_PRODUCTS[v[:mode]]
            Array(na_get(config, "PanelTypes")).each_with_index do |row, index|
                unless row.is_a?(Hash)
                    errors << "Panel type #{index + 1} is not a set of values."
                    next
                end
                code = row["Code"].to_s.strip.upcase
                unless Defaults.na_valid_type_code?(code)
                    errors << "Panel type code '#{row['Code']}' will not do: a letter, then up to five letters or digits (A, B2, DR1)."
                    next
                end
                if types.key?(code)
                    errors << "Panel type #{code} is listed twice."
                    next
                end
                product = row["Product"].to_s
                errors << "Panel type #{code}: '#{product}' is not a #{v[:mode]} product (#{products.join(', ')})." unless products.include?(product)
                types[code] = {
                    :code         => code,
                    :product      => product,
                    :system       => Defaults::NA_MODE_SYSTEMS[v[:mode]],
                    :width        => na_type_size(row["Width_mm"], "Panel type #{code} width", errors),
                    :height       => na_type_size(row["Height_mm"], "Panel type #{code} height", errors),
                    :sill         => na_to_float(row["SillHeight_mm"]) || 0.0,
                    :element_id   => row["ElementId"].to_s.empty? ? nil : row["ElementId"].to_s,
                    :auto         => row["Auto"] == true,
                    :derived_from => row["DerivedFrom"].to_s.empty? ? nil : row["DerivedFrom"].to_s.upcase,
                    :label        => row["Label"].to_s,
                    :widths       => [],
                    :spans        => []
                }
                errors << "Panel type #{code}: the sill height cannot be below 0." if types[code][:sill] < 0
            end
            types
        end
        private_class_method :na_panel_types
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Type's Width or Height: a Number, or Nil for Auto
        # ------------------------------------------------------------
        def self.na_type_size(raw, label, errors)
            return nil if raw.nil? || raw.to_s.strip.empty? || raw.to_s.casecmp?("auto")
            value = na_to_float(raw)
            if value.nil? || value < Defaults::NA_MIN_SPAN_MM
                errors << "#{label} is #{raw.inspect}; give at least #{na_trim(Defaults::NA_MIN_SPAN_MM)}mm, or leave it out to share the leg."
                return nil
            end
            value
        end
        private_class_method :na_type_size
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Legs and Corners
# -----------------------------------------------------------------------------

        # FUNCTION | The Path's Legs, Checked
        # ------------------------------------------------------------
        def self.na_legs(config, errors)
            closed = na_get(config, "PathClosed") == true
            points = PathMath.na_clean_points(na_get(config, "PathPoints"), closed)
            if points.length < 2 || (closed && points.length < 3)
                errors << (closed ? "A closed path needs at least three corners." : "The path needs at least two points.")
                return [[], closed, points]
            end
            legs = PathMath.na_legs(points, closed)
            errors << "The path has #{legs.length} legs; the most a run takes is #{Defaults::NA_MAX_LEGS}." if legs.length > Defaults::NA_MAX_LEGS
            legs.each do |leg|
                next unless leg[:length] < Defaults::NA_MIN_LEG_MM
                errors << "Leg #{leg[:index] + 1} is only #{na_trim(leg[:length])}mm long (the least is #{na_trim(Defaults::NA_MIN_LEG_MM)})."
            end
            legs.each { |leg| leg.merge!(:setback_start => 0.0, :setback_end => 0.0, :corner_start => nil, :corner_end => nil) }
            [legs, closed, points]
        end
        private_class_method :na_legs
        # ---------------------------------------------------------------

        # FUNCTION | The Corner at Every Vertex Two Legs Share
        # ------------------------------------------------------------
        # Writes each leg's setbacks. A corner turns TOWARDS the band when the
        # elements of its two legs would run into each other there (an outside
        # corner of a framework, an inside corner of a room for cabinets);
        # turning away it leaves a notch between them.
        # @return [Array<Hash>]
        def self.na_corners(config, legs, closed, v, warnings, errors)
            overrides = Array(na_get(config, "Corners"))
            vertices  = closed ? (0...legs.length).to_a : (1...legs.length).to_a
            vertices.each_with_index.map do |vertex, order|
                leg_in  = legs[(vertex - 1) % legs.length]
                leg_out = legs[vertex % legs.length]
                turn    = PathMath.na_turn_deg(leg_in[:dir], leg_out[:dir])
                if turn.abs > 179.0
                    errors << "The path doubles back on itself at corner #{order + 1}."
                    turn = 90.0
                end
                override = overrides[order].is_a?(Hash) ? overrides[order]["Column"].to_s : ""
                wanted   = override.empty? ? v[:corner] : override
                unless Defaults::NA_CORNER_KINDS_BY_MODE[v[:mode]].include?(wanted)
                    errors << "Corner #{order + 1}: '#{wanted}' is not a #{v[:mode]} corner (#{Defaults::NA_CORNER_KINDS_BY_MODE[v[:mode]].join(', ')})."
                    wanted = v[:corner]
                end
                corner = na_corner(order, vertex, leg_in, leg_out, turn, wanted, v, warnings)
                leg_in[:setback_end]    = corner[:setback_in]
                leg_in[:corner_end]     = order
                leg_out[:setback_start] = corner[:setback_out]
                leg_out[:corner_start]  = order
                corner
            end
        end
        private_class_method :na_corners
        # ---------------------------------------------------------------

        # SUB FUNCTION | One Corner: Kind, Setbacks and Plan Outline
        # ------------------------------------------------------------
        def self.na_corner(order, vertex, leg_in, leg_out, turn, wanted, v, warnings)
            toward = v[:band_left] ? turn > 0 : turn < 0
            square = (turn.abs - 90.0).abs <= Defaults::NA_SQUARE_TOLERANCE_DEG
            band   = na_band_depth(v)
            reach  = band * Math.tan(turn.abs * PathMath::NA_RADIANS / 2.0)   # <-- Where the two bands' inner edges cross, back from the corner
            label  = "Corner #{order + 1}"
            kind   = wanted
            size   = band
            set_in = set_out = 0.0
            library = nil

            if toward
                case wanted
                when Defaults::NA_CORNER_VALE_260, Defaults::NA_CORNER_VALE_290
                    if square
                        library = wanted
                        size    = Defaults::NA_LIBRARY_COLUMNS[wanted][:corner_leg_mm]
                        set_in  = set_out = size
                    else
                        warnings << "#{label} turns #{na_trim(turn.abs)} degrees: a library corner column needs 90. A plain corner block is built there instead."
                        kind   = Defaults::NA_CORNER_POST
                        set_in = set_out = reach
                    end
                when Defaults::NA_CORNER_POST
                    size   = square ? [v[:corner_post], band].max : band
                    set_in = set_out = square ? size : reach
                when Defaults::NA_CORNER_UNIT
                    if square
                        size   = v[:corner_unit_leg]
                        set_in = set_out = size
                    else
                        warnings << "#{label} turns #{na_trim(turn.abs)} degrees: a corner unit needs 90. The corner is left open instead."
                        kind   = Defaults::NA_CORNER_OPEN
                        set_in = set_out = reach
                    end
                when Defaults::NA_CORNER_BLIND
                    set_in  = 0.0
                    set_out = square ? band + v[:front_allowance] : reach + v[:front_allowance]
                else
                    set_in = set_out = reach
                end
            else
                # Turning away, the legs leave a notch: nothing collides, so
                # neither stops short. A frame post fills the notch.
                if [Defaults::NA_CORNER_VALE_260, Defaults::NA_CORNER_VALE_290].include?(wanted)
                    warnings << "#{label} is an inside corner: the library corner columns are for outside corners. A plain corner block is built there instead."
                    kind = Defaults::NA_CORNER_POST
                elsif !v[:frames]
                    kind = Defaults::NA_CORNER_OPEN
                end
            end

            {
                :index       => order,
                :vertex      => vertex,
                :leg_in      => leg_in[:index],
                :leg_out     => leg_out[:index],
                :point       => leg_in[:p1],
                :dir_in      => leg_in[:dir],
                :dir_out     => leg_out[:dir],
                :turn_deg    => turn,
                :toward_band => toward,
                :square      => square,
                :kind        => kind,
                :library     => library,
                :size        => size,
                :setback_in  => set_in,
                :setback_out => set_out,
                :outline     => na_corner_outline(leg_in, leg_out, toward, kind, size, band, reach, v)
            }
        end
        private_class_method :na_corner
        # ---------------------------------------------------------------

        # SUB FUNCTION | The Plan Outline of What Stands in a Corner
        # ------------------------------------------------------------
        # A block's footprint, in the run's plan. Nil for an open corner, a
        # blind corner and a corner unit (the unit builder sets its own out).
        def self.na_corner_outline(leg_in, leg_out, toward, kind, size, band, reach, v)
            corner = leg_in[:p1]
            n_in   = v[:band_left] ? leg_in[:left]  : PathMath.na_right(leg_in[:dir])
            n_out  = v[:band_left] ? leg_out[:left] : PathMath.na_right(leg_out[:dir])
            case kind
            when Defaults::NA_CORNER_POST
                if toward
                    back    = (size - band).abs < 0.01 ? reach : size
                    depth   = (size - band).abs < 0.01 ? band : size
                    scale   = depth / (1.0 + n_in[0] * n_out[0] + n_in[1] * n_out[1])
                    [corner,
                     PathMath.na_add(corner, leg_in[:dir], -back),
                     PathMath.na_add(PathMath.na_add(corner, n_in, scale), n_out, scale),
                     PathMath.na_add(corner, leg_out[:dir], back)]
                else
                    scale = band / (1.0 + n_in[0] * n_out[0] + n_in[1] * n_out[1])
                    [corner,
                     PathMath.na_add(corner, n_in, band),
                     PathMath.na_add(PathMath.na_add(corner, n_in, scale), n_out, scale),
                     PathMath.na_add(corner, n_out, band)]
                end
            when Defaults::NA_CORNER_VALE_260, Defaults::NA_CORNER_VALE_290
                backing = Defaults::NA_LIBRARY_COLUMNS[kind][:backing_mm]
                step    = lambda { |along_in, along_out| PathMath.na_add(PathMath.na_add(corner, leg_in[:dir], -along_in), leg_out[:dir], along_out) }
                [step.call(0, 0), step.call(size, 0), step.call(size, backing), step.call(backing, backing), step.call(backing, size), step.call(0, size)]
            end
        end
        private_class_method :na_corner_outline
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | A Leg's Source Items (Its Own, or Its Fill Rule Expanded)
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | A Span Item of a Panel Type
        # ------------------------------------------------------------
        def self.na_span(code, source = nil)
            { :kind => NA_SPAN, :type => code, :source => source }
        end
        private_class_method :na_span
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Column Item of a Kind and Width
        # ------------------------------------------------------------
        def self.na_column(kind, width, source = nil, origin = "Item")
            library = Defaults::NA_LIBRARY_COLUMNS[kind]
            { :kind => NA_COLUMN, :role => kind, :width => (library ? library[:width_mm] : width.to_f), :source => source, :origin => origin }
        end
        private_class_method :na_column
        # ---------------------------------------------------------------

        # FUNCTION | The Items a Leg Starts From
        # ------------------------------------------------------------
        # @param available [Float] the leg's usable length less its end columns
        def self.na_source_items(leg_config, leg, available, v, types, derived, warnings, errors)
            label = "Leg #{leg[:index] + 1}"
            items = leg_config.is_a?(Hash) ? leg_config["Items"] : nil
            if items.is_a?(Array) && !items.empty?
                return na_explicit_items(items, label, v, types, errors)
            end

            fill = leg_config.is_a?(Hash) && leg_config["Fill"].is_a?(Hash) ? leg_config["Fill"] : nil
            fill ||= { "PanelType" => types.keys.first.to_s }                    # <-- A leg left empty takes the first panel type
            code = fill["PanelType"].to_s.strip.upcase
            unless types.key?(code)
                errors << (types.empty? ? "The run has no panel types yet: add one before filling #{label}." : "#{label} fills with panel type '#{code}', which is not in the list (#{types.keys.join(', ')}).")
                return []
            end
            v[:frames] ? na_fill_frames(fill, code, label, errors) : na_fill_cabinets(fill, code, label, available, v, types, derived, warnings, errors)
        end
        private_class_method :na_source_items
        # ---------------------------------------------------------------

        # SUB FUNCTION | A Leg's Own Item List, Checked
        # ------------------------------------------------------------
        def self.na_explicit_items(items, label, v, types, errors)
            allowed = Defaults::NA_COLUMN_KINDS_BY_MODE[v[:mode]] - [Defaults::NA_COLUMN_NONE]
            if items.length > Defaults::NA_MAX_SPANS_PER_LEG * 2
                errors << "#{label} lists #{items.length} items; the most is #{Defaults::NA_MAX_SPANS_PER_LEG * 2}."
                return []
            end
            items.each_with_index.filter_map do |item, index|
                unless item.is_a?(Hash)
                    errors << "#{label}, item #{index + 1} is not a set of values."
                    next nil
                end
                case item["Kind"].to_s
                when NA_SPAN
                    code = item["PanelType"].to_s.strip.upcase
                    unless types.key?(code)
                        errors << "#{label}, item #{index + 1}: panel type '#{code}' is not in the list (#{types.keys.join(', ')})."
                        next nil
                    end
                    na_span(code, index)
                when NA_COLUMN
                    kind = item["Column"].to_s
                    unless allowed.include?(kind)
                        errors << "#{label}, item #{index + 1}: column '#{kind}' is not one of #{allowed.join(', ')}."
                        next nil
                    end
                    width = na_to_float(item["Width_mm"]) || v[:joint_width]
                    low, high = Defaults::NA_LIMITS["JointWidth_mm"]
                    if !Defaults::NA_LIBRARY_COLUMNS.key?(kind) && (width < low || width > high)
                        errors << "#{label}, item #{index + 1}: a #{kind.downcase} of #{na_trim(width)}mm is outside #{na_trim(low)} to #{na_trim(high)}."
                        next nil
                    end
                    column = na_column(kind, width, index)
                    column[:worktop] = false if item["Worktop"] == false                 # <-- A cooker space: the worktop stops either side (V2.7.4)
                    column
                else
                    errors << "#{label}, item #{index + 1}: Kind must be Span or Column, not '#{item['Kind']}'."
                    nil
                end
            end
        end
        private_class_method :na_explicit_items
        # ---------------------------------------------------------------

        # SUB FUNCTION | Frames: a Count of Spans of One Panel Type
        # ------------------------------------------------------------
        def self.na_fill_frames(fill, code, label, errors)
            count = fill["Count"].nil? ? 1 : fill["Count"].to_i
            unless count.between?(1, Defaults::NA_MAX_SPANS_PER_LEG)
                errors << "#{label}: Count is #{fill['Count'].inspect}; give 1 to #{Defaults::NA_MAX_SPANS_PER_LEG} spans."
                return []
            end
            Array.new(count) { na_span(code) }
        end
        private_class_method :na_fill_frames
        # ---------------------------------------------------------------

        # SUB FUNCTION | Cabinets: Fill a Leg From One Standard Width
        # ------------------------------------------------------------
        # Whole standard units, then what is left over as narrower units at
        # the start, the end or both; or every unit the same width (Equal).
        # A remainder too narrow to be a unit becomes an infill block.
        def self.na_fill_cabinets(fill, code, label, available, v, types, derived, warnings, errors)
            base     = types[code]
            standard = base[:width] || na_to_float(fill["StandardWidth_mm"]) || 600.0
            minimum  = na_to_float(fill["MinInfillWidth_mm"]) || 150.0
            infill   = fill["Infill"].to_s.empty? ? Defaults::NA_INFILL_END : fill["Infill"].to_s
            { "StandardWidth_mm" => standard, "MinInfillWidth_mm" => minimum }.each do |name, value|
                low, high = Defaults::NA_LIMITS[name]
                errors << "#{label}: #{name} is #{na_trim(value)}; it must be between #{na_trim(low)} and #{na_trim(high)}." if value < low || value > high
            end
            unless Defaults::NA_INFILL_MODES.include?(infill)
                errors << "#{label}: Infill is '#{infill}'; it must be one of #{Defaults::NA_INFILL_MODES.join(', ')}."
                return []
            end
            if available < minimum
                errors << "#{label} has only #{na_trim(available)}mm to fill: less than the narrowest unit (#{na_trim(minimum)})."
                return []
            end
            base[:width] ||= standard

            if infill == Defaults::NA_INFILL_EQUAL
                count = [(available / standard).round, 1].max
                width = (available / count * 10.0).floor / 10.0
                code_each = (width - standard).abs < 0.05 ? code : na_derived_type(base, width, types, derived)
                return Array.new(count) { na_span(code_each) }
            end

            count = ((available + 0.01) / standard).floor
            rest  = available - count * standard
            units = Array.new(count) { na_span(code) }
            return units if rest < Defaults::NA_WIDTH_TOLERANCE_MM

            parts = infill == Defaults::NA_INFILL_BOTH ? 2 : 1
            each  = ((rest / parts) * 10.0).floor / 10.0
            piece = lambda do
                next na_span(na_derived_type(base, each, types, derived)) if each >= minimum
                na_column(Defaults::NA_COLUMN_INFILL, each, nil, "Fill")
            end
            warnings << "#{label}: the #{na_trim(rest)}mm left over is too narrow for a unit, so it is #{parts == 2 ? 'two infill blocks' : 'an infill block'}." if each < minimum
            case infill
            when Defaults::NA_INFILL_START then [piece.call] + units
            when Defaults::NA_INFILL_BOTH  then [piece.call] + units + [piece.call]
            else                                units + [piece.call]
            end
        end
        private_class_method :na_fill_cabinets
        # ---------------------------------------------------------------

        # SUB FUNCTION | The Panel Type a Fill Needs at Another Width
        # ------------------------------------------------------------
        # An earlier fill's type of the same base is used again: the one of
        # this width when there is one, else one no leg has taken yet in
        # this pass, moved to this width (its code and element are kept, and
        # the element is resized). Otherwise the next free code is taken.
        # @return [String] the code
        def self.na_derived_type(base, width, types, derived)
            earlier = types.values.select { |type| type[:auto] && type[:derived_from] == base[:code] }
            found   = earlier.find { |type| type[:width] && (type[:width] - width).abs < 0.05 }
            found ||= earlier.find { |type| !type[:claimed] }
            if found
                found[:width]   = width
                found[:claimed] = true
                return found[:code]
            end

            code = Defaults.na_next_type_code(types.keys)
            types[code] = base.merge(:code => code, :width => width, :element_id => nil, :auto => true, :derived_from => base[:code], :claimed => true,
                                     :label => "", :widths => [], :spans => [])
            derived << code
            code
        end
        private_class_method :na_derived_type
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | A Leg's Sequence, Widths and Stations
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The Column an End of the Run or a Joint Takes
        # ------------------------------------------------------------
        def self.na_default_column(kind, width, origin)
            return nil if kind == Defaults::NA_COLUMN_NONE
            na_column(kind, width, nil, origin)
        end
        private_class_method :na_default_column
        # ---------------------------------------------------------------

        # FUNCTION | Joints, End Columns and Fused Posts Round a Leg's Items
        # ------------------------------------------------------------
        def self.na_sequence(source, leg, legs, closed, v)
            sequence      = []
            previous_span = false
            source.each do |item|
                if item[:kind] == NA_SPAN
                    joint = previous_span ? na_default_column(v[:joint], v[:joint_width], "Joint") : nil
                    sequence << joint if joint
                    previous_span = true
                else
                    previous_span = false
                end
                sequence << item
            end
            unless closed
                first = na_default_column(v[:end_column], v[:end_width], "End")
                last  = na_default_column(v[:end_column], v[:end_width], "End")
                sequence.unshift(first) if first && leg[:index].zero?
                sequence.push(last)     if last && leg[:index] == legs.length - 1
            end
            v[:fuse] ? na_fuse(sequence, v) : sequence
        end
        private_class_method :na_sequence
        # ---------------------------------------------------------------

        # SUB FUNCTION | Fuse Framework: the Run's Own Mullions and Jambs
        # ------------------------------------------------------------
        # Every span is built without side frames. Between two spans stands
        # one mullion; where a span meets anything else (a column, a gap, a
        # corner, the run's end) stands a jamb.
        def self.na_fuse(sequence, v)
            fused = []
            sequence.each_with_index do |item, index|
                unless item[:kind] == NA_SPAN
                    fused << item
                    next
                end
                before = index.zero? ? nil : sequence[index - 1]
                after  = sequence[index + 1]
                fused << { :kind => NA_POST, :role => Defaults::NA_POST_JAMB, :width => v[:jamb] } if v[:jamb] > 0 && !(before && before[:kind] == NA_SPAN)
                fused << item
                if after && after[:kind] == NA_SPAN
                    fused << { :kind => NA_POST, :role => Defaults::NA_POST_MULLION, :width => v[:mullion] }
                elsif v[:jamb] > 0
                    fused << { :kind => NA_POST, :role => Defaults::NA_POST_JAMB, :width => v[:jamb] }
                end
            end
            fused
        end
        private_class_method :na_fuse
        # ---------------------------------------------------------------

        # FUNCTION | Give Every Item of a Leg Its Width, Station and Extents
        # ------------------------------------------------------------
        def self.na_place(sequence, leg, v, types, warnings, errors)
            label = "Leg #{leg[:index] + 1}"
            sequence.each { |item| item[:width] = types[item[:type]][:width] if item[:kind] == NA_SPAN }

            usable = leg[:usable]
            fixed  = sequence.sum { |item| item[:width].to_f }
            shares = sequence.select { |item| item[:kind] == NA_SPAN && item[:width].nil? }
            unless shares.empty?
                share = (((usable - fixed) / shares.length) * 10.0).floor / 10.0
                if share < Defaults::NA_MIN_SPAN_MM
                    errors << "#{label}: its #{shares.length} span#{shares.length == 1 ? '' : 's'} would be #{na_trim(share)}mm wide. " \
                              "The leg has #{na_trim(usable)}mm and #{na_trim(fixed)}mm of it is fixed."
                    share = Defaults::NA_MIN_SPAN_MM
                end
                shares.each { |item| item[:width] = share }
            end

            total    = sequence.sum { |item| item[:width].to_f }
            leftover = usable - total
            if leftover < -Defaults::NA_WIDTH_TOLERANCE_MM
                errors << "#{label}: its items add up to #{na_trim(total)}mm, #{na_trim(-leftover)}mm more than the #{na_trim(usable)}mm it has."
            elsif leftover > Defaults::NA_WIDTH_TOLERANCE_MM
                warnings << "#{label}: #{na_trim(leftover)}mm is left empty at its end. Leave a span's width out and it takes up the slack."
            end
            errors << "#{label} has no spans." if sequence.none? { |item| item[:kind] == NA_SPAN }

            station    = leg[:setback_start]
            span_count = 0
            sequence.each_with_index do |item, order|
                item[:leg] = leg[:index]
                item[:seq] = order
                item[:s0]  = station
                item[:s1]  = station + item[:width].to_f
                station    = item[:s1]
                na_extents!(item, v, types)
                next unless item[:kind] == NA_SPAN

                item[:span] = span_count
                item[:key]  = "L#{leg[:index] + 1}S#{span_count + 1}"
                span_count += 1
                types[item[:type]][:widths] << item[:width]
                types[item[:type]][:spans]  << item[:key]
            end
            leg[:items]    = sequence
            leg[:leftover] = leftover
        end
        private_class_method :na_place
        # ---------------------------------------------------------------

        # SUB FUNCTION | An Item's Depth Across the Leg and Its Height
        # ------------------------------------------------------------
        # y0 / y1 are offsets to the LEFT of the leg; z0 / z1 heights above
        # the run's base. A gap has neither.
        def self.na_extents!(item, v, types)
            if item[:kind] == NA_SPAN
                type      = types[item[:type]]
                item[:z0] = type[:sill]
                item[:z1] = v[:frames] ? type[:sill] + (type[:height] || (v[:height] - type[:sill])) : nil
                return
            end
            return if item[:role] == Defaults::NA_COLUMN_GAP

            if v[:frames]
                library   = Defaults::NA_LIBRARY_COLUMNS[item[:role]]
                item[:y0] = library ? 0.0 : v[:post_inset]
                item[:y1] = library ? library[:backing_mm] : v[:post_inset] + v[:post_depth]
                item[:z0] = 0.0
                item[:z1] = v[:height]
            else
                item[:y0] = -v[:unit_depth]
                item[:y1] = 0.0
                item[:z0] = 0.0
                item[:z1] = v[:filler_height]
            end
        end
        private_class_method :na_extents!
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API
# -----------------------------------------------------------------------------

        # FUNCTION | Resolve a Run Configuration Into Its Layout
        # ------------------------------------------------------------
        # Never raises on bad values: every problem is named in :errors (the
        # run cannot be built) or :warnings (it can, with that caveat).
        # @param config [Hash] the Na__AssemblyRunConfiguration block
        # @return [Hash] { :mode, :closed, :points, :settings, :legs,
        #     :corners, :types, :derived_types, :warnings, :errors,
        #     :total_length, :span_count, :bounds }
        def self.na_resolve(config)
            config   = {} unless config.is_a?(Hash)
            errors   = []
            warnings = []
            derived  = []
            v        = na_settings(config, errors)
            types    = na_panel_types(config, v, errors)
            legs, closed, points = na_legs(config, errors)
            corners  = legs.empty? ? [] : na_corners(config, legs, closed, v, warnings, errors)
            leg_rows = Array(na_get(config, "Legs"))

            legs.each do |leg|
                leg[:usable] = leg[:length] - leg[:setback_start] - leg[:setback_end]
                if leg[:usable] < Defaults::NA_MIN_SPAN_MM
                    errors << "Leg #{leg[:index] + 1} is #{na_trim(leg[:length])}mm long and its corners take #{na_trim(leg[:setback_start] + leg[:setback_end])}mm of it: no room for a span."
                    leg[:items]    = []
                    leg[:leftover] = 0.0
                    next
                end
                ends      = na_end_width(leg, legs, closed, v)
                source    = na_source_items(leg_rows[leg[:index]], leg, leg[:usable] - ends, v, types, derived, warnings, errors)
                sequence  = na_sequence(source, leg, legs, closed, v)
                na_place(sequence, leg, v, types, warnings, errors)
            end

            na_settle_types!(types, v, errors)
            cills, boards = na_run_cills!(legs, corners, types, closed, v, errors)
            worktops      = na_run_worktops(legs, corners, types, closed, v)
            cutouts       = na_worktop_cutouts(config, v, errors)
            plinths       = na_run_flagged(legs, corners, types, closed, v[:join_plinths], Defaults::NA_PLINTH_PRODUCTS)
            top_fillers   = na_run_flagged(legs, corners, types, closed, v[:soffit_height].to_f > 0.0, Defaults::NA_TOP_FILLER_PRODUCTS)
            types.each_value do |type|                                           # <-- V2.7.6: the run builds this type's plinth (PlinthByRun)
                type[:plinth_joined] = v[:join_plinths] && Defaults::NA_PLINTH_PRODUCTS.include?(type[:product].to_s)
            end
            {
                :mode          => v[:mode],
                :closed        => closed,
                :points        => points,
                :settings      => v,
                :legs          => legs,
                :corners       => corners,
                :types         => types,
                :derived_types => derived,
                :cills         => cills,
                :boards        => boards,
                :worktops      => worktops,
                :worktop_cutouts => cutouts,
                :plinths       => plinths,                                       # <-- V2.7.6: the kickboard stretches
                :top_fillers   => top_fillers,                                   # <-- V2.7.6: the top filler stretches
                :warnings      => warnings.uniq,
                :errors        => errors.uniq,
                :total_length  => legs.sum { |leg| leg[:length] },
                :span_count    => legs.sum { |leg| Array(leg[:items]).count { |item| item[:kind] == NA_SPAN } },
                :bounds        => PathMath.na_bounds(points)
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | One Cill and One Window Board Along the Run (V2.7.3)
        # ------------------------------------------------------------
        # Marks what each panel type gives up to the run, finds the stretches
        # the cill and board run along, stands posts, blocks and corner posts
        # on the cill, and gives each cill stretch its plan outline.
        # @return [Array] [cill stretches, board stretches]
        def self.na_run_cills!(legs, corners, types, closed, v, errors)
            types.each_value do |type|
                base   = type[:sill].to_f <= Defaults::NA_WIDTH_TOLERANCE_MM
                window = Defaults::NA_WINDOW_PRODUCTS.include?(type[:product].to_s)
                type[:window]       = window
                type[:cill_joined]  = v[:join_cills] && base
                type[:board_joined] = type[:cill_joined] && window
                type[:frameless]    = v[:fuse] && window && base                 # <-- Fused: the run builds this window's head and bottom rail
                type[:cill_lift]    = type[:cill_joined] ? v[:cill_height] : 0.0
                next unless type[:cill_joined] && type[:height] && type[:count].to_i > 0
                if type[:height] - type[:cill_lift] < Defaults::NA_MIN_SPAN_MM
                    errors << "Panel type #{type[:code]}: a #{na_trim(type[:cill_lift])}mm cill leaves no height for its #{na_trim(type[:height])}mm panel."
                end
            end
            legs.each { |leg| Array(leg[:items]).each { |item| item[:base_z] = item[:z0].to_f if item[:kind] == NA_SPAN } }
            return [[], []] unless v[:join_cills] && !legs.empty?

            found = RunCills.na_stretches(legs, corners, types, closed)
            RunCills.na_lift!(legs, corners, found[:cills], v[:cill_height])
            back = na_band_depth(v)
            found[:cills].each do |stretch|
                stretch[:outline] = RunCills.na_band_outline(stretch[:centreline], -v[:cill_projection], back, stretch[:closed])
            end
            [found[:cills], found[:boards]].each { |list| list.each { |stretch| stretch.delete(:segments) } }   # <-- The walk holds the items themselves: never reported
            [found[:cills], found[:boards]]
        end
        private_class_method :na_run_cills!
        # ---------------------------------------------------------------

        # FUNCTION | One Worktop Along the Base and Drawer Units (V2.7.4)
        # ------------------------------------------------------------
        # Where it runs. How deep and how high it is are the units' own
        # settings, known only once their elements are built: the builder
        # sizes it (Na__FrameworkBuilder.na_build_worktops) and the dialog's
        # preview from each product's starting values.
        # @return [Array<Hash>] the worktop stretches (none when it is off)
        def self.na_run_worktops(legs, corners, types, closed, v)
            return [] unless v[:worktop] && !legs.empty?
            stretches = RunCills.na_worktop_stretches(legs, corners, types, closed, v[:worktop_end])
            stretches.each { |stretch| stretch.delete(:segments) }
            stretches
        end
        private_class_method :na_run_worktops
        # ---------------------------------------------------------------

        # FUNCTION | Stretches of Spans of Given Products (V2.7.6)
        # ------------------------------------------------------------
        # The kickboard (floor units) and the top filler (tall units): where
        # they run, as the worktop's stretches give it. Their sizes are the
        # units' own, known once the elements are built
        # (Na__FrameworkBuilder.na_build_plinths / na_build_top_fillers).
        # @return [Array<Hash>] the stretches (none when it is off)
        def self.na_run_flagged(legs, corners, types, closed, wanted, products)
            return [] unless wanted && !legs.empty?
            stretches = RunCills.na_product_stretches(legs, corners, types, closed, products)
            stretches.each { |stretch| stretch.delete(:segments) }
            stretches
        end
        private_class_method :na_run_flagged
        # ---------------------------------------------------------------

        # FUNCTION | The Worktop's Cut-Outs, Checked (V2.7.5)
        # ------------------------------------------------------------
        # Holes for a hob or a sink, notches for a sit-on sink: each an
        # outline in the run's own plan (the agent seam turns a world
        # rectangle into one), cut through every worktop it lies on by the
        # builder. Cabinets only; a problem with one is named and refused.
        # @return [Array<Hash>] { :index, :label, :outline => [[x, y] ...] }
        def self.na_worktop_cutouts(config, v, errors)
            rows = na_get(config, "WorktopCutouts")
            return [] if v[:frames] || rows.nil?
            unless rows.is_a?(Array)
                errors << "WorktopCutouts must be a list of cut-outs."
                return []
            end
            if rows.length > Defaults::NA_CUTOUT_MAX_COUNT
                errors << "WorktopCutouts lists #{rows.length}; the most is #{Defaults::NA_CUTOUT_MAX_COUNT}."
                return []
            end
            rows.each_with_index.filter_map do |row, index|
                label   = row.is_a?(Hash) && !row["Label"].to_s.strip.empty? ? row["Label"].to_s.strip : "Cut-out #{index + 1}"
                points  = row.is_a?(Hash) ? Array(row["Outline_mm"]) : []
                outline = points.map { |point| point.is_a?(Array) && point.length >= 2 ? [na_to_float(point[0]), na_to_float(point[1])] : [nil, nil] }
                if outline.length < 3 || outline.flatten.any?(&:nil?)
                    errors << "WorktopCutouts #{label}: its outline needs three or more [x, y] points in mm."
                    next nil
                end
                shortest = outline.each_index.map { |i| PathMath.na_distance(outline[i], outline[(i + 1) % outline.length]) }.min
                if shortest < Defaults::NA_CUTOUT_MIN_SIDE_MM
                    errors << "WorktopCutouts #{label}: a side is #{na_trim(shortest)}mm long; the least is #{na_trim(Defaults::NA_CUTOUT_MIN_SIDE_MM)}."
                    next nil
                end
                { :index => index, :label => label, :outline => outline }
            end
        end
        private_class_method :na_worktop_cutouts
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Width the Run's End Columns Take From a Leg
        # ------------------------------------------------------------
        def self.na_end_width(leg, legs, closed, v)
            return 0.0 if closed || v[:end_column] == Defaults::NA_COLUMN_NONE
            each  = Defaults::NA_LIBRARY_COLUMNS[v[:end_column]] ? Defaults::NA_LIBRARY_COLUMNS[v[:end_column]][:width_mm] : v[:end_width]
            count = (leg[:index].zero? ? 1 : 0) + (leg[:index] == legs.length - 1 ? 1 : 0)
            each * count
        end
        private_class_method :na_end_width
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Each Panel Type's One Width and Height
        # ------------------------------------------------------------
        def self.na_settle_types!(types, v, errors)
            types.each_value do |type|
                widths = type[:widths]
                type[:count] = widths.length
                unless widths.empty?
                    if widths.max - widths.min > Defaults::NA_WIDTH_TOLERANCE_MM
                        errors << "Panel type #{type[:code]} comes out at #{na_trim(widths.min)}mm on one leg and #{na_trim(widths.max)}mm on another. " \
                                  "Give it a set width, or use a different panel type on one of them."
                    end
                    type[:width] = widths.first
                end
                next unless v[:frames]

                type[:height] ||= v[:height] - type[:sill]
                errors << "Panel type #{type[:code]}: a #{na_trim(type[:sill])}mm sill leaves no height under the run's #{na_trim(v[:height])}mm." if type[:height] < Defaults::NA_MIN_SPAN_MM
            end
        end
        private_class_method :na_settle_types!
        # ---------------------------------------------------------------

        # FUNCTION | A Layout as Plain JSON Data (String Keys, Rounded mm)
        # ------------------------------------------------------------
        # What the dialog draws and what an agent reads.
        def self.na_report(layout)
            na_plain(layout.reject { |key, _value| key == :settings }.merge(:settings => layout[:settings]))
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Symbols to Strings, Floats to Two Places
        # ------------------------------------------------------------
        def self.na_plain(value)
            case value
            when Hash   then value.each_with_object({}) { |(key, item), plain| plain[key.to_s] = na_plain(item) }
            when Array  then value.map { |item| na_plain(item) }
            when Float  then value.round(2)
            when Symbol then value.to_s
            else value
            end
        end
        private_class_method :na_plain
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__LayoutResolver
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
