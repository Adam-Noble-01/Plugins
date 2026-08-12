# =============================================================================
# VALE LANTERN IMPORTER - DEFINITION REGISTRY
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__DefinitionRegistry__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__DefinitionRegistry
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Create the component definitions an import needs, name them so a
#              model holding three lanterns stays readable, and recognise when a
#              part it is asked for is one it has already built.
#
# DESCRIPTION:
# - Owns definition IDENTITY and nothing about how a face is made. The prism
#   builder asks this module two questions: have you seen this shape before, and
#   what should I call the definition if you have not.
# - State is per import. na_begin_import clears it, so two imports in one session
#   never share a definition by accident and a reload starts from nothing.
#
# -----------------------------------------------------------------------------
#
# WHY A LANTERN NEEDS THIS AT ALL:
#
# A lantern has four hips. Each hip is four parts - core, beam, blocking,
# flashing - and each of those four parts is the SAME extrusion, placed at four
# different corners. A slope carries N glaze bars, each one three parts, and on a
# trapezoidal slope those are all the same length. Built naively that is well
# over a hundred definitions holding perhaps a dozen genuinely different shapes,
# each one carrying its own copy of a section's worth of faces.
#
# Recognising the repeats collapses that. One definition, four instances: one
# copy of the geometry in the file, one place to edit if a modeller wants to, and
# the Component browser reporting a count that means something.
#
# -----------------------------------------------------------------------------
#
# HOW TWO PARTS ARE RECOGNISED AS THE SAME SHAPE:
#
# The payload gives every part in FINISHED WORLD COORDINATES - already mitred,
# already positioned. Two hip beams at two corners therefore share not one
# coordinate. So congruence has to be tested in a frame derived from the part
# itself:
#
#   1  DERIVE A LOCAL FRAME from the part's own point list, by rule and in index
#      order: origin at the first point, X toward the first point far enough away
#      to give a direction, Z from the cross product with the first point after
#      that which is not collinear, Y from Z cross X. Purely geometric, no
#      payload field involved, and identical for two congruent parts because the
#      exporter emits both from the same section in the same order.
#
#   2  EXPRESS EVERY POINT IN THAT FRAME. A part and its rigid copy now hold
#      identical local coordinates, to about 1e-12 inch of floating point noise.
#
#   3  ROUND AND CONCATENATE into a signature string, along with the ring spans
#      and the part's TagKey.
#
#   4  MATCH the signature. A hit means the shape has been built; the instance
#      transform is this part's own frame.
#
# The TagKey is in the signature deliberately. Two parts from different families
# that happen to be geometrically identical would be a legitimate share, but the
# definition would then be named after whichever was built first - a glaze bar
# core called HipBlocking. Keeping families apart costs one or two definitions on
# a lantern and keeps every name honest.
#
# -----------------------------------------------------------------------------
#
# MIRROR IMAGES, AND WHY THE Z SIGN IS ALL IT TAKES:
#
# On a rectangular lantern the four hips are not four rotations of one shape.
# They are two rotations and two reflections: front-right rotated 180 degrees
# about Z gives back-left, but front-right MIRRORED gives front-left. A rigid
# only test therefore finds two definitions of two instances where one of four
# was available.
#
# The frame construction above is always right handed - Y is derived as Z cross X
# rather than measured - and that is what makes the mirror cheap to detect. Take
# a part M that is the reflection of a part R under some reflection Q. Then:
#
#     X_M = Q X_R,  and  Z_M = X_M cross tmp_M = det(Q) . Q Z_R = -Q Z_R
#     Y_M = Z_M cross X_M = -det(Q) . Q Y_R = +Q Y_R
#
# So the X and Y axes carry through the reflection and Z comes out flipped, which
# means the LOCAL coordinates of M are those of R with z negated and nothing
# else. Testing for a mirror is therefore testing one extra signature with the z
# column's sign reversed - no search, no tolerance, no second code path.
#
# The instance transform for a mirrored placement is the part's own frame times a
# scaling of (1, 1, -1), which has a negative determinant. SketchUp handles that
# - a mirrored component is exactly what the Scale tool makes with a negative
# handle - and the config carries a switch to turn it off if a mirrored part ever
# renders with its back faces outward.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__DefinitionRegistry

