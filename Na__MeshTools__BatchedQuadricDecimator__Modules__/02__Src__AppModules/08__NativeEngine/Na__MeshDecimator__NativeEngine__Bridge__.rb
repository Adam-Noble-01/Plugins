# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - NATIVE ENGINE BRIDGE
# =============================================================================
#
# FILE       : Na__MeshDecimator__NativeEngine__Bridge__.rb
# NAMESPACE  : Na__MeshDecimator::Na__NativeEngine::Na__Bridge
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Loads the optional C++ Ruby native extension and exposes a small
#              Ruby-safe wrapper around the pure mesh simplification call.
#
# =============================================================================

module Na__MeshDecimator
    module Na__NativeEngine
        module Na__Bridge

            NA_NATIVE_ENGINE_ROOT = File.expand_path('../../02__Src__NativeEngine', __dir__)
            NA_NATIVE_BINARY_PATH = File.join(
                NA_NATIVE_ENGINE_ROOT,
                '04__Bin__WindowsSketchUp2026',
                'Na__MeshDecimator__NativeQemEngine.so'
            )

            @na_load_error = nil
            @na_loaded     = false

            # -----------------------------------------------------------------
            # REGION | Native Load
            # -----------------------------------------------------------------

            def self.na_load_native_engine
                return true if @na_loaded

                unless File.exist?(NA_NATIVE_BINARY_PATH)
                    @na_load_error = "Native binary not found: #{NA_NATIVE_BINARY_PATH}"
                    return false
                end

                require NA_NATIVE_BINARY_PATH
                @na_loaded = true
                @na_load_error = nil
                true
            rescue StandardError => e
                @na_loaded = false
                @na_load_error = "#{e.class}: #{e.message}"
                false
            end

            def self.na_available?
                na_load_native_engine
            end

            def self.na_load_error
                @na_load_error
            end

            # -----------------------------------------------------------------
            # REGION | Simplification API
            # -----------------------------------------------------------------

            def self.na_simplify_mesh(mesh_data, target_triangles, options)
                unless na_available?
                    raise "Native decimator unavailable: #{na_load_error}"
                end

                Na__MeshDecimator::Na__NativeQemEngine.na_simplify_mesh(
                    mesh_data,
                    target_triangles,
                    options
                )
            end

        end
    end
end
