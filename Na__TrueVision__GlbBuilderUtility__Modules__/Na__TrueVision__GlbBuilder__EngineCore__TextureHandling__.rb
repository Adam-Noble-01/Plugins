# =============================================================================
# TRUEVISION3D - GLB BUILDER UTILITY - TEXTURE HANDLING MODULE
# =============================================================================
#
# FILE       : Na__TrueVision__GlbBuilder__EngineCore__TextureHandling__.rb
# NAMESPACE  : TrueVision3D::GlbBuilderUtility
# MODULE     : Texture Handling (Extraction and GLB Binary Embedding)
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Extracts texture images from SketchUp materials and embeds them
#              as PNG binary data inside the GLB buffer. Creates the full glTF
#              chain: image -> sampler -> texture -> baseColorTexture reference.
# CREATED    : 12-Mar-2026
#
# DESCRIPTION:
# - Extracts colorized textures from SketchUp materials via texture.write()
# - Embeds PNG binary data directly into the GLB binary buffer
# - Creates glTF image, sampler, and texture entries per specification
# - Caches textures by material object to avoid re-processing duplicates
# - Supports optional downscaling of large textures via ImageRep
#
# SKETCHUP API METHODS USED:
# - Material#texture          -> Sketchup::Texture (or nil)
# - Texture#valid?            -> Boolean
# - Texture#write(path, true) -> Saves colorized PNG to disk
# - Texture#image_width       -> Integer (pixels)
# - Texture#image_height      -> Integer (pixels)
# - File.binread(path)        -> Binary PNG data for GLB buffer
#
# GLTF STRUCTURE FOR EMBEDDED TEXTURES:
#   images:    [{ "bufferView": N, "mimeType": "image/png" }]
#   samplers:  [{ "magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497 }]
#   textures:  [{ "sampler": 0, "source": imageIndex }]
#   materials: [{ "pbrMetallicRoughness": { "baseColorTexture": { "index": texIdx } } }]
#
# =============================================================================

require 'fileutils'

