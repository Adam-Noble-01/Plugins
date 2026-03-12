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
#   :indexed_only   - Only standard indexed materials (MAT___) and exempt
#                     materials (MAT000E__) exported
# - Integrates with MaterialLookupSystem for PBR enrichment of indexed
#   materials, injecting opacity, metallic, roughness, and doubleSided
#   directly into the glTF material entries.
# - Integrates with TextureHandling to embed texture images in GLB binary.
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
# 12-Mar-2026 - Version 3.0.0
# - Integrated TextureHandling for PNG texture embedding in GLB binary.
# - Added bin_buffer parameter to EnsureMaterialRegistered and callers.
# - Added MAT000E__ exempt prefix support in indexed_only mode.
# - Face-only material resolution (no group/component inheritance).
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -----------------------------------------------------------------------------
    # REGION | Module State
    # -----------------------------------------------------------------------------

        @material_map  = {}
        @export_mode   = :no_materials

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

        # FUNCTION | Ensure Single Material Is Registered for Export
        # ---------------------------------------------------------------
        # Registers a SketchUp material into gltf["materials"] according
        # to the current export mode. Reuses @material_map if already
        # registered. Applies MaterialLookup enrichment for indexed
        # materials and embeds textures via TextureEngine when present.
        #
        # @param material   [Sketchup::Material|nil]
        # @param gltf       [Hash]    glTF JSON structure
        # @param bin_buffer  [String]  Binary buffer for texture embedding (ASCII-8BIT)
        # @return           [Integer]  glTF material index (0 = default fallback)
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__EnsureMaterialRegistered(material, gltf, bin_buffer = nil)
            return 0 if @export_mode == :no_materials
            return 0 unless material

            @material_map ||= {}
            return @material_map[material] if @material_map.key?(material)

            material_name = material.respond_to?(:display_name) ? material.display_name : ""
            is_indexed    = self.Na__MaterialLookup__IsIndexedMaterial?(material_name)
            is_exempt     = self.Na__MaterialLookup__IsExemptMaterial?(material_name)

            return 0 if @export_mode == :indexed_only && !is_indexed && !is_exempt

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

            # Enrich indexed materials with PBR metadata (not exempt materials).
            if is_indexed && (@export_mode == :indexed_only || @export_mode == :all_materials)
                library_data = self.Na__MaterialLookup__FetchLibrary
                if library_data
                    self.Na__MaterialLookup__BuildIndex
                    config = self.Na__MaterialLookup__GetConfig(material_name)
                    if config
                        self.Na__MaterialLookup__EnrichGltfMaterial(gltf_material, config)
                        puts "    [MaterialEngine] Enriched: #{material_name}"
                    end
                end
            end

            # Embed texture when material has a valid texture and bin_buffer is available.
            if bin_buffer && material.respond_to?(:texture) && material.texture && material.texture.valid?
                if respond_to?(:Na__TextureEngine__ExtractAndEmbedTexture)
                    texture_index = self.Na__TextureEngine__ExtractAndEmbedTexture(material, gltf, bin_buffer)
                    if texture_index
                        gltf_material["pbrMetallicRoughness"]["baseColorTexture"] = {
                            "index"    => texture_index,
                            "texCoord" => 0
                        }
                    end
                end
            end

            material_index = gltf["materials"].length
            gltf["materials"] << gltf_material
            @material_map[material] = material_index
            material_index
        end
        # ---------------------------------------------------------------

        # FUNCTION | Prepare Materials for GLB Export
        # ---------------------------------------------------------------
        # Builds the glTF materials array based on the current export
        # mode. Always provides a default whitecard material at index 0.
        # Resets TextureEngine state for a clean export run.
        #
        # Modes:
        #   :no_materials  - Only the default material, all meshes use index 0
        #   :all_materials - All unique materials exported, indexed ones enriched
        #   :indexed_only  - Only indexed/exempt materials exported, others default
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__PrepareMaterialsForExport(face_groups, gltf, binary_buffer)
            @material_map ||= {}
            @material_map.clear

            if respond_to?(:Na__TextureEngine__ResetState)
                self.Na__TextureEngine__ResetState
            end

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

            unique_materials = []
            face_groups.each_value do |group_data|
                material = group_data[:material]
                next unless material
                unique_materials << material unless unique_materials.include?(material)
            end

            if @export_mode == :indexed_only || @export_mode == :all_materials
                library_data = self.Na__MaterialLookup__FetchLibrary
                if library_data
                    self.Na__MaterialLookup__BuildIndex
                end
            end

            unique_materials.each do |material|
                self.Na__MaterialEngine__EnsureMaterialRegistered(material, gltf, binary_buffer)
            end

            mode_label = (@export_mode == :indexed_only) ? "indexed-only" : "all-materials"
            puts "    [MaterialEngine] #{mode_label} mode: #{@material_map.length} material(s) exported"
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
        # or if no-materials mode is active. When gltf and bin_buffer are
        # provided, registers the material on demand so all mesh export
        # paths use the same indexed-material rules.
        # ---------------------------------------------------------------
        def self.Na__MaterialEngine__ResolveMaterialIndexForGroup(group_data, gltf = nil, bin_buffer = nil)
            return 0 if @export_mode == :no_materials

            material = group_data[:material]
            return 0 unless material
            if gltf
                return self.Na__MaterialEngine__EnsureMaterialRegistered(material, gltf, bin_buffer)
            end
            return 0 unless @material_map && @material_map.has_key?(material)
            @material_map[material]
        end
        # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
