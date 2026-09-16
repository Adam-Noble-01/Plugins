# frozen_string_literal: true

require_relative 'Na__Noble3dModellingTools__VegetationSketcher__TreeForms__'

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    # Pure millimetre geometry. No model mutations: shared vertices and outward
    # quad winding survive rounding, noise, preview and final triangulation.
    module Mesh
      MAX_QUADS = 80_000
      PREVIEW_QUADS = 2600
      VIEWPORT_QUADS = 1300

      def self.dimensions(o, length = nil)
        if o['preset'] == 'hedge'
          [o['path'] ? HedgePath.length(o['path']) : (length || o['length']), o['width'], o['height']]
        else
          [o['width'], o['depth'], o['height'] - (o['preset'] == 'tree' ? o['trunk_height'] : 0)]
        end
      end

      def self.divisions(dims, resolution)
        dims.map { |d| [(d / resolution.to_f).ceil, 2].max }
      end

      def self.grid(dims, resolution, path = nil)
        div = divisions(dims, resolution)
        if path
          div[0] = path[:segments].sum { |s| [(s[:mesh_length] / resolution).ceil, 1].max }
          div[1] = [(dims[1] * path[:width_scale] / resolution).ceil, 2].max
        end
        div
      end

      def self.count(dims, resolution, path = nil)
        x, y, z = grid(dims, resolution, path)
        2 * (x * y + x * z + y * z)
      end

      def self.build(o, length: nil, preview: false)
        dims = dimensions(o, length)
        path = o['preset'] == 'hedge' && o['path'] ? HedgePath.prepare(o['path'], o['width']) : nil
        resolution = o['resolution'].to_f
        requested = count(dims, resolution, path)
        if !preview && requested > MAX_QUADS
          raise ArgumentError, "#{requested.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} quads exceeds the 80,000 limit. Choose a coarser resolution or a smaller form."
        end
        if preview
          # Half the linear resolution while drawing: e.g. 100 mm -> 200 mm.
          # A separate cap also reduces work on full-size trees and long paths.
          viewport = preview == :viewport
          resolution *= 2.0 if viewport
          budget = viewport ? VIEWPORT_QUADS : PREVIEW_QUADS
          resolution *= 1.15 while count(dims, resolution, path) > budget
        end
        div = grid(dims, resolution, path)
        stations = path ? HedgePath.stations(path, resolution) : nil
        points, quads, lookup = [], [], {}
        # Each face shares integer lattice keys at seams. No disconnected panels.
        3.times do |axis|
          u, v = (axis + 1) % 3, (axis + 2) % 3
          [0, div[axis]].each do |side|
            div[u].times do |i|
              div[v].times do |j|
                ids = [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]].map do |a, b|
                  key = [0, 0, 0]
                  key[axis], key[u], key[v] = side, a, b
                  lookup[key] ||= begin
                    p = 3.times.map { |k| dims[k] * (key[k].to_f / div[k] - 0.5) }
                    p[0] = stations[key[0]] - dims[0] / 2.0 if stations
                    points << shape(p, dims, o, div, path: path)
                    points.length - 1
                  end
                end
                ids.reverse! if side.zero?
                quads << ids
              end
            end
          end
        end
        offset = o['preset'] == 'tree' ? o['trunk_height'] : 0.0
        points.each do |p|
          p[0] += dims[0] / 2.0 if o['preset'] == 'hedge' && !path
          p[2] += dims[2] / 2.0 + offset unless path
          p[2] = [p[2], 0.0].max
        end
        TreeForms.fit_dimensions!(points, dims, offset) if TreeForms.species?(o)
        { points: points, quads: quads, trunk: trunk(o), requested_quads: requested,
          resolution: resolution.round(1), preview_coarse: resolution > o['resolution'], dimensions: dims,
          path: o['path'], viewport_preview: preview == :viewport }
      end

      def self.shape(p, dims, o, div, path: nil)
        half = dims.map { |d| d / 2.0 }
        amount = o['soften'] / 100.0
        if o['preset'] == 'hedge'
          radius = half.min * amount * 0.95
          core = 3.times.map { |k| p[k].clamp(-half[k] + radius, half[k] - radius) }
          delta = 3.times.map { |k| p[k] - core[k] }
          magnitude = Math.sqrt(delta.sum { |x| x * x })
          rounded = magnitude.zero? ? p.dup : 3.times.map { |k| core[k] + delta[k] * radius / magnitude }
        else
          a = 3.times.map { |k| p[k] / half[k] }
          sphere = 3.times.map do |k|
            b, c = a[(k + 1) % 3]**2, a[(k + 2) % 3]**2
            a[k] * Math.sqrt([1.0 - b / 2 - c / 2 + b * c / 3, 0].max)
          end
          rounded = if TreeForms.species?(o)
                      TreeForms.crown(sphere, dims, o)
                    else
                      3.times.map { |k| p[k] * (1 - amount) + sphere[k] * half[k] * amount }
                    end
        end
        # Modifier order is deliberate: round first, then displace XYZ. Smooth
        # value-noise gives organic volume; small independent jitter gives facets.
        amplitude = [o['random'].to_f, dims.min * 0.18].min
        cell = 3.times.map { |k| dims[k] / div[k] }.min
        wave = [dims.min * 0.55, 250.0, amplitude * 8].max
        ground = ((rounded[2] + half[2]) / [half[2] * 0.35, 1].max).clamp(0.0, 1.0)
        ground = 1.0 if o['preset'] == 'tree'
        # The conifer's tiny leader/base cells must not receive the full jitter
        # of the broad lower crown; otherwise triangles can fold over the tip.
        detail = if TreeForms.species?(o) && o['tree_type'] == 'douglas_fir'
                   t = ((sphere[2] + 1.0) / 2.0).clamp(0.0, 1.0)
                   [t * 20.0, (1.0 - t) * 8.0, 1.0].min
                 else
                   1.0
                 end
        # Corner construction is part of the base form. XYZ displacement is
        # applied in the final hedge coordinates, after rounding and the sweep.
        rounded = HedgePath.warp([rounded[0] + half[0], rounded[1], rounded[2] + half[2]], path) if path
        3.times.map do |k|
          drift = noise(rounded.map { |x| x / wave }, o['seed'] + k * 103) * amplitude
          jitter = hash_noise(*(p.map { |x| (x * 100).round }), o['seed'] + k * 997) * [amplitude * 0.14, cell * 0.12].min * detail
          rounded[k] + (drift + jitter) * ground
        end
      end

      def self.hash_noise(x, y, z, seed)
        n = (x * 374761393 + y * 668265263 + z * 2147483647 + seed * 1274126177) & 0xffffffff
        n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
        ((n ^ (n >> 16)) & 0xffffffff) / 2147483647.5 - 1.0
      end

      def self.noise(p, seed)
        base = p.map(&:floor)
        t = 3.times.map { |k| f = p[k] - base[k]; f * f * (3 - 2 * f) }
        value = 0.0
        2.times do |x|
          2.times do |y|
            2.times do |z|
              weight = (x.zero? ? 1 - t[0] : t[0]) * (y.zero? ? 1 - t[1] : t[1]) * (z.zero? ? 1 - t[2] : t[2])
              value += weight * hash_noise(base[0] + x, base[1] + y, base[2] + z, seed)
            end
          end
        end
        value
      end

      def self.trunk(o)
        return { points: [], faces: [] } unless o['preset'] == 'tree'
        return TreeForms.timber(o) if TreeForms.species?(o)
        points = []
        [0, o['trunk_height'] + (o['height'] - o['trunk_height']) * 0.42].each_with_index do |z, level|
          8.times do |i|
            angle = i * Math::PI / 4
            r = o['trunk_diameter'] / 2.0 * (level.zero? ? 1.0 : 0.62)
            points << [Math.cos(angle) * r, Math.sin(angle) * r, z]
          end
        end
        faces = 8.times.map { |i| [i, (i + 1) % 8, (i + 1) % 8 + 8, i + 8] }
        faces << (0...8).to_a.reverse << (8...16).to_a
        { points: points, faces: faces }
      end
    end
  end
end