# -----------------------------------------------------------------------------
# REGION | Module References and Constants
# -----------------------------------------------------------------------------

            DebugTools   = Na__ValeLantern::Na__Importer::Na__DebugTools
            ConfigLoader = Na__ValeLantern::Na__Importer::Na__ConfigLoader

            NA_ATTRIBUTE_DICTIONARY = 'VghLantern'.freeze

            NA_RECORD_PART      = 'ValeLanternPartDefinition'.freeze                                 # <-- Stamped on every definition this module creates
            NA_RECORD_CONTAINER = 'ValeLanternContainerDefinition'.freeze

            NA_MIN_AXIS_INCH   = 1.0e-4                                                              # <-- 0.0025mm; below this two points are one point as far as a frame goes
            NA_MIRROR_SCALING  = [1.0, 1.0, -1.0].freeze
            NA_FALLBACK_TOKEN  = 'ValeLantern'.freeze
            NA_FALLBACK_FAMILY = 'Part'.freeze

            @na_by_signature  = {}                                                                  # <-- Signature string, Sketchup::ComponentDefinition out
            @na_family_counts = {}                                                                  # <-- Family token, how many definitions it has produced
            @na_root_token    = NA_FALLBACK_TOKEN.dup
            @na_shared_hits   = 0                                                                   # <-- Placements served from an existing definition
            @na_mirror_hits   = 0

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Import Lifecycle — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Clear the registry at the start of an import
            # ------------------------------------------------------------
            # Signatures must NEVER survive an import. A definition matched from a
            # previous run could have been erased, edited by the user, or belong
            # to a different lantern that happened to share a shape - and the
            # second and third of those would silently rewrite work somebody had
            # already done.
            #
            # @param root_token [String] The payload's RootGroupName, used in every
            #                            definition name this import creates
            def self.na_begin_import(root_token)
                @na_by_signature  = {}
                @na_family_counts = {}
                @na_shared_hits   = 0
                @na_mirror_hits   = 0

                token = root_token.to_s.strip
                @na_root_token = token.empty? ? NA_FALLBACK_TOKEN.dup : token
                nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | How many placements were served from a shared definition
            # ------------------------------------------------------------
            def self.na_shared_hit_count
                @na_shared_hits
            end
            # ---------------------------------------------------------------

            # FUNCTION | How many of those shares were mirror images
            # ------------------------------------------------------------
            def self.na_mirror_hit_count
                @na_mirror_hits
            end
            # ---------------------------------------------------------------

            # FUNCTION | How many distinct definitions the import created
            # ------------------------------------------------------------
            def self.na_definition_count
                @na_by_signature.length
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Local Frame and Signature — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Derive a local frame from a part's own points
            # ------------------------------------------------------------
            # Deterministic and index ordered, so two congruent parts derive the
            # same frame relative to their own geometry. See the header for why
            # the handedness of the result is what makes mirror detection cheap.
            #
            # @param points [Array<Geom::Point3d>] Both rings, payload order
            # @return [Geom::Transformation, nil] nil when the points are
            #         collinear or degenerate and no frame can be built
            def self.na_local_frame(points)
                return nil unless points.is_a?(Array)

                origin = points.first
                return nil if origin.nil?

                x_axis = nil
                points.each do |point|
                    next if point.nil?
                    offset = point - origin
                    next if offset.length < NA_MIN_AXIS_INCH
                    x_axis = offset.normalize
                    break
                end
                return nil if x_axis.nil?

                z_axis = nil
                points.each do |point|
                    next if point.nil?
                    offset = point - origin
                    next if offset.length < NA_MIN_AXIS_INCH
                    cross = x_axis.cross(offset)
                    next if cross.length < NA_MIN_AXIS_INCH                                         # <-- Collinear with X, so it fixes no second direction
                    z_axis = cross.normalize
                    break
                end
                return nil if z_axis.nil?

                y_axis = z_axis.cross(x_axis)                                                       # <-- Unit and orthogonal by construction, never measured

                Geom::Transformation.axes(origin, x_axis, y_axis, z_axis)

            rescue StandardError => e
                DebugTools.na_detail("Local frame could not be derived: #{e.message}")
                nil
            end
            # ---------------------------------------------------------------

            # FUNCTION | Express a point list in a frame
            # ------------------------------------------------------------
            # @return [Array<Geom::Point3d>] The same list, frame relative
            def self.na_to_local(points, frame)
                inverse = frame.inverse
                points.map { |point| point.nil? ? nil : point.transform(inverse) }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Signature of one part's local geometry
            # ------------------------------------------------------------
            # @param tag_key [String, nil]  The part family
            # @param rings [Array<Hash>]    Payload ring spans
            # @param local_points [Array]   Points already in the local frame
            # @param mirrored [Boolean]     Negate the z column, for the mirror test
            # @return [String, nil]
            def self.na_signature(tag_key, rings, local_points, mirrored = false)
                return nil unless local_points.is_a?(Array) && !local_points.empty?
                return nil if local_points.include?(nil)

                scale  = 10 ** ConfigLoader.na_signature_decimals
                z_sign = mirrored ? -1.0 : 1.0

                span = rings.is_a?(Array) ? rings.map { |ring| "#{ring['Start'].to_i}:#{ring['Count'].to_i}" }.join(',') : ''

                coordinates = local_points.map do |point|
                    x = (point.x.to_f * scale).round
                    y = (point.y.to_f * scale).round
                    z = (point.z.to_f * scale * z_sign).round
                    "#{x}|#{y}|#{z}"
                end

                "#{tag_key}#>#{span}#>#{coordinates.join(';')}"

            rescue StandardError => e
                DebugTools.na_detail("Signature could not be built: #{e.message}")
                nil
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definition Lookup and Registration — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Look for a definition already holding this shape
            # ------------------------------------------------------------
            # The direct signature is tried first, then - when the config allows
            # it - the mirrored one. A definition found but since deleted is
            # dropped from the registry rather than handed back.
            #
            # @param signature [String, nil]        Direct signature
            # @param mirror_signature [String, nil] Signature with z negated
            # @return [Hash, nil] { :Definition, :Mirrored } or nil for a miss
            def self.na_lookup(signature, mirror_signature)
                return nil unless ConfigLoader.na_share_definitions?

                if signature
                    definition = na_live_definition(signature)
                    if definition
                        @na_shared_hits += 1
                        return { :Definition => definition, :Mirrored => false }
                    end
                end

                return nil unless ConfigLoader.na_share_mirrored?
                return nil if mirror_signature.nil?

                definition = na_live_definition(mirror_signature)
                return nil unless definition

                @na_shared_hits += 1
                @na_mirror_hits += 1
                { :Definition => definition, :Mirrored => true }
            end
            # ---------------------------------------------------------------

            # FUNCTION | Register a freshly built definition against its signature
            # ------------------------------------------------------------
            def self.na_register(signature, definition)
                return false unless signature && definition
                return false unless ConfigLoader.na_share_definitions?

                @na_by_signature[signature] = definition
                true
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The registered definition for a signature, if still alive
            # ------------------------------------------------------------
            # A definition can be removed between two parts of one import - the
            # prism builder discards a definition that produced no faces - so a
            # registry hit is checked before it is trusted.
            def self.na_live_definition(signature)
                definition = @na_by_signature[signature]
                return nil if definition.nil?

                if definition.deleted? || !definition.valid?
                    @na_by_signature.delete(signature)
                    return nil
                end

                definition
            rescue StandardError
                @na_by_signature.delete(signature)
                nil
            end
            private_class_method :na_live_definition

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Definition Creation — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Create an empty, stamped definition for one part family
            # ------------------------------------------------------------
            # @param model [Sketchup::Model]
            # @param tag_key [String, nil] The part family, for the name
            # @param part_name [String]    Fallback when there is no tag key
            # @return [Sketchup::ComponentDefinition, nil]
            def self.na_create_part_definition(model, tag_key, part_name)
                return nil unless model

                family = na_family_token(tag_key, part_name)
                index  = na_next_family_index(family)
                name   = na_render_name(
                    ConfigLoader.na_definition_name_template,
                    'RootToken' => @na_root_token,
                    'Family'    => family,
                    'Index'     => format('%02d', index),
                    'Name'      => part_name.to_s
                )

                definition = na_add_definition(model, name)
                return nil unless definition

                na_stamp(definition, 'RecordType', NA_RECORD_PART)
                na_stamp(definition, 'PartFamily', family)
                na_stamp(definition, 'TagKey',     tag_key.to_s) unless tag_key.nil?
                definition
            end
            # ---------------------------------------------------------------

            # FUNCTION | Create an empty, stamped definition for one container
            # ------------------------------------------------------------
            # The root lantern, an assembly, or a lazily created part group. These
            # are never shared - a lantern's base assembly is unique to it - so
            # they carry no signature.
            #
            # @param model [Sketchup::Model]
            # @param container_name [String] The container's own payload name
            # @param use_root_token [Boolean] False for the root itself, whose name
            #                                 IS the root token
            # @return [Sketchup::ComponentDefinition, nil]
            def self.na_create_container_definition(model, container_name, use_root_token = true)
                return nil unless model

                definition = na_add_definition(model, na_container_name(container_name, use_root_token))
                return nil unless definition

                na_stamp(definition, 'RecordType', NA_RECORD_CONTAINER)
                definition
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | The definition name for one container
            # ------------------------------------------------------------
            # The root lantern's own name IS the token every other definition is
            # prefixed with, so it passes through untemplated. Everything below it
            # is prefixed, which is what makes one lantern's thirty definitions
            # sort together in the Component browser.
            def self.na_container_name(container_name, use_root_token)
                return container_name.to_s unless use_root_token

                na_render_name(
                    ConfigLoader.na_container_name_template,
                    'RootToken' => @na_root_token,
                    'Name'      => container_name.to_s,
                    'Family'    => container_name.to_s,
                    'Index'     => '01'
                )
            end
            private_class_method :na_container_name

            # FUNCTION | Discard a definition that produced nothing
            # ------------------------------------------------------------
            # A definition with no faces in it is worse than no definition: it
            # sits in the Component browser forever with nothing inside. Removal
            # is guarded because an instance may already have been placed, and
            # because definitions.remove arrived later than the rest of this API.
            def self.na_discard_definition(model, definition)
                return false unless model && definition
                return false if definition.deleted?
                return false unless model.definitions.respond_to?(:remove)

                model.definitions.remove(definition)
                true
            rescue StandardError => e
                DebugTools.na_detail("Definition '#{definition.name rescue '?'}' could not be removed: #{e.message}")
                false
            end
            # ---------------------------------------------------------------

            # FUNCTION | The transformation that places one instance
            # ------------------------------------------------------------
            # For a direct match this is the part's own derived frame. For a
            # mirror match it is that frame followed by a z flip, so the shared
            # definition's local geometry lands the other way round.
            #
            # SketchUp composes right to left - t1 * t2 applies t2 first - so the
            # flip has to be the RIGHT operand: the definition's points are
            # mirrored, then the whole mirrored part is moved into place.
            def self.na_placement(frame, mirrored)
                return frame unless mirrored

                frame * Geom::Transformation.scaling(
                    NA_MIRROR_SCALING[0], NA_MIRROR_SCALING[1], NA_MIRROR_SCALING[2]
                )
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Naming
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Add a definition under a name nothing else holds
            # ------------------------------------------------------------
            # definitions.add RETURNS AN EXISTING DEFINITION when the name is
            # already taken rather than raising or renaming, which would quietly
            # hand a second lantern the first one's geometry and then let the
            # builder append four hundred more faces to it. The name is made
            # unique first, every time.
            def self.na_add_definition(model, base_name)
                model.definitions.add(na_unique_definition_name(model, base_name))
            rescue StandardError => e
                DebugTools.na_warn("Definition '#{base_name}' could not be created: #{e.message}")
                nil
            end
            private_class_method :na_add_definition

            # HELPER FUNCTION | A definition name nothing in the model holds yet
            # ------------------------------------------------------------
            def self.na_unique_definition_name(model, base_name)
                name = base_name.to_s.strip
                name = "#{NA_FALLBACK_TOKEN}__Unnamed" if name.empty?
                return name unless model.definitions[name]

                counter = 2
                counter += 1 while model.definitions["#{name}__#{counter}"]
                "#{name}__#{counter}"
            end
            private_class_method :na_unique_definition_name

            # HELPER FUNCTION | Substitute the name template's tokens
            # ------------------------------------------------------------
            def self.na_render_name(template, values)
                rendered = template.to_s
                values.each { |token, value| rendered = rendered.gsub("{#{token}}", value.to_s) }
                rendered.gsub(/\{[A-Za-z]+\}/, '')                                                  # <-- A token the caller did not supply leaves no braces behind
            end
            private_class_method :na_render_name

            # HELPER FUNCTION | Family token for a definition name
            # ------------------------------------------------------------
            # The TagKey with its first letter capitalised - hipBeam becomes
            # HipBeam - because the tag key IS the family and the exporter already
            # stamps it on every part. A part with no tag key falls back to its
            # own name with any trailing index or side stripped, which is the best
            # guess available and never wrong enough to matter: the name is only
            # ever read by a human in the Component browser.
            def self.na_family_token(tag_key, part_name)
                key = tag_key.to_s.strip
                unless key.empty?
                    return key.sub(/\A[a-z]/) { |first| first.upcase }
                end

                fallback = part_name.to_s.strip.sub(/__[0-9]+\z/, '').sub(/__(Front|Right|Back|Left)\z/, '')
                fallback.empty? ? NA_FALLBACK_FAMILY.dup : fallback
            end
            private_class_method :na_family_token

            # HELPER FUNCTION | Next index within one family, for this import
            # ------------------------------------------------------------
            def self.na_next_family_index(family)
                @na_family_counts[family] = (@na_family_counts[family] || 0) + 1
            end
            private_class_method :na_next_family_index

            # HELPER FUNCTION | Write one attribute, tolerating a refusal
            # ------------------------------------------------------------
            def self.na_stamp(entity, key, value)
                return if value.nil?
                entity.set_attribute(NA_ATTRIBUTE_DICTIONARY, key, value)
            rescue StandardError => e
                DebugTools.na_detail("Attribute '#{key}' refused: #{e.message}")
            end
            private_class_method :na_stamp

# endregion -------------------------------------------------------------------

        end
    end
end
