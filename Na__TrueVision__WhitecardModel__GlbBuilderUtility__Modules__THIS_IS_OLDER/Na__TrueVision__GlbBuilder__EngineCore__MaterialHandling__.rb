# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MATERIAL HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Material Handling (Debug-Safe / Texture Disabled)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Isolated material handling for GLB export
# CREATED    : 2025
#
# IMPORTANT DEBUG NOTE:
# - Texture/image export paths are intentionally disabled while the core geometry
#   engine is being debugged.
# - These paths are commented out / bypassed until the geometry pipeline is stable.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility
    
    # -----------------------------------------------------------------------------
    # REGION | Material Processing (Debug-Safe Mode)
    # -----------------------------------------------------------------------------
    
        # FUNCTION | Build glTF Materials Without Texture Export (Debug Mode)
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__PrepareMaterialsForExport(face_groups, gltf, _binary_buffer)
            @material_map ||= {}
            @material_map.clear

            unique_materials = []
            face_groups.each_value do |group_data|
                material = group_data[:material]
                next unless material
                unique_materials << material unless unique_materials.include?(material)
            end

            # Always provide a default fallback material at index 0.
            gltf["materials"] << {
                "name" => "Default",
                "pbrMetallicRoughness" => {
                    "baseColorFactor" => [0.8, 0.8, 0.8, 1.0],
                    "metallicFactor" => 0.0,
                    "roughnessFactor" => 1.0
                }
            }

            unique_materials.each_with_index do |material, index|
                @material_map[material] = index + 1

                rgba =
                    if material.respond_to?(:color) && material.color
                        c = material.color
                        [
                            c.red.to_f / 255.0,
                            c.green.to_f / 255.0,
                            c.blue.to_f / 255.0,
                            1.0
                        ]
                    else
                        [0.8, 0.8, 0.8, 1.0]
                    end

                # Texture export intentionally disabled during geometry debugging.
                # Future implementation can inject texture references here.
                gltf["materials"] << {
                    "name" => material.display_name,
                    "pbrMetallicRoughness" => {
                        "baseColorFactor" => rgba,
                        "metallicFactor" => 0.0,
                        "roughnessFactor" => 1.0
                    }
                }
            end

            puts "    Material handling active (debug mode): texture exporting is temporarily disabled."
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Material Index for Group Data
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__ResolveMaterialIndexForGroup(group_data)
            material = group_data[:material]
            return 0 unless material
            return 0 unless @material_map && @material_map.has_key?(material)
            @material_map[material]
        end
        # ---------------------------------------------------------------
    
    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
