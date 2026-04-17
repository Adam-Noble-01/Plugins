# =============================================================================
# NA DEV TOOLS - MATERIALS LIBRARY WEB LOAD TO SKETCHUP MODEL
# =============================================================================
#
# FILE       : Na__DevUtil__LoadMaterials__.rb
# NAMESPACE  : Na__DevUtil__LoadMaterials
# MODULE     : Na__DevUtil__LoadMaterials
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Fetch MaterialsLibrary JSON from the web and build coloured material preview cubes
# CREATED    : 2026
#
# DESCRIPTION:
# - Loads the published MaterialsLibrary JSON over HTTPS.
# - Flattens series/material entries that define BaseColor into a name → data map.
# - Creates one group per material, assigns SketchUp materials from BaseColor, and lays out cubes in a grid.
# - Intended for execution via the Dev Tools UI.
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 17-Apr-2026 - Version 1.0.0
# - Initial structured module refactor (regional layout, safe operation abort).
#
# 17-Apr-2026 - Version 1.0.1
# - Module renamed to Na__DevUtil__LoadMaterials; entry Na__DevUtil__LoadMaterials.run.
#
# =============================================================================

require 'open-uri'
require 'json'

module Na__DevUtil__LoadMaterials

    # -----------------------------------------------------------------------------
    # REGION | Module Constants and Operation Labels
    # -----------------------------------------------------------------------------

    # MODULE CONSTANTS | Remote Config and Layout Grid
    # ------------------------------------------------------------
    JSON_URL_NA__APPCONFIG__MATERIALS_LIBRARY  = "https://www.noble-architecture.com/na-apps/30__TrueVision__CoreAppCode/02__Src__AppModules/02__AppData/Na__AppConfig__MaterialsLibrary.json" # <-- Published library JSON
    CUBE_SIZE                                = 1.m # <-- Preview cube edge length
    CUBE_GAP                                 = 1.m # <-- Gap between cube origins on X/Y
    MAX_CUBES_PER_ROW                        = 5 # <-- Grid width before wrapping to next row
    OPERATION_LABEL__CREATE_MATERIAL_CUBES   = "Create Material Cubes From URL" # <-- Undo stack label
    # ---------------------------------------------------------------

    # MODULE CONSTANTS | Derived Layout (depends on CUBE_SIZE / CUBE_GAP)
    # ------------------------------------------------------------
    STEP_XY  = CUBE_SIZE + CUBE_GAP # <-- Distance between adjacent cube origin columns/rows
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | JSON and Colour Parsing
    # -----------------------------------------------------------------------------

    # HELPER FUNCTION | Parse rgb(r, g, b) String to Sketchup::Color
    # ---------------------------------------------------------------
    def self.na__parse_rgb_string_to_color(rgb_string)
        match = rgb_string.to_s.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/i) # <-- Accept optional whitespace
        raise "Invalid RGB string: #{rgb_string}" unless match # <-- Fail fast on bad config
        Sketchup::Color.new(match[1].to_i, match[2].to_i, match[3].to_i) # <-- Build colour from capture groups
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Fetch and Parse JSON from HTTPS URL
    # ---------------------------------------------------------------
    def self.na__fetch_json_from_url(url)
        JSON.parse(URI.open(url).read) # <-- open-uri + JSON parse
    end
    # ---------------------------------------------------------------

    # HELPER FUNCTION | Flatten Na__AppConfig__MaterialsLibrary to Material Name → Entry Hash
    # ---------------------------------------------------------------
    def self.na__extract_materials_map_from_library_json(json_data)
        library = json_data["Na__AppConfig__MaterialsLibrary"] # <-- Root key from shared schema
        raise "Missing key: Na__AppConfig__MaterialsLibrary" unless library.is_a?(Hash) # <-- Schema guard

        flat_materials = {} # <-- Output map

        library.each do |_series_name, series_materials|
            next unless series_materials.is_a?(Hash) # <-- Skip non-series nodes

            series_materials.each do |material_key, material_data|
                next unless material_data.is_a?(Hash) # <-- Skip invalid entries
                next unless material_data["BaseColor"] # <-- Only entries with a swatch colour

                material_name = material_data["SketchUpName"] || material_key # <-- Prefer explicit SU name
                flat_materials[material_name] = material_data # <-- One row per material name
            end
        end

        flat_materials
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

    # -----------------------------------------------------------------------------
    # REGION | SketchUp Geometry and Materials
    # -----------------------------------------------------------------------------

    # SUB FUNCTION | Apply Material to All Faces in Group (front and back)
    # ---------------------------------------------------------------
    def self.na__paint_all_faces_with_material(group, material)
        group.entities.grep(Sketchup::Face).each do |face|
            face.material = material # <-- Front face
            face.back_material = material # <-- Back face
        end
    end
    # ---------------------------------------------------------------

    # SUB FUNCTION | Add Single Preview Cube Group at Grid Index
    # ---------------------------------------------------------------
    def self.na__add_material_preview_cube(entities, materials, material_name, material_data, index)
        base_color = material_data["BaseColor"] # <-- Swatch source
        return unless base_color # <-- Caller may pass sparse maps; guard anyway

        material = materials[material_name] || materials.add(material_name) # <-- Reuse or create material
        material.color = na__parse_rgb_string_to_color(base_color) # <-- Assign diffuse from JSON

        col = index % MAX_CUBES_PER_ROW # <-- Column within row
        row = index / MAX_CUBES_PER_ROW # <-- Row index
        x = col * STEP_XY # <-- Origin X
        y = row * STEP_XY # <-- Origin Y
        z = 0 # <-- Ground plane

        group = entities.add_group # <-- Container for this preview
        group.name = material_name # <-- Outliner label

        pts = [
            Geom::Point3d.new(x, y, z),
            Geom::Point3d.new(x + CUBE_SIZE, y, z),
            Geom::Point3d.new(x + CUBE_SIZE, y + CUBE_SIZE, z),
            Geom::Point3d.new(x, y + CUBE_SIZE, z)
        ] # <-- Bottom face rectangle on Z = 0

        face = group.entities.add_face(pts) # <-- Base face
        face.reverse! if face.normal.z < 0 # <-- Ensure pushpull along +Z
        face.pushpull(CUBE_SIZE) # <-- Extrude to cube

        na__paint_all_faces_with_material(group, material) # <-- Apply material to all faces
    end
    # ---------------------------------------------------------------

    # FUNCTION | Run End-to-End Load — Fetch JSON, Then Create Material Cubes in One Operation
    # ------------------------------------------------------------
    def self.run
        model     = Sketchup.active_model # <-- Active model
        entities  = model.active_entities # <-- Insert context
        materials = model.materials # <-- Material collection

        json_data = nil # <-- Parsed JSON (set after fetch)
        materials_data = nil # <-- Flattened map

        begin
            json_data = na__fetch_json_from_url(JSON_URL_NA__APPCONFIG__MATERIALS_LIBRARY) # <-- Network + parse
            materials_data = na__extract_materials_map_from_library_json(json_data) # <-- Build name map
        rescue => e
            puts "Error: #{e.message}" # <-- User-visible failure
            puts e.backtrace.join("\n") # <-- Debug trace
            return # <-- No model operation started yet
        end

        model.start_operation(OPERATION_LABEL__CREATE_MATERIAL_CUBES, true) # <-- Undoable batch

        begin
            materials_data.each_with_index do |(material_name, material_data), index|
                na__add_material_preview_cube(entities, materials, material_name, material_data, index) # <-- One cube per entry
            end

            model.commit_operation # <-- Close operation on success
            puts "Created #{materials_data.length} material cubes from URL." # <-- Summary
        rescue => e
            model.abort_operation # <-- Roll back partial geometry if something failed mid-loop
            puts "Error: #{e.message}" # <-- User-visible failure
            puts e.backtrace.join("\n") # <-- Debug trace
        end
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end
