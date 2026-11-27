# =============================================================================
# NA SKETCHUP MCP - HANDLERS - EDGE COLOUR AUDIT
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__EdgeAudit__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__EdgeAudit
# PURPOSE    : edge_colour_audit - fast read-only SSOT edge-colour audit
#              returning unpainted (NIL) edge counts, red helper edge flags,
#              and per-group material tallies for any entity ids or the model.
# CREATED    : 26-Nov-2026 (1.0.44)
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__EdgeAudit

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_UNPAINTED_KEY     = 'NIL'.freeze
        NA_RED_EDGE_MATERIAL = 'MTE201__LineColour__Red'.freeze
        NA_HELPER_TAG_PREFIX = '00__OriginPoint'.freeze
        NA_DEFAULT_MAX_DEPTH = 16
        NA_DEFAULT_LIMIT     = 200
        NA_MAX_LIMIT         = 1000

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | edge_colour_audit
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EdgeAudit__Audit(params, ctx)
            model          = ctx[:model]
            include_hidden = Na__Params.Na__Params__Boolean(params, 'include_hidden', false)
            include_soft   = Na__Params.Na__Params__Boolean(params, 'include_soft', true)
            max_depth      = Na__Params.Na__Params__Integer(params, 'max_depth', NA_DEFAULT_MAX_DEPTH, min: 0, max: 32)
            only_issues    = Na__Params.Na__Params__Boolean(params, 'only_issues', false)
            limit          = Na__Params.Na__Params__Integer(params, 'limit', NA_DEFAULT_LIMIT, min: 1, max: NA_MAX_LIMIT)

            targets = if Na__Params.Na__Params__Has(params, 'ids')
                          ids = Na__Params.Na__Params__IdArray(params, 'ids')
                          ids.map { |id| Na__EntityResolver.Na__EntityResolver__RequireInstance(model, id, 'ids') }
                      else
                          model.entities.select { |e| Na__EntityResolver.Na__EntityResolver__IsInstance(e) }
                      end

            rows         = []
            seen_defs    = {}
            root_edges   = 0
            root_nil     = 0
            root_mats    = Hash.new(0)

            # Include loose root edges only when auditing the whole model without explicit ids.
            unless Na__Params.Na__Params__Has(params, 'ids')
                model.entities.grep(Sketchup::Edge).each do |edge|
                    next if !include_hidden && !na_entity_shown?(edge)
                    next if !include_soft && (edge.soft? || edge.smooth?)

                    key = edge.material ? edge.material.name : NA_UNPAINTED_KEY
                    root_edges += 1
                    root_nil   += 1 if key == NA_UNPAINTED_KEY
                    root_mats[key] += 1
                end
                if root_edges > 0
                    rows << {
                        'id'          => 0,
                        'name'        => '<Model Root Edges>',
                        'definition'  => '<Model>',
                        'path'        => '<Model>',
                        'tag'         => 'Untagged',
                        'copies'      => 1,
                        'edges'       => root_edges,
                        'unpainted'   => root_nil,
                        'red_edges'   => root_mats[NA_RED_EDGE_MATERIAL].to_i,
                        'materials'   => na_sorted_tally(root_mats)
                    }
                end
            end

            targets.each do |inst|
                na_walk_instance(inst, '', 0, max_depth, include_hidden, include_soft, seen_defs, rows)
            end

            summary_data = Na__Handlers__EdgeAudit__SummarizeTallies(rows, only_issues: only_issues, limit: limit)
            summary_data['scope'] = Na__Params.Na__Params__Has(params, 'ids') ?
                                        "#{targets.length} target(s)" : 'entire model'
            summary_data
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Pure Tally & Gate Summary (tested offline in Tests__BridgeCore)
# -----------------------------------------------------------------------------

        def self.Na__Handlers__EdgeAudit__SummarizeTallies(rows, only_issues: false, limit: NA_DEFAULT_LIMIT)
            total_edges     = 0
            unpainted_edges = 0
            red_edges       = 0
            all_mats        = Hash.new(0)
            issue_groups    = []

            rows.each do |row|
                total_edges     += row['edges'].to_i
                unpainted_edges += row['unpainted'].to_i
                red_edges       += row['red_edges'].to_i
                (row['materials'] || {}).each { |mat, cnt| all_mats[mat] += cnt.to_i }
                if row['unpainted'].to_i > 0 || row['red_edges'].to_i > 0
                    issue_groups << row
                end
            end

            shown = only_issues ? issue_groups : rows
            truncated = shown.length > limit
            shown_capped = shown.first(limit)
            clean = unpainted_edges.zero? && red_edges.zero?

            sorted_mats = na_sorted_tally(all_mats)
            summary = if clean
                          top = sorted_mats.first(4).map { |k, v| "#{k}: #{v}" }.join(', ')
                          "Clean: #{total_edges} edges across #{rows.length} group(s), 0 unpainted, 0 red helper edges#{top.empty? ? '' : " (#{top})"}."
                      else
                          offenders = issue_groups.first(5).map { |r| "#{r['name']}: #{r['unpainted']} NIL#{r['red_edges'].to_i > 0 ? ", #{r['red_edges']} red" : ''}" }.join('; ')
                          "FAIL: #{unpainted_edges} unpainted edge(s), #{red_edges} red edge(s) across #{issue_groups.length} of #{rows.length} group(s) (#{offenders})."
                      end

            {
                'clean'              => clean,
                'total_edges'        => total_edges,
                'unpainted_edges'    => unpainted_edges,
                'red_edges'          => red_edges,
                'groups_audited'     => rows.length,
                'groups_with_issues' => issue_groups.length,
                'materials'          => sorted_mats,
                'groups'             => shown_capped,
                'truncated'          => truncated,
                'summary'            => summary
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Traversal Helpers
# -----------------------------------------------------------------------------

        def self.na_walk_instance(inst, prefix, depth, max_depth, include_hidden, include_soft, seen_defs, rows)
            return unless inst && inst.valid?
            return if !include_hidden && !na_entity_shown?(inst)

            defn = inst.definition
            return unless defn

            display = inst.name.to_s.empty? ? defn.name.to_s : inst.name.to_s
            path    = prefix.empty? ? display : "#{prefix} > #{display}"
            tag     = Na__EntityResolver.Na__EntityResolver__TagDisplayName(inst.layer)

            # Deduplicate shared definitions so each unique definition is tallied once.
            return if seen_defs[defn]

            seen_defs[defn] = true

            edge_count = 0
            nil_count  = 0
            red_count  = 0
            mats       = Hash.new(0)
            is_origin_helper = tag.start_with?(NA_HELPER_TAG_PREFIX) || display.start_with?(NA_HELPER_TAG_PREFIX)

            defn.entities.grep(Sketchup::Edge).each do |edge|
                next if !include_hidden && !na_entity_shown?(edge)
                next if !include_soft && (edge.soft? || edge.smooth?)

                key = edge.material ? edge.material.name : NA_UNPAINTED_KEY
                edge_count += 1
                nil_count  += 1 if key == NA_UNPAINTED_KEY
                red_count  += 1 if key == NA_RED_EDGE_MATERIAL && !is_origin_helper
                mats[key]  += 1
            end

            if edge_count > 0
                rows << {
                    'id'          => inst.persistent_id,
                    'name'        => display,
                    'definition'  => defn.name.to_s,
                    'path'        => path,
                    'tag'         => tag,
                    'copies'      => defn.instances.length,
                    'edges'       => edge_count,
                    'unpainted'   => nil_count,
                    'red_edges'   => red_count,
                    'materials'   => na_sorted_tally(mats)
                }
            end

            return if depth >= max_depth

            defn.entities.each do |child|
                next unless Na__EntityResolver.Na__EntityResolver__IsInstance(child)

                na_walk_instance(child, path, depth + 1, max_depth, include_hidden, include_soft, seen_defs, rows)
            end
        end
        private_class_method :na_walk_instance

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

        def self.na_sorted_tally(counts)
            counts.sort_by { |k, v| [-v, k] }.to_h
        end
        private_class_method :na_sorted_tally

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__EdgeAudit
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
