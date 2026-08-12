# =============================================================================
# VALE LANTERN IMPORTER - PRISM BUILDER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__PrismBuilder__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__PrismBuilder
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Build one payload prism into a named SketchUp component instance.
#
# DESCRIPTION:
# - Every solid in a Vale lantern arrives as the same shape: two rings of
#   millimetre points, plus the ring spans saying which run of each is an outer
#   loop and which is a hole. A glaze bar, a mitred head beam, a hollow builders
#   upstand and a pane of glass are all that shape, so this is the only solid
#   builder the importer has.
# - No geometry is computed here. Every mitre, plumb cut and eaves extension was
#   applied by the web application's geometry brain before the file was written.
#   This file turns point lists into faces and nothing else.
#
# -----------------------------------------------------------------------------
#
# BUILD ORDER, AND WHY IT IS WALLS FIRST:
#
#   1  WALLS   one quad per section edge, both rings, in the order the payload
#              gives them. The section winding is normalised upstream — outer
#              loops counter clockwise, holes clockwise — which is what makes
#              this quad order face outward on the holes as well as the outside.
#
#   2  CAPS    the outer loop at each end. Adding these AFTER the walls means
#              the hole loops already exist as edges in the cap plane, so
#              SketchUp usually recognises them as inner loops on its own. Where
#              it does not, the hole face is added and immediately erased, which
#              leaves the loop behind as a hole because the wall faces still
#              need its edges.
#
#   3  CLEAN   coplanar edges between two faces are erased, merging them. An
#              extruded aluminium section has long flat faces crossed by a
#              vertex every few millimetres, and without this pass every one of
#              those vertices leaves a line down the middle of a flat surface.
#
#   4  ORIENT  the signed volume of the finished shell decides whether the whole
#              thing came out inside in, and every face is reversed if it did.
#
#   5  SOFTEN  the shallow edges LEFT OVER after the merge - the facet boundaries
#              of a crown, a rolled edge, a cornice curve - are softened and
#              smoothed from the plugin config's per family rule. Last, because
#              it depends on both the passes before it: the merge must already
#              have erased the flats, and the orientation pass is what makes the
#              angle between two normals mean the real dihedral. See
#              Na__EdgeSoftener for the full argument.
#
# -----------------------------------------------------------------------------
#
# WHY SIGNED VOLUME RATHER THAN THE CENTROID TEST:
#
# The usual trick — compare each face normal against the vector from the lump
# centre to the face centre — is correct only on a convex solid. A cornice, a
# glaze bar trim and a lead flashing are all emphatically not convex, and on
# those the test reverses faces that were already right. Summing the signed
# volume over the triangulation reads the shell as a whole and is exact for any
# closed shape, concave or not, at the cost of one pass over the faces.
#
# -----------------------------------------------------------------------------
#
# WHY A COMPONENT INSTANCE AND NOT A GROUP, AND WHY LOCAL COORDINATES:
#
# A part is built into a ComponentDefinition and placed as an instance, so that
# four hip beams at four corners can be four placements of ONE definition rather
# than four copies of the same faces. A group cannot do that: SketchUp makes a
# copied group unique the moment anybody edits it.
#
# Sharing forces the geometry into LOCAL coordinates. The payload gives finished
# world positions, so two hip beams share not one coordinate and cannot be
# recognised as the same shape until both are expressed in a frame derived from
# their own points. Na__DefinitionRegistry owns that derivation and the matching;
# this file only asks it two questions, and builds the points it is handed back.
#
# The local frame has a second dividend that has nothing to do with sharing: a
# component whose geometry sits at its own origin has its axes ON the part rather
# than at the model origin a few metres away, which is what makes Entity Info's
# dimensions and the Move tool's inferences read sensibly on a selected member.
#
# A part whose points are collinear or degenerate yields no frame. Those build in
# world coordinates at an identity transform and never share, which is exactly
# how the importer behaved before definitions were shared at all.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__PrismBuilder

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools         = Na__ValeLantern::Na__Importer::Na__DebugTools
            Units              = Na__ValeLantern::Na__Importer::Na__Units
            TagManager         = Na__ValeLantern::Na__Importer::Na__TagManager
            MaterialManager    = Na__ValeLantern::Na__Importer::Na__MaterialManager
            ConfigLoader       = Na__ValeLantern::Na__Importer::Na__ConfigLoader
            EdgeSoftener       = Na__ValeLantern::Na__Importer::Na__EdgeSoftener
            DefinitionRegistry = Na__ValeLantern::Na__Importer::Na__DefinitionRegistry

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze                                           # <-- Where part attributes land on every instance
            NA_MIN_RING_POINTS      = 3                                                             # <-- Below this there is no loop
            NA_COPLANAR_DOT_LIMIT   = 0.9999                                                        # <-- Two normals above this are the same plane
            NA_POINT_MERGE_INCH     = 0.0005                                                        # <-- Below SketchUp's own tolerance; duplicate points

            NA_COUNT_PRISM          = 'Prisms'.freeze
            NA_COUNT_SHARED         = 'Prisms (shared definition)'.freeze
            NA_COUNT_MIRRORED       = 'Prisms (shared, mirrored)'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Prism Construction — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Build one prism part into a named component instance
            # ------------------------------------------------------------
            # @param parent_entities [Sketchup::Entities] Where the part is created
            # @param part [Hash] One payload part record of Kind 'prism'
            # @param options [Hash] The payload's Model.Options block
            # @return [Sketchup::ComponentInstance, Sketchup::Group, nil]
            #         The finished part, or nil on refusal
            def self.na_build_prism(parent_entities, part, options)
                part_name = part['Name'].to_s

                rings    = part['Rings']
                points_a = na_convert_points(part['PointsA'])
                points_b = na_convert_points(part['PointsB'])

                return nil unless na_prism_is_sane?(rings, points_a, points_b, part_name)

                if ConfigLoader.na_container_is_component?(:Part)
                    na_build_as_component(parent_entities, part, options, rings, points_a, points_b)
                else
                    na_build_as_group(parent_entities, part, options, rings, points_a, points_b)
                end
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Component Path
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Build or reuse a definition and place one instance
            # ------------------------------------------------------------
            # Three outcomes, in the order they are tried:
            #
            #   SHARE   the registry recognises the shape - a hip beam whose three
            #           siblings are already built - and one add_instance is the
            #           whole cost of this part.
            #   BUILD   the shape is new. A definition is created, the geometry
            #           built into it in local coordinates, cleaned, oriented and
            #           softened, then registered so the siblings can share it.
            #   REFUSE  the definition could not be made or produced no walls. The
            #           definition is discarded so nothing empty is left in the
            #           Component browser, and the part is named in the report.
            def self.na_build_as_component(parent_entities, part, options, rings, points_a, points_b)
                part_name  = part['Name'].to_s
                definition = nil                                                                    # <-- Declared up here so the rescue below can see them
                instance   = nil
                model      = Sketchup.active_model
                return nil unless model

                placement = na_resolve_placement(part['TagKey'], rings, points_a, points_b)

                existing = DefinitionRegistry.na_lookup(placement[:Signature], placement[:MirrorSignature])
                if existing
                    return na_place_shared(parent_entities, part, part_name, placement, existing)
                end

                definition = DefinitionRegistry.na_create_part_definition(model, part['TagKey'], part_name)
                if definition.nil?
                    DebugTools.na_record_failure(part_name, 'no component definition could be created')
                    return nil
                end

                entities   = definition.entities
                wall_count = na_build_walls(entities, rings, placement[:LocalA], placement[:LocalB])
                if wall_count.zero?
                    DebugTools.na_record_failure(part_name, 'no wall face could be built')
                    DefinitionRegistry.na_discard_definition(model, definition)
                    return nil
                end

                na_build_caps(entities, rings, placement[:LocalA], placement[:LocalB])
                na_merge_coplanar_faces(entities) if options['MergeCoplanarFaces'] != false
                na_orient_outward(entities)       if options['OrientSolidsOutward'] != false
                EdgeSoftener.na_soften_for_tag(entities, part['TagKey'])

                instance = na_add_instance(parent_entities, definition, placement[:Frame])
                if instance.nil?
                    DebugTools.na_record_failure(part_name, 'the instance could not be placed')
                    DefinitionRegistry.na_discard_definition(model, definition)
                    return nil
                end

                DefinitionRegistry.na_register(placement[:Signature], definition)
                na_finish_instance(instance, part, part_name)

                if DebugTools.na_verbose?
                    DebugTools.na_detail(
                        "Built prism '#{part_name}' as '#{definition.name}' (#{entities.grep(Sketchup::Face).length} faces)"
                    )
                end                                                                                 # <-- Guarded: the face count is a walk, and this runs a few hundred times
                DebugTools.na_count(NA_COUNT_PRISM)
                instance

            rescue StandardError => e
                DebugTools.na_record_failure(part['Name'].to_s, "#{e.class}: #{e.message}")

                # A definition created but never placed is an empty entry in the
                # Component browser nobody asked for. Only discarded when no
                # instance got as far as being added - removing a definition that
                # HAS one would erase the instance along with it, and a part that
                # built and then failed to be painted is still a built part.
                #
                # A discarded definition that was already registered is safe: the
                # registry tests every hit for deletion before handing it back.
                if instance.nil? && definition
                    DefinitionRegistry.na_discard_definition(Sketchup.active_model, definition)
                end
                nil
            end
            private_class_method :na_build_as_component

            # HELPER FUNCTION | Place an instance of a definition already built
            # ------------------------------------------------------------
            # The whole point of the exercise: a hip beam whose three siblings are
            # already in the model costs one transformation and no geometry.
            def self.na_place_shared(parent_entities, part, part_name, placement, existing)
                transformation = DefinitionRegistry.na_placement(placement[:Frame], existing[:Mirrored])
                instance       = na_add_instance(parent_entities, existing[:Definition], transformation)

                if instance.nil?
                    DebugTools.na_record_failure(part_name, 'a shared instance could not be placed')
                    return nil
                end

                na_finish_instance(instance, part, part_name)

                DebugTools.na_detail(
                    "Shared '#{existing[:Definition].name}' for '#{part_name}'#{existing[:Mirrored] ? ' (mirrored)' : ''}"
                )
                DebugTools.na_count(existing[:Mirrored] ? NA_COUNT_MIRRORED : NA_COUNT_SHARED)
                instance
            end
            private_class_method :na_place_shared

            # HELPER FUNCTION | The local frame, local points and both signatures
            # ------------------------------------------------------------
            # Both rings are handed to the frame derivation as one list, in payload
            # order, so the frame depends only on the geometry and its indexing -
            # which is what makes two congruent parts derive the same one.
            #
            # A part that yields no frame falls back to world coordinates at an
            # identity transform with no signatures, so it builds correctly and
            # simply never shares.
            #
            # @return [Hash] { :Frame, :LocalA, :LocalB, :Signature, :MirrorSignature }
            def self.na_resolve_placement(tag_key, rings, points_a, points_b)
                combined = points_a + points_b
                frame    = DefinitionRegistry.na_local_frame(combined)

                if frame.nil?
                    DebugTools.na_detail('No local frame could be derived - building in world coordinates without sharing.')
                    return {
                        :Frame           => Geom::Transformation.new,
                        :LocalA          => points_a,
                        :LocalB          => points_b,
                        :Signature       => nil,
                        :MirrorSignature => nil
                    }
                end

                local = DefinitionRegistry.na_to_local(combined, frame)

                {
                    :Frame           => frame,
                    :LocalA          => local[0, points_a.length],
                    :LocalB          => local[points_a.length, points_b.length],
                    :Signature       => DefinitionRegistry.na_signature(tag_key, rings, local, false),
                    :MirrorSignature => DefinitionRegistry.na_signature(tag_key, rings, local, true)
                }
            end
            private_class_method :na_resolve_placement

            # HELPER FUNCTION | Add one instance, tolerating a refusal
            # ------------------------------------------------------------
            def self.na_add_instance(parent_entities, definition, transformation)
                parent_entities.add_instance(definition, transformation)
            rescue StandardError => e
                DebugTools.na_detail("Instance placement refused: #{e.message}")
                nil
            end
            private_class_method :na_add_instance

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Group Path
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Build one prism into a plain group
            # ------------------------------------------------------------
            # What the importer did before version 1.4.0, kept behind
            # Containers.PartAsComponent so a part that comes out wrong can be
            # rebuilt without the definition machinery in the way. World
            # coordinates and no sharing, exactly as before.
            def self.na_build_as_group(parent_entities, part, options, rings, points_a, points_b)
                part_name  = part['Name'].to_s

                group      = parent_entities.add_group
                group.name = part_name
                entities   = group.entities

                wall_count = na_build_walls(entities, rings, points_a, points_b)
                if wall_count.zero?
                    DebugTools.na_record_failure(part_name, 'no wall face could be built')
                    group.erase! if group.valid?
                    return nil
                end

                na_build_caps(entities, rings, points_a, points_b)
                na_merge_coplanar_faces(entities) if options['MergeCoplanarFaces'] != false
                na_orient_outward(entities)       if options['OrientSolidsOutward'] != false
                EdgeSoftener.na_soften_for_tag(entities, part['TagKey'])

                na_finish_instance(group, part, part_name)
                if DebugTools.na_verbose?
                    DebugTools.na_detail("Built prism '#{part_name}' (#{entities.grep(Sketchup::Face).length} faces)")
                end
                DebugTools.na_count(NA_COUNT_PRISM)
                group

            rescue StandardError => e
                DebugTools.na_record_failure(part['Name'].to_s, "#{e.class}: #{e.message}")
                group.erase! if defined?(group) && group && group.valid?
                nil
            end
            private_class_method :na_build_as_group

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Input Preparation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Convert a payload point array to Geom::Point3d
            # ------------------------------------------------------------
            def self.na_convert_points(raw_points)
                return [] unless raw_points.is_a?(Array)
                raw_points.map { |triple| Units.na_point(triple) }
            end
            private_class_method :na_convert_points

            # HELPER FUNCTION | Whether a prism record can be built at all
            # ------------------------------------------------------------
            # Checked once, up front, rather than discovered halfway through a
            # definition that would then have to be unwound.
            def self.na_prism_is_sane?(rings, points_a, points_b, part_name)
                unless rings.is_a?(Array) && !rings.empty?
                    DebugTools.na_record_failure(part_name, 'no ring spans')
                    return false
                end

                if points_a.length != points_b.length
                    DebugTools.na_record_failure(part_name, 'ring lengths disagree')
                    return false
                end

                if points_a.length < NA_MIN_RING_POINTS
                    DebugTools.na_record_failure(part_name, 'point list is short')
                    return false
                end

                if points_a.include?(nil) || points_b.include?(nil)
                    DebugTools.na_record_failure(part_name, 'point list is malformed')
                    return false
                end                                                                                 # <-- Both rings: a nil in either is a triple the payload wrote wrong

                true
            end
            private_class_method :na_prism_is_sane?

            # HELPER FUNCTION | The slice of a point list one ring span covers
            # ------------------------------------------------------------
            def self.na_ring_slice(points, ring)
                start = ring['Start'].to_i
                count = ring['Count'].to_i
                return [] if count < NA_MIN_RING_POINTS

                points[start, count] || []
            end
            private_class_method :na_ring_slice

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Wall and Cap Construction
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Raise one quad per section edge, both rings
            # ------------------------------------------------------------
            # A quad whose two ends have collapsed onto each other — which a deep
            # mitre can do to the outermost vertex of a section — degenerates to a
            # triangle rather than being dropped, because the hole it would leave
            # in the shell is worse than the extra triangle.
            def self.na_build_walls(entities, rings, points_a, points_b)
                built = 0

                rings.each do |ring|
                    start = ring['Start'].to_i
                    count = ring['Count'].to_i
                    next if count < NA_MIN_RING_POINTS

                    count.times do |k|
                        current_index = start + k
                        next_index    = start + ((k + 1) % count)

                        quad = na_dedupe_points([
                            points_a[current_index],
                            points_a[next_index],
                            points_b[next_index],
                            points_b[current_index]
                        ])
                        next if quad.length < NA_MIN_RING_POINTS

                        begin
                            face = entities.add_face(quad)
                            built += 1 if face
                        rescue StandardError => e
                            DebugTools.na_detail("Wall quad refused: #{e.message}")
                        end
                    end
                end

                built
            end
            private_class_method :na_build_walls

            # HELPER FUNCTION | Cap both ends over the outer ring, punching holes
            # ------------------------------------------------------------
            # The near cap is wound backwards from the far cap so both face away
            # from the solid. Where SketchUp has already found the hole loops on
            # its own, the punch pass finds the cap face returned for the hole
            # ring and leaves it alone rather than erasing the cap it just made.
            def self.na_build_caps(entities, rings, points_a, points_b)
                outer = rings.first

                far_cap  = na_add_cap(entities, na_ring_slice(points_b, outer))
                near_cap = na_add_cap(entities, na_ring_slice(points_a, outer).reverse)

                return if rings.length < 2

                rings[1..-1].each do |hole_ring|
                    na_punch_hole(entities, na_ring_slice(points_b, hole_ring), far_cap)
                    na_punch_hole(entities, na_ring_slice(points_a, hole_ring), near_cap)
                end
            end
            private_class_method :na_build_caps

            # HELPER FUNCTION | Add one cap face, tolerating a refusal
            # ------------------------------------------------------------
            def self.na_add_cap(entities, ring_points)
                points = na_dedupe_points(ring_points)
                return nil if points.length < NA_MIN_RING_POINTS

                entities.add_face(points)
            rescue StandardError => e
                DebugTools.na_detail("Cap face refused: #{e.message}")
                nil
            end
            private_class_method :na_add_cap

            # HELPER FUNCTION | Turn one hole ring into a hole in its cap
            # ------------------------------------------------------------
            def self.na_punch_hole(entities, ring_points, cap_face)
                points = na_dedupe_points(ring_points)
                return if points.length < NA_MIN_RING_POINTS

                hole_face = entities.add_face(points)
                return if hole_face.nil?
                return if cap_face && hole_face == cap_face                                         # <-- SketchUp already read it as an inner loop

                hole_face.erase! if hole_face.valid?
            rescue StandardError => e
                DebugTools.na_detail("Hole punch refused: #{e.message}")
            end
            private_class_method :na_punch_hole

            # HELPER FUNCTION | Drop consecutive points that have collapsed together
            # ------------------------------------------------------------
            # SketchUp merges points closer than its own tolerance, so a face
            # given a repeated point either raises or comes back with fewer
            # vertices than asked for. Removing them here keeps the failure
            # visible in this file rather than in the API's error message.
            def self.na_dedupe_points(points)
                cleaned = []

                points.each do |point|
                    next if point.nil?
                    previous = cleaned.last
                    next if previous && previous.distance(point) < NA_POINT_MERGE_INCH
                    cleaned << point
                end

                if cleaned.length >= 2 && cleaned.first.distance(cleaned.last) < NA_POINT_MERGE_INCH
                    cleaned.pop                                                                     # <-- The ring closes itself; a repeated last point is not an edge
                end

                cleaned
            end
            private_class_method :na_dedupe_points

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Cleanup and Orientation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Erase edges that divide two coplanar faces
            # ------------------------------------------------------------
            # The edge list is taken as a snapshot before anything is erased,
            # because erasing an edge merges its two faces and invalidates every
            # reference either of them held.
            def self.na_merge_coplanar_faces(entities)
                edges  = entities.grep(Sketchup::Edge)
                merged = 0

                edges.each do |edge|
                    next unless edge.valid?

                    faces = edge.faces
                    next unless faces.length == 2
                    next unless faces[0].valid? && faces[1].valid?
                    next unless na_normals_agree?(faces[0], faces[1])

                    edge.erase!
                    merged += 1
                end

                DebugTools.na_detail("Merged #{merged} coplanar edge(s)") if merged > 0
                merged
            end
            private_class_method :na_merge_coplanar_faces

            # HELPER FUNCTION | Whether two faces lie in the same plane, same way up
            # ------------------------------------------------------------
            def self.na_normals_agree?(face_a, face_b)
                dot = face_a.normal.dot(face_b.normal)
                dot > NA_COPLANAR_DOT_LIMIT
            rescue StandardError
                false
            end
            private_class_method :na_normals_agree?

            # HELPER FUNCTION | Reverse every face if the shell came out inside in
            # ------------------------------------------------------------
            # The signed volume of a closed shell is positive when its faces face
            # out and negative when they face in, whatever shape it is. A shell
            # that is not closed sums to something near zero and is left alone,
            # because reversing an open shell is as likely to be wrong as right.
            def self.na_orient_outward(entities)
                faces = entities.grep(Sketchup::Face)
                return 0 if faces.empty?

                volume = na_signed_volume(faces)
                return 0 if volume >= 0

                faces.each { |face| face.reverse! if face.valid? }
                DebugTools.na_detail('Solid was inside in - every face reversed')
                faces.length
            end
            private_class_method :na_orient_outward

            # HELPER FUNCTION | Signed volume of a face set, from its triangulation
            # ------------------------------------------------------------
            # Sum over every triangle of the scalar triple product of its three
            # vertices, divided by six. face.mesh triangulates in the face's own
            # front-face winding, so the sign that comes out IS the orientation.
            def self.na_signed_volume(faces)
                total = 0.0

                faces.each do |face|
                    next unless face.valid?

                    mesh = face.mesh
                    mesh.polygons.each do |polygon|
                        indices = polygon.map { |index| index.abs }
                        next if indices.length < 3

                        p1 = mesh.point_at(indices[0])
                        p2 = mesh.point_at(indices[1])
                        p3 = mesh.point_at(indices[2])

                        total += (p1.x * ((p2.y * p3.z) - (p3.y * p2.z))) \
                               - (p1.y * ((p2.x * p3.z) - (p3.x * p2.z))) \
                               + (p1.z * ((p2.x * p3.y) - (p3.x * p2.y)))
                    end
                end

                total / 6.0
            rescue StandardError => e
                DebugTools.na_detail("Signed volume could not be read: #{e.message}")
                0.0
            end
            private_class_method :na_signed_volume

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Instance Finishing
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Name, tag, paint and stamp a finished part
            # ------------------------------------------------------------
            # ALL THREE GO ON THE INSTANCE, NEVER ON THE SHARED DEFINITION. The
            # tag, the material and the attribute block are precisely what differs
            # between two placements of the same geometry - HipBeam__01 and
            # HipBeam__03 hold the same faces and different corner numbers - so
            # writing any of them to the definition would have the four hips
            # overwrite each other's identity and end up with the last one's.
            #
            # Attributes land in one dictionary named for the application, so a
            # downstream report can walk a model and pick out Vale lantern parts
            # without matching on names.
            def self.na_finish_instance(entity, part, part_name)
                entity.name = part_name if entity.respond_to?(:name=)

                TagManager.na_apply_tag(entity, part['TagKey'])
                MaterialManager.na_apply_material(entity, part['MaterialKey'])

                attributes = part['Attributes']
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
            private_class_method :na_finish_instance

# endregion -------------------------------------------------------------------

        end
    end
end
