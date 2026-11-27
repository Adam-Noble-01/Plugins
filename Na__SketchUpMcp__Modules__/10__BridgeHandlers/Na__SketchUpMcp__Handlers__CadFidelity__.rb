# =============================================================================
# NA SKETCHUP MCP - HANDLERS - CAD FIDELITY AUDIT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__CadFidelity__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__CadFidelity
# PURPOSE    : cad_fidelity_audit - fast read-only two-way CAD vs live model
#              elevation fidelity audit returning Recall (CAD -> Model),
#              Precision (Model -> CAD), median/P90/P95/max distances, pass/fail
#              gate, per-region breakdown, and worst-offender segment coords.
# CREATED    : 27-Nov-2026 (1.0.45)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__CadFidelity

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MM_PER_INCH          = 25.4
        NA_DEFAULT_BAND_MM      = 350.0
        NA_DEFAULT_TOL_MM       = 6.0
        NA_DEFAULT_MIN_EDGE_MM  = 15.0
        NA_DEFAULT_STEP_MM      = 15.0
        NA_DEFAULT_MIN_RECALL   = 90.0
        NA_DEFAULT_MIN_PREC     = 90.0
        NA_DEFAULT_MAX_MEDIAN   = 4.0
        NA_DEFAULT_OFFENDERS    = 15
        NA_MAX_OFFENDERS        = 100
        NA_MAX_DEPTH            = 32

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | cad_fidelity_audit (Live Read-Only Handler)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__CadFidelity__Audit(params, ctx)
            model = ctx[:model]
            unit  = ctx[:unit] || 'mm'

            cad_selector   = Na__Params.Na__Params__Required(params, 'cad_group')
            target_sels    = Na__Params.Na__Params__Array(params, 'model_targets', required: true, min_items: 1, max_items: 200)
            explicit_plane = Na__Params.Na__Params__Enum(params, 'plane', %w[x y], nil)
            tol_mm         = Na__Params.Na__Params__Number(params, 'tol_mm', NA_DEFAULT_TOL_MM, min: 0.1, max: 500.0)
            min_edge_mm    = Na__Params.Na__Params__Number(params, 'min_edge_mm', NA_DEFAULT_MIN_EDGE_MM, min: 0.1, max: 5000.0)
            sample_step_mm = Na__Params.Na__Params__Number(params, 'sample_step_mm', NA_DEFAULT_STEP_MM, min: 1.0, max: 500.0)
            min_recall     = Na__Params.Na__Params__Number(params, 'min_recall', NA_DEFAULT_MIN_RECALL, min: 0.0, max: 100.0)
            min_precision  = Na__Params.Na__Params__Number(params, 'min_precision', NA_DEFAULT_MIN_PREC, min: 0.0, max: 100.0)
            max_median     = Na__Params.Na__Params__Number(params, 'max_median', NA_DEFAULT_MAX_MEDIAN, min: 0.0, max: 5000.0)
            clip_pad_mm    = Na__Params.Na__Params__Number(params, 'clip_pad_mm', nil, min: 0.0, max: 50_000.0)
            include_hidden = Na__Params.Na__Params__Boolean(params, 'include_hidden', false)
            include_soft   = Na__Params.Na__Params__Boolean(params, 'include_soft', false)
            max_offenders  = Na__Params.Na__Params__Integer(params, 'max_offenders', NA_DEFAULT_OFFENDERS, min: 1, max: NA_MAX_OFFENDERS)

            depth_range_mm = na_parse_depth_range_mm(params, unit)
            band_depth_mm  = na_parse_length_mm(params, 'band_depth', NA_DEFAULT_BAND_MM, unit)
            regions_mm     = na_parse_regions_mm(params, unit)

            indexed = na_index_containers(model, include_hidden)
            cad_hit = na_resolve_single_container(indexed, cad_selector, 'cad_group')
            mod_hits = na_resolve_target_containers(indexed, target_sels)

            cad_edges_3d = []
            na_collect_world_edges(model, cad_hit[:path], include_hidden, include_soft, cad_edges_3d, 0)

            inferred_plane, inferred_coord = self.Na__Handlers__CadFidelity__InferPlane(cad_edges_3d)
            plane = explicit_plane || inferred_plane || 'y'
            plane_mm = inferred_coord

            if plane_mm.nil? && !cad_edges_3d.empty?
                coords = cad_edges_3d.flat_map { |e| plane == 'x' ? [e[0], e[3]] : [e[1], e[4]] }
                plane_mm = 0.5 * (coords.min + coords.max)
            end

            effective_depth = depth_range_mm
            if effective_depth.nil? && !plane_mm.nil?
                effective_depth = [plane_mm - band_depth_mm, plane_mm + band_depth_mm]
            end

            cad_segs = self.Na__Handlers__CadFidelity__ProjectEdges(
                cad_edges_3d,
                plane: plane,
                depth_range: nil,
                min_edge_mm: min_edge_mm
            )

            clip_box = nil
            if !clip_pad_mm.nil? && !cad_segs.empty?
                us = cad_segs.flat_map { |s| [s[0], s[2]] }
                zs = cad_segs.flat_map { |s| [s[1], s[3]] }
                clip_box = [us.min - clip_pad_mm, us.max + clip_pad_mm, zs.min - clip_pad_mm, zs.max + clip_pad_mm]
            end

            mod_edges_3d = []
            target_summaries = []
            mod_hits.each do |hit|
                before = mod_edges_3d.length
                na_collect_world_edges(model, hit[:path], include_hidden, include_soft, mod_edges_3d, 0)
                target_summaries << {
                    'id' => hit[:inst].persistent_id,
                    'name' => na_display_name(hit[:inst]),
                    'tag' => Na__EntityResolver.Na__EntityResolver__TagDisplayName(hit[:inst].layer),
                    'raw_edge_count' => mod_edges_3d.length - before
                }
            end

            model_segs = self.Na__Handlers__CadFidelity__ProjectEdges(
                mod_edges_3d,
                plane: plane,
                depth_range: effective_depth,
                min_edge_mm: min_edge_mm,
                clip_box: clip_box
            )

            result = self.Na__Handlers__CadFidelity__CompareSegments(
                cad_segs,
                model_segs,
                tol_mm: tol_mm,
                sample_step_mm: sample_step_mm,
                min_recall: min_recall,
                min_precision: min_precision,
                max_median: max_median,
                max_offenders: max_offenders,
                regions: regions_mm,
                min_region_edge_mm: min_edge_mm
            )

            result['cad_group'] = {
                'id' => cad_hit[:inst].persistent_id,
                'name' => na_display_name(cad_hit[:inst]),
                'tag' => Na__EntityResolver.Na__EntityResolver__TagDisplayName(cad_hit[:inst].layer)
            }
            result['model_targets'] = target_summaries
            result['plane'] = plane
            result['plane_mm'] = plane_mm.nil? ? nil : plane_mm.round(1)
            result['depth_range_mm'] = effective_depth.nil? ? nil : [effective_depth[0].round(1), effective_depth[1].round(1)]
            result
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pure Geometry & Two-Way Fidelity Engine (tested offline in BridgeCore)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__CadFidelity__InferPlane(raw_edges, flat_tol_mm: 15.0)
            pts3 = raw_edges.select { |e| e.is_a?(Array) && e.length == 6 }
            return [nil, nil] if pts3.empty?

            min_x = Float::INFINITY
            max_x = -Float::INFINITY
            min_y = Float::INFINITY
            max_y = -Float::INFINITY
            pts3.each do |e|
                min_x = e[0] if e[0] < min_x
                min_x = e[3] if e[3] < min_x
                max_x = e[0] if e[0] > max_x
                max_x = e[3] if e[3] > max_x
                min_y = e[1] if e[1] < min_y
                min_y = e[4] if e[4] < min_y
                max_y = e[1] if e[1] > max_y
                max_y = e[4] if e[4] > max_y
            end

            dx = max_x - min_x
            dy = max_y - min_y
            if dx <= flat_tol_mm && dy > flat_tol_mm
                ['x', 0.5 * (min_x + max_x)]
            elsif dy <= flat_tol_mm && dx > flat_tol_mm
                ['y', 0.5 * (min_y + max_y)]
            elsif dx < dy
                ['x', 0.5 * (min_x + max_x)]
            else
                ['y', 0.5 * (min_y + max_y)]
            end
        end

        def self.Na__Handlers__CadFidelity__ProjectEdges(raw_edges, plane: 'y', depth_range: nil, min_edge_mm: NA_DEFAULT_MIN_EDGE_MM, clip_box: nil, dedupe_mm: 0.2)
            plane_key = plane.to_s.downcase
            unless plane_key == 'x' || plane_key == 'y'
                raise Na__McpError.new('invalid_params', "Unsupported plane '#{plane}'; expected 'x' or 'y'.", nil)
            end

            d_lo = nil
            d_hi = nil
            if depth_range && depth_range.length == 2
                d_lo = [depth_range[0].to_f, depth_range[1].to_f].min
                d_hi = [depth_range[0].to_f, depth_range[1].to_f].max
            end

            inv_dedupe = dedupe_mm && dedupe_mm > 0.0 ? (1.0 / dedupe_mm.to_f) : 0.0
            seen = {}
            segs = []

            raw_edges.each do |e|
                next unless e.is_a?(Array)

                if e.length == 6
                    x0 = e[0].to_f
                    y0 = e[1].to_f
                    z0 = e[2].to_f
                    x1 = e[3].to_f
                    y1 = e[4].to_f
                    z1 = e[5].to_f
                    if plane_key == 'y'
                        u0 = x0
                        d0 = y0
                        u1 = x1
                        d1 = y1
                    else
                        u0 = y0
                        d0 = x0
                        u1 = y1
                        d1 = x1
                    end
                    if d_lo && d_hi
                        iv = na_clip_1d(0.0, 1.0, d0, d1, d_lo, d_hi)
                        next unless iv

                        t0, t1 = iv
                        du = u1 - u0
                        dz = z1 - z0
                        nu0 = u0 + t0 * du
                        nz0 = z0 + t0 * dz
                        nu1 = u0 + t1 * du
                        nz1 = z0 + t1 * dz
                        u0 = nu0
                        z0 = nz0
                        u1 = nu1
                        z1 = nz1
                    end
                elsif e.length == 4
                    u0 = e[0].to_f
                    z0 = e[1].to_f
                    u1 = e[2].to_f
                    z1 = e[3].to_f
                else
                    next
                end

                if clip_box
                    clipped = na_clip_box_2d(u0, z0, u1, z1, clip_box[0], clip_box[1], clip_box[2], clip_box[3])
                    next unless clipped

                    u0, z0, u1, z1 = clipped
                end

                len = Math.hypot(u1 - u0, z1 - z0)
                next if len < min_edge_mm

                if inv_dedupe > 0.0
                    k0 = [(u0 * inv_dedupe).round, (z0 * inv_dedupe).round]
                    k1 = [(u1 * inv_dedupe).round, (z1 * inv_dedupe).round]
                    key = (k0 <=> k1) <= 0 ? [k0, k1] : [k1, k0]
                    next if seen[key]

                    seen[key] = true
                end

                segs << [u0, z0, u1, z1]
            end

            segs
        end

        def self.Na__Handlers__CadFidelity__CompareSegments(cad_segs, model_segs, opts = {})
            tol_mm        = (opts[:tol_mm] || NA_DEFAULT_TOL_MM).to_f
            step_mm       = [(opts[:sample_step_mm] || NA_DEFAULT_STEP_MM).to_f, 1.0].max
            min_recall    = (opts[:min_recall] || NA_DEFAULT_MIN_RECALL).to_f
            min_precision = (opts[:min_precision] || NA_DEFAULT_MIN_PREC).to_f
            max_median    = (opts[:max_median] || NA_DEFAULT_MAX_MEDIAN).to_f
            max_offenders = (opts[:max_offenders] || NA_DEFAULT_OFFENDERS).to_i
            regions       = opts[:regions]
            min_reg_edge  = (opts[:min_region_edge_mm] || NA_DEFAULT_MIN_EDGE_MM).to_f

            cad_pts, cad_sidx = na_sample_segments(cad_segs, step_mm)
            mod_pts, mod_sidx = na_sample_segments(model_segs, step_mm)

            cell = [tol_mm * 8.0, 80.0].max
            d_c2m = na_min_distances_to_segments(cad_pts, model_segs, cell)
            d_m2c = na_min_distances_to_segments(mod_pts, cad_segs, cell)

            c2m_stats = na_direction_stats(d_c2m, tol_mm)
            m2c_stats = na_direction_stats(d_m2c, tol_mm)

            if !d_c2m.empty? && !d_m2c.empty?
                both = (d_c2m + d_m2c).sort
                if both.all?(&:finite?)
                    med = na_percentile_sorted(both, 50.0).round(2)
                    p90 = na_percentile_sorted(both, 90.0).round(2)
                    p95 = na_percentile_sorted(both, 95.0).round(2)
                    mx  = both.last.round(2)
                else
                    med = p90 = p95 = mx = nil
                end
            else
                med = p90 = p95 = mx = nil
            end

            recall    = c2m_stats['pct_within_tol']
            precision = m2c_stats['pct_within_tol']

            fail_reasons = []
            fail_reasons << 'no_cad_edges' if cad_segs.empty?
            fail_reasons << 'no_model_edges' if model_segs.empty?
            fail_reasons << format('recall %.1f%% < %.1f%%', recall, min_recall) if recall < min_recall
            fail_reasons << format('precision %.1f%% < %.1f%%', precision, min_precision) if precision < min_precision
            if med.nil? || med > max_median
                med_str = med.nil? ? 'inf' : format('%.2f mm', med)
                fail_reasons << format('median %s > %.2f mm', med_str, max_median)
            end

            passed = fail_reasons.empty?

            uncovered_cad = na_worst_segments(cad_segs, cad_sidx, d_c2m, tol_mm, max_offenders)
            extra_model   = na_worst_segments(model_segs, mod_sidx, d_m2c, tol_mm, max_offenders)

            region_results = []
            if regions.is_a?(Array) && !regions.empty?
                regions.each do |reg|
                    box = [
                        [reg['u0'].to_f, reg['u1'].to_f].min,
                        [reg['u0'].to_f, reg['u1'].to_f].max,
                        [reg['z0'].to_f, reg['z1'].to_f].min,
                        [reg['z0'].to_f, reg['z1'].to_f].max
                    ]
                    r_cad = self.Na__Handlers__CadFidelity__ProjectEdges(cad_segs, plane: 'y', min_edge_mm: min_reg_edge, clip_box: box, dedupe_mm: 0.0)
                    r_mod = self.Na__Handlers__CadFidelity__ProjectEdges(model_segs, plane: 'y', min_edge_mm: min_reg_edge, clip_box: box, dedupe_mm: 0.0)
                    r_res = self.Na__Handlers__CadFidelity__CompareSegments(
                        r_cad,
                        r_mod,
                        tol_mm: tol_mm,
                        sample_step_mm: step_mm,
                        min_recall: min_recall,
                        min_precision: min_precision,
                        max_median: max_median,
                        max_offenders: 5,
                        regions: nil
                    )
                    region_results << {
                        'name' => reg['name'].to_s,
                        'box_mm' => box.map { |v| v.round(1) },
                        'cad_edge_count' => r_res['cad_edge_count'],
                        'model_edge_count' => r_res['model_edge_count'],
                        'cad_to_model_pct' => r_res['cad_to_model_pct'],
                        'model_to_cad_pct' => r_res['model_to_cad_pct'],
                        'median_mm' => r_res['median_mm'],
                        'p90_mm' => r_res['p90_mm'],
                        'p95_mm' => r_res['p95_mm'],
                        'max_mm' => r_res['max_mm'],
                        'pass' => r_res['pass'],
                        'fail_reasons' => r_res['fail_reasons']
                    }
                end
            end

            med_lbl = med.nil? ? 'n/a' : format('%.2f mm', med)
            summary = if passed
                          format('PASS: Recall %.1f%%, Precision %.1f%%, median %s (%d CAD / %d model edges, tol %.1f mm).',
                                 recall, precision, med_lbl, cad_segs.length, model_segs.length, tol_mm)
                      else
                          format('FAIL: Recall %.1f%%, Precision %.1f%%, median %s (%s).',
                                 recall, precision, med_lbl, fail_reasons.join('; '))
                      end

            {
                'pass' => passed,
                'fail_reasons' => fail_reasons,
                'tol_mm' => tol_mm.round(2),
                'sample_step_mm' => step_mm.round(2),
                'thresholds' => {
                    'min_recall_pct' => min_recall.round(2),
                    'min_precision_pct' => min_precision.round(2),
                    'max_median_mm' => max_median.round(2)
                },
                'cad_edge_count' => cad_segs.length,
                'model_edge_count' => model_segs.length,
                'cad_to_model_pct' => recall,
                'model_to_cad_pct' => precision,
                'median_mm' => med,
                'p90_mm' => p90,
                'p95_mm' => p95,
                'max_mm' => mx,
                'cad_to_model' => c2m_stats,
                'model_to_cad' => m2c_stats,
                'uncovered_cad' => uncovered_cad,
                'extra_model' => extra_model,
                'regions' => region_results,
                'summary' => summary
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Private Geometry & Spatial-Grid Helpers
# -----------------------------------------------------------------------------

        def self.na_clip_1d(t0, t1, v0, v1, lo, hi)
            dv = v1 - v0
            if dv.abs < 1.0e-12
                return nil if v0 < lo || v0 > hi

                return [t0, t1]
            end
            a = (lo - v0) / dv
            b = (hi - v0) / dv
            a, b = b, a if a > b
            nt0 = t0 > a ? t0 : a
            nt1 = t1 < b ? t1 : b
            return nil if nt0 > nt1

            [nt0, nt1]
        end
        private_class_method :na_clip_1d

        def self.na_clip_box_2d(u0, z0, u1, z1, bu0, bu1, bz0, bz1)
            lo_u = bu0 <= bu1 ? bu0 : bu1
            hi_u = bu0 <= bu1 ? bu1 : bu0
            lo_z = bz0 <= bz1 ? bz0 : bz1
            hi_z = bz0 <= bz1 ? bz1 : bz0
            iv = na_clip_1d(0.0, 1.0, u0, u1, lo_u, hi_u)
            return nil unless iv

            iv = na_clip_1d(iv[0], iv[1], z0, z1, lo_z, hi_z)
            return nil unless iv

            t0, t1 = iv
            du = u1 - u0
            dz = z1 - z0
            [u0 + t0 * du, z0 + t0 * dz, u0 + t1 * du, z0 + t1 * dz]
        end
        private_class_method :na_clip_box_2d

        def self.na_sample_segments(segs, step_mm)
            pts = []
            sidx = []
            segs.each_with_index do |seg, i|
                u0, z0, u1, z1 = seg
                du = u1 - u0
                dz = z1 - z0
                len = Math.hypot(du, dz)
                n = (len / step_mm).ceil
                n = 2 if n < 2
                inv_n = 1.0 / n.to_f
                j = 0
                while j < n
                    t = (j + 0.5) * inv_n
                    pts << [u0 + t * du, z0 + t * dz]
                    sidx << i
                    j += 1
                end
            end
            [pts, sidx]
        end
        private_class_method :na_sample_segments

        def self.na_point_to_seg_sq(px, pz, seg)
            ax = seg[0]
            az = seg[1]
            abx = seg[2] - ax
            abz = seg[3] - az
            ab2 = abx * abx + abz * abz
            if ab2 <= 1.0e-12
                dx = px - ax
                dz = pz - az
                return dx * dx + dz * dz
            end
            t = ((px - ax) * abx + (pz - az) * abz) / ab2
            t = 0.0 if t < 0.0
            t = 1.0 if t > 1.0
            dx = px - (ax + t * abx)
            dz = pz - (az + t * abz)
            dx * dx + dz * dz
        end
        private_class_method :na_point_to_seg_sq

        def self.na_min_distances_to_segments(pts, segs, cell_mm)
            return [] if pts.empty?
            return Array.new(pts.length, Float::INFINITY) if segs.empty?

            cell = cell_mm < 25.0 ? 25.0 : cell_mm.to_f
            inv_cell = 1.0 / cell
            cell_sq = cell * cell

            grid = Hash.new { |h, k| h[k] = [] }
            segs.each_with_index do |seg, si|
                u0, z0, u1, z1 = seg
                du = u1 - u0
                dz = z1 - z0
                span = [du.abs, dz.abs].max * inv_cell
                steps = (span * 2.0).ceil
                steps = 1 if steps < 1
                inv_s = 1.0 / steps.to_f
                touched = {}
                k = 0
                while k <= steps
                    f = k * inv_s
                    cx = ((u0 + f * du) * inv_cell).floor
                    cz = ((z0 + f * dz) * inv_cell).floor
                    key = [cx, cz]
                    unless touched[key]
                        touched[key] = true
                        grid[key] << si
                    end
                    k += 1
                end
            end

            dists = Array.new(pts.length)
            pts.each_with_index do |pt, pi|
                px = pt[0]
                pz = pt[1]
                cx = (px * inv_cell).floor
                cz = (pz * inv_cell).floor

                best_sq = Float::INFINITY
                checked = {}
                (-1..1).each do |dx|
                    (-1..1).each do |dz|
                        bucket = grid[[cx + dx, cz + dz]]
                        next unless bucket

                        bucket.each do |si|
                            next if checked[si]

                            checked[si] = true
                            d2 = na_point_to_seg_sq(px, pz, segs[si])
                            best_sq = d2 if d2 < best_sq
                        end
                    end
                end

                # Exact fallback when nearest segment lies beyond the 3x3 ring.
                if best_sq > cell_sq
                    segs.each_with_index do |seg, si|
                        next if checked[si]

                        d2 = na_point_to_seg_sq(px, pz, seg)
                        best_sq = d2 if d2 < best_sq
                    end
                end

                dists[pi] = Math.sqrt(best_sq)
            end
            dists
        end
        private_class_method :na_min_distances_to_segments

        def self.na_percentile_sorted(sorted, pct)
            return 0.0 if sorted.empty?
            return sorted.first if sorted.length == 1

            pos = (pct / 100.0) * (sorted.length - 1)
            lo = pos.floor
            hi = pos.ceil
            return sorted[lo] if lo == hi

            sorted[lo] + (pos - lo) * (sorted[hi] - sorted[lo])
        end
        private_class_method :na_percentile_sorted

        def self.na_direction_stats(dists, tol_mm)
            if dists.empty?
                return {
                    'sample_count' => 0,
                    'within_tol_count' => 0,
                    'pct_within_tol' => 0.0,
                    'median_mm' => nil,
                    'mean_mm' => nil,
                    'p90_mm' => nil,
                    'p95_mm' => nil,
                    'max_mm' => nil
                }
            end
            unless dists.any?(&:finite?)
                return {
                    'sample_count' => dists.length,
                    'within_tol_count' => 0,
                    'pct_within_tol' => 0.0,
                    'median_mm' => nil,
                    'mean_mm' => nil,
                    'p90_mm' => nil,
                    'p95_mm' => nil,
                    'max_mm' => nil
                }
            end
            sorted = dists.sort
            within = dists.count { |d| d <= tol_mm }
            mean = dists.sum / dists.length.to_f
            {
                'sample_count' => dists.length,
                'within_tol_count' => within,
                'pct_within_tol' => (100.0 * within / dists.length.to_f).round(2),
                'median_mm' => na_percentile_sorted(sorted, 50.0).round(2),
                'mean_mm' => mean.round(2),
                'p90_mm' => na_percentile_sorted(sorted, 90.0).round(2),
                'p95_mm' => na_percentile_sorted(sorted, 95.0).round(2),
                'max_mm' => sorted.last.round(2)
            }
        end
        private_class_method :na_direction_stats

        def self.na_worst_segments(segs, sidx, dists, tol_mm, max_offenders)
            return [] if segs.empty? || dists.empty?

            by_seg = Hash.new { |h, k| h[k] = [] }
            sidx.each_with_index { |si, i| by_seg[si] << dists[i] }

            rows = []
            by_seg.each do |si, dlist|
                max_d = dlist.max
                next if max_d <= tol_mm

                u0, z0, u1, z1 = segs[si]
                len = Math.hypot(u1 - u0, z1 - z0)
                within = dlist.count { |d| d <= tol_mm }
                mean_d = dlist.sum / dlist.length.to_f
                score = (mean_d.finite? ? mean_d : 1.0e6) * [len, 1.0].max
                rows << [
                    score,
                    {
                        'u0_mm' => u0.round(1),
                        'z0_mm' => z0.round(1),
                        'u1_mm' => u1.round(1),
                        'z1_mm' => z1.round(1),
                        'length_mm' => len.round(1),
                        'max_dist_mm' => max_d.finite? ? max_d.round(2) : nil,
                        'mean_dist_mm' => mean_d.finite? ? mean_d.round(2) : nil,
                        'within_tol_pct' => (100.0 * within / dlist.length.to_f).round(1)
                    }
                ]
            end
            rows.sort_by { |score, _row| -score }.first(max_offenders).map { |_score, row| row }
        end
        private_class_method :na_worst_segments

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | SketchUp Container Resolution & Open-Context-Safe Edge Collection
# -----------------------------------------------------------------------------

        def self.na_parse_length_mm(params, key, default_mm, unit)
            return default_mm unless Na__Params.Na__Params__Has(params, key)

            inches = Na__Units.Na__Units__ToInches(params[key], unit)
            mm_val = inches * NA_MM_PER_INCH
            if mm_val < 0.0
                raise Na__McpError.new('invalid_params', "'#{key}' must be >= 0.", nil)
            end
            mm_val
        end
        private_class_method :na_parse_length_mm

        def self.na_parse_depth_range_mm(params, unit)
            return nil unless Na__Params.Na__Params__Has(params, 'depth_range')

            arr = Na__Params.Na__Params__Array(params, 'depth_range', min_items: 2, max_items: 2)
            a = Na__Units.Na__Units__ToInches(arr[0], unit) * NA_MM_PER_INCH
            b = Na__Units.Na__Units__ToInches(arr[1], unit) * NA_MM_PER_INCH
            [a < b ? a : b, a < b ? b : a]
        end
        private_class_method :na_parse_depth_range_mm

        def self.na_parse_regions_mm(params, unit)
            return nil unless Na__Params.Na__Params__Has(params, 'regions')

            arr = Na__Params.Na__Params__Array(params, 'regions', max_items: 100)
            arr.map do |item|
                unless item.is_a?(Hash)
                    raise Na__McpError.new('invalid_params', 'Each item in regions must be an object with name, u0, u1, z0, z1.', nil)
                end
                {
                    'name' => Na__Params.Na__Params__String(item, 'name', required: true),
                    'u0' => Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(item, 'u0'), unit) * NA_MM_PER_INCH,
                    'u1' => Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(item, 'u1'), unit) * NA_MM_PER_INCH,
                    'z0' => Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(item, 'z0'), unit) * NA_MM_PER_INCH,
                    'z1' => Na__Units.Na__Units__ToInches(Na__Params.Na__Params__Required(item, 'z1'), unit) * NA_MM_PER_INCH
                }
            end
        end
        private_class_method :na_parse_regions_mm

        def self.na_display_name(inst)
            name = inst.name.to_s
            return name unless name.empty?

            inst.definition ? inst.definition.name.to_s : ''
        end
        private_class_method :na_display_name

        def self.na_entity_shown?(entity)
            return false if entity.hidden?

            layer = entity.layer
            return true unless layer
            return false unless layer.visible?

            folder = layer.respond_to?(:folder) ? layer.folder : nil
            while folder
                return false unless folder.visible?

                folder = folder.respond_to?(:folder) ? folder.folder : nil
            end
            true
        end
        private_class_method :na_entity_shown?

        def self.na_index_containers(model, include_hidden)
            list = []
            na_index_walk(model.entities, [], 0, include_hidden, list)
            list
        end
        private_class_method :na_index_containers

        def self.na_index_walk(entities, parent_path, depth, include_hidden, list)
            return if depth > NA_MAX_DEPTH

            entities.each do |e|
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(e)
                next if !include_hidden && !na_entity_shown?(e)

                path = parent_path + [e]
                list << {
                    inst: e,
                    path: path,
                    depth: depth,
                    pid: e.persistent_id,
                    name: na_display_name(e),
                    tag: Na__EntityResolver.Na__EntityResolver__TagDisplayName(e.layer)
                }
                defn = e.definition
                na_index_walk(defn.entities, path, depth + 1, include_hidden, list) if defn
            end
        end
        private_class_method :na_index_walk

        def self.na_match_selector(indexed, selector)
            if selector.is_a?(Integer) || (selector.is_a?(Float) && selector == selector.floor)
                pid = selector.to_i
                return indexed.select { |h| h[:pid] == pid }
            end
            text = selector.to_s.strip
            return [] if text.empty?
            if text =~ /\A\d+\z/
                pid = text.to_i
                by_pid = indexed.select { |h| h[:pid] == pid }
                return by_pid unless by_pid.empty?
            end

            down = text.downcase
            # 1. Exact root tag match
            hits = indexed.select { |h| h[:depth] == 0 && h[:tag].downcase == down }
            return hits unless hits.empty?
            # 2. Exact root name match
            hits = indexed.select { |h| h[:depth] == 0 && h[:name].downcase == down }
            return hits unless hits.empty?
            # 3. Exact nested name match
            hits = indexed.select { |h| h[:name].downcase == down }
            return hits unless hits.empty?
            # 4. Exact nested tag match
            hits = indexed.select { |h| h[:tag].downcase == down }
            return hits unless hits.empty?
            # 5. Substring name match (root first, then nested)
            hits = indexed.select { |h| h[:depth] == 0 && h[:name].downcase.include?(down) }
            return hits unless hits.empty?

            indexed.select { |h| h[:name].downcase.include?(down) }
        end
        private_class_method :na_match_selector

        def self.na_resolve_single_container(indexed, selector, label)
            hits = na_match_selector(indexed, selector)
            if hits.empty?
                raise Na__McpError.new('not_found', "No visible group or component matched '#{selector}' for #{label}.",
                                       'Pass a persistent_id or exact group name from outliner_tree (or include_hidden: true).')
            end
            if hits.length > 1
                names = hits.first(5).map { |h| "#{h[:name]} (id #{h[:pid]})" }.join(', ')
                raise Na__McpError.new('invalid_params', "Ambiguous #{label} '#{selector}' matched #{hits.length} containers: #{names}.",
                                       'Pass an exact group name or persistent_id.')
            end
            hits.first
        end
        private_class_method :na_resolve_single_container

        def self.na_resolve_target_containers(indexed, selectors)
            out = []
            seen = {}
            selectors.each do |sel|
                hits = na_match_selector(indexed, sel)
                if hits.empty?
                    raise Na__McpError.new('not_found', "No visible group, component, or tag matched '#{sel}' in model_targets.",
                                           'Check root names or tag names with outliner_tree / collection_list.')
                end
                hits.each do |h|
                    next if seen[h[:pid]]

                    seen[h[:pid]] = true
                    out << h
                end
            end
            out
        end
        private_class_method :na_resolve_target_containers

        def self.na_collect_world_edges(model, path, include_hidden, include_soft, acc, depth)
            return if depth > NA_MAX_DEPTH

            inst = path.last
            return unless inst && inst.valid?

            defn = inst.definition
            return unless defn

            to_world = Na__Coordinates.Na__Coordinates__ReportedToWorld(model, path)
            defn.entities.each do |e|
                next if !include_hidden && !na_entity_shown?(e)

                if e.is_a?(Sketchup::Edge)
                    next if !include_soft && (e.soft? || e.smooth?)

                    p1 = e.start.position.transform(to_world)
                    p2 = e.end.position.transform(to_world)
                    acc << [
                        p1.x.to_f * NA_MM_PER_INCH, p1.y.to_f * NA_MM_PER_INCH, p1.z.to_f * NA_MM_PER_INCH,
                        p2.x.to_f * NA_MM_PER_INCH, p2.y.to_f * NA_MM_PER_INCH, p2.z.to_f * NA_MM_PER_INCH
                    ]
                elsif Na__EntityResolver.Na__EntityResolver__IsInstance(e)
                    na_collect_world_edges(model, path + [e], include_hidden, include_soft, acc, depth + 1)
                end
            end
        end
        private_class_method :na_collect_world_edges

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__CadFidelity
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
