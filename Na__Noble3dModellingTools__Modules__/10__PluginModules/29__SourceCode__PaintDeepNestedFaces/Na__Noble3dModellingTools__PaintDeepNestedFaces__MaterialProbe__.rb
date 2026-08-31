# =============================================================================
# NA NOBLE3D MODELLING TOOLS - PAINT DEEP NESTED FACES - MATERIAL PROBE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__PaintDeepNestedFaces__MaterialProbe__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__PaintDeepNestedFaces__MaterialProbe
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Read the material currently active in the SketchUp Materials tray
#              and describe it as a plain hash the HtmlDialog can preview.
# CREATED    : 2026
#
# DESIGN NOTES:
# - Sketchup::Materials#current is the single source of truth for the swatch the
#   user last clicked in the Materials window or Paint Bucket.
# - Only colour, opacity and name are read. Textures are reported as a flag so
#   the dialog can caption the swatch honestly, but no image data is extracted.
# - Material#use_alpha? is the API transparency test (alpha compared to fully
#   opaque with a floating point tolerance) and it drives the back face rule.
#
# THE DEFAULT MATERIAL IS nil:
# SketchUp has no Material object and no name string for the Default swatch. The
# API represents it as nil throughout - Materials#current returns nil when
# Default is picked, and face.material = nil is how the default is applied. So
# nil is not treated here as "nothing selected"; it is a first class choice that
# arms the tool in strip mode. Its swatch colours come from the model rendering
# options FaceFrontColor / FaceBackColor, which is what SketchUp itself draws.
#
# LIBRARY MATERIALS ARE NOT IN THE MODEL:
# A swatch clicked in a material library rather than In Model comes back from
# Materials#current as a material that does not belong to model.materials.
# Reading it is safe; applying it to an entity crashes SketchUp. The payload
# therefore carries an in_model flag, and the Run module resolves the material
# into the model before any face is touched.
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__PaintDeepNestedFaces__MaterialProbe

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_FALLBACK_HEX      = '#B4B4B4'.freeze                                     # <-- Shown when a colour cannot be read
        NA_DEFAULT_FRONT_HEX = '#FFFFFF'.freeze                                     # <-- Used if FaceFrontColor cannot be read
        NA_DEFAULT_BACK_HEX  = '#8194A5'.freeze                                     # <-- Used if FaceBackColor cannot be read
        NA_OPAQUE_ALPHA_MIN  = 0.999                                                # <-- Alpha at or above this counts as opaque
        NA_MATERIAL_TYPE_MAP = {
            0 => 'Solid colour',
            1 => 'Textured',
            2 => 'Textured (colourised)'
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Probe API
# -----------------------------------------------------------------------------

        # FUNCTION | Describe the Material Currently Active in the Materials Tray
        # ------------------------------------------------------------
        # Reads Sketchup::Materials#current from the supplied model and returns
        # the preview payload consumed by the dialog. A nil current material is
        # the Default swatch, not an empty tray, so it returns the default
        # material payload and leaves the tool armed in strip mode.
        #
        # @param model [Sketchup::Model] Model to read the current material from
        # @return [Hash] Preview payload with string keys
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__MaterialProbe__DescribeCurrent(model = nil)
            model ||= Sketchup.active_model
            return na_unavailable_payload unless model

            material = model.materials.current
            return na_default_material_payload(model) if material.nil?

            Na__PaintDeepNestedFaces__MaterialProbe__DescribeMaterial(material, model)
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Material probe warning: #{error.class}: #{error.message}"
            na_unavailable_payload
        end
        # ------------------------------------------------------------

        # FUNCTION | Describe One Material as a Dialog Preview Payload
        # ------------------------------------------------------------
        # @param material [Sketchup::Material, nil] Material to describe
        # @param model    [Sketchup::Model, nil]    Model used for the in_model test
        # @return [Hash] Preview payload with string keys
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__MaterialProbe__DescribeMaterial(material, model = nil)
            return na_default_material_payload(model) if material.nil?
            return na_unavailable_payload unless na_usable_material?(material)

            alpha_value    = na_alpha_for(material)
            is_transparent = na_transparent?(material, alpha_value)
            rgb_values     = na_rgb_for(material)

            {
                'has_material'    => true,
                'is_default'      => false,
                'name'            => material.display_name.to_s,
                'raw_name'        => material.name.to_s,
                'hex'             => na_rgb_to_hex(rgb_values),
                'rgb'             => rgb_values,
                'back_hex'        => nil,
                'alpha'           => alpha_value,
                'opacity_percent' => (alpha_value * 100.0).round,
                'is_transparent'  => is_transparent,
                'is_textured'     => !material.texture.nil?,
                'texture_name'    => na_texture_name(material),
                'material_type'   => na_material_type_label(material),
                'back_face_rule'  => is_transparent ? 'paint_both' : 'front_only',
                'in_model'        => Na__PaintDeepNestedFaces__MaterialProbe__IsInModel(model, material)
            }
        rescue => error
            puts "[Na__PaintDeepNestedFaces] Material describe warning: #{error.class}: #{error.message}"
            na_unavailable_payload
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether a Material Belongs to the Model
        # ------------------------------------------------------------
        # A swatch clicked in a material library is returned by Materials#current
        # without being part of the model. Applying such a material to an entity
        # crashes SketchUp, so every paint path checks this first.
        #
        # @param model    [Sketchup::Model, nil]    Model to test against
        # @param material [Sketchup::Material, nil] Material to look for
        # @return [Boolean] True when the material is safe to apply
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__MaterialProbe__IsInModel(model, material)
            return true  if material.nil?                                           # <-- Default material always applies
            return false unless model

            return true if model.materials.include?(material)

            named_material = model.materials[material.name]
            !named_material.nil? && named_material.equal?(material)
        rescue
            false
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether a Material Reference Can Be Painted With
        # ------------------------------------------------------------
        # @param material [Sketchup::Material, nil] Material to test
        # @return [Boolean] True when the material is live and usable
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__MaterialProbe__IsUsable(material)
            na_usable_material?(material)
        end
        # ------------------------------------------------------------

        # FUNCTION | Report Whether a Material Should Paint Both Face Sides
        # ------------------------------------------------------------
        # The painter calls this directly so the applied rule can never drift
        # away from the rule previewed in the dialog.
        #
        # @param material [Sketchup::Material, nil] Material about to be applied
        # @return [Boolean] True when the back face should receive the material
        # ------------------------------------------------------------
        def self.Na__PaintDeepNestedFaces__MaterialProbe__IsTransparent(material)
            return false unless na_usable_material?(material)

            na_transparent?(material, na_alpha_for(material))
        rescue
            false
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Reading Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Check a Material Reference Is Alive and Readable
        # ------------------------------------------------------------
        def self.na_usable_material?(material)
            return false if material.nil?
            return false unless material.is_a?(Sketchup::Material)
            return false if material.respond_to?(:valid?) && !material.valid?
            return false if material.respond_to?(:deleted?) && material.deleted?

            true
        rescue
            false
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Material Alpha as a 0.0 - 1.0 Float
        # ------------------------------------------------------------
        def self.na_alpha_for(material)
            alpha_value = material.alpha
            return 1.0 if alpha_value.nil?

            [[alpha_value.to_f, 0.0].max, 1.0].min
        rescue
            1.0
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Decide Whether a Material Counts as Transparent
        # ------------------------------------------------------------
        # use_alpha? is the API transparency test. The numeric alpha check is
        # kept as a backstop so an unexpected nil never silently reports the
        # material as opaque and skips the back face.
        # ------------------------------------------------------------
        def self.na_transparent?(material, alpha_value)
            return true if material.respond_to?(:use_alpha?) && material.use_alpha?

            alpha_value < NA_OPAQUE_ALPHA_MIN
        rescue
            alpha_value < NA_OPAQUE_ALPHA_MIN
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read the Material Colour as Integer RGB Values
        # ------------------------------------------------------------
        # Material#color returns the average texture colour for textured
        # materials, and can be nil in edge cases, so the texture average is
        # queried directly before falling back to the neutral swatch grey.
        # ------------------------------------------------------------
        def self.na_rgb_for(material)
            colour = material.color
            colour = material.texture.average_color if colour.nil? && material.texture
            return na_hex_to_rgb(NA_FALLBACK_HEX) if colour.nil?

            [colour.red.to_i, colour.green.to_i, colour.blue.to_i]
        rescue
            na_hex_to_rgb(NA_FALLBACK_HEX)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return the Texture File Name When One Is Present
        # ------------------------------------------------------------
        def self.na_texture_name(material)
            texture = material.texture
            return '' unless texture

            File.basename(texture.filename.to_s)
        rescue
            ''
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Return a Readable Label for the Material Type
        # ------------------------------------------------------------
        def self.na_material_type_label(material)
            NA_MATERIAL_TYPE_MAP.fetch(material.materialType.to_i, 'Unknown')
        rescue
            'Unknown'
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Colour Conversion Utilities
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Convert Integer RGB Values to a Hex String
        # ------------------------------------------------------------
        def self.na_rgb_to_hex(rgb_values)
            format('#%02X%02X%02X', rgb_values[0], rgb_values[1], rgb_values[2])
        rescue
            NA_FALLBACK_HEX
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Convert a Hex String to Integer RGB Values
        # ------------------------------------------------------------
        def self.na_hex_to_rgb(hex_string)
            cleaned = hex_string.to_s.delete('#')
            [
                cleaned[0, 2].to_i(16),
                cleaned[2, 2].to_i(16),
                cleaned[4, 2].to_i(16)
            ]
        rescue
            [180, 180, 180]
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Default Material and Unavailable States
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build the Payload for the Default Material
        # ------------------------------------------------------------
        # The Default swatch is a real choice, so has_material stays true and the
        # tool arms in strip mode. Its two colours are read from the model
        # rendering options, which is exactly what SketchUp draws in the tray.
        # ------------------------------------------------------------
        def self.na_default_material_payload(model = nil)
            front_rgb = na_default_face_rgb(model, 'FaceFrontColor', NA_DEFAULT_FRONT_HEX)
            back_rgb  = na_default_face_rgb(model, 'FaceBackColor',  NA_DEFAULT_BACK_HEX)

            {
                'has_material'    => true,
                'is_default'      => true,
                'name'            => 'Default',
                'raw_name'        => '',
                'hex'             => na_rgb_to_hex(front_rgb),
                'rgb'             => front_rgb,
                'back_hex'        => na_rgb_to_hex(back_rgb),
                'alpha'           => 1.0,
                'opacity_percent' => 100,
                'is_transparent'  => false,
                'is_textured'     => false,
                'texture_name'    => '',
                'material_type'   => 'Default (no material)',
                'back_face_rule'  => 'strip_both',
                'in_model'        => true
            }
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read One Default Face Colour From the Rendering Options
        # ------------------------------------------------------------
        def self.na_default_face_rgb(model, option_key, fallback_hex)
            return na_hex_to_rgb(fallback_hex) unless model

            colour = model.rendering_options[option_key]
            return na_hex_to_rgb(fallback_hex) if colour.nil?

            [colour.red.to_i, colour.green.to_i, colour.blue.to_i]
        rescue
            na_hex_to_rgb(fallback_hex)
        end
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Payload Used When the Tray Cannot Be Read
        # ------------------------------------------------------------
        # Reached only when there is no model, or the current material is a live
        # object that cannot be inspected. A nil current material is the Default
        # swatch and never lands here.
        # ------------------------------------------------------------
        def self.na_unavailable_payload
            {
                'has_material'    => false,
                'is_default'      => false,
                'name'            => 'Unavailable',
                'raw_name'        => '',
                'hex'             => NA_FALLBACK_HEX,
                'rgb'             => na_hex_to_rgb(NA_FALLBACK_HEX),
                'back_hex'        => nil,
                'alpha'           => 1.0,
                'opacity_percent' => 100,
                'is_transparent'  => false,
                'is_textured'     => false,
                'texture_name'    => '',
                'material_type'   => 'None',
                'back_face_rule'  => 'front_only',
                'in_model'        => false
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__PaintDeepNestedFaces__MaterialProbe
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
