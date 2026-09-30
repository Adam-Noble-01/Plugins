# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MATERIALS
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__Materials__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__Materials
# PURPOSE    : material_manage (upsert, delete, rename; colour, alpha, texture,
#              PBR maps) and material_apply (paint entities or the faces inside)
# CREATED    : 2026
#
# PBR (SketchUp 2025+):
# Metallic/roughness/normal/AO properties exist only from 2025.0 (normal and AO
# enable flags from 2025.0.2), so each is guarded with respond_to? and refused
# with the version named on older SketchUp. Normal mapping needs its texture
# set BEFORE normal_enabled (the setter raises otherwise).
#
# PAINTING ("faces_inside"):
# Like the Na__ Paint Deep Nested Faces tool: every face inside the given
# groups/components (recursively) is painted. Shared definitions are painted
# once and the result says how many copies that changed; make_unique:true
# paints only the targeted instances.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__Materials

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_PBR_TEXTURE_KEYS = {
            'metallic_texture_path'  => :metallic_texture=,
            'roughness_texture_path' => :roughness_texture=,
            'normal_texture_path'    => :normal_texture=,
            'ao_texture_path'        => :ao_texture=
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | material_manage
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Materials__Manage(params, ctx)
            model = ctx[:model]
            action = Na__Params.Na__Params__Enum(params, 'action', %w[upsert delete rename], 'upsert')
            name = Na__Params.Na__Params__String(params, 'name', nil, required: true)

            case action
            when 'delete' then na_delete(model, name)
            when 'rename' then na_rename(model, name, Na__Params.Na__Params__String(params, 'new_name', nil, required: true), ctx)
            else na_upsert(model, name, params, ctx)
            end
        end

        def self.na_upsert(model, name, params, ctx)
            material = model.materials[name]
            created = material.nil?
            material ||= model.materials.add(name)

            material.color = Na__EntityResolver.Na__EntityResolver__ParseColour(params['color']) if params.key?('color')
            material.alpha = Na__Params.Na__Params__Number(params, 'alpha', nil, min: 0.0, max: 1.0) if params.key?('alpha')
            na_set_texture(material, params, ctx) if params.key?('texture_path')
            na_set_pbr(material, params)

            item = Na__Handlers__Collections.Na__Handlers__Collections__MaterialItem(material, model, ctx, true, nil)
            item.merge('created' => created, 'summary' => "#{created ? 'Created' : 'Updated'} material '#{material.name}'.")
        end

        def self.na_set_texture(material, params, ctx)
            if params['texture_path'].nil? || params['texture_path'].to_s.empty?
                # Material#texture= documents a path, [path, w, h] or an ImageRep; clearing is not documented.
                raise Na__McpError.new('invalid_params', 'texture_path must be an image file path.',
                                       'To drop a texture, create a plain colour material (material_manage with color only) and paint with it.')
            end

            path = File.expand_path(params['texture_path'].to_s)
            raise Na__McpError.new('file_error', "Texture not found: #{path}.", nil) unless File.file?(path)

            unit = ctx[:unit]
            width = Na__Params.Na__Params__Has(params, 'texture_width') ? Na__Units.Na__Units__PositiveLength(params['texture_width'], unit, 'texture_width') : nil
            height = Na__Params.Na__Params__Has(params, 'texture_height') ? Na__Units.Na__Units__PositiveLength(params['texture_height'], unit, 'texture_height') : nil
            if width && height
                material.texture = [path, width, height]
            else
                material.texture = path
                material.texture.size = width if width # a single value keeps the image's aspect ratio
            end
        end

        def self.na_set_pbr(material, params)
            requested = %w[metallic roughness normal_scale ao_strength] + NA_PBR_TEXTURE_KEYS.keys
            return unless requested.any? { |key| params.key?(key) }

            unless material.respond_to?(:metalness_enabled=)
                raise Na__McpError.new('unsupported', 'PBR material properties need SketchUp 2025 or newer.', 'Use color, alpha and texture only.')
            end

            NA_PBR_TEXTURE_KEYS.each do |key, setter|
                next unless params.key?(key)

                path = File.expand_path(params[key].to_s)
                raise Na__McpError.new('file_error', "#{key} not found: #{path}.", nil) unless File.file?(path)

                begin
                    material.public_send(setter, path)
                rescue ArgumentError => error
                    raise Na__McpError.new('invalid_params', "SketchUp refused #{key}: #{error.message}", 'Normal maps need 24-bit colour or more.')
                end
            end

            if params.key?('metallic')
                material.metalness_enabled = true
                material.metallic_factor = Na__Params.Na__Params__Number(params, 'metallic', nil, min: 0.0, max: 1.0)
            end
            if params.key?('roughness')
                material.roughness_enabled = true
                material.roughness_factor = Na__Params.Na__Params__Number(params, 'roughness', nil, min: 0.0, max: 1.0)
            end
            material.normal_enabled = true if params.key?('normal_texture_path') && material.respond_to?(:normal_enabled=)
            material.normal_scale = Na__Params.Na__Params__Number(params, 'normal_scale', nil, min: 0.0) if params.key?('normal_scale')
            material.ao_enabled = true if params.key?('ao_texture_path') && material.respond_to?(:ao_enabled=)
            material.ao_strength = Na__Params.Na__Params__Number(params, 'ao_strength', nil, min: 0.0, max: 1.0) if params.key?('ao_strength')
        end

        def self.na_delete(model, name)
            material = na_require_material(model, name)
            model.materials.remove(material)
            { 'deleted' => name, 'summary' => "Deleted material '#{name}'; anything painted with it is now default." }
        end

        def self.na_rename(model, name, new_name, ctx)
            material = na_require_material(model, name)
            begin
                material.name = new_name
            rescue ArgumentError => error
                raise Na__McpError.new('invalid_params', "SketchUp refused the name '#{new_name}': #{error.message}", 'Names must be unique; choose another.')
            end
            { 'renamed' => name, 'name' => material.name }
        end

        def self.na_require_material(model, name)
            material = model.materials[name]
            return material if material

            raise Na__McpError.new('not_found', "No material named '#{name}'.", 'List them with collection_list collection="materials".')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | material_apply
# -----------------------------------------------------------------------------

        def self.Na__Handlers__Materials__Apply(params, ctx)
            model = ctx[:model]
            material = Na__EntityResolver.Na__EntityResolver__ResolveMaterial(model, Na__Params.Na__Params__Required(params, 'material'), ctx[:warnings])
            targets = Na__EntityResolver.Na__EntityResolver__RequireEntities(model, Na__Params.Na__Params__IdArray(params, 'ids'))
            side = Na__Params.Na__Params__Enum(params, 'side', %w[front back both], 'front')
            mode = Na__Params.Na__Params__Enum(params, 'mode', %w[entity faces_inside], 'entity')

            painted = if mode == 'faces_inside'
                          na_paint_inside(targets, material, side, params, ctx)
                      else
                          targets.count { |target| na_paint(target, material, side) }
                      end
            { 'painted' => painted, 'material' => material ? material.name : 'default', 'mode' => mode, 'side' => side,
              'summary' => "Painted #{painted} element(s) with #{material ? material.name : 'the default material'}." }
        end

        def self.na_paint(entity, material, side)
            if entity.is_a?(Sketchup::Face)
                entity.material = material if side != 'back'
                entity.back_material = material if side != 'front'
                return true
            end
            return false unless entity.respond_to?(:material=)

            entity.material = material
            true
        end

        def self.na_paint_inside(targets, material, side, params, ctx)
            if Na__Params.Na__Params__Boolean(params, 'make_unique', false)
                targets = targets.map do |target|
                    target.make_unique if Na__EntityResolver.Na__EntityResolver__IsInstance(target) && target.definition.count_instances > 1
                    target
                end
            end
            faces, _edges, definitions = Na__Handlers__GeometryEdit.Na__Handlers__GeometryEdit__Collect(targets, true)
            shared = definitions.select { |definition| definition.count_instances > 1 }
            unless shared.empty?
                ctx[:warnings] << "#{shared.length} painted definition(s) are used more than once; every copy changed. Pass make_unique:true to limit it."
            end
            faces.count { |face| na_paint(face, material, side) }
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__Materials
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
