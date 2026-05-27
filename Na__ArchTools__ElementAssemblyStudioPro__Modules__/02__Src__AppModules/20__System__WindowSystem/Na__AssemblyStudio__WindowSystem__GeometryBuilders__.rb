# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - GEOMETRY BUILDERS
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__GeometryBuilders__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__GeometryBuilders
# AUTHOR     : Noble Architecture
# PURPOSE    : High-level geometry builder functions for window elements
# CREATED    : 2026
# VERSION    : 0.2.3b
#
# DESCRIPTION:
# - High-level builders that compose low-level GeometryHelpers primitives
# - Domain-specific functions for frame, mullion, casement, glass, glaze bars, cill
# - Handles joinery conventions (stiles full height, rails inset)
# - Manages Y-offset for frame wall inset feature
# - Material management (get or create)
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix
#
# =============================================================================

require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative 'Na__AssemblyStudio__WindowSystem__GeometryHelpers__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__GeometryBuilders

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        GeometryHelpers = Na__AssemblyStudio::Na__WindowSystem::Na__GeometryHelpers

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Management
# -----------------------------------------------------------------------------

        # FUNCTION | Get or Create Material
        # ------------------------------------------------------------
        # Creates a new material or updates the color of an existing one.
        # @param name [String] Material name
        # @param color [Sketchup::Color] Material color
        # @return [Sketchup::Material] The material
        def self.na_get_or_create_material(name, color)
            materials = Sketchup.active_model.materials
            material = materials[name]
            
            unless material
                material = materials.add(name)
            end
            
            # Always update color to reflect current selection
            material.color = color
            material.alpha = color.alpha / 255.0 if color.alpha < 255
            
            return material
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Frame Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Create Frame Geometry (Outer Frame)
        # ------------------------------------------------------------
        # JOINERY CONVENTION: Stiles (vertical) span full height, 
        # Rails (horizontal) are inset between stiles.
        # This matches real window construction.
        # Each piece is created as a separate named group for easy identification.
        # 
        # @param entities [Sketchup::Entities] Target entities collection
        # @param width [Float] Overall window width
        # @param height [Float] Overall window height
        # @param thickness_or_edges [Float, Hash] Uniform frame thickness or per-edge thickness hash
        # @param depth [Float] Frame depth (Y direction)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame (pushes into wall reveal)
        def self.na_create_frame_geometry(entities, width, height, thickness_or_edges, depth, material, wall_inset = 0)
            frame_thicknesses = if thickness_or_edges.is_a?(Hash)
                {
                    top: thickness_or_edges[:top].to_f,
                    bottom: thickness_or_edges[:bottom].to_f,
                    left: thickness_or_edges[:left].to_f,
                    right: thickness_or_edges[:right].to_f
                }
            else
                thickness = thickness_or_edges.to_f
                {
                    top: thickness,
                    bottom: thickness,
                    left: thickness,
                    right: thickness
                }
            end

            left_thickness = frame_thicknesses[:left]
            right_thickness = frame_thicknesses[:right]
            top_thickness = frame_thicknesses[:top]
            bottom_thickness = frame_thicknesses[:bottom]
            clear_width = width - left_thickness - right_thickness

            DebugTools.na_debug_geometry("Creating outer frame: #{width.to_mm.round}x#{height.to_mm.round}mm, wall_inset: #{wall_inset.to_mm.round}mm")
            
            # Left stile - FULL HEIGHT (Z = 0 to height)
            if left_thickness > 0
                GeometryHelpers.na_create_frame_stile(entities, "Left", 0, wall_inset, 0, left_thickness, depth, height, material)
            end
            
            # Right stile - FULL HEIGHT (Z = 0 to height) at X = width - thickness
            if right_thickness > 0
                GeometryHelpers.na_create_frame_stile(entities, "Right", width - right_thickness, wall_inset, 0, right_thickness, depth, height, material)
            end
            
            # Bottom rail - INSET between stiles (X = thickness to width - thickness), at Z = 0
            if bottom_thickness > 0 && clear_width > 0
                GeometryHelpers.na_create_frame_rail(entities, "Bottom", left_thickness, wall_inset, 0, clear_width, depth, bottom_thickness, material)
            end
            
            # Top rail - INSET between stiles (X = thickness to width - thickness), at Z = height - thickness
            if top_thickness > 0 && clear_width > 0
                GeometryHelpers.na_create_frame_rail(entities, "Top", left_thickness, wall_inset, height - top_thickness, clear_width, depth, top_thickness, material)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Mullion Geometry (Vertical Divider)
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Target entities collection
        # @param mullion_index [Integer] Index of this mullion (1-based)
        # @param x_pos [Float] X position for the mullion
        # @param inner_height [Float] Height of the inner window area (between top/bottom rails)
        # @param mullion_width [Float] Width of the mullion
        # @param depth [Float] Depth of the mullion (Y direction)
        # @param frame_thickness [Float] Thickness of the outer frame (for Z offset)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        def self.na_create_mullion_geometry(entities, mullion_index, x_pos, inner_height, mullion_width, depth, frame_thickness, material, wall_inset = 0)
            DebugTools.na_debug_geometry("Creating mullion #{mullion_index} at X=#{x_pos.to_mm.round}mm")
            
            # Mullion spans from bottom frame rail to top frame rail
            GeometryHelpers.na_create_mullion(entities, mullion_index, x_pos, wall_inset, frame_thickness, mullion_width, depth, inner_height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Transom Geometry (Horizontal Divider)
        # ------------------------------------------------------------
        # @param entities [Sketchup::Entities] Target entities collection
        # @param transom_identifier [String] Unique identifier for this transom segment
        # @param x_pos [Float] X position for the left edge of the transom
        # @param z_pos [Float] Z position for the bottom edge of the transom
        # @param span_width [Float] Width of the opening span
        # @param transom_height [Float] Vertical height of the transom member
        # @param depth [Float] Depth of the transom (Y direction)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        def self.na_create_transom_geometry(entities, transom_identifier, x_pos, z_pos, span_width, transom_height, depth, material, wall_inset = 0)
            DebugTools.na_debug_geometry("Creating transom #{transom_identifier} at Z=#{z_pos.to_mm.round}mm")
            GeometryHelpers.na_create_transom(entities, transom_identifier, x_pos, wall_inset, z_pos, span_width, depth, transom_height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Casement Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Create Casement Geometry (Legacy - uniform thickness)
        # ------------------------------------------------------------
        # JOINERY CONVENTION: Stiles (vertical) span full height, 
        # Rails (horizontal) are inset between stiles.
        # This matches real window construction.
        # Each piece is created as a separate named group for easy identification.
        # 
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param cas_width [Float] Casement width
        # @param cas_height [Float] Casement height
        # @param thickness [Float] Uniform casement member thickness
        # @param depth [Float] Casement depth (Y direction)
        # @param offset_x [Float] X offset from frame origin
        # @param offset_z [Float] Z offset from frame origin
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_inset [Float] Casement inset from frame face
        def self.na_create_casement_geometry(entities, opening_index, cas_width, cas_height, thickness, depth, offset_x, offset_z, material, wall_inset = 0, casement_inset = 10.mm)
            DebugTools.na_debug_geometry("Creating casement #{opening_index} at offset (#{offset_x.to_mm.round}, #{offset_z.to_mm.round})")
            
            y_offset = wall_inset + casement_inset
            
            # Left stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Left", offset_x, y_offset, offset_z, thickness, depth, cas_height, material)
            
            # Right stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Right", offset_x + cas_width - thickness, y_offset, offset_z, thickness, depth, cas_height, material)
            
            # Bottom rail - INSET between stiles
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Bottom", offset_x + thickness, y_offset, offset_z, cas_width - (2 * thickness), depth, thickness, material)
            
            # Top rail - INSET between stiles
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Top", offset_x + thickness, y_offset, offset_z + cas_height - thickness, cas_width - (2 * thickness), depth, thickness, material)
        end
        # ---------------------------------------------------------------
        
        # FUNCTION | Create Casement Geometry with Individual Sizes
        # ------------------------------------------------------------
        # JOINERY CONVENTION: Stiles (vertical) span full height, 
        # Rails (horizontal) are inset between stiles.
        # This version supports different widths for each rail and stile.
        # 
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param cas_width [Float] Total casement width
        # @param cas_height [Float] Total casement height
        # @param top_rail [Float] Top rail thickness
        # @param bottom_rail [Float] Bottom rail thickness
        # @param left_stile [Float] Left stile thickness
        # @param right_stile [Float] Right stile thickness
        # @param depth [Float] Casement depth (Y direction)
        # @param offset_x [Float] X offset from frame origin
        # @param offset_z [Float] Z offset from frame origin
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_inset [Float] Casement inset from frame face
        def self.na_create_casement_geometry_individual(entities, opening_index, cas_width, cas_height, top_rail, bottom_rail, left_stile, right_stile, depth, offset_x, offset_z, material, wall_inset = 0, casement_inset = 10.mm)
            DebugTools.na_debug_geometry("Creating casement #{opening_index} with individual sizes at offset (#{offset_x.to_mm.round}, #{offset_z.to_mm.round})")
            DebugTools.na_debug_geometry("  - Top Rail: #{top_rail.to_mm.round}mm, Bottom Rail: #{bottom_rail.to_mm.round}mm")
            DebugTools.na_debug_geometry("  - Left Stile: #{left_stile.to_mm.round}mm, Right Stile: #{right_stile.to_mm.round}mm")
            
            y_offset = wall_inset + casement_inset
            
            # Left stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Left", offset_x, y_offset, offset_z, left_stile, depth, cas_height, material)
            
            # Right stile - FULL HEIGHT of casement
            GeometryHelpers.na_create_casement_stile(entities, opening_index, "Right", offset_x + cas_width - right_stile, y_offset, offset_z, right_stile, depth, cas_height, material)
            
            # Bottom rail - INSET between stiles (width excludes both stiles)
            rail_width = cas_width - left_stile - right_stile
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Bottom", offset_x + left_stile, y_offset, offset_z, rail_width, depth, bottom_rail, material)
            
            # Top rail - INSET between stiles (positioned at top minus rail height)
            GeometryHelpers.na_create_casement_rail(entities, opening_index, "Top", offset_x + left_stile, y_offset, offset_z + cas_height - top_rail, rail_width, depth, top_rail, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Glass and Glaze Bar Builders
# -----------------------------------------------------------------------------

        # FUNCTION | Build Glaze Bar Storage Key
        # ------------------------------------------------------------
        def self.na_build_glazebar_key(opening_index, cell_index, panel_index, sash_index, orientation, bar_index)
            "#{opening_index}:#{cell_index}:#{panel_index}:#{sash_index}:#{orientation}:#{bar_index}"
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Glaze Bar Removal
        # ------------------------------------------------------------
        def self.na_glazebar_removed?(removed_glazebars, opening_index, cell_index, panel_index, sash_index, orientation, bar_index)
            return false unless removed_glazebars.is_a?(Array)

            removed_glazebars.include?(na_build_glazebar_key(opening_index, cell_index, panel_index, sash_index, orientation, bar_index))
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Glass Geometry
        # ------------------------------------------------------------
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param glass_width [Float] Glass width
        # @param glass_height [Float] Glass height
        # @param thickness [Float] Glass thickness
        # @param offset_x [Float] X offset
        # @param offset_z [Float] Z offset
        # @param frame_depth [Float] Frame depth (for centering glass when direct-glazed)
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_depth [Float, nil] Casement depth (when glass inside casement, centers on casement)
        # @param casement_inset [Float, nil] Casement inset from frame face
        def self.na_create_glass_geometry(entities, opening_index, glass_width, glass_height, thickness, offset_x, offset_z, frame_depth, material, wall_inset = 0, casement_depth = nil, casement_inset = nil)
            DebugTools.na_debug_geometry("Creating glass pane #{opening_index}: #{glass_width.to_mm.round}x#{glass_height.to_mm.round}mm")
            
            if casement_depth && casement_inset
                # Glass centered on casement midpoint
                y_offset = wall_inset + casement_inset + (casement_depth - thickness) / 2.0
            else
                # Direct-glazed: center glass in frame depth
                y_offset = wall_inset + (frame_depth - thickness) / 2.0
            end
            
            GeometryHelpers.na_create_glass_pane(entities, opening_index, offset_x, y_offset, offset_z, glass_width, thickness, glass_height, material)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Glaze Bar Geometry
        # ------------------------------------------------------------
        # @param opening_index [Integer] Index of the opening (0-based)
        # @param glass_width [Float] Glass width
        # @param glass_height [Float] Glass height
        # @param h_bars [Integer] Number of horizontal bars
        # @param v_bars [Integer] Number of vertical bars
        # @param bar_width [Float] Bar width
        # @param glass_thickness [Float] Glass thickness
        # @param offset_x [Float] X offset
        # @param offset_z [Float] Z offset
        # @param frame_depth [Float] Frame depth
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame
        # @param casement_depth [Float, nil] Casement depth (when bars inside casement)
        # @param casement_inset [Float, nil] Casement inset from frame face
        # @param glazebar_inset [Float] Glaze bar inset from front/back of casement (or frame)
        def self.na_create_glazebar_geometry(entities, opening_index, glass_width, glass_height, h_bars, v_bars, bar_width, glass_thickness, offset_x, offset_z, frame_depth, material, wall_inset = 0, casement_depth = nil, casement_inset = nil, glazebar_inset = 0, removed_glazebars = [], opening_layout_index = 0, cell_index = 0, panel_index = 0, sash_index = 0, advanced = nil)
            DebugTools.na_debug_geometry("Creating glaze bars for opening #{opening_index}: #{h_bars}H x #{v_bars}V")

            if casement_depth && casement_inset
                # Bars inset from casement faces
                y_offset = wall_inset + casement_inset + glazebar_inset
                bar_depth = casement_depth - (2 * glazebar_inset)
            else
                # Direct-glazed: inset from frame depth
                y_offset = wall_inset + glazebar_inset
                bar_depth = frame_depth - (2 * glazebar_inset)
            end
            bar_depth = [bar_depth, glass_thickness].max

            # Resolve advanced options with safe fallbacks. `advanced` is an
            # optional hash carrying the Margin Glazing + Gothic Arch state
            # so callers that have not yet been migrated still get the
            # legacy divide-by-(N+1) behaviour.
            adv = advanced.is_a?(Hash) ? advanced : {}
            margin_enabled   = adv[:margin_enabled]    == true
            margin_offset    = (adv[:margin_offset]    || 0).to_f
            arch_enabled     = adv[:arch_enabled]      == true
            arch_amount      = [[(adv[:arch_amount]    || 2).to_i, 1].max, 8].min                  # <-- V1.9.4 Allow single lancet arch (was clamped to 2 minimum)
            arch_height      = (adv[:arch_height]      || 0).to_f
            arch_height_mm   = (adv[:arch_height_mm]   || 0).to_f
            h_offset         = (adv[:h_offset]         || 0).to_f                          # <-- Inches; positive lifts horizontal bars towards top of glass

            # Gothic arch zone shrinks the effective glass area available
            # for regular bars. We subtract the FULL arch zone (apex +
            # overshoot) so the overshoot termini land at the top of glass
            # and the apex sits below -- matching the 2D preview and the
            # casement-header tracery convention.
            effective_glass_height = glass_height
            if arch_enabled && arch_height > 0 && arch_amount >= 1
                bay_width = glass_width.to_f / arch_amount
                total_arch_zone = na_compute_gothic_total_zone_height(bay_width, arch_height)
                effective_glass_height = [glass_height - total_arch_zone, 0].max
            end

            # Horizontal bars (margin-aware positioning + user offset).
            # The h_offset is applied AFTER the automatic spacing math
            # so the slider acts as a uniform vertical nudge - critical
            # when a Gothic arch shrinks the effective glass height and
            # the auto-centred bar no longer aligns with the springing.
            if h_bars > 0 && effective_glass_height > 0
                h_positions = na_compute_bar_positions(offset_z, effective_glass_height, h_bars, margin_enabled, margin_offset)
                h_positions = h_positions.map { |z| z + h_offset } if h_offset != 0.0

                h_positions.each_with_index do |bar_center_z, idx|
                    i = idx + 1
                    next if na_glazebar_removed?(removed_glazebars, opening_layout_index, cell_index, panel_index, sash_index, "horizontal", i)

                    bar_z = bar_center_z - (bar_width / 2)
                    GeometryHelpers.na_create_glaze_bar_horizontal(entities, opening_index, i, offset_x, y_offset, bar_z, glass_width, bar_depth, bar_width, material)
                end
            end

            # Vertical bars (margin-aware positioning, span only the non-arch zone).
            # When arches are on and v_bars pairs naturally with arches
            # (one vbar under every interior springing), align vbars to
            # the extended-zone springings so they sit directly beneath
            # the arch springings. Margin glazing takes precedence.
            arch_align_vbars = arch_enabled && !margin_enabled && (v_bars + 1 == arch_amount)
            if v_bars > 0 && effective_glass_height > 0
                v_positions = if arch_align_vbars
                                  na_compute_arch_aligned_bar_positions(offset_x, glass_width, v_bars, bar_width, arch_amount)
                              else
                                  na_compute_bar_positions(offset_x, glass_width, v_bars, margin_enabled, margin_offset)
                              end
                v_positions.each_with_index do |bar_center_x, idx|
                    i = idx + 1
                    next if na_glazebar_removed?(removed_glazebars, opening_layout_index, cell_index, panel_index, sash_index, "vertical", i)

                    bar_x = bar_center_x - (bar_width / 2)
                    GeometryHelpers.na_create_glaze_bar_vertical(entities, opening_index, i, bar_x, y_offset, offset_z, bar_width, bar_depth, effective_glass_height, material)
                end
            end

            # Gothic arch tracery (post-positioning, top of the glazed area).
            # glass_top_z is passed so the arch builder can clip its
            # extended geometry back to the glass area boundary, producing
            # clean plumb edges where the arches meet the casement.
            if arch_enabled && arch_height > 0 && arch_amount >= 1
                springing_z = offset_z + effective_glass_height
                glass_top_z = offset_z + glass_height
                na_create_gothic_arch_geometry(
                    entities, opening_index,
                    offset_x, springing_z, glass_width, arch_height, arch_amount,
                    bar_width, bar_depth, y_offset,
                    arch_height_mm, material,
                    glass_top_z
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Compute Bar Centerline Positions Along One Axis
        # ------------------------------------------------------------
        # Mirrors window.Na__GlazebarMath.na_computeBarPositions in JS so
        # 2D and 3D stay in lockstep. Default mode evenly divides `size`
        # into (count+1) sections. Margin mode only kicks in for count >= 2:
        # the outer pair is inset by `margin_offset` and inner bars are
        # redistributed evenly between them.
        def self.na_compute_bar_positions(start, size, count, margin_enabled, margin_offset)
            return [] if count.nil? || count <= 0

            if !margin_enabled || count < 2
                step = size.to_f / (count + 1)
                return (1..count).map { |i| start + step * i }
            end

            first_pos = start + margin_offset
            last_pos  = start + size - margin_offset
            return [first_pos, last_pos] if count == 2

            inner_step = (last_pos - first_pos) / (count - 1).to_f
            (0...count).map { |i| first_pos + inner_step * i }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Arch-Aligned Bar Positions (3D Mirror of JS Helper)
        # ------------------------------------------------------------
        # Returns vbar centerline positions aligned with the interior
        # springings of the EXTENDED arch zone (glass + bar_width wider).
        # Used when arches are enabled and v_bars + 1 == arch_amount so
        # every vertical bar sits directly beneath an arch springing.
        def self.na_compute_arch_aligned_bar_positions(glass_start, glass_size, count, bar_width, arch_amount)
            return [] if count.nil? || count <= 0 || arch_amount.nil? || arch_amount < 2
            half_bar = bar_width / 2.0
            ext_glass_start = glass_start - half_bar
            ext_glass_size  = glass_size  + (2 * half_bar)
            ext_bay_width   = ext_glass_size / arch_amount.to_f
            (0...count).map { |i| ext_glass_start + (i + 1) * ext_bay_width }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create Gothic Arch Tracery Geometry For One Glazed Panel
        # ------------------------------------------------------------
        # Produces `arch_amount` two-centred lancet arches across the top
        # of the glazed area. Each arch is composed of TWO arc-halves
        # (left + right), each built as a single ring-segment face that
        # is then push-pulled into the wall -- the idiomatic SketchUp
        # workflow (draw 2D profile, extrude). One solid per arc-half
        # fuses cleanly with the straight glaze bars in the FuseParts
        # pipeline; no tiny-box tessellation, no outer_shell chains.
        #
        # Geometry parameters match the JS GlazebarMath helper exactly:
        #   bay_width  = glass_width / arch_amount
        #   c          = bay_width/4 + arch_height^2 / bay_width
        #   radius     = c
        #   arc sweep  = (apex angle +/- 15deg of overshoot)
        def self.na_create_gothic_arch_geometry(entities, opening_index, glass_left_x, springing_z, glass_width, arch_height, arch_amount, bar_width, bar_depth, y_offset, arch_height_mm, material, glass_top_z = nil)
            half_bar = bar_width / 2.0

            # Extend the arch zone outward (half_bar on each side, half_bar
            # on top). The extended boundary points are then CLIPPED in 2D
            # (Sutherland-Hodgman against the glass rectangle) BEFORE
            # add_face is called, so each arch half is constructed already
            # pre-clipped. This replaced an earlier approach that ran a
            # SketchUp solid Group#intersect against a transient cube per
            # arch half -- the boolean was the single biggest contributor
            # to Live Mode lag (~50-200ms per intersect x up to 16 halves).
            # The 2D clip costs microseconds.
            ext_glass_left  = glass_left_x - half_bar
            ext_glass_width = glass_width  + (2 * half_bar)
            ext_arch_height = arch_height  + half_bar
            bay_width       = ext_glass_width.to_f / arch_amount

            segments_per_arc = na_gothic_tessellation_segment_count(arch_height_mm)

            # Build clip-bounds hash once, reused for every arch half.
            clip_bounds = nil
            if glass_top_z
                clip_bounds = {
                    x_min: glass_left_x,
                    x_max: glass_left_x + glass_width,
                    y_min: springing_z,
                    y_max: glass_top_z
                }
            end

            (0...arch_amount).each do |bay_index|
                bay_left = ext_glass_left + (bay_index * bay_width)
                arch_index = bay_index + 1

                params = na_compute_gothic_arc_params(bay_width, ext_arch_height)
                radius_outer = params[:radius] + half_bar
                radius_inner = [params[:radius] - half_bar, 0.01].max

                # Left arc-half: face boundary computed, clipped in 2D
                # against `clip_bounds` if provided, then push-pulled
                # into the wall by bar_depth.
                GeometryHelpers.na_create_glaze_bar_arch_half(
                    entities, opening_index, arch_index, "L",
                    bay_left + params[:left_center_x], springing_z,
                    radius_outer, radius_inner,
                    params[:left_start_ang], params[:left_end_ang],
                    segments_per_arc,
                    y_offset, bar_depth, material,
                    clip_bounds
                )

                # Right arc-half (mirror).
                GeometryHelpers.na_create_glaze_bar_arch_half(
                    entities, opening_index, arch_index, "R",
                    bay_left + params[:right_center_x], springing_z,
                    radius_outer, radius_inner,
                    params[:right_start_ang], params[:right_end_ang],
                    segments_per_arc,
                    y_offset, bar_depth, material,
                    clip_bounds
                )
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Two-Centred Gothic Arc Parameters (Mirror of JS Helper)
        # ------------------------------------------------------------
        def self.na_compute_gothic_arc_params(bay_width, arch_height)
            w = [bay_width.to_f, 0.0001].max
            h = [arch_height.to_f, 0.0001].max
            c = (w / 4.0) + (h * h) / w

            apex_angle_left  = Math.atan2(h, (w / 2.0) - c)
            overshoot        = (15.0 * Math::PI) / 180.0
            right_center_x   = w - c
            apex_angle_right = Math.atan2(h, (w / 2.0) - right_center_x)

            {
                bay_width:        w,
                arch_height:      h,
                radius:           c,
                left_center_x:    c,
                right_center_x:   right_center_x,
                left_start_ang:   Math::PI,
                left_end_ang:     apex_angle_left - overshoot,
                right_start_ang:  0.0,
                right_end_ang:    apex_angle_right + overshoot
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Total Visible Arch Zone Height (Apex + Overshoot)
        # ------------------------------------------------------------
        # Mirror of na_computeGothicTotalZoneHeight in JS GlazebarMath.
        # The 15-deg overshoot pushes each arc's terminus ABOVE the apex;
        # this returns the visible top of the arch tracery so callers can
        # shift the springing line down by the right amount and keep the
        # entire tracery inside the casement header rather than letting
        # the overshoot escape into the frame above.
        def self.na_compute_gothic_total_zone_height(bay_width, apex_height)
            params = na_compute_gothic_arc_params(bay_width, apex_height)
            terminus_z = params[:radius] * Math.sin(params[:left_end_ang])
            [apex_height, terminus_z].max
        end
        # ---------------------------------------------------------------

        # FUNCTION | Tessellation Segment Count Per Arc (Height-Driven)
        # ------------------------------------------------------------
        # Matches the JS table exactly so 2D, 3D, and DXF stay aligned.
        def self.na_gothic_tessellation_segment_count(arch_height_mm)
            h = arch_height_mm.to_f
            return 24 if h < 450.0
            return 36 if h <= 600.0
            48
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Cill Builder
# -----------------------------------------------------------------------------

        # FUNCTION | Create Cill Geometry
        # ------------------------------------------------------------
        # The cill extends from the wall face (not from the inset frame).
        # When frame_wall_inset > 0, the cill still starts at the front of the wall.
        # 
        # @param entities [Sketchup::Entities] Target entities collection
        # @param width [Float] Cill width (matches window width)
        # @param cill_projection [Float] Cill projection from frame
        # @param cill_height [Float] Cill height
        # @param frame_depth [Float] Frame depth
        # @param material [Sketchup::Material] Material to apply
        # @param wall_inset [Float] Y offset for frame (cill extends through this)
        def self.na_create_cill_geometry(entities, width, cill_projection, cill_height, frame_depth, material, wall_inset = 0)
            DebugTools.na_debug_geometry("Creating cill: #{width.to_mm.round}mm wide, #{cill_projection.to_mm.round}mm projection, wall_inset: #{wall_inset.to_mm.round}mm")
            
            # Cill sits below window (negative Z) and projects forward (negative Y)
            # Cill starts at wall face (Y=0, not at wall_inset) and extends to back of frame
            cill_x = 0
            cill_y = -cill_projection
            cill_z = -cill_height
            cill_depth = cill_projection + wall_inset + frame_depth  # Projects front and extends through inset to back of frame
            
            GeometryHelpers.na_create_cill(entities, cill_x, cill_y, cill_z, width, cill_depth, cill_height, material)
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__GeometryBuilders
end # module Na__WindowSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
