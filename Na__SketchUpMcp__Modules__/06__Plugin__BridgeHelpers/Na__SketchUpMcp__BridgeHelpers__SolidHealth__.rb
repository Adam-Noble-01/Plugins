# =============================================================================
# NA SKETCHUP MCP - BRIDGE HELPERS - SOLID HEALTH
# =============================================================================
#
# FILE       : Na__SketchUpMcp__BridgeHelpers__SolidHealth__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__SolidHealth
# PURPOSE    : Keep solids healthy before SketchUp's solid engine sees them:
#              faces oriented consistently and outward, and a plain-words account
#              of why a group or component is not a solid
# CREATED    : 2026
#
# WHY (30-Sep-2026, Adam's MCP__Testing__ activity log):
# Solid Tools only work on closed shells whose faces all point out. One subtract
# on a dense curved mesh ran 29 s and returned nothing. Another left a result
# with holes, and the next boolean refused it with a bare "Not a solid". Agents
# build meshes point by point and easily wind a polygon the wrong way. So:
#   - geometry_create_mesh orients every shell consistently: a shared edge must
#     run opposite ways in its two faces (Edge#reversed_in?), SketchUp's own
#     Orient Faces rule. It then turns closed shells outward;
#   - solid_boolean explains a non-solid in counts (open edges = holes, edges
#     on three or more faces = internal faces) instead of naming an id.
#
# SIGNED VOLUME:
# For planar faces V = sum(d * area) / 3 with d = normal . (any point on the
# face): the divergence theorem, x . n being constant across a planar face. V is
# positive when the fronts face out. Normals and positions come from the same
# frame, so the sign does not depend on that frame, and nothing relies on how
# SketchUp signs Group#volume.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__SolidHealth

# -----------------------------------------------------------------------------
# REGION | Orientation
# -----------------------------------------------------------------------------

        # Orients each connected shell of faces like its first face, then turns closed shells
        # outward. Returns counts for the tool result.
        def self.Na__SolidHealth__OrientShells(faces)
            report = { 'shells' => 0, 'closed_shells' => 0, 'faces_flipped' => 0, 'shells_turned_outward' => 0 }
            visited = {}
            faces.each do |seed|
                next unless seed.valid? && !visited[seed.entityID]

                shell, closed = na_orient_shell(seed, visited, report)
                report['shells'] += 1
                next unless closed

                report['closed_shells'] += 1
                next unless self.Na__SolidHealth__SignedVolume(shell) < 0.0

                shell.each(&:reverse!)
                report['shells_turned_outward'] += 1
            end
            report
        end

        # Breadth-first over edges shared by exactly two faces. Returns [faces, closed?].
        def self.na_orient_shell(seed, visited, report)
            visited[seed.entityID] = true
            shell = [seed]
            queue = [seed]
            closed = true
            until queue.empty?
                face = queue.shift
                face.edges.each do |edge|
                    neighbours = edge.faces
                    unless neighbours.length == 2
                        closed = false
                        next
                    end

                    other = neighbours[0].entityID == face.entityID ? neighbours[1] : neighbours[0]
                    next if visited[other.entityID]

                    if edge.reversed_in?(face) == edge.reversed_in?(other)
                        other.reverse!
                        report['faces_flipped'] += 1
                    end
                    visited[other.entityID] = true
                    shell << other
                    queue << other
                end
            end
            [shell, closed]
        end

        # Signed volume (cubic inches) enclosed by planar faces; positive when they face out.
        def self.Na__SolidHealth__SignedVolume(faces)
            faces.sum(0.0) do |face|
                normal = face.normal
                point = face.vertices.first.position
                ((normal.x * point.x) + (normal.y * point.y) + (normal.z * point.z)) * face.area / 3.0
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Diagnosis
# -----------------------------------------------------------------------------

        # What stops a group/component being a solid, counted over its own definition.
        def self.Na__SolidHealth__Problems(instance)
            entities = instance.definition.entities
            edges = entities.grep(Sketchup::Edge)
            faces = entities.grep(Sketchup::Face)
            {
                'faces'          => faces.length,
                'open_edges'     => edges.count { |edge| edge.faces.length == 1 },
                'internal_edges' => edges.count { |edge| edge.faces.length > 2 },
                'stray_edges'    => edges.count { |edge| edge.faces.empty? },
                'nested'         => entities.count { |entity| Na__EntityResolver.Na__EntityResolver__IsInstance(entity) },
                'inside_out'     => !faces.empty? && instance.manifold? && self.Na__SolidHealth__SignedVolume(faces) <= 0.0
            }
        end

        # One sentence an agent can act on, e.g.
        # "id 812 (Scroll Corbel) has 14 open edges (holes) and 3 edges on three or more faces (internal faces)".
        def self.Na__SolidHealth__Describe(instance, problems = nil)
            problems ||= self.Na__SolidHealth__Problems(instance)
            parts = []
            parts << na_count(problems['open_edges'], 'open edge', 'open edges') + ' (holes)' if problems['open_edges'] > 0
            parts << na_count(problems['internal_edges'], 'edge', 'edges') + ' on three or more faces (internal faces)' if problems['internal_edges'] > 0
            parts << na_count(problems['stray_edges'], 'stray edge', 'stray edges') + ' touching no face' if problems['stray_edges'] > 0
            parts << na_count(problems['nested'], 'nested group/component', 'nested groups/components') + ' inside it' if problems['nested'] > 0
            parts << 'its faces pointing inward (inside out)' if problems['inside_out']
            parts << 'no problem visible in its own faces and edges' if parts.empty?
            name = Na__EntityResolver.Na__EntityResolver__DisplayName(instance).to_s
            label = name.empty? ? '' : " (#{name})"
            "id #{instance.persistent_id}#{label} has #{parts.join(', ')}"
        end

        def self.Na__SolidHealth__FaceCount(instance)
            instance.definition.entities.grep(Sketchup::Face).length
        end

        def self.na_count(number, singular, plural)
            "#{number} #{number == 1 ? singular : plural}"
        end

# endregion -------------------------------------------------------------------

    end # module Na__SolidHealth
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
