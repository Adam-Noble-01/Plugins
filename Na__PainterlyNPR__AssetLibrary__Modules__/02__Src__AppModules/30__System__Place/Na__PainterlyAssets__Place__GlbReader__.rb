# =============================================================================
# NA PAINTERLYNPR ASSETS - PLACE - GLB READER
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Place__GlbReader__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__GlbReader
# PURPOSE    : Reads an asset's MOD (the factory's binary glTF proxy) into plain
#              triangle lists, one per mesh primitive, each with its material,
#              every position carried through its node's transform into the
#              asset's own frame (metres, +Y up, front +Z, origin at the base
#              centre). Pure Ruby: nothing here touches the model.
# CREATED    : 30-Oct-2026
#
# WHAT IT READS (glTF 2.0, GLB container):
# - The 12 byte header, then the JSON chunk and the BIN chunk.
# - The default scene's node tree, each node's matrix or its translation,
#   rotation (a quaternion) and scale, multiplied root first.
# - Triangle primitives (mode 4, the default): POSITION, and indices when
#   there are any (the factory's are not indexed: three corners per
#   triangle). A node whose transform mirrors (determinant below 0) has its
#   triangles' winding reversed, so faces still point out.
# - Each material's name, baseColorFactor (linear RGBA), doubleSided, and the
#   factory's extras (MaterialClass, Label).
#
# WHAT IT REFUSES, SAYING WHY: a file that is not GLB 2, a required extension
# (Draco or meshopt compression, quantised positions), sparse accessors, an
# external buffer. Points, lines and strips are skipped and counted.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__GlbReader

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_GLB_MAGIC      = 0x46546C67 unless defined?(NA_GLB_MAGIC)                                # <-- 'glTF'
        NA_CHUNK_JSON     = 0x4E4F534A unless defined?(NA_CHUNK_JSON)                               # <-- 'JSON'
        NA_CHUNK_BIN      = 0x004E4942 unless defined?(NA_CHUNK_BIN)                                # <-- 'BIN\0'
        NA_MODE_TRIANGLES = 4          unless defined?(NA_MODE_TRIANGLES)
        NA_MAX_NODE_DEPTH = 64         unless defined?(NA_MAX_NODE_DEPTH)                           # <-- A node tree deeper than this is a loop
        NA_IDENTITY       = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0].freeze unless defined?(NA_IDENTITY)

        # componentType => [String#unpack directive, bytes]: little-endian, as glTF is
        NA_COMPONENTS = {
            5120 => ['c',  1], 5121 => ['C',  1],
            5122 => ['s<', 2], 5123 => ['S<', 2],
            5125 => ['L<', 4], 5126 => ['e',  4]
        }.freeze unless defined?(NA_COMPONENTS)

        NA_WIDTHS = { 'SCALAR' => 1, 'VEC2' => 2, 'VEC3' => 3, 'VEC4' => 4, 'MAT4' => 16 }.freeze unless defined?(NA_WIDTHS)

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Read a GLB File's JSON and Binary Chunks
        # ------------------------------------------------------------
        # @return [Hash] { 'json' => Hash, 'bin' => String (binary), 'file' => basename }
        def self.Na__Glb__Read(path)
            name = File.basename(path)
            data = File.binread(path)
            raise "#{name} is too short to be a GLB file." if data.bytesize < 20

            magic, version, length = data.unpack('L<3')
            raise "#{name} is not a GLB file." unless magic == NA_GLB_MAGIC
            raise "#{name} is glTF #{version}; only glTF 2 is read." unless version == 2
            raise "#{name} is shorter than its header says (#{data.bytesize} of #{length} bytes)." if length > data.bytesize

            json   = nil
            bin    = nil
            offset = 12
            while offset + 8 <= length
                chunk_length, chunk_type = data.unpack('L<2', offset: offset)
                body = data.byteslice(offset + 8, chunk_length)
                json = JSON.parse(body.force_encoding('UTF-8')) if chunk_type == NA_CHUNK_JSON && json.nil?
                bin  = body if chunk_type == NA_CHUNK_BIN && bin.nil?
                offset += 8 + chunk_length
            end
            raise "#{name} has no JSON chunk." unless json.is_a?(Hash)

            required = Array(json['extensionsRequired'])
            raise "#{name} needs glTF extensions this reader does not decode: #{required.join(', ')}." unless required.empty?

            { 'json' => json, 'bin' => bin || ''.b, 'file' => name }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Every Triangle Primitive in the Default Scene, in the Asset's Frame
        # ------------------------------------------------------------
        # @param glb [Hash] from Na__Glb__Read
        # @return [Hash] { 'primitives' => [{ 'label', 'positions', 'triangles', 'material' }], 'skipped' => Integer }
        def self.Na__Glb__Primitives(glb)
            json       = glb['json']
            nodes      = Array(json['nodes'])
            scenes     = Array(json['scenes'])
            scene      = scenes[(json['scene'] || 0).to_i]
            roots      = scene ? Array(scene['nodes']) : (0...nodes.length).to_a                     # <-- No scene at all: every node is a root
            primitives = []
            skipped    = 0
            stack      = roots.reverse.map { |index| [index.to_i, NA_IDENTITY, 0] }

            until stack.empty?
                index, parent, depth = stack.pop
                raise "#{glb['file']}: its node tree is deeper than #{NA_MAX_NODE_DEPTH} (a loop?)." if depth > NA_MAX_NODE_DEPTH

                node = nodes[index]
                raise "#{glb['file']}: node #{index} does not exist." unless node.is_a?(Hash)

                matrix = self.na_multiply(parent, self.na_node_matrix(node))
                if node.key?('mesh')
                    mesh = Array(json['meshes'])[node['mesh'].to_i]
                    raise "#{glb['file']}: mesh #{node['mesh']} does not exist." unless mesh.is_a?(Hash)

                    label = node['name'] || mesh['name'] || "Mesh #{node['mesh']}"
                    Array(mesh['primitives']).each_with_index do |primitive, number|
                        record = self.na_read_primitive(glb, primitive, matrix, "#{label} #{number}")
                        if record
                            primitives << record
                        else
                            skipped += 1
                        end
                    end
                end
                Array(node['children']).reverse_each { |child| stack.push([child.to_i, matrix, depth + 1]) }
            end

            { 'primitives' => primitives, 'skipped' => skipped }
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - Primitives, Accessors, Materials
    # -------------------------------------------------------------------------

        # nil for a primitive that is not triangles (counted by the caller).
        def self.na_read_primitive(glb, primitive, matrix, label)
            mode = primitive.key?('mode') ? primitive['mode'].to_i : NA_MODE_TRIANGLES
            return nil unless mode == NA_MODE_TRIANGLES

            attributes = primitive['attributes'] || {}
            raise "#{glb['file']}: a primitive has no POSITION." unless attributes.key?('POSITION')

            positions = self.na_read_accessor(glb, attributes['POSITION'].to_i).map { |point| self.na_transform(matrix, point) }
            indices   = primitive.key?('indices') ? self.na_read_accessor(glb, primitive['indices'].to_i).flatten : (0...positions.length).to_a
            triangles = indices.each_slice(3).select { |corners| corners.length == 3 }
            triangles = triangles.map(&:reverse) if self.na_determinant(matrix) < 0.0               # <-- A mirroring node turns every face inside out

            limit = positions.length
            bad   = triangles.find { |corners| corners.any? { |corner| corner.to_i >= limit || corner.to_i < 0 } }
            raise "#{glb['file']}: a triangle points past its #{limit} positions." if bad

            {
                'label'     => label,
                'positions' => positions,
                'triangles' => triangles,
                'material'  => self.na_material(glb['json'], primitive['material'])
            }
        end

        # One accessor as an array of tuples (or of numbers for SCALAR).
        def self.na_read_accessor(glb, index)
            json     = glb['json']
            accessor = Array(json['accessors'])[index]
            raise "#{glb['file']}: accessor #{index} does not exist." unless accessor.is_a?(Hash)
            raise "#{glb['file']}: sparse accessors are not read." if accessor.key?('sparse')

            directive, size = NA_COMPONENTS[accessor['componentType'].to_i]
            width           = NA_WIDTHS[accessor['type'].to_s]
            raise "#{glb['file']}: accessor #{index} has an unknown componentType or type." unless directive && width

            count = accessor['count'].to_i
            return [] if count.zero?
            raise "#{glb['file']}: accessor #{index} has no bufferView." unless accessor.key?('bufferView')

            view   = Array(json['bufferViews'])[accessor['bufferView'].to_i]
            raise "#{glb['file']}: bufferView #{accessor['bufferView']} does not exist." unless view.is_a?(Hash)

            buffer = Array(json['buffers'])[view['buffer'].to_i]
            raise "#{glb['file']}: only the GLB's own buffer is read, not #{buffer && buffer['uri'] ? 'an external one' : "buffer #{view['buffer']}"}." if view['buffer'].to_i != 0 || (buffer && buffer['uri'])

            element = size * width
            stride  = (view['byteStride'] || element).to_i
            start   = (view['byteOffset'] || 0).to_i + (accessor['byteOffset'] || 0).to_i
            finish  = start + stride * (count - 1) + element
            raise "#{glb['file']}: accessor #{index} runs past the end of its buffer." if finish > glb['bin'].bytesize

            values = if stride == element
                         glb['bin'].byteslice(start, count * element).unpack("#{directive}*")
                     else
                         (0...count).flat_map { |item| glb['bin'].byteslice(start + item * stride, element).unpack("#{directive}#{width}") }
                     end
            width == 1 ? values : values.each_slice(width).to_a
        end

        def self.na_material(json, index)
            return nil if index.nil?

            material = Array(json['materials'])[index.to_i]
            return nil unless material.is_a?(Hash)

            pbr    = material['pbrMetallicRoughness'] || {}
            extras = material['extras'].is_a?(Hash) ? material['extras'] : {}
            rgba   = Array(pbr['baseColorFactor'] || [1.0, 1.0, 1.0, 1.0]).map(&:to_f)
            rgba  += [1.0] * (4 - rgba.length) if rgba.length < 4
            {
                'index'         => index.to_i,
                'name'          => material['name'].to_s,
                'materialClass' => extras['MaterialClass'].to_s,
                'label'         => extras['Label'].to_s,
                'rgba'          => rgba.first(4),                                                    # <-- Linear, as glTF stores it: Na__ProxyBuilder turns it into sRGB
                'doubleSided'   => material['doubleSided'] == true
            }
        end

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals - 4x4 Matrices (column-major, as glTF writes them)
    # -------------------------------------------------------------------------

        def self.na_node_matrix(node)
            matrix = node['matrix']
            return matrix.map(&:to_f) if matrix.is_a?(Array) && matrix.length == 16

            tx, ty, tz     = Array(node['translation'] || [0, 0, 0]).map(&:to_f)
            qx, qy, qz, qw = Array(node['rotation']    || [0, 0, 0, 1]).map(&:to_f)
            sx, sy, sz     = Array(node['scale']       || [1, 1, 1]).map(&:to_f)
            [
                (1 - 2 * (qy * qy + qz * qz)) * sx, (2 * (qx * qy + qw * qz)) * sx,     (2 * (qx * qz - qw * qy)) * sx,     0.0,
                (2 * (qx * qy - qw * qz)) * sy,     (1 - 2 * (qx * qx + qz * qz)) * sy, (2 * (qy * qz + qw * qx)) * sy,     0.0,
                (2 * (qx * qz + qw * qy)) * sz,     (2 * (qy * qz - qw * qx)) * sz,     (1 - 2 * (qx * qx + qy * qy)) * sz, 0.0,
                tx,                                 ty,                                 tz,                                 1.0
            ]
        end

        # a * b: b applies first, as a parent's matrix times its child's.
        def self.na_multiply(a, b)
            (0...16).map do |cell|
                column = cell / 4
                row    = cell % 4
                (0...4).sum { |k| a[k * 4 + row] * b[column * 4 + k] }
            end
        end

        def self.na_transform(m, point)
            x, y, z = point.map(&:to_f)
            [
                m[0] * x + m[4] * y + m[8]  * z + m[12],
                m[1] * x + m[5] * y + m[9]  * z + m[13],
                m[2] * x + m[6] * y + m[10] * z + m[14]
            ]
        end

        def self.na_determinant(m)
            m[0] * (m[5] * m[10] - m[9] * m[6]) -
                m[4] * (m[1] * m[10] - m[9] * m[2]) +
                m[8] * (m[1] * m[6] - m[5] * m[2])
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
