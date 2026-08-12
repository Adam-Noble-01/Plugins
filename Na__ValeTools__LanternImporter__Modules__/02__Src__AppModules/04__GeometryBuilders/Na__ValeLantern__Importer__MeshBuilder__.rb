# =============================================================================
# VALE LANTERN IMPORTER - MESH BUILDER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__MeshBuilder__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__MeshBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Turn a payload mesh definition into a SketchUp ComponentDefinition
#              and place instances of it.
#
# DESCRIPTION:
# - Components are the only things in a lantern that are not a swept section. A
#   finial arrives as the authored mesh from the asset library: a vertex table
#   and a list of face loops referencing it.
# - The loops are carried through AS loops rather than as triangles. SketchUp
#   then builds real n-gon faces with real inner loops, which is the difference
#   between a finial somebody can push-pull and a triangle soup they can only
#   look at.
# - One definition per asset, however many anchors it is placed at, so the
#   finials on a roof stay linked and count properly in the component browser.
#
# -----------------------------------------------------------------------------
#
# WHY THE DEFINITION IS BUILT ONCE AND CACHED BY KEY:
#
# A ball finial is nine hundred vertices and six hundred faces. Building it per
# anchor would be the same work two, four or eight times over, and would leave
# SketchUp holding several unrelated copies of the same object. Building it once
# into a definition and adding instances costs one transformation per anchor.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__MeshBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and State
# -----------------------------------------------------------------------------

            DebugTools      = Na__ValeLantern::Na__Importer::Na__DebugTools
            Units           = Na__ValeLantern::Na__Importer::Na__Units
            TagManager      = Na__ValeLantern::Na__Importer::Na__TagManager
            MaterialManager = Na__ValeLantern::Na__Importer::Na__MaterialManager
            DataLibBridge   = Na__ValeLantern::Na__Importer::Na__DataLibBridge

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze
            NA_MIN_LOOP_POINTS      = 3
            NA_POINT_MERGE_INCH     = 0.0005
            NA_EDGE_KEY_DP          = 4                                                                 # <-- 1e-4 inch, about 0.0025mm

            @na_definitions_by_key = {}                                                             # <-- Payload key, Sketchup::ComponentDefinition out

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definition Preparation — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Build every definition the payload declares
            # ------------------------------------------------------------
            # Run before any instance is placed, so an instance can never be the
            # thing that discovers its definition is missing.
            #
            # @param definition_table [Array<Hash>] The payload's Model.Definitions array
            # @return [Integer] How many definitions are now available by key
            def self.na_prepare_definitions(definition_table)
                @na_definitions_by_key = {}
                return 0 unless definition_table.is_a?(Array)

                model = Sketchup.active_model
                return 0 unless model

                definition_table.each do |entry|
                    next unless entry.is_a?(Hash)

                    key = entry['Key']
                    next if key.nil?

                    definition = na_build_definition(model, entry)
                    @na_definitions_by_key[key.to_s] = definition if definition
                end

                DebugTools.na_info("Component definitions prepared: #{@na_definitions_by_key.length}")
                @na_definitions_by_key.length
            end
            # ---------------------------------------------------------------

            # FUNCTION | The definition registered against one payload key
            # ------------------------------------------------------------
            def self.na_definition_for_key(key)
                return nil if key.nil?
                @na_definitions_by_key[key.to_s]
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Instance Placement — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Place one instance part into a parent entities collection
            # ------------------------------------------------------------
            # @param parent_entities [Sketchup::Entities] Where the instance is placed
            # @param part [Hash] One payload part record of Kind 'instance'
            # @return [Sketchup::ComponentInstance, nil]
            def self.na_place_instance(parent_entities, part)
                part_name  = part['Name'].to_s
                definition = na_definition_for_key(part['DefinitionKey'])

                unless definition
                    DebugTools.na_record_failure(part_name, "definition '#{part['DefinitionKey']}' was not built")
                    return nil
                end

                transformation = na_build_transformation(part['Transform'])
                unless transformation
                    DebugTools.na_record_failure(part_name, 'transform is malformed')
                    return nil
                end

                instance      = parent_entities.add_instance(definition, transformation)
                instance.name = part_name

                TagManager.na_apply_tag(instance, part['TagKey'])
                MaterialManager.na_apply_material(instance, part['MaterialKey'])
                na_stamp_attributes(instance, part['Attributes'])

                DebugTools.na_detail("Placed instance '#{part_name}'")
                DebugTools.na_count('Component instances')
                instance

            rescue StandardError => e
                DebugTools.na_record_failure(part['Name'].to_s, "#{e.class}: #{e.message}")
                nil
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Definition Construction
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Build one component definition from a mesh entry
            # ------------------------------------------------------------
            # A definition name that already exists in the model is reused rather
            # than duplicated, so importing a second lantern with the same finial
            # adds instances of the definition already there.
            def self.na_build_definition(model, entry)
                name = entry['Name'].to_s
                name = entry['AssetId'].to_s if name.empty?
                return nil if name.empty?

                existing = model.definitions[name]
                if existing
                    DebugTools.na_detail("Reusing existing definition '#{name}'")
                    return existing
                end

                vertices = na_convert_vertices(entry['Vertices'])
                faces    = entry['Faces']

                if vertices.empty? || !faces.is_a?(Array) || faces.empty?
                    DebugTools.na_warn("Definition '#{name}' carries no usable mesh - skipped.")
                    return nil
                end

                definition = model.definitions.add(name)
                built      = na_build_faces(definition.entities, vertices, faces, name)

                if built.zero?
                    DebugTools.na_warn("Definition '#{name}' built no faces - removed.")
                    model.definitions.remove(definition) if model.definitions.respond_to?(:remove)
                    return nil
                end

                styled = na_apply_edge_styles(definition.entities, vertices, entry['Edges'], name)

                definition.set_attribute(NA_ATTRIBUTE_DICTIONARY, 'AssetId', entry['AssetId'].to_s)
                DebugTools.na_detail("Built definition '#{name}' (#{built} faces, #{styled} edges styled)")
                DebugTools.na_count('Component definitions')
                definition
            end
            private_class_method :na_build_definition

            # HELPER FUNCTION | Convert the payload vertex table to Geom::Point3d
            # ------------------------------------------------------------
            def self.na_convert_vertices(raw_vertices)
                return [] unless raw_vertices.is_a?(Array)
                raw_vertices.map { |triple| Units.na_point(triple) }.compact
            end
            private_class_method :na_convert_vertices

            # HELPER FUNCTION | Build every face loop into the definition entities
            # ------------------------------------------------------------
            # Inner loops are punched the same way a prism's holes are: add the
            # loop as a face, then erase that face, which leaves the loop behind
            # as a hole in the outer face it sits inside.
            def self.na_build_faces(entities, vertices, faces, definition_name)
                built   = 0
                skipped = 0

                faces.each do |face_entry|
                    next unless face_entry.is_a?(Hash)

                    outer = na_loop_points(vertices, face_entry['Outer'])
                    if outer.length < NA_MIN_LOOP_POINTS
                        skipped += 1
                        next
                    end

                    begin
                        face = entities.add_face(outer)
                        next if face.nil?
                        built += 1

                        # An author who hid this face in the source component
                        # meant it. Rebuild it either way - it is still part of
                        # the solid - then put the hide back.
                        face.hidden = true if face_entry['Hidden'] && face.valid?

                        inner_loops = face_entry['Inner']
                        next unless inner_loops.is_a?(Array)

                        inner_loops.each do |inner_indices|
                            hole_points = na_loop_points(vertices, inner_indices)
                            next if hole_points.length < NA_MIN_LOOP_POINTS

                            hole_face = entities.add_face(hole_points)
                            next if hole_face.nil? || hole_face == face
                            hole_face.erase! if hole_face.valid?
                        end

                    rescue StandardError => e
                        skipped += 1
                        DebugTools.na_detail("Face refused in '#{definition_name}': #{e.message}")
                    end
                end

                if skipped > 0
                    DebugTools.na_warn("Definition '#{definition_name}': #{skipped} face(s) refused.")
                end

                built
            end
            private_class_method :na_build_faces

            # HELPER FUNCTION | Resolve one index loop to deduplicated points
            # ------------------------------------------------------------
            def self.na_loop_points(vertices, indices)
                return [] unless indices.is_a?(Array)

                points  = []
                indices.each do |index|
                    point = vertices[index.to_i]
                    next if point.nil?

                    previous = points.last
                    next if previous && previous.distance(point) < NA_POINT_MERGE_INCH
                    points << point
                end

                if points.length >= 2 && points.first.distance(points.last) < NA_POINT_MERGE_INCH
                    points.pop
                end

                points
            end
            private_class_method :na_loop_points

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Authored Edge Style Restoration
# -----------------------------------------------------------------------------
#
# WHY THIS EXISTS AT ALL
#
# add_face gives every edge SketchUp's defaults: visible, hard, unpainted. A
# lathed finial rebuilt that way is a black wireframe of every tessellation
# segment, and the only fix used to be a softening pass with an angle
# threshold. A threshold cannot tell a deliberately hidden edge from a shallow
# one, and it has no opinion at all about edge colour. So the author's actual
# choices are carried through the payload and replayed here.
#
# THE THREE FLAGS ARE NOT INTERCHANGEABLE (SketchUp's own definitions)
#
#   soft     edge is not drawn AND its two faces merge into a Surface entity.
#            Does not by itself change shading.
#   smooth   the shading blends across the edge. ON ITS OWN THE EDGE STAYS
#            VISIBLE - SketchUp only hides it as well because the Soften/Smooth
#            slider sets soft and smooth together.
#   hidden   Edit > Hide. Not drawn, no surface merge, shading unchanged.
#
# All three are replayed independently rather than collapsed into one "soften"
# call, because collapsing them is exactly the loss this work set out to fix.
#
# MATCHING PAYLOAD EDGES TO BUILT EDGES
#
# The payload numbers its edges against the same vertex table the faces were
# built from, but SketchUp decides for itself which edges exist - it merges
# coincident geometry and can split an edge that another vertex lands on. So
# rather than trusting a built order, every edge in the definition is looked
# up by the rounded positions of its two ends. An edge the payload does not
# describe simply keeps SketchUp's defaults, which is the safe direction to
# fail in.
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Replay the authored soft / smooth / hidden / colour state
            # ------------------------------------------------------------
            # @param entities   [Sketchup::Entities]  The definition's entities
            # @param vertices   [Array<Geom::Point3d>] Same table the faces used
            # @param raw_edges  [Array<Hash>]         Payload Edges array
            # @return [Integer] How many edges were matched and styled
            def self.na_apply_edge_styles(entities, vertices, raw_edges, definition_name)
                return 0 unless raw_edges.is_a?(Array) && !raw_edges.empty?

                position_index = na_build_position_index(vertices)
                return 0 if position_index.empty?

                style_by_pair = {}
                raw_edges.each do |record|
                    next unless record.is_a?(Hash)
                    index_a = record['A']
                    index_b = record['B']
                    next if index_a.nil? || index_b.nil?
                    style_by_pair[[index_a.to_i, index_b.to_i].sort] = record
                end
                return 0 if style_by_pair.empty?

                model   = Sketchup.active_model
                styled  = 0
                unknown = 0

                entities.grep(Sketchup::Edge).each do |edge|
                    next unless edge.valid?

                    index_a = position_index[na_position_key(edge.start.position)]
                    index_b = position_index[na_position_key(edge.end.position)]
                    if index_a.nil? || index_b.nil?
                        unknown += 1
                        next
                    end

                    record = style_by_pair[[index_a, index_b].sort]
                    if record.nil?
                        unknown += 1
                        next
                    end

                    styled += 1 if na_style_one_edge(model, edge, record)
                end

                if unknown > 0
                    DebugTools.na_detail(
                        "Definition '#{definition_name}': #{unknown} edge(s) had no authored style and kept SketchUp defaults."
                    )
                end

                styled
            rescue StandardError => e
                DebugTools.na_warn("Edge styling refused for '#{definition_name}': #{e.class}: #{e.message}")
                0
            end
            private_class_method :na_apply_edge_styles

            # HELPER FUNCTION | Apply one payload style record to one edge
            # ------------------------------------------------------------
            # smooth is set before soft, and hidden last. The three are separate
            # flags in SketchUp, but writing hidden last means that if a future
            # SketchUp ever did couple them, the author's explicit hide is the
            # one that survives.
            def self.na_style_one_edge(model, edge, record)
                edge.smooth = !!record['Smooth'] if record.key?('Smooth')
                edge.soft   = !!record['Soft']   if record.key?('Soft')
                edge.hidden = !!record['Hidden'] if record.key?('Hidden')

                if record.key?('CastsShadows') && edge.respond_to?(:casts_shadows=)
                    edge.casts_shadows = !!record['CastsShadows']
                end

                material = na_edge_material_from_record(model, record)
                edge.material = material if material

                true
            rescue StandardError => e
                DebugTools.na_detail("Edge style refused: #{e.message}")
                false
            end
            private_class_method :na_style_one_edge

            # HELPER FUNCTION | Resolve the material an authored edge colour asks for
            # ------------------------------------------------------------
            # The MTE library is asked first, so an imported red datum line is the
            # same material object as one painted by the rest of the toolchain and
            # stays recognisable to Na__EdgeUtil__PaintDeepNestedEdges. Only when
            # DataLib cannot answer is a plain material created from the exported
            # hex, so a colour authored outside the library is still not lost.
            #
            # An edge with no authored material returns nil and is left unpainted,
            # rather than forced to black - unpainted is what SketchUp itself
            # calls an untinted edge, and it keeps Color By Tag working.
            def self.na_edge_material_from_record(model, record)
                return nil unless model
                return nil unless record['HasOwnMaterial']

                style_key = record['MaterialName'].to_s
                unless style_key.empty?
                    material = DataLibBridge.na_edge_material_for(model, style_key)
                    return material if material
                end

                na_material_from_hex(model, style_key, record['ColorHex'])
            rescue StandardError => e
                DebugTools.na_detail("Edge material refused: #{e.message}")
                nil
            end
            private_class_method :na_edge_material_from_record

            # HELPER FUNCTION | Create or reuse a plain material for a hex colour
            # ------------------------------------------------------------
            def self.na_material_from_hex(model, preferred_name, hex_value)
                hex = hex_value.to_s.strip
                return nil unless hex =~ /\A#?[0-9A-Fa-f]{6}\z/

                hex   = hex.sub(/\A#/, '')
                red   = hex[0, 2].to_i(16)
                green = hex[2, 2].to_i(16)
                blue  = hex[4, 2].to_i(16)

                name = preferred_name.to_s.empty? ? "Na__EdgeColour__##{hex.upcase}" : preferred_name.to_s
                existing = model.materials[name]
                return existing if existing

                material       = model.materials.add(name)
                material.color = Sketchup::Color.new(red, green, blue)
                material
            rescue StandardError => e
                DebugTools.na_detail("Edge colour material refused: #{e.message}")
                nil
            end
            private_class_method :na_material_from_hex

            # HELPER FUNCTION | Index the vertex table by rounded position
            # ------------------------------------------------------------
            def self.na_build_position_index(vertices)
                index = {}
                vertices.each_with_index do |point, position|
                    next if point.nil?
                    key = na_position_key(point)
                    index[key] = position unless index.key?(key)
                end
                index
            end
            private_class_method :na_build_position_index

            # HELPER FUNCTION | Rounded position key for vertex matching
            # ------------------------------------------------------------
            def self.na_position_key(point)
                "#{point.x.to_f.round(NA_EDGE_KEY_DP)}|" \
                "#{point.y.to_f.round(NA_EDGE_KEY_DP)}|" \
                "#{point.z.to_f.round(NA_EDGE_KEY_DP)}"
            end
            private_class_method :na_position_key

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Transform Construction
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Build a transformation from an origin and three axes
            # ------------------------------------------------------------
            # Axes rather than a rotation angle, because a component standing on a
            # hip has no single angle that describes it. Geom::Transformation.axes
            # takes the frame directly and never has to be told a rotation order.
            def self.na_build_transformation(transform)
                return nil unless transform.is_a?(Hash)

                origin = Units.na_point(transform['Origin'])
                x_axis = Units.na_vector(transform['XAxis'])
                y_axis = Units.na_vector(transform['YAxis'])
                z_axis = Units.na_vector(transform['ZAxis'])
                return nil if origin.nil? || x_axis.nil? || y_axis.nil? || z_axis.nil?

                placement = Geom::Transformation.axes(origin, x_axis, y_axis, z_axis)

                scale = transform['ScaleFactor']
                return placement unless scale.is_a?(Numeric) && (scale.to_f - 1.0).abs > 1e-9

                placement * Geom::Transformation.scaling(scale.to_f)
            rescue StandardError => e
                DebugTools.na_detail("Transform refused: #{e.message}")
                nil
            end
            private_class_method :na_build_transformation

            # HELPER FUNCTION | Stamp the payload attributes onto an instance
            # ------------------------------------------------------------
            def self.na_stamp_attributes(entity, attributes)
                return unless attributes.is_a?(Hash)

                attributes.each do |key, value|
                    next if value.nil?
                    begin
                        entity.set_attribute(NA_ATTRIBUTE_DICTIONARY, key.to_s, value)
                    rescue StandardError => e
                        DebugTools.na_detail("Attribute '#{key}' refused: #{e.message}")
                    end
                end
            end
            private_class_method :na_stamp_attributes

# endregion -------------------------------------------------------------------

        end
    end
end
