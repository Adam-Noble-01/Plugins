# =============================================================================
# NA NOBLE3D MODELLING TOOLS - TEXTURED PLANE TO IMAGE - NATIVE BRIDGE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__TexturedPlaneToImage__NativeBridge__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__TexturedPlaneToImage__NativeBridge
# PURPOSE    : Load the compiled texture sampler and expose one Ruby call
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__TexturedPlaneToImage__NativeBridge

        NA_NATIVE_BINARY_PATH = File.join(
            File.dirname(__FILE__),
            '02__NativeEngine',
            '04__Bin__WindowsSketchUp2026',
            'Na__Noble3dModellingTools__TexturedPlaneToImage__NativeSampler.so'
        ).freeze unless const_defined?(:NA_NATIVE_BINARY_PATH)

        def self.na_available?
            na_load_sampler
        end

        def self.na_load_error
            @na_load_error
        end

        # FUNCTION | Sample the Texture Buffer in Compiled Code
        # ------------------------------------------------------------
        def self.Na__TexturedPlaneToImage__NativeBridge__Sample(source, corner_uvs, output_width, output_height)
            return nil unless na_load_sampler

            flat_uvs = []
            corner_uvs.each do |uv|
                flat_uvs << uv.x.to_f
                flat_uvs << uv.y.to_f
            end

            Na__TexturedPlaneToImage__NativeSampler.na_sample_texture(
                source.data,
                source.width,
                source.height,
                source.bits_per_pixel,
                source.row_padding,
                flat_uvs,
                output_width,
                output_height
            )
        end
        # ------------------------------------------------------------

        def self.na_load_sampler
            return true if @na_loaded
            return false if @na_load_failed

            unless File.exist?(NA_NATIVE_BINARY_PATH)
                @na_load_failed = true
                @na_load_error = "Native sampler not built: #{NA_NATIVE_BINARY_PATH}"
                return false
            end

            require NA_NATIVE_BINARY_PATH
            @na_loaded = true
            @na_load_error = nil
            true
        rescue StandardError => error
            @na_loaded = false
            @na_load_failed = true
            @na_load_error = "#{error.class}: #{error.message}"
            false
        end

    end # module Na__TexturedPlaneToImage__NativeBridge
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
