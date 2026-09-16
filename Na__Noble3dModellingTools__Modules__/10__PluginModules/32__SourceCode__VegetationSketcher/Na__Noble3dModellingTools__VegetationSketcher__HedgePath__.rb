# frozen_string_literal: true

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    # Planar sweep with shared miter sections. A bend is one cross section of
    # one closed surface: there are no internal end caps or overlapping boxes.
    module HedgePath
      def self.validate(raw)
        return nil if raw.nil?
        raise ArgumentError, 'A hedge path needs 2 to 256 points.' unless raw.is_a?(Array) && raw.length.between?(2, 256)
        points = raw.map do |point|
          raise ArgumentError, 'Invalid hedge path point.' unless point.is_a?(Array) && point.length == 3
          p = point.map { |n| Float(n) }
          raise ArgumentError, 'Hedge path coordinates must be finite.' unless p.all?(&:finite?)
          raise ArgumentError, 'Hedge paths must stay on their horizontal planting plane.' if p[2].abs > 0.001
          [p[0], p[1], 0.0]
        end
        lengths = points.each_cons(2).map { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
        raise ArgumentError, 'Each hedge run must be at least 50 mm.' if lengths.any? { |n| n < 49.999 }
        raise ArgumentError, 'Keep the total hedge path within 100 m.' if lengths.sum > 100000.001
        points
      end

      def self.length(points)
        points.each_cons(2).sum { |a, b| Math.hypot(b[0] - a[0], b[1] - a[1]) }
      end

      def self.dot(a, b); a[0] * b[0] + a[1] * b[1]; end

      def self.prepare(points, width)
        segments = points.each_cons(2).map do |a, b|
          distance = Math.hypot(b[0] - a[0], b[1] - a[1])
          tangent = [(b[0] - a[0]) / distance, (b[1] - a[1]) / distance]
          { length: distance, tangent: tangent, normal: [-tangent[1], tangent[0]] }
        end
        miters = points.each_index.map do |i|
          if i.zero?
            segments.first[:normal]
          elsif i == points.length - 1
            segments.last[:normal]
          else
            a, b = segments[i - 1], segments[i]
            denominator = 1 + dot(a[:tangent], b[:tangent])
            raise ArgumentError, 'This turn is too sharp. Add a wider turn instead of doubling back.' if denominator < 0.15
            2.times.map { |k| (a[:normal][k] + b[:normal][k]) / denominator }
          end
        end
        total = 0.0
        segments.each_with_index do |segment, i|
          shear = dot(2.times.map { |k| miters[i + 1][k] - miters[i][k] }, segment[:tangent]).abs * width / 2.0
          raise ArgumentError, 'Lengthen the run at this corner, or reduce the hedge width.' if segment[:length] <= shear + 2
          segment[:mesh_length] = segment[:length] + shear
          segment[:start] = total
          total += segment[:length]
          segment[:finish] = total
        end
        # Check the outline, including parallel runs that would overlap at this
        # width. Reject an invalid sweep before allocating a mesh or model data.
        left = points.each_with_index.map { |p, i| 2.times.map { |k| p[k] + miters[i][k] * width / 2.0 } }
        right = points.each_with_index.map { |p, i| 2.times.map { |k| p[k] - miters[i][k] * width / 2.0 } }
        outline = left + right.reverse
        outline.each_index do |i|
          (i + 2...outline.length).each do |j|
            next if i.zero? && j == outline.length - 1
            if intersects?(outline[i], outline[(i + 1) % outline.length], outline[j], outline[(j + 1) % outline.length])
              raise ArgumentError, 'These hedge runs overlap. Space the path farther apart or reduce its width.'
            end
          end
        end
        { points: points, miters: miters, segments: segments, length: total,
          width_scale: miters.map { |v| Math.hypot(*v) }.max }
      end

      def self.intersects?(a, b, c, d)
        cross = lambda { |p, q, r| (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0]) }
        x, y, z, w = cross.call(a, b, c), cross.call(a, b, d), cross.call(c, d, a), cross.call(c, d, b)
        return true if x * y < 0 && z * w < 0
        [[x, c, a, b], [y, d, a, b], [z, a, c, d], [w, b, c, d]].any? do |area, p, q, r|
          area.abs < 0.0001 && p[0].between?([q[0], r[0]].min - 0.001, [q[0], r[0]].max + 0.001) &&
            p[1].between?([q[1], r[1]].min - 0.001, [q[1], r[1]].max + 0.001)
        end
      end

      def self.stations(path, resolution)
        values = [0.0]
        path[:segments].each do |segment|
          n = [(segment[:mesh_length] / resolution).ceil, 1].max
          1.upto(n) { |i| values << segment[:start] + segment[:length] * i / n.to_f }
        end
        values
      end

      def self.warp(point, path)
        s, y, z = point
        index = path[:segments].bsearch_index { |segment| segment[:finish] >= s } || path[:segments].length - 1
        segment = path[:segments][index]
        t = (s - segment[:start]) / segment[:length]
        a, b = path[:points][index], path[:points][index + 1]
        n0, n1 = path[:miters][index], path[:miters][index + 1]
        [a[0] + (b[0] - a[0]) * t + (n0[0] + (n1[0] - n0[0]) * t) * y,
         a[1] + (b[1] - a[1]) * t + (n0[1] + (n1[1] - n0[1]) * t) * y, z]
      end
    end
  end
end
