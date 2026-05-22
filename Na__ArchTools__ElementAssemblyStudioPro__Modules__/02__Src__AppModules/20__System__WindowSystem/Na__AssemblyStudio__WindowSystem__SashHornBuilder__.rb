# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - WINDOW SYSTEM - SASH HORN BUILDER
# =============================================================================
#
# FILE       : Na__AssemblyStudio__WindowSystem__SashHornBuilder__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__WindowSystem
# MODULE     : Na__SashHornBuilder
# PURPOSE    : Load 2D sash horn assets and build extruded 3D horn solids.
# =============================================================================

require 'json'
require 'sketchup.rb'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../02__AppData/Na__AssemblyStudio__AppData__ConfigLoader__'

module Na__AssemblyStudio
module Na__WindowSystem
    module Na__SashHornBuilder

        DebugTools   = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        ConfigLoader = Na__AssemblyStudio::Na__AppData::Na__ConfigLoader

        NA_ASSET_FILE_PREFIX = 'Na__Window__SlidingSash__SashHorn__Type'.freeze
        NA_MM_TO_INCH        = 1.0 / 25.4
        NA_SOFTEN_ANGLE_RAD  = 22.0 * Math::PI / 180.0

        # FUNCTION | Load All Sash Horn Assets for JS Preview Cache
        # ------------------------------------------------------------
        def self.na_load_all_assets
            (1..4).each_with_object({}) do |type, assets|
                asset = na_load_asset(type)
                assets[type.to_s] = asset if asset
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Load Sash Horn Asset JSON
        # ------------------------------------------------------------
        def self.na_load_asset(type)
            path = na_asset_file_path(type)
            return nil unless File.exist?(path)

            JSON.parse(File.read(path, encoding: 'UTF-8'))
        rescue StandardError => e
            DebugTools.na_debug_error("Failed to load sash horn asset #{type}", e)
            nil
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Sash Horns for Top Sash
        # ------------------------------------------------------------
        def self.na_build_sash_horns(entities, panel_id, panel_x, panel_z, panel_width, params, material)
            return [] unless params[:sash_horns_enabled]

            geometry = na_asset_geometry(params[:sash_horn_type])
            return [] unless geometry

            front_y = params[:frame_wall_inset] + params[:casement_inset]
            depth = params[:casement_depth]
            return [] if depth <= 0

            left_points = na_build_profile_points(
                na_scale_vertices(geometry[:vertices], NA_MM_TO_INCH),
                na_scale_bbox(geometry[:bbox], NA_MM_TO_INCH),
                :left,
                panel_x,
                panel_z,
                panel_width,
                params[:cas_left_stile],
                params[:cas_right_stile]
            )
            right_points = na_build_profile_points(
                na_scale_vertices(geometry[:vertices], NA_MM_TO_INCH),
                na_scale_bbox(geometry[:bbox], NA_MM_TO_INCH),
                :right,
                panel_x,
                panel_z,
                panel_width,
                params[:cas_left_stile],
                params[:cas_right_stile]
            )

            [
                na_create_horn_group(entities, "Na_Casement_#{panel_id}_SashHorn_Left", left_points, front_y, depth, material),
                na_create_horn_group(entities, "Na_Casement_#{panel_id}_SashHorn_Right", right_points, front_y, depth, material)
            ].compact
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Sash Horn Profiles in Millimetres
        # ------------------------------------------------------------
        def self.na_build_profiles_mm(type, panel_x, panel_z, panel_width, left_stile, right_stile)
            geometry = na_asset_geometry(type)
            return [] unless geometry

            [
                {
                    side: :left,
                    points: na_build_profile_points(geometry[:vertices], geometry[:bbox], :left, panel_x, panel_z, panel_width, left_stile, right_stile)
                },
                {
                    side: :right,
                    points: na_build_profile_points(geometry[:vertices], geometry[:bbox], :right, panel_x, panel_z, panel_width, left_stile, right_stile)
                }
            ]
        end
        # ---------------------------------------------------------------

        # FUNCTION | Extract Elevation Polygon and Bounding Box
        # ------------------------------------------------------------
        def self.na_asset_geometry(type)
            asset = na_load_asset(type)
            elevation = asset && asset['Na__Asset__Elevation2D']
            paths = elevation && elevation['Na__Geometry__Paths']
            bbox = elevation && elevation['Na__Geometry__BoundingBox']
            return nil unless paths.is_a?(Array) && bbox.is_a?(Hash)

            polygon = paths.find { |path| path.is_a?(Hash) && path['PathType'] == 'Polygon' && path['Vertices_mm'].is_a?(Array) }
            return nil unless polygon && polygon['Vertices_mm'].length >= 3

            {
                vertices: polygon['Vertices_mm'].map { |vertex| { x: vertex['X'].to_f, y: vertex['Y'].to_f } },
                bbox: {
                    min_x: bbox['Na__Geometry__MinX_mm'].to_f,
                    max_x: bbox['Na__Geometry__MaxX_mm'].to_f,
                    min_y: bbox['Na__Geometry__MinY_mm'].to_f,
                    max_y: bbox['Na__Geometry__MaxY_mm'].to_f,
                    width: bbox['Na__Geometry__Width_mm'].to_f
                }
            }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Build Transformed 2D Profile Points
        # ------------------------------------------------------------
        def self.na_build_profile_points(vertices, bbox, side, panel_x, panel_z, panel_width, left_stile, right_stile)
            left_outer_x = panel_x
            right_outer_x = panel_x + panel_width

            vertices.map do |vertex|
                local_x = vertex[:x]
                local_y = vertex[:y]
                x = if side == :left
                    left_outer_x + (bbox[:max_x] - local_x)
                else
                    right_outer_x - bbox[:width] + (local_x - bbox[:min_x])
                end

                { x: x, z: panel_z - bbox[:max_y] + local_y }
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Create One Extruded Horn Group
        # ------------------------------------------------------------
        def self.na_create_horn_group(entities, group_name, profile_points, front_y, depth, material)
            return nil unless profile_points.is_a?(Array) && profile_points.length >= 3

            group = entities.add_group
            group.name = group_name

            points = profile_points.map { |point| Geom::Point3d.new(point[:x], front_y, point[:z]) }
            face = group.entities.add_face(points)
            unless face && face.valid?
                entities.erase_entities(group)
                return nil
            end

            face.reverse! if (face.normal % Y_AXIS) < 0
            face.pushpull(depth, false)
            na_apply_material(group, material)
            softened_count = na_soften_smooth_edges_below_angle(group, NA_SOFTEN_ANGLE_RAD)

            DebugTools.na_debug_geometry("Created sash horn: #{group_name}, softened #{softened_count} edges")
            group
        end
        # ---------------------------------------------------------------

        # FUNCTION | Soften and Smooth Shallow Profile Edges
        # ------------------------------------------------------------
        def self.na_soften_smooth_edges_below_angle(group, angle_threshold_rad)
            softened_count = 0

            group.entities.grep(Sketchup::Edge).each do |edge|
                next unless edge && edge.valid?
                next unless na_edge_angle_below_threshold?(edge, angle_threshold_rad)

                edge.soft = true
                edge.smooth = true
                softened_count += 1
            end

            softened_count
        end
        # ---------------------------------------------------------------

        # FUNCTION | Check Edge Face Angle Against Threshold
        # ------------------------------------------------------------
        def self.na_edge_angle_below_threshold?(edge, angle_threshold_rad)
            faces = edge.faces
            return false unless faces.length == 2

            angle = faces[0].normal.angle_between(faces[1].normal)
            angle <= angle_threshold_rad
        rescue StandardError
            false
        end
        # ---------------------------------------------------------------

        # FUNCTION | Apply Material to All Horn Faces
        # ------------------------------------------------------------
        def self.na_apply_material(group, material)
            return unless material

            group.entities.each do |entity|
                next unless entity.is_a?(Sketchup::Face)
                entity.material = material
                entity.back_material = material
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Asset File Path
        # ------------------------------------------------------------
        def self.na_asset_file_path(type)
            File.join(na_asset_folder, "#{NA_ASSET_FILE_PREFIX}-#{format('%02d', na_normalize_type(type))}__.json")
        end
        # ---------------------------------------------------------------

        # FUNCTION | Resolve Asset Folder
        # ------------------------------------------------------------
        def self.na_asset_folder
            root_folder = ConfigLoader.na_get_or('04__Data__AssetLibrary', 'assetLibrary', 'rootFolder')
            sash_folder = ConfigLoader.na_get_or('Windows__SashHorns__', 'assetLibrary', 'window', 'sashHorns')
            modules_root = File.expand_path('../..', __dir__)
            File.join(modules_root, root_folder, sash_folder)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Normalize Sash Horn Type
        # ------------------------------------------------------------
        def self.na_normalize_type(type)
            match = type.to_s.match(/(\d+)/)
            value = match ? match[1].to_i : 1
            value.clamp(1, 4)
        end
        # ---------------------------------------------------------------

        # FUNCTION | Scale Vertices
        # ------------------------------------------------------------
        def self.na_scale_vertices(vertices, scale)
            vertices.map { |vertex| { x: vertex[:x] * scale, y: vertex[:y] * scale } }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Scale Bounding Box
        # ------------------------------------------------------------
        def self.na_scale_bbox(bbox, scale)
            {
                min_x: bbox[:min_x] * scale,
                max_x: bbox[:max_x] * scale,
                min_y: bbox[:min_y] * scale,
                max_y: bbox[:max_y] * scale,
                width: bbox[:width] * scale
            }
        end
        # ---------------------------------------------------------------

    end
end
end

# =============================================================================
# END OF FILE
# =============================================================================
