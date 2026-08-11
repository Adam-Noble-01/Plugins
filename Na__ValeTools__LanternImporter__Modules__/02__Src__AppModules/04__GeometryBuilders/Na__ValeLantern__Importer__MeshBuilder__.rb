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

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze
            NA_MIN_LOOP_POINTS      = 3
            NA_POINT_MERGE_INCH     = 0.0005

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

                definition.set_attribute(NA_ATTRIBUTE_DICTIONARY, 'AssetId', entry['AssetId'].to_s)
                DebugTools.na_detail("Built definition '#{name}' (#{built} faces)")
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
