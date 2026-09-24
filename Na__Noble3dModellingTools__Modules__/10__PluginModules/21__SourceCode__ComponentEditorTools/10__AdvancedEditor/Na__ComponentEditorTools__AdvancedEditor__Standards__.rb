require 'json'
require 'digest'

module Na__ComponentEditorTools
    module Na__AdvancedStandards
        class << self
            def directory
                File.expand_path('../../../../Na__Common__DataLib__CoreSuEntityStandards', __dir__)
            end

            def load_catalog
                catalog = { tags: [], materials: [], errors: [], fingerprints: {} }
                { tags: ['Tags', 'Tag__SketchUpName', 'Tag__Description'],
                  materials: ['Materials', 'SketchUpName', 'Description'] }.each do |kind, (suffix, name_key, description_key)|
                    begin
                        path = File.join(directory, "Na__DataLib__CoreIndex__#{suffix}__.json")
                        content = File.binread(path)
                        payload = JSON.parse(content.sub(/\A\xEF\xBB\xBF/n, ''))
                        root = payload.fetch("Na__DataLib__CoreIndex__#{suffix}")
                        raise 'The collection must be an object.' unless root.is_a?(Hash)
                        entries = []
                        walk = lambda do |node, group|
                            node.each do |key, value|
                                next unless value.is_a?(Hash)
                                if value[name_key].is_a?(String) && !value[name_key].strip.empty?
                                    entries << { key: key, name: value[name_key], group: group,
                                                 description: value[description_key].to_s,
                                                 default: value['IsDefault'] == true,
                                                 raw: value, meta: payload['meta'] || {} }
                                else
                                    walk.call(value, group.empty? ? key : group)
                                end
                            end
                        end
                        walk.call(root, '')
                        raise 'Duplicate collection keys.' unless entries.map { |e| e[:key] }.uniq.length == entries.length
                        catalog[kind] = entries.sort_by { |entry| [entry[:group], entry[:name]] }
                        catalog[:fingerprints][path] = Digest::SHA256.hexdigest(content)
                    rescue => error
                        catalog[:errors] << "#{suffix} SSOT: #{error.message}"
                    end
                end
                catalog
            end

            def public_catalog(catalog)
                { tags: catalog[:tags].map { |entry| entry.reject { |k, _| [:raw, :meta].include?(k) } },
                  materials: catalog[:materials].map { |entry| entry.reject { |k, _| [:raw, :meta].include?(k) } },
                  errors: catalog[:errors] }
            end

            def selected(catalog, kind, key)
                catalog[:fingerprints].each do |path, fingerprint|
                    raise 'The SSOT files changed. Query again to refresh the dropdowns.' unless Digest::SHA256.file(path).hexdigest == fingerprint
                end
                catalog[kind].find { |entry| entry[:key] == key } || raise('Choose an item from the SSOT dropdown.')
            end

            def build_tag(model, entry)
                existing = model.layers[entry[:name]]
                return existing if existing
                require_relative '../../09__SourceCode__TagUtils/Na__Noble3dModellingTools__TagUtils__Run__'
                edge_path = File.join(directory, 'Na__DataLib__CoreIndex__EdgeMaterials__.json')
                edge_payload = JSON.parse(File.read(edge_path, encoding: 'bom|utf-8'))
                utils = Na__Noble3dModellingTools::Na__TagUtils
                applied = utils.na_create_or_update_tag(model, entry[:key], entry[:name], entry[:raw], entry[:meta], utils.na_edge_materials_root_from_payload(edge_payload))
                verify_build(applied)
                model.layers[entry[:name]] || raise('Could not create the SSOT tag.')
            end

            def build_material(model, entry, catalog)
                return [nil, nil] if entry[:default]
                require_relative '../../08__SourceCode__MaterialUtils/Na__Noble3dModellingTools__MaterialUtils__Run__'
                utils = Na__Noble3dModellingTools::Na__MaterialUtils
                defaults = catalog[:materials].find { |item| item[:default] }
                raise 'The SSOT default material recipe is missing.' unless defaults
                properties = utils.na_resolve_material_properties(defaults[:raw].reject { |k, _| ['IsDefault', 'SketchUpName', 'Description'].include?(k) }, entry[:raw])
                # Build a fresh canonical material so textures/PBR maps from a
                # same-named local material cannot leak into the SSOT recipe.
                previous = model.materials[entry[:name]]
                previous.name = model.materials.unique_name("#{entry[:name]}__BeforeSSOT") if previous
                applied = utils.na_create_or_update_material(model.materials, entry[:key], entry[:group], properties, entry[:raw], entry[:meta])
                verify_build(applied)
                material = model.materials[entry[:name]] || raise('Could not create the SSOT material.')
                [material, previous]
            end

            def verify_build(applied)
                raise(applied[:reason] || 'Could not apply the SSOT recipe.') unless [:created, :updated].include?(applied[:status])
                raise "SSOT recipe could not be fully applied: #{applied[:warning]}" if applied[:warning] && !applied[:warning].empty?
            end
        end
    end
end
