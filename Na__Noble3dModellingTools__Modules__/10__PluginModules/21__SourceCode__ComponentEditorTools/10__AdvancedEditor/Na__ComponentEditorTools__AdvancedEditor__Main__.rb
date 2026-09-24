# Advanced editor: query the actual model, never import a library definition into
# an unrelated model. Row changes are undoable; file saving is an explicit action.
require 'securerandom'
require 'digest'
require 'fileutils'
require_relative 'Na__ComponentEditorTools__AdvancedEditor__Standards__'

module Na__ComponentEditorTools
    module Na__AdvancedEditor
        class << self
            def request(payload)
                case payload['action']
                when 'query' then query(payload['path'].to_s)
                when 'rename', 'delete_tag', 'retag_ssot', 'swap_material_ssot' then edit(payload)
                when 'save_file' then save_file(payload)
                else raise 'Unknown advanced editor action.'
                end
            rescue => error
                { success: false, message: error.message }
            end

            def query(path)
                @session = nil
                model = Sketchup.active_model
                unless path.empty?
                    path = File.realpath(path)
                    raise 'Choose a SketchUp (.skp) file.' unless File.extname(path).downcase == '.skp'
                    unless same_path?(model.path, path)
                        raise 'Save or discard your current model changes in SketchUp before opening this component. Then click Query again.' if model.modified?
                        status = Sketchup.open_file(path, with_status: true)
                        raise 'Opening the component was cancelled or failed.' unless status
                        @unsafe_model = Sketchup.active_model unless status == Sketchup::Model::LOAD_STATUS_SUCCESS
                        raise 'This file comes from a newer SketchUp version. Advanced editing is disabled to avoid saving incomplete data.' unless status == Sketchup::Model::LOAD_STATUS_SUCCESS
                        model = Sketchup.active_model
                    end
                    raise 'The selected component is not the active model. Query again.' unless same_path?(model.path, path)
                end
                raise 'This model was loaded from a newer SketchUp version; advanced editing is disabled.' if model.equal?(@unsafe_model)
                @session = { model: model, path: model.path.to_s, token: SecureRandom.hex(16),
                             fingerprint: fingerprint(model.path), resources: {}, standards: Na__AdvancedStandards.load_catalog }
                result('Query complete. Edits apply to this entire model, including nested definitions.')
            end

            def same_path?(left, right)
                return false if left.to_s.empty? || right.to_s.empty?
                a = File.expand_path(left).tr('\\', '/')
                b = File.expand_path(right).tr('\\', '/')
                Sketchup.platform == :platform_win ? a.casecmp?(b) : a == b
            end

            def fingerprint(path)
                File.file?(path.to_s) ? Digest::SHA256.file(path).hexdigest : nil
            end

            def checked_model(payload)
                s = @session
                raise 'Query the component before editing.' unless s && payload['token'] == s[:token]
                model = Sketchup.active_model
                raise 'The active model changed. Query again before editing.' unless model.equal?(s[:model]) && model.path.to_s == s[:path]
                model
            end

            # Definitions include groups, nested and unused components. Enumerate
            # each definition once so shared instances do not inflate the counts.
            def all_entities(model)
                model.entities.to_a + model.definitions.to_a.flat_map { |definition| definition.entities.to_a }
            end

            def snapshot
                model = @session[:model]
                entities = all_entities(model)
                tag_counts = Hash.new(0)
                material_counts = Hash.new(0)
                types = Hash.new(0)
                entities.each do |entity|
                    types[entity.typename] += 1
                    tag_counts[entity.layer] += 1 if entity.respond_to?(:layer)
                    material_counts[entity.material] += 1 if entity.respond_to?(:material) && entity.material
                    material_counts[entity.back_material] += 1 if entity.respond_to?(:back_material) && entity.back_material
                end
                resources = {}
                tags = model.layers.map do |tag|
                    id = "tag:#{tag.entityID}"
                    resources[id] = tag
                    { id: id, name: tag.name, display_name: tag.display_name,
                      default: tag == model.layers[0], active: tag == model.active_layer,
                      visible: tag.visible?, folder: tag.folder ? tag.folder.name : '',
                      uses: tag_counts[tag] }
                end
                materials = model.materials.map do |material|
                    id = "material:#{material.entityID}"
                    resources[id] = material
                    color = material.color
                    texture = material.texture
                    { id: id, name: material.name, display_name: material.display_name,
                      color: '#%02x%02x%02x' % [color.red, color.green, color.blue],
                      opacity: (material.alpha * 100).round, uses: material_counts[material],
                      texture: texture ? texture.filename : '' }
                end
                @session[:resources] = resources
                definitions = model.definitions.map do |definition|
                    { name: definition.name, entities: definition.entities.length,
                      instances: definition.instances.length,
                      kind: definition.image? ? 'Image' : (definition.group? ? 'Group' : 'Component') }
                end
                { token: @session[:token], path: model.path, title: model.title,
                  standards: Na__AdvancedStandards.public_catalog(@session[:standards]),
                  modified: model.modified?, tags: tags.sort_by { |t| [t[:default] ? 0 : 1, t[:name].downcase] },
                  materials: materials.sort_by { |m| m[:name].downcase },
                  definitions: definitions.sort_by { |d| d[:name].downcase },
                  entity_types: types, entity_count: entities.length,
                  root_count: model.entities.length, definition_count: definitions.length }
            end

            def result(message)
                { success: true, message: message, data: snapshot }
            end

            def edit(payload)
                model = checked_model(payload)
                resource = @session[:resources][payload['id']]
                raise 'This item no longer exists. Query again.' unless resource && resource.valid?
                raise 'This item was renamed outside this panel. Query again.' unless resource.name == payload['existing_name']
                is_tag = resource.is_a?(Sketchup::Layer)
                raise 'The default Untagged tag cannot be renamed or deleted.' if is_tag && resource == model.layers[0]
                raise 'Live Components are present. Edit these through their supported controls.' if model.definitions.any? { |d| d.respond_to?(:live_component?) && d.live_component? }
                raise 'Only tags can be deleted here.' if payload['action'] == 'delete_tag' && !is_tag
                if ['retag_ssot', 'swap_material_ssot'].include?(payload['action'])
                    raise 'Choose the correct resource type.' unless (payload['action'] == 'retag_ssot') == is_tag
                    standard = Na__AdvancedStandards.selected(@session[:standards], is_tag ? :tags : :materials, payload['standard_key'])
                end

                if payload['action'] == 'rename'
                    name = payload['name'].to_s.strip
                    raise 'Enter a non-empty name without control characters.' if name.empty? || name.match?(/[[:cntrl:]]/)
                    collection = is_tag ? model.layers : model.materials
                    raise 'That name already exists. Choose a unique name.' if collection.any? { |item| item != resource && item.name.casecmp?(name) }
                    return result('Name is unchanged.') if resource.name == name
                end

                started = model.start_operation(standard ? 'Apply SSOT component resource' : (payload['action'] == 'delete_tag' ? 'Delete tag: move to Untagged' : 'Rename component resource'), true)
                raise 'Could not start an undoable operation.' unless started
                begin
                    if standard
                        count = replace_standard(model, resource, standard, is_tag)
                        message = "SSOT applied to #{count} assignments. Original resources are retained; Save file to keep this change on disk."
                    elsif payload['action'] == 'delete_tag'
                        delete_tag(model, resource)
                        message = 'Tag deleted. Its entities are now Untagged; geometry was preserved. Save file to keep this change on disk.'
                    else
                        resource.name = name
                        raise 'SketchUp did not accept the exact name.' unless resource.name == name
                        message = 'Name saved in the model. Save file to keep this change on disk.'
                    end
                    model.commit_operation
                rescue
                    model.abort_operation
                    raise
                end
                result(message)
            end

            def replace_standard(model, source, standard, is_tag)
                before = all_entities(model)
                ids = before.map(&:entityID).sort
                if is_tag
                    target = Na__AdvancedStandards.build_tag(model, standard)
                    assignments = before.select { |e| e.respond_to?(:layer) && e.layer == source }.map { |e| [e, :layer] }
                else
                    target, previous = Na__AdvancedStandards.build_material(model, standard, @session[:standards])
                    sources = [source, previous].compact
                    assignments = before.flat_map do |entity|
                        [:material, :back_material].filter_map do |property|
                            [entity, property] if entity.respond_to?(property) && sources.include?(entity.public_send(property))
                        end
                    end
                end
                assignments.each { |entity, property| entity.public_send("#{property}=", target) }
                preserved = before.all?(&:valid?) && all_entities(model).map(&:entityID).sort == ids
                raise 'Entity preservation check failed; replacement was rolled back.' unless preserved
                raise 'Assignment check failed; replacement was rolled back.' unless assignments.all? { |entity, property| entity.public_send(property) == target }
                assignments.length
            end

            def delete_tag(model, tag)
                before = all_entities(model)
                tagged = before.select { |entity| entity.respond_to?(:layer) && entity.layer == tag }
                default = model.layers[0]
                model.active_layer = default if model.active_layer == tag
                # Official contract: false moves geometry to Layer 0; true erases it.
                # https://ruby.sketchup.com/Sketchup/Layers.html#remove-instance_method
                removed = model.layers.remove(tag, false)
                raise 'SketchUp could not remove the tag.' unless removed && !model.layers.to_a.include?(tag)
                after = all_entities(model)
                preserved = before.all?(&:valid?) && before.map(&:entityID).sort == after.map(&:entityID).sort
                raise 'Geometry verification failed; the operation has been rolled back.' unless preserved
                raise 'Untagged reassignment verification failed; the operation has been rolled back.' unless tagged.all? { |entity| entity.layer == default }
            end

            def save_file(payload)
                model = checked_model(payload)
                path = @session[:path]
                raise 'Save this model through SketchUp first, then query again.' if path.empty?
                raise 'The file changed on disk since the query. Reopen or reconcile it before saving.' unless @session[:fingerprint] && fingerprint(path) == @session[:fingerprint]
                return result('The file is already up to date.') unless model.modified?
                backup = "#{path}.na-backup-#{Time.now.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(4)}.bak"
                FileUtils.copy_file(path, backup)
                raise 'Backup verification failed. The component was not saved.' unless fingerprint(backup) == @session[:fingerprint]
                raise "SketchUp could not save the file. Original backup: #{backup}" unless model.save
                @session[:fingerprint] = fingerprint(path)
                Na__LibraryExtractor.Na__ComponentEditorTools__InvalidateCache
                Na__LibraryScanner.Na__ComponentEditorTools__InvalidateCache
                result("File saved. Original backup: #{backup}")
            end
        end
    end
end
