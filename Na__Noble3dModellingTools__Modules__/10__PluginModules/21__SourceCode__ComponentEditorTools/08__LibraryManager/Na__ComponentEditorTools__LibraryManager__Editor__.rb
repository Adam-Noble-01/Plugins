# =============================================================================
# NA COMPONENT EDITOR TOOLS - LIBRARY MANAGER | EDITOR
# =============================================================================
#
# FILE       : Na__ComponentEditorTools__LibraryManager__Editor__.rb
# NAMESPACE  : Na__ComponentEditorTools::Na__LibraryEditor
# PURPOSE    : Perform on-disk metadata edits on a .skp file by loading the
#              definition into the current model, applying changes, saving back
#              via save_as, then purging the temporary definition.
#              Supports: rename definition name + file, edit description,
#              set/delete attribute dictionary pairs.
# CREATED    : 2026
#
# =============================================================================

require 'fileutils'

module Na__ComponentEditorTools
    module Na__LibraryEditor

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_FIELD_LABELS = {
            'code'             => 'Code',
            'gallery_name'     => 'Gallery Name',
            'category'         => 'Category',
            'type'             => 'Type',
            'def_name'         => 'Definition Name',
            'description'      => 'Description',
            'notes'            => 'Notes',
            'file_name'        => 'File Name',
            'relative_dir'     => 'Folder',
            'truevision_valid' => 'TrueVision Valid'
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public API

        def self.Na__ComponentEditorTools__RenameComponent(payload_hash)
            file_path    = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'path').to_s.strip
            new_def_name = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'new_def_name').to_s.strip
            rename_file  = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'rename_file')

            return self.Na__ComponentEditorTools__Result(false, 'Component path is required.') if file_path.empty?
            return self.Na__ComponentEditorTools__Result(false, 'New definition name is required.') if new_def_name.empty?
            return self.Na__ComponentEditorTools__Result(false, "File not found: #{file_path}") unless File.exist?(file_path)

            new_file_path = self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path) do |definition|
                raise 'Live Components should not be renamed through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(definition)

                definition.name = new_def_name

                if rename_file
                    safe_filename = new_def_name.gsub(/[\\\/:"*?<>|]/, '_') + '.skp'
                    File.join(File.dirname(file_path), safe_filename)
                else
                    nil
                end
            end

            Na__LibraryExtractor.Na__ComponentEditorTools__InvalidateCache
            Na__LibraryScanner.Na__ComponentEditorTools__InvalidateCache

            if new_file_path && new_file_path != file_path && File.exist?(file_path)
                File.rename(file_path, new_file_path)
                self.Na__ComponentEditorTools__Result(true, "Renamed to \"#{new_def_name}\". File moved to #{File.basename(new_file_path)}.", new_file_path)
            else
                self.Na__ComponentEditorTools__Result(true, "Definition renamed to \"#{new_def_name}\".", file_path)
            end
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__UpdateLibraryData(payload_hash)
            file_path = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'path').to_s.strip

            return self.Na__ComponentEditorTools__Result(false, 'Component path is required.') if file_path.empty?
            return self.Na__ComponentEditorTools__Result(false, "File not found: #{file_path}") unless File.exist?(file_path)

            self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path) do |definition|
                raise 'Live Components should not be modified through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(definition)

                Na__LibrarySerializer.Na__ComponentEditorTools__WriteToDefinition(definition, payload_hash)
                nil
            end

            Na__LibraryExtractor.Na__ComponentEditorTools__InvalidateCache
            Na__LibraryScanner.Na__ComponentEditorTools__InvalidateCache

            self.Na__ComponentEditorTools__Result(true, 'Library data saved to component.', file_path)
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        # Single inline-edited field router. Writes one table cell back to the
        # component (or moves/renames the file on disk for file_name/folder),
        # returning the resulting (possibly new) file path so the caller can
        # re-extract just that component.
        def self.Na__ComponentEditorTools__UpdateField(payload_hash)
            file_path = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'path').to_s.strip
            field     = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'field').to_s.strip
            value     = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'value').to_s

            return self.Na__ComponentEditorTools__Result(false, 'Component path is required.') if file_path.empty?
            return self.Na__ComponentEditorTools__Result(false, 'Field name is required.') if field.empty?
            return self.Na__ComponentEditorTools__Result(false, "File not found: #{file_path}") unless File.exist?(file_path)

            new_path = file_path

            case field
            when 'code', 'gallery_name', 'notes', 'category', 'type', 'truevision_valid'
                self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path) do |definition|
                    raise 'Live Components should not be modified through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(definition)
                    Na__LibrarySerializer.Na__ComponentEditorTools__WriteSingleField(definition, field, value)
                    nil
                end
            when 'def_name'
                return self.Na__ComponentEditorTools__Result(false, 'Definition name cannot be empty.') if value.strip.empty?
                self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path) do |definition|
                    raise 'Live Components should not be modified through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(definition)
                    definition.name = value.strip
                    nil
                end
            when 'description'
                self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path) do |definition|
                    raise 'Live Components should not be modified through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(definition)
                    definition.description = value
                    nil
                end
            when 'file_name'
                new_path = self.Na__ComponentEditorTools__RenameFileOnDisk(file_path, value)
            when 'relative_dir'
                new_path = self.Na__ComponentEditorTools__MoveFileToRelativeDir(file_path, value)
            else
                return self.Na__ComponentEditorTools__Result(false, "Field is not editable: #{field}")
            end

            Na__LibraryExtractor.Na__ComponentEditorTools__InvalidateCache
            Na__LibraryScanner.Na__ComponentEditorTools__InvalidateCache

            label = NA_FIELD_LABELS[field] || field
            self.Na__ComponentEditorTools__Result(true, "#{label} saved.", new_path)
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

        def self.Na__ComponentEditorTools__UpdateMetadata(payload_hash)
            file_path   = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'path').to_s.strip
            def_name    = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'def_name').to_s.strip
            description = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'description')
            attributes  = self.Na__ComponentEditorTools__PayloadValue(payload_hash, 'attributes')

            return self.Na__ComponentEditorTools__Result(false, 'Component path is required.') if file_path.empty?
            return self.Na__ComponentEditorTools__Result(false, "File not found: #{file_path}") unless File.exist?(file_path)

            self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path) do |definition|
                raise 'Live Components should not be modified through this utility.' if self.Na__ComponentEditorTools__LiveComponent?(definition)

                definition.name        = def_name unless def_name.empty?
                definition.description = description.to_s if description

                if attributes.is_a?(Array)
                    attributes.each do |attr_item|
                        dict_name  = attr_item['dictionary'].to_s.strip
                        attr_key   = attr_item['key'].to_s.strip
                        attr_value = attr_item['value']
                        action     = attr_item['action'].to_s

                        next if dict_name.empty? || attr_key.empty?

                        if action == 'delete'
                            definition.delete_attribute(dict_name, attr_key)
                        else
                            definition.set_attribute(dict_name, attr_key, attr_value)
                        end
                    end
                end

                nil
            end

            Na__LibraryExtractor.Na__ComponentEditorTools__InvalidateCache
            Na__LibraryScanner.Na__ComponentEditorTools__InvalidateCache

            self.Na__ComponentEditorTools__Result(true, 'Component metadata updated and saved to disk.', file_path)
        rescue => error
            self.Na__ComponentEditorTools__Result(false, "#{error.class}: #{error.message}")
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Core Load/Edit/Save/Remove
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__LoadEditSaveRemove(file_path)
            model      = Sketchup.active_model
            definition = model.definitions.load(file_path)
            raise "Could not load definition from: #{file_path}" unless definition

            new_save_path = yield(definition)
            save_path     = new_save_path || file_path

            save_ok = definition.save_as(save_path)
            raise "save_as returned false for: #{save_path}" unless save_ok

            model.definitions.remove(definition) rescue nil

            save_path
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | File System Operations
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__RenameFileOnDisk(file_path, new_file_name)
            clean_name = new_file_name.to_s.strip
            raise 'File name is required.' if clean_name.empty?

            clean_name += '.skp' unless clean_name.downcase.end_with?('.skp')
            safe_name = clean_name.gsub(/[\\\/:"*?<>|]/, '_')

            target      = File.join(File.dirname(file_path), safe_name).tr('\\', '/')
            current     = file_path.tr('\\', '/')
            return current if target == current

            raise "A file named \"#{safe_name}\" already exists in this folder." if File.exist?(target)

            File.rename(file_path, target)
            target
        end

        def self.Na__ComponentEditorTools__MoveFileToRelativeDir(file_path, new_relative_dir)
            library_root = Na__UserConfig.Na__ComponentEditorTools__LibraryPath.to_s.tr('\\', '/').chomp('/')
            raise 'Library folder is not configured.' if library_root.empty?

            rel = new_relative_dir.to_s.strip.tr('\\', '/')
            rel = '' if rel == '(root)'
            rel = rel.gsub(%r{^/+}, '').gsub(%r{/+$}, '')

            target_dir = rel.empty? ? library_root : File.join(library_root, rel)
            FileUtils.mkdir_p(target_dir)

            target  = File.join(target_dir, File.basename(file_path)).tr('\\', '/')
            current = file_path.tr('\\', '/')
            return current if target == current

            raise "A file with this name already exists in \"#{rel.empty? ? '(root)' : rel}\"." if File.exist?(target)

            File.rename(file_path, target)
            target
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        def self.Na__ComponentEditorTools__PayloadValue(payload_hash, key_name)
            payload_hash[key_name] || payload_hash[key_name.to_sym]
        end

        def self.Na__ComponentEditorTools__LiveComponent?(definition)
            definition.respond_to?(:live_component?) && definition.live_component?
        end

        def self.Na__ComponentEditorTools__Result(success_flag, message_text, updated_path = nil)
            hash = {
                success: !!success_flag,
                message: message_text.to_s
            }
            hash[:updated_path] = updated_path.to_s if updated_path
            hash
        end

# endregion -------------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