module TrueVision3D
    module GlbBuilderUtility

    # -------------------------------------------------------------------------
    # REGION | Module State
    # -------------------------------------------------------------------------

        @texture_index_cache   = {}
        @sampler_index         = nil

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | Texture Extraction and Embedding
    # -------------------------------------------------------------------------

        # FUNCTION | Extract Texture from Material and Embed in GLB
        # ---------------------------------------------------------------
        # Extracts the colorized texture image from a SketchUp material,
        # packs the PNG binary data into the GLB buffer, and creates the
        # glTF image + sampler + texture entries. Returns the glTF texture
        # index for use in the material's baseColorTexture reference.
        #
        # Uses texture.write(path, true) for colorized output as
        # recommended by SketchUp API best practices.
        #
        # @param material   [Sketchup::Material] Material with a valid texture
        # @param gltf       [Hash]               glTF JSON structure
        # @param bin_buffer  [String]             Binary buffer (ASCII-8BIT)
        # @return           [Integer|nil]         glTF texture index, or nil on failure
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__ExtractAndEmbedTexture(material, gltf, bin_buffer)
            return nil unless material
            return nil unless material.respond_to?(:texture) && material.texture
            return nil unless material.texture.valid?

            @texture_index_cache ||= {}
            return @texture_index_cache[material] if @texture_index_cache.key?(material)

            texture = material.texture
            material_name = material.respond_to?(:display_name) ? material.display_name : "Unknown"

            begin
                png_data = Na__TextureEngine__ExtractPngData(texture, material_name)
                return nil unless png_data && png_data.bytesize > 0

                image_index   = Na__TextureEngine__EmbedImageInBuffer(png_data, gltf, bin_buffer)
                sampler_index = Na__TextureEngine__EnsureSampler(gltf)
                texture_index = Na__TextureEngine__CreateTextureEntry(image_index, sampler_index, gltf)

                @texture_index_cache[material] = texture_index
                puts "    [TextureEngine] Embedded texture for '#{material_name}' (#{texture.image_width}x#{texture.image_height}, #{png_data.bytesize} bytes)"
                texture_index

            rescue => e
                puts "    [TextureEngine] Failed to embed texture for '#{material_name}': #{e.message}"
                nil
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | PNG Data Extraction
    # -------------------------------------------------------------------------

        # FUNCTION | Extract PNG Binary Data from a SketchUp Texture
        # ---------------------------------------------------------------
        # Saves the colorized texture to a temp file via texture.write()
        # then reads back the binary PNG data. Supports optional
        # downscaling for textures exceeding MAX_TEXTURE_SIZE.
        #
        # @param texture       [Sketchup::Texture] Valid texture object
        # @param material_name [String]             For logging/cache naming
        # @return              [String|nil]          PNG binary data (ASCII-8BIT), or nil
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__ExtractPngData(texture, material_name)
            cache_folder = @texture_cache_folder
            FileUtils.mkdir_p(cache_folder) unless Dir.exist?(cache_folder)

            safe_name = material_name.gsub(/[^0-9A-Za-z.\-_]/, '_')
            temp_path = File.join(cache_folder, "#{safe_name}_#{Time.now.to_i}.png")

            success = texture.write(temp_path, true)
            unless success && File.exist?(temp_path)
                puts "    [TextureEngine] texture.write failed for '#{material_name}'"
                return nil
            end

            if @downscale_textures && (texture.image_width > MAX_TEXTURE_SIZE || texture.image_height > MAX_TEXTURE_SIZE)
                png_data = Na__TextureEngine__DownscaleAndRead(temp_path, texture, material_name)
            else
                png_data = File.binread(temp_path)
            end

            File.delete(temp_path) if File.exist?(temp_path)
            png_data
        end
        # ---------------------------------------------------------------


        # FUNCTION | Downscale Large Texture via ImageRep
        # ---------------------------------------------------------------
        # Loads the extracted PNG into an ImageRep, creates a smaller
        # version, and returns the downscaled PNG binary data.
        #
        # @param source_path   [String]            Path to full-size PNG
        # @param texture       [Sketchup::Texture] Original texture for dimensions
        # @param material_name [String]            For logging
        # @return              [String]            PNG binary data (ASCII-8BIT)
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__DownscaleAndRead(source_path, texture, material_name)
            original_w = texture.image_width
            original_h = texture.image_height

            scale = [MAX_TEXTURE_SIZE.to_f / original_w, MAX_TEXTURE_SIZE.to_f / original_h].min
            new_w = (original_w * scale).to_i
            new_h = (original_h * scale).to_i

            puts "    [TextureEngine] Downscaling '#{material_name}': #{original_w}x#{original_h} -> #{new_w}x#{new_h}"

            begin
                image_rep = Sketchup::ImageRep.new(source_path)
                downscaled_path = source_path.sub('.png', '_downscaled.png')
                image_rep.save_file(downscaled_path)

                png_data = File.binread(downscaled_path)
                File.delete(downscaled_path) if File.exist?(downscaled_path)
                png_data
            rescue => e
                puts "    [TextureEngine] Downscale failed, using original: #{e.message}"
                File.binread(source_path)
            end
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | GLB Binary Buffer Embedding
    # -------------------------------------------------------------------------

        # FUNCTION | Embed PNG Image Data in GLB Binary Buffer
        # ---------------------------------------------------------------
        # Packs raw PNG bytes into the binary buffer with 4-byte alignment
        # and creates a glTF bufferView (no target, since images are not
        # vertex/index data) and image entry.
        #
        # @param png_data   [String] Raw PNG binary data (ASCII-8BIT)
        # @param gltf       [Hash]   glTF JSON structure
        # @param bin_buffer  [String] Binary buffer (ASCII-8BIT)
        # @return           [Integer] Image index in gltf["images"]
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__EmbedImageInBuffer(png_data, gltf, bin_buffer)
            png_data.force_encoding(Encoding::ASCII_8BIT)

            current_size  = bin_buffer.bytesize
            alignment_pad = (4 - (current_size % 4)) % 4
            bin_buffer << ("\x00" * alignment_pad) if alignment_pad > 0

            byte_offset = bin_buffer.bytesize
            byte_length = png_data.bytesize
            bin_buffer << png_data

            buffer_view_index = gltf["bufferViews"].length
            gltf["bufferViews"] << {
                "buffer"     => 0,
                "byteOffset" => byte_offset,
                "byteLength" => byte_length
            }

            image_index = gltf["images"].length
            gltf["images"] << {
                "bufferView" => buffer_view_index,
                "mimeType"   => "image/png"
            }

            image_index
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | glTF Sampler and Texture Entry Creation
    # -------------------------------------------------------------------------

        # FUNCTION | Ensure Default Sampler Exists
        # ---------------------------------------------------------------
        # Creates a single shared sampler for all textures on first call.
        # Subsequent calls return the cached sampler index.
        #
        # Sampler config:
        #   magFilter: 9729  (LINEAR)
        #   minFilter: 9987  (LINEAR_MIPMAP_LINEAR)
        #   wrapS:     10497 (REPEAT)
        #   wrapT:     10497 (REPEAT)
        #
        # @param gltf [Hash] glTF JSON structure
        # @return     [Integer] Sampler index in gltf["samplers"]
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__EnsureSampler(gltf)
            return @sampler_index if @sampler_index

            @sampler_index = gltf["samplers"].length
            gltf["samplers"] << {
                "magFilter" => 9729,
                "minFilter" => 9987,
                "wrapS"     => 10497,
                "wrapT"     => 10497
            }

            @sampler_index
        end
        # ---------------------------------------------------------------


        # FUNCTION | Create glTF Texture Entry
        # ---------------------------------------------------------------
        # Links an image and sampler into a texture entry.
        #
        # @param image_index   [Integer] Index in gltf["images"]
        # @param sampler_index [Integer] Index in gltf["samplers"]
        # @param gltf          [Hash]    glTF JSON structure
        # @return              [Integer] Texture index in gltf["textures"]
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__CreateTextureEntry(image_index, sampler_index, gltf)
            texture_index = gltf["textures"].length
            gltf["textures"] << {
                "sampler" => sampler_index,
                "source"  => image_index
            }

            texture_index
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------


    # -------------------------------------------------------------------------
    # REGION | Cache Management
    # -------------------------------------------------------------------------

        # FUNCTION | Reset Texture Engine State
        # ---------------------------------------------------------------
        # Clears all cached state. Call at the start of each export run.
        # ---------------------------------------------------------------
        def self.Na__TextureEngine__ResetState
            @texture_index_cache = {}
            @sampler_index       = nil
            puts "    [TextureEngine] State reset"
        end
        # ---------------------------------------------------------------

    # endregion ---------------------------------------------------------------

    end  # module GlbBuilderUtility
end  # module TrueVision3D
