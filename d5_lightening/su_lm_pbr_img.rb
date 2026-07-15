require "base64"
require "digest"
require "fileutils"
module Dimension5
  module Lightening
    module PbrTextureTool
      TEXPOOL = "PBR_TEXTURE_TOOL"
      MATDICT = "LITE_PBR"

      CHUNK_SIZE = 8 * 1024 * 1024

      CHANNELS = %w[
        normal
        roughness
        opacity
      ]

      def self.set_material_texture(material, channel, file_path)
        raise "Invalid channel: #{channel}" unless CHANNELS.include?(channel)

        raw = File.binread(file_path)
        hash = Digest::MD5.hexdigest(raw)

        store_texture_if_needed(Sketchup.active_model, hash, raw)

        dict = material.attribute_dictionary(MATDICT, true)
        dict["#{channel}_ref"] = hash
        dict["#{channel}_name"] = File.basename(file_path)

        hash
      end

      def self.get_material_texture_b64(material, channel)
        dict = material.attribute_dictionary(MATDICT, false)
        return nil unless dict

        hash = dict["#{channel}_ref"]
        return nil unless hash

        load_texture_b64(Sketchup.active_model, hash)
      end

      def self.export_material_texture(material, channel, out_dir)
        dict = material.attribute_dictionary(MATDICT, false)
        return nil unless dict

        hash = dict["#{channel}_ref"]
        return nil unless hash

        b64 = load_texture_b64(Sketchup.active_model, hash)
        return nil unless b64

        name = dict["#{channel}_name"] || "#{hash}.png"
        # if exsits, skip, return path
        out = File.join(out_dir, name)
        return out if File.exist?(out)

        File.binwrite(out, Base64.decode64(b64))
        out
      end

      def self.get_material_pbr(material)
        dict = material.attribute_dictionary(MATDICT, false)
        return {} unless dict

        result = {}
        CHANNELS.each do |ch|
          result[ch] = dict["#{ch}_ref"]
        end
        result
      end

      def self.store_texture_if_needed(model, hash, raw)
        pool = model.attribute_dictionary(TEXPOOL, true)
        count = normalize_chunk_count(pool["#{hash}_count"])
        if count
          cached = load_large_string(pool, hash)
          return if cached && !cached.empty?
          clear_large_string(pool, hash, count)
        end

        b64 = Base64.strict_encode64(raw)
        save_large_string(pool, hash, b64)
      end

      def self.load_texture_b64(model, hash)
        pool = model.attribute_dictionary(TEXPOOL, false)
        return nil unless pool

        load_large_string(pool, hash)
      end

      def self.save_large_string(dict, key, str)
        old_count = normalize_chunk_count(dict["#{key}_count"]) || 0
        chunks = str.bytes.each_slice(CHUNK_SIZE).map { |s| s.pack("C*") }

        chunks.each_with_index do |chunk, i|
          dict["#{key}_#{i}"] = chunk
        end
        dict["#{key}_count"] = chunks.size

        # Cleanup stale tail chunks when rewriting with fewer parts.
        (chunks.size...old_count).each do |i|
          dict.delete_key("#{key}_#{i}")
        end
      end

      def self.load_large_string(dict, key)
        count = normalize_chunk_count(dict["#{key}_count"])
        return nil unless count

        result = +"".b
        count.times do |i|
          chunk = dict["#{key}_#{i}"]
          unless chunk.is_a?(String)
            clear_large_string(dict, key, count)
            return nil
          end
          result << chunk
        end
        result
      end

      def self.normalize_chunk_count(value)
        return nil if value.nil?

        count = value.to_i
        return nil if count < 0

        count
      rescue StandardError
        nil
      end

      def self.clear_large_string(dict, key, count = nil)
        chunk_count = count || normalize_chunk_count(dict["#{key}_count"]) || 0
        chunk_count.times do |i|
          dict.delete_key("#{key}_#{i}")
        end
        dict.delete_key("#{key}_count")
      rescue StandardError
        nil
      end
    end
  end
end
