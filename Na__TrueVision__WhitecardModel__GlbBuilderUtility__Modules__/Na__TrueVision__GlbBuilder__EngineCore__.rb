# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - ENGINE CORE MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Engine Core (GLB Export Orchestrator + File Writer)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Orchestrates export flow and writes GLB binary files
# CREATED    : 2025
# REWRITTEN  : 2026-02-10 (v1.1.0 - Non-destructive Virtual Flattening)
#
# IMPORTANT!
# - This module is the orchestrator for the GLB export process.
#   - Uses `Na__TrueVision__GlbBuilder__EngineCore__GeometryHandling__.rb` for geometry.
#   - Uses `Na__TrueVision__GlbBuilder__EngineCore__MaterialHandling__.rb` for materials.
# - Export is fully NON-DESTRUCTIVE: the SketchUp model is never modified.
#   No start_operation / abort_operation is needed.
#
# =============================================================================

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Export Orchestration
    # -------------------------------------------------------------------------

        # FUNCTION | Export Entities to GLB Format (Virtual Flattening)
        # ---------------------------------------------------------------
        # Non-destructive export: recursively traverses the scene graph
        # accumulating transforms, extracts geometry in world space,
        # packs into binary buffers, and writes a valid GLB file.
        #
        # @param entities [Array<Sketchup::Entity>] Top-level entities to export
        # @param filepath [String] Output GLB file path
        # @return [Boolean] true on success, false on failure
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__ExportEntitiesToGlb(entities, filepath)
            filepath += GLB_FILE_EXTENSION unless filepath.end_with?(GLB_FILE_EXTENSION)
            puts "  Using virtual flattening for non-destructive world-space export..."

            begin
                # Phase 1: Create geometry buckets and root transform
                buckets        = Na__GlbEngine__CreateBuckets()
                root_transform = Z_UP_TO_Y_UP_MATRIX
                entity_count   = 0

                # Phase 2: Traverse each top-level entity into the bucket store
                entities.each do |entity|
                    next if Na__Helpers__EntityExcluded?(entity)

                    if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
                        entity_count += 1
                        entity_name = Na__GlbEngine__SanitizeEntityName(entity)
                        puts "    Traversing: #{entity_name}..."

                        # Accumulate this entity's transform with the root Y-up conversion
                        accumulated_transform = root_transform * entity.transformation
                        # Top-level entities define their own layer context
                        entity_layer = entity.layer

                        Na__GlbEngine__TraverseEntities(
                            entity.definition.entities,
                            accumulated_transform,
                            entity_layer,
                            buckets
                        )

                    elsif entity.is_a?(Sketchup::Face)
                        # Bare face at model root (uncommon but handled for safety)
                        is_mirrored   = Na__GlbEngine__CalcDeterminant3x3(root_transform) < 0
                        normal_matrix = Na__GlbEngine__CalcNormalMatrix(root_transform)
                        layer_name    = entity.layer.name
                        Na__GlbEngine__AddFaceToBucket(entity, root_transform, normal_matrix, is_mirrored, layer_name, buckets)

                    elsif entity.is_a?(Sketchup::Edge) && MESH_MODEL_INCLUDE_EDGES
                        # Bare hard edge at model root (when MESH_MODEL_INCLUDE_EDGES is true)
                        if !entity.soft? && !entity.smooth?
                            layer_name = entity.layer.name
                            Na__GlbEngine__AddEdgeToBucket(entity, root_transform, layer_name, buckets)
                        end
                    end
                end

                # Report traversal results
                total_verts = 0
                total_tris  = 0
                buckets.each_value do |b|
                    total_verts += b[:vertex_count]
                    total_tris  += b[:indices].length / 3
                end
                puts "    Traversal complete: #{entity_count} entities -> #{buckets.length} buckets, #{total_verts} vertices, #{total_tris} triangles"

                # Phase 3: Build glTF structure and pack binary buffers
                gltf, bin_buffer = Na__GlbEngine__BuildGltfFromBuckets(buckets)

                # Phase 4: Write GLB file to disk
                Na__GlbEngine__WriteGlbFile(filepath, gltf, bin_buffer)

                puts "  ✓ Export complete (non-destructive, model unchanged)"
                true

            rescue => e
                puts "  ERROR: Export failed - #{e.message}"
                puts "  #{e.backtrace.first(5).join("\n  ")}"
                false
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | GLB File Writing
    # -------------------------------------------------------------------------

        # FUNCTION | Write GLB File to Disk
        # ---------------------------------------------------------------
        # Constructs and writes a valid GLB (glTF 2.0 Binary) file.
        # Binary chunks are 4-byte aligned per specification:
        #   JSON chunk padded with 0x20 (space)
        #   BIN  chunk padded with 0x00 (null)
        #
        # @param filepath   [String] Output file path
        # @param gltf       [Hash]   glTF JSON structure
        # @param bin_buffer  [String] Binary buffer (ASCII-8BIT encoded string)
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__WriteGlbFile(filepath, gltf, bin_buffer)
            # Remove empty optional arrays from JSON to keep output clean
            gltf.delete("images")   if gltf["images"]   && gltf["images"].empty?
            gltf.delete("textures") if gltf["textures"]  && gltf["textures"].empty?
            gltf.delete("samplers") if gltf["samplers"]  && gltf["samplers"].empty?

            # Ensure binary buffer is a proper binary string
            binary_data = bin_buffer.is_a?(String) ? bin_buffer.dup : bin_buffer.pack('C*')
            binary_data.force_encoding(Encoding::ASCII_8BIT)

            # Pad BIN chunk to 4-byte boundary with null bytes (0x00)
            bin_padding = (4 - (binary_data.bytesize % 4)) % 4
            binary_data << ("\x00" * bin_padding) if bin_padding > 0

            # Set buffer length in JSON (must match BIN chunk data length)
            gltf["buffers"] = [{ "byteLength" => binary_data.bytesize }]

            # Serialize and pad JSON to 4-byte boundary with spaces (0x20)
            json_string = JSON.generate(gltf)
            json_padding = (4 - (json_string.bytesize % 4)) % 4
            json_string += " " * json_padding if json_padding > 0

            # Calculate total GLB file size: Header + JSON chunk + BIN chunk
            total_size = 12 + 8 + json_string.bytesize + 8 + binary_data.bytesize

            # Write GLB binary file
            File.open(filepath, 'wb') do |file|
                # Header (12 bytes)
                file.write([GLB_MAGIC].pack('V'))               # Magic: "glTF"
                file.write([GLB_VERSION].pack('V'))             # Version: 2
                file.write([total_size].pack('V'))              # Total file length

                # Chunk 0: JSON
                file.write([json_string.bytesize].pack('V'))    # Chunk length
                file.write([GLB_CHUNK_TYPE_JSON].pack('V'))     # Chunk type: "JSON"
                file.write(json_string)                         # JSON payload

                # Chunk 1: BIN
                file.write([binary_data.bytesize].pack('V'))    # Chunk length
                file.write([GLB_CHUNK_TYPE_BIN].pack('V'))      # Chunk type: "BIN\0"
                file.write(binary_data)                         # Binary payload
            end

            puts "GLB file written: #{filepath} (#{total_size} bytes, BIN: #{binary_data.bytesize} bytes)"
            Na__GlbEngine__ValidateGlbStructure(filepath)
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Validate GLB Structure
        # ---------------------------------------------------------------
        # Reads back the GLB file and verifies the header magic, version,
        # and chunk structure for correctness.
        # ---------------------------------------------------------------
        def self.Na__GlbEngine__ValidateGlbStructure(filepath)
            puts "\n  Validating GLB structure..."

            File.open(filepath, 'rb') do |file|
                magic   = file.read(4)
                version = file.read(4).unpack('V')[0]
                length  = file.read(4).unpack('V')[0]

                puts "    Magic: #{magic} (should be 'glTF')"
                puts "    Version: #{version} (should be 2)"
                puts "    File size: #{length} bytes"

                valid = true
                valid = false unless magic == 'glTF'
                valid = false unless version == 2

                chunk_count = 0
                while file.pos < length
                    chunk_length = file.read(4).unpack('V')[0]
                    chunk_type   = file.read(4)

                    chunk_count += 1
                    puts "    Chunk #{chunk_count}: #{chunk_type.inspect}, Length: #{chunk_length} bytes"
                    file.seek(chunk_length, IO::SEEK_CUR)
                end

                puts "  ✓ GLB validation #{valid ? 'passed' : 'FAILED'}"
                valid
            end
        rescue => e
            puts "  ✗ GLB Validation Error: #{e.message}"
            false
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
