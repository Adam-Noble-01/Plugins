# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - SECTION DOMAIN
# =============================================================================
#
# FILE       : Na__SceneDataTransfer__SectionDomain__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__SectionDomain
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Capture section plane entities and which plane each scene
#              activates, then recreate both in another model.
# CREATED    : 2026
#
# SKETCHUP RUBY API REFERENCE (verified against ruby.sketchup.com, 2026):
#
# SectionPlane HAS NO #transformation AND NO #transform!.
#   It has exactly eight own methods: activate, active?, get_plane, set_plane,
#   name, name=, symbol, symbol=. Its position and orientation are expressed
#   SOLELY as a plane array, in the coordinate system of whichever Entities
#   collection owns it.
#
# THE PLANE FORMAT IS ASYMMETRIC.
#   add_section_plane and set_plane accept EITHER [a, b, c, d] or
#   [Geom::Point3d, Geom::Vector3d], but get_plane ALWAYS returns the four-float
#   coefficient form, with a unit-length normal (a, b, c) and d the negated
#   signed distance from the origin along that normal, in INCHES. Four plain
#   floats, so it is trivially JSON-safe.
#
# SCENES DO NOT OWN SECTION PLANE ENTITIES.
#   The planes are model geometry that exists regardless of scenes. A Page
#   merely records WHICH plane was active in each Entities collection. That is
#   why this domain has two halves: recreate the plane entities once at model
#   level, then per scene record which one is active.
#
# ACTIVATION CANNOT BE WRITTEN DIRECTLY ONTO A PAGE.
#   There is no Page#active_section_plane=. The only route is to set the state
#   on the model and then bake it with Page#update(PAGE_USE_SECTION_PLANES),
#   which pulls from CURRENT model state. This module therefore saves the
#   model's own active plane before the import and restores it afterwards.
#
# THERE IS NO Model#active_section_plane (SINGULAR).
#   That accessor exists only on Sketchup::Entities. SketchUp 2026 added the
#   READ-ONLY Model#active_section_planes and Page#active_section_planes
#   (plural), which is what finally makes capture possible without activating
#   every scene tab in turn. Page#active_section_planes returns nil when
#   use_section_planes? is false.
#
# WHETHER THE CUT IS DRAWN IS A STYLE MATTER, NOT A SECTION MATTER.
#   DisplaySectionPlanes, DisplaySectionCuts, SectionCutFilled, SectionCutWidth
#   and the Section*Color keys all live in RenderingOptions and travel with the
#   style domain, under use_rendering_options - NOT under use_section_planes.
#
# SCOPE LIMIT IN 0.02:
#   Only section planes living in the model ROOT are recreated. A plane nested
#   inside a group or component has a plane expressed in that container's
#   coordinate system, and recreating it faithfully needs the full world
#   transform of the container, which has no counterpart in the target model.
#   Nested planes are counted and REPORTED rather than silently mangled.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__SectionDomain

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_DOMAIN_KEY       = 'sections'.freeze
        NA_PLANE_PRECISION  = 6                                                     # <-- Decimal places used to build a stable key

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Capture
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Every Root-Level Section Plane in the Model
        # ------------------------------------------------------------
        # Called once per capture run.
        def self.Na__SceneDataTransfer__CaptureModelSections(model)
            return nil unless model

            root_planes = model.entities.grep(Sketchup::SectionPlane)

            planes = root_planes.map do |section_plane|
                {
                    'key'       => na_plane_key(section_plane),
                    'name'      => na_safe_string(section_plane, :name),
                    'symbol'    => na_safe_string(section_plane, :symbol),
                    'plane'     => na_plane_array(section_plane),
                    'hidden'    => (section_plane.hidden? rescue false),
                    'tag_name'  => na_layer_name(section_plane)
                }
            end.reject { |record| record['plane'].nil? }

            {
                'planes'       => planes,
                'nested_count' => na_count_nested_planes(model)
            }
        rescue => error
            puts "[Na__SceneDataTransfer] Section capture error: #{error.class}: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Capture Which Section Planes a Page Activates
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__CaptureSections(page)
            return nil unless page

            unless page.use_section_planes?
                return { 'uses_sections' => false, 'active_keys' => [] }
            end

            unless page.respond_to?(:active_section_planes)
                return {
                    'uses_sections' => true,
                    'active_keys'   => [],
                    'unreadable'    => true                                         # <-- Needs SketchUp 2026 to read without activating
                }
            end

            active_planes = page.active_section_planes                              # <-- nil when use_section_planes? is false
            active_keys   = Array(active_planes).map { |section_plane| na_plane_key(section_plane) }.compact

            { 'uses_sections' => true, 'active_keys' => active_keys }
        rescue => error
            puts "[Na__SceneDataTransfer] Scene section capture warning: #{error.message}"
            nil
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild - Model Level
# -----------------------------------------------------------------------------

        # FUNCTION | Recreate the Captured Section Planes in the Target Model
        # ------------------------------------------------------------
        # Called ONCE per import, before any page is built. Returns a lookup of
        # payload key -> live SectionPlane so the per-page pass can activate the
        # right one without re-searching.
        def self.Na__SceneDataTransfer__EnsureModelSections(model, inventory_hash)
            return na_result(false, ['No model supplied.'], {})             unless model
            return na_result(false, ['No section inventory supplied.'], {}) unless inventory_hash.is_a?(Hash)

            warnings = []
            lookup   = na_existing_plane_lookup(model)
            created  = 0

            Array(inventory_hash['planes']).each do |plane_record|
                plane_key = plane_record['key'].to_s
                next if plane_key.empty?
                next if lookup.key?(plane_key)                                      # <-- An equivalent plane already exists

                section_plane = na_create_section_plane(model, plane_record, warnings)
                next unless section_plane

                lookup[plane_key] = section_plane
                created += 1
            end

            warnings << "Created #{created} section plane(s)." if created > 0

            nested_count = inventory_hash['nested_count'].to_i
            if nested_count > 0
                warnings << "#{nested_count} section plane(s) nested inside groups or components were not " \
                            'transferred. Only model-level section planes can be recreated reliably.'
            end

            na_result(true, warnings, lookup)
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"], {})
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Lookup of the Planes Already in the Model
        # ------------------------------------------------------------
        def self.na_existing_plane_lookup(model)
            model.entities.grep(Sketchup::SectionPlane).each_with_object({}) do |section_plane, lookup|
                plane_key = na_plane_key(section_plane)
                lookup[plane_key] = section_plane if plane_key
            end
        rescue
            {}
        end
        private_class_method :na_existing_plane_lookup
        # ------------------------------------------------------------

        # HELPER FUNCTION | Create One Section Plane From Its Captured Record
        # ------------------------------------------------------------
        def self.na_create_section_plane(model, plane_record, warnings)
            coefficients = plane_record['plane']
            return nil unless na_is_quad(coefficients)

            section_plane = na_add_section_plane(model.entities, coefficients)
            return nil unless section_plane

            na_apply_identity(section_plane, plane_record, warnings)
            section_plane
        rescue => error
            warnings << "Could not create section plane '#{plane_record['name']}': #{error.class}: #{error.message}"
            nil
        end
        private_class_method :na_create_section_plane
        # ------------------------------------------------------------

        # HELPER FUNCTION | Add a Section Plane, Preferring the Point-Vector Form
        # ------------------------------------------------------------
        # The point-and-vector form is the more robust of the two accepted
        # representations. The raw coefficient array is kept as a fallback.
        def self.na_add_section_plane(entities, coefficients)
            normal = Geom::Vector3d.new(coefficients[0].to_f, coefficients[1].to_f, coefficients[2].to_f)
            origin = Geom::Point3d.new(0, 0, 0).offset(normal, -coefficients[3].to_f)

            entities.add_section_plane([origin, normal])
        rescue
            begin
                entities.add_section_plane(coefficients.map(&:to_f))
            rescue
                nil
            end
        end
        private_class_method :na_add_section_plane
        # ------------------------------------------------------------

        # HELPER FUNCTION | Restore a Section Plane's Name, Symbol and Hidden State
        # ------------------------------------------------------------
        def self.na_apply_identity(section_plane, plane_record, warnings)
            plane_name = plane_record['name'].to_s
            section_plane.name = plane_name if !plane_name.empty? && section_plane.respond_to?(:name=)

            plane_symbol = plane_record['symbol'].to_s
            section_plane.symbol = plane_symbol if !plane_symbol.empty? && section_plane.respond_to?(:symbol=)

            section_plane.hidden = true if plane_record['hidden'] == true

            na_apply_tag(section_plane, plane_record['tag_name'])
        rescue => error
            warnings << "Section plane identity partly failed: #{error.message}"
        end
        private_class_method :na_apply_identity
        # ------------------------------------------------------------

        # HELPER FUNCTION | Put a Section Plane on Its Source Tag if It Exists
        # ------------------------------------------------------------
        # The tag domain creates missing tags before this runs, so a tag will
        # normally be present when tags were also ticked.
        def self.na_apply_tag(section_plane, tag_name)
            clean_name = tag_name.to_s
            return if clean_name.empty?

            model = section_plane.model
            layer = model.layers[clean_name]
            section_plane.layer = layer if layer
        rescue
            nil
        end
        private_class_method :na_apply_tag
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Rebuild - Page Level
# -----------------------------------------------------------------------------

        # FUNCTION | Bake the Active Section Plane Onto an Existing Page
        # ------------------------------------------------------------
        # There is no Page#active_section_plane=, so this sets the state on the
        # model and bakes it with Page#update(PAGE_USE_SECTION_PLANES). Only that
        # one bit is passed, so nothing else about the page is re-baked.
        def self.Na__SceneDataTransfer__ApplySectionsToPage(page, section_hash, plane_lookup)
            return na_result(false, ['No page supplied.'], {})         unless page
            return na_result(false, ['No section data supplied.'], {}) unless section_hash.is_a?(Hash)

            model = page.model
            return na_result(false, ['This page has no model.'], {}) unless model

            page.use_section_planes = true                                          # <-- Must be true BEFORE the bake

            if section_hash['unreadable'] == true
                return na_result(true, ['The source model was captured on a SketchUp older than 2026, which ' \
                                        'cannot report a scene\'s active section plane. The planes themselves ' \
                                        'were transferred, but no scene activates one.'], {})
            end

            active_keys = Array(section_hash['active_keys'])
            target      = active_keys.map { |plane_key| (plane_lookup || {})[plane_key.to_s] }.compact.first

            na_bake_active_plane(model, page, target)

            warnings = []
            if target.nil? && !active_keys.empty?
                warnings << 'The section plane this scene activated could not be matched in this model.'
            end

            na_result(true, warnings, {})
        rescue => error
            na_result(false, ["#{error.class}: #{error.message}"], {})
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Set Model State, Bake It, and Leave the Bit Alone After
        # ------------------------------------------------------------
        def self.na_bake_active_plane(model, page, section_plane)
            model.entities.active_section_plane = section_plane                     # <-- nil deactivates
            return unless Object.const_defined?(:PAGE_USE_SECTION_PLANES)

            page.update(Object.const_get(:PAGE_USE_SECTION_PLANES))
        rescue => error
            puts "[Na__SceneDataTransfer] Section bake warning: #{error.message}"
        end
        private_class_method :na_bake_active_plane
        # ------------------------------------------------------------

        # FUNCTION | Read the Model's Current Active Section Plane
        # ------------------------------------------------------------
        # The importer saves this before the section pass and restores it after,
        # so the user's own model state survives the import untouched.
        def self.Na__SceneDataTransfer__ReadActiveSectionPlane(model)
            return nil unless model

            model.entities.active_section_plane
        rescue
            nil
        end
        # ------------------------------------------------------------

        # FUNCTION | Restore the Model's Active Section Plane
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__RestoreActiveSectionPlane(model, section_plane)
            return false unless model

            model.entities.active_section_plane = (section_plane && section_plane.valid?) ? section_plane : nil
            true
        rescue => error
            puts "[Na__SceneDataTransfer] Section restore warning: #{error.message}"
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Plane Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Read a Section Plane's Four Coefficients
        # ------------------------------------------------------------
        def self.na_plane_array(section_plane)
            plane = section_plane.get_plane
            return nil unless na_is_quad(plane)

            plane.map { |coefficient| coefficient.to_f }
        rescue
            nil
        end
        private_class_method :na_plane_array
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build a Stable Cross-Model Key for a Section Plane
        # ------------------------------------------------------------
        # entityID and persistent_id are model-local, so identity is derived from
        # the geometry itself plus the name, rounded so floating point noise does
        # not produce two keys for the same plane.
        def self.na_plane_key(section_plane)
            plane = na_plane_array(section_plane)
            return nil unless plane

            rounded = plane.map { |coefficient| coefficient.round(NA_PLANE_PRECISION) }
            "#{na_safe_string(section_plane, :name)}|#{rounded.join(',')}"
        rescue
            nil
        end
        private_class_method :na_plane_key
        # ------------------------------------------------------------

        # HELPER FUNCTION | Count Section Planes Nested Inside Definitions
        # ------------------------------------------------------------
        def self.na_count_nested_planes(model)
            model.definitions.reduce(0) do |running_total, definition|
                next running_total if definition.image?

                running_total + definition.entities.grep(Sketchup::SectionPlane).length
            end
        rescue
            0
        end
        private_class_method :na_count_nested_planes
        # ------------------------------------------------------------

        # HELPER FUNCTION | Validate a Four-Number Array
        # ------------------------------------------------------------
        def self.na_is_quad(candidate)
            candidate.is_a?(Array) && candidate.length == 4 &&
                candidate.all? { |component| component.is_a?(Numeric) }
        end
        private_class_method :na_is_quad
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a String Property Defensively
        # ------------------------------------------------------------
        def self.na_safe_string(entity, method_name)
            entity.respond_to?(method_name) ? entity.send(method_name).to_s : ''
        rescue
            ''
        end
        private_class_method :na_safe_string
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Tag Name a Section Plane Sits On
        # ------------------------------------------------------------
        def self.na_layer_name(section_plane)
            layer = section_plane.layer
            layer ? layer.name.to_s : ''
        rescue
            ''
        end
        private_class_method :na_layer_name
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Apply Result Hash
        # ------------------------------------------------------------
        def self.na_result(applied_flag, warnings, lookup)
            { 'applied' => !!applied_flag, 'warnings' => Array(warnings), 'lookup' => lookup || {} }
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__SectionDomain
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
