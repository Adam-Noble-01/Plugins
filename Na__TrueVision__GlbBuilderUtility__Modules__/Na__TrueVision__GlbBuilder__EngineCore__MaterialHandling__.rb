# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - MATERIAL HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Material Handling
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Material processing for GLB export with 3 export modes
# CREATED    : 2025
#
# DESCRIPTION:
# - Supports three material export modes controlled via the UI:
#   :no_materials   - Sanitised whitecard export (all meshes use default)
#   :all_materials  - All SketchUp materials exported with PBR enrichment
#   :indexed_only   - Only standard indexed materials (MAT___) exported
# - Integrates with MaterialLookupSystem for PBR enrichment of indexed
#   materials, injecting opacity, metallic, roughness, and doubleSided
#   directly into the glTF material entries.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 2025 - Version 1.0.0
# - Initial debug-safe implementation with texture export disabled.
#
# 23-Feb-2026 - Version 2.0.0
# - Added three export modes: no_materials, all_materials, indexed_only.
# - Integrated MaterialLookupSystem for PBR enrichment of indexed materials.
# - Added IsDoubleSided support for glTF doubleSided flag.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Module State
    # -----------------------------------------------------------------------------

        # MODULE VARIABLES | Material Export State
        # ------------------------------------------------------------
        @material_map  = {}                                                   # <-- { SketchUp::Material => glTF index }
        @export_mode   = :no_materials                                        # <-- Current export mode
        # ------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Export Mode Control
    # -----------------------------------------------------------------------------

        # FUNCTION | Set Material Export Mode
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__SetExportMode(mode)
            valid_modes = [:no_materials, :all_materials, :indexed_only]
            unless valid_modes.include?(mode)
                puts "    [MaterialEngine] Invalid export mode: #{mode}, defaulting to :no_materials"
                mode = :no_materials
            end
            @export_mode = mode
            puts "    [MaterialEngine] Export mode set to: #{mode}"
        end
        # ---------------------------------------------------------------


        # FUNCTION | Get Current Material Export Mode
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__GetExportMode
            @export_mode
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Material Processing
    # -----------------------------------------------------------------------------

        # FUNCTION | Prepare Materials for GLB Export
        # ---------------------------------------------------------------
        # Builds the glTF materials array based on the current export
        # mode. Always provides a default whitecard material at index 0.
        #
        # Modes:
        #   :no_materials  - Only the default material, all meshes use index 0
        #   :all_materials - All unique materials exported, indexed ones enriched
        #   :indexed_only  - Only indexed materials exported, others use default
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__PrepareMaterialsForExport(face_groups, gltf, _binary_buffer)
            @material_map ||= {}
            @material_map.clear

            # DEFAULT FALLBACK MATERIAL (always at index 0)
            gltf["materials"] << {
                "name" => "Default",
                "pbrMetallicRoughness" => {
                    "baseColorFactor" => [0.8, 0.8, 0.8, 1.0],
                    "metallicFactor"  => 0.0,
                    "roughnessFactor" => 1.0
                }
            }

            if @export_mode == :no_materials
                puts "    [MaterialEngine] No-materials mode: all meshes will use default whitecard"
                return true
            end

            # COLLECT UNIQUE MATERIALS FROM FACE GROUPS
            unique_materials = []
            face_groups.each_value do |group_data|
                material = group_data[:material]
                next unless material
                unique_materials << material unless unique_materials.include?(material)
            end

            # BUILD LOOKUP INDEX (fetch library if not already cached)
            lookup_available = false
            if @export_mode == :indexed_only || @export_mode == :all_materials
                library_data = self.Na__MaterialLookup__FetchLibrary
                if library_data
                    self.Na__MaterialLookup__BuildIndex
                    lookup_available = true
                end
            end

            # PROCESS EACH UNIQUE MATERIAL
            material_index = 0
            unique_materials.each do |material|
                material_name = material.respond_to?(:display_name) ? material.display_name : ""
                is_indexed    = self.Na__MaterialLookup__IsIndexedMaterial?(material_name)

                # INDEXED-ONLY MODE: skip non-indexed materials
                if @export_mode == :indexed_only && !is_indexed
                    next
                end

                material_index += 1
                @material_map[material] = material_index

                # EXTRACT BASE COLOUR FROM SKETCHUP MATERIAL
                rgba = if material.respond_to?(:color) && material.color
                    c = material.color
                    [c.red.to_f / 255.0, c.green.to_f / 255.0, c.blue.to_f / 255.0, 1.0]
                else
                    [0.8, 0.8, 0.8, 1.0]
                end

                gltf_material = {
                    "name" => material_name,
                    "pbrMetallicRoughness" => {
                        "baseColorFactor" => rgba,
                        "metallicFactor"  => 0.0,
                        "roughnessFactor" => 1.0
                    }
                }

                # ENRICH WITH PBR VALUES FROM LIBRARY (if indexed and lookup available)
                if is_indexed && lookup_available
                    config = self.Na__MaterialLookup__GetConfig(material_name)
                    if config
                        self.Na__MaterialLookup__EnrichGltfMaterial(gltf_material, config)
                        puts "    [MaterialEngine] Enriched: #{material_name}"
                    end
                end

                gltf["materials"] << gltf_material
            end

            mode_label = (@export_mode == :indexed_only) ? "indexed-only" : "all-materials"
            puts "    [MaterialEngine] #{mode_label} mode: #{material_index} material(s) exported"
            true
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Material Index Resolution
    # -----------------------------------------------------------------------------

        # FUNCTION | Resolve Material Index for Group Data
        # ---------------------------------------------------------------
        # Returns the glTF material index for a face group's material.
        # Returns 0 (default whitecard) if the material was not exported
        # or if no-materials mode is active.
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__ResolveMaterialIndexForGroup(group_data)
            return 0 if @export_mode == :no_materials                         # <-- All meshes use default

            material = group_data[:material]
            return 0 unless material
            return 0 unless @material_map && @material_map.has_key?(material)
            @material_map[material]
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
