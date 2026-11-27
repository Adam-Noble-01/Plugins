# =============================================================================
# NA SKETCHUP MCP - HANDLERS - MODEL FILE
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__ModelFile__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__ModelFile
# PURPOSE    : model_file (save, save_as, save_copy, open, new, export, import)
#              and dxf_import (DXF/DWG import with ASCII header unit check)
# CREATED    : 2026
#
# SAFETY RULES (these actions reach outside the model):
# - Never overwrite an existing file unless overwrite:true.
# - Never discard unsaved work unless discard_unsaved_changes:true. Without it,
#   open/new on a modified model is refused (SketchUp's "save changes?" prompt
#   would otherwise block the bridge until someone clicks it).
# - Exporter and importer summary dialogs are forced off (show_summary:false)
#   unless the caller explicitly asks, because a modal dialog blocks the bridge.
# - Valid exporter/importer options are the ones documented in the stubs'
#   pages/exporter_options.md and importer_options.md; the Python server checks
#   option names against them before the call arrives here.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__ModelFile

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_ACTIONS = %w[save save_as save_copy open new export import].freeze
        NA_RASTER_EXTENSIONS = %w[.png .jpg .jpeg .bmp .tif .tiff .gif].freeze
        NA_DXF_EXTENSIONS = %w[.dxf .dwg].freeze
        NA_DXF_HEADER_MAX_LINES = 80_000
        NA_DXF_SENTINEL_EXTENT = 1.0e18
        NA_DXF_INSUNITS_NAMES = {
            0 => 'unitless', 1 => 'inches', 2 => 'feet', 3 => 'miles',
            4 => 'mm', 5 => 'cm', 6 => 'm', 7 => 'km',
            8 => 'microinches', 9 => 'mils', 10 => 'yards', 11 => 'angstroms',
            12 => 'nanometres', 13 => 'microns', 14 => 'dm', 15 => 'dam',
            16 => 'hm', 17 => 'gm', 18 => 'au', 19 => 'light_years', 20 => 'parsecs'
        }.freeze
        NA_DXF_MEASUREMENT_NAMES = { 0 => 'imperial', 1 => 'metric' }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Dispatch
# -----------------------------------------------------------------------------

        def self.Na__Handlers__ModelFile__File(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_ACTIONS, nil, required: true)
            case action
            when 'save'      then na_save(ctx)
            when 'save_as'   then na_save_to(params, ctx, false)
            when 'save_copy' then na_save_to(params, ctx, true)
            when 'open'      then na_open(params, ctx)
            when 'new'       then na_new(params, ctx)
            when 'export'    then na_export(params, ctx)
            when 'import'    then na_import(params, ctx)
            end
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Save
# -----------------------------------------------------------------------------

        def self.na_save(ctx)
            model = ctx[:model]
            if model.path.to_s.empty?
                raise Na__McpError.new('invalid_params', 'This model has never been saved, so it has no file to save to.',
                                       'Use action "save_as" with a full .skp path.')
            end

            na_require_success(model.save, 'save')
            { 'saved' => true, 'path' => model.path.to_s, 'summary' => "Saved #{File.basename(model.path)}." }
        end

        def self.na_save_to(params, ctx, as_copy)
            model = ctx[:model]
            path = na_target_path(params, '.skp')
            na_require_success(as_copy ? model.save_copy(path) : model.save(path), as_copy ? 'save_copy' : 'save_as')
            Na__ConnectionFile.Na__ConnectionFile__Refresh unless as_copy
            { 'saved' => true, 'path' => path, 'model_path' => model.path.to_s, 'copy' => as_copy,
              'summary' => "#{as_copy ? 'Saved a copy to' : 'Saved as'} #{File.basename(path)}." }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Open / New
# -----------------------------------------------------------------------------

        def self.na_open(params, ctx)
            path = na_existing_path(params, %w[.skp])
            na_release_current_model(params, ctx, 'open')
            status = Sketchup.open_file(path, with_status: true)
            unless [true, Sketchup::Model::LOAD_STATUS_SUCCESS, Sketchup::Model::LOAD_STATUS_SUCCESS_MORE_RECENT].include?(status)
                raise Na__McpError.new('operation_failed', "SketchUp could not open #{File.basename(path)} (status #{status.inspect}).",
                                       'Check the file opens by hand; it may be from a newer SketchUp or damaged.')
            end

            Na__ConnectionFile.Na__ConnectionFile__Refresh
            na_model_brief(Sketchup.active_model).merge('opened' => true, 'summary' => "Opened #{File.basename(path)}.")
        end

        def self.na_new(params, ctx)
            model = ctx[:model]
            if model.modified?
                na_release_current_model(params, ctx, 'new')
            else
                Sketchup.file_new
            end
            Na__ConnectionFile.Na__ConnectionFile__Refresh
            na_model_brief(Sketchup.active_model).merge('created' => true, 'summary' => 'Started a new, empty model.')
        end

        # Model#close(true) discards changes; on Windows it performs File > New.
        def self.na_release_current_model(params, ctx, action)
            model = ctx[:model]
            return unless model.modified?

            unless Na__Params.Na__Params__Boolean(params, 'discard_unsaved_changes', false)
                raise Na__McpError.new('invalid_params', "The open model '#{model.title}' has unsaved changes; #{action} would lose them.",
                                       'Save first (model_file action "save" or "save_as"), or only if the user has agreed, pass discard_unsaved_changes: true.')
            end

            model.close(true)
        end

        def self.na_model_brief(model)
            return { 'title' => '', 'path' => '' } unless model

            { 'title' => model.title.to_s, 'path' => model.path.to_s }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Export / Import
# -----------------------------------------------------------------------------

        def self.na_export(params, ctx)
            path = na_target_path(params, nil)
            extension = File.extname(path).downcase
            if NA_RASTER_EXTENSIONS.include?(extension)
                raise Na__McpError.new('invalid_params', "#{extension} is a raster image; model_file export writes 3D/CAD/PDF formats.",
                                       'Use view_capture with save_path for PNG/JPG images of the view.')
            end

            options = na_symbolised_options(params)
            options[:selectionset_only] = true if Na__Params.Na__Params__Boolean(params, 'selection_only', false)
            na_require_success(ctx[:model].export(path, options), "export #{extension}")
            unless File.exist?(path)
                raise Na__McpError.new('operation_failed', "SketchUp reported success but #{path} was not written.",
                                       'Some exporters need SketchUp Pro; check the format is available under File > Export > 3D Model.')
            end

            { 'exported' => true, 'path' => path, 'format' => extension.delete('.'), 'bytes' => File.size(path),
              'options' => options.transform_keys(&:to_s), 'summary' => "Exported #{File.basename(path)} (#{File.size(path)} bytes)." }
        end

        def self.na_import(params, ctx)
            path = na_existing_path(params, nil)
            if File.extname(path).casecmp?('.skp')
                raise Na__McpError.new('invalid_params', 'A .skp file is placed as a component, not imported here.',
                                       'Use component_place with skp_path (it loads the file as a definition and places one instance).')
            end

            model = ctx[:model]
            definitions_before = model.definitions.to_a
            entities_before = model.active_entities.to_a
            options = na_symbolised_options(params)

            ok = Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, "MCP: Import #{File.basename(path)}") do
                model.import(path, options)
            end
            na_require_success(ok, "import #{File.extname(path)}")

            new_definitions = model.definitions.to_a - definitions_before
            new_entities = model.active_entities.to_a - entities_before
            active_tool = model.tools.active_tool_name.to_s
            if new_entities.empty? && !new_definitions.empty?
                ctx[:warnings] << "SketchUp may be waiting for you to click to place the import (active tool: #{active_tool}). " \
                                  'Place it in the model, or press Esc and use component_place with the new definition.'
            end

            {
                'imported'        => true,
                'path'            => path,
                'new_definitions' => new_definitions.map { |definition| { 'id' => definition.persistent_id, 'name' => definition.name } },
                'new_entities'    => new_entities.first(200).map { |entity| Na__Serializer.Na__Serializer__Summary(entity, ctx) },
                'active_tool'     => active_tool,
                'summary'         => "Imported #{File.basename(path)}: #{new_entities.length} new entities, #{new_definitions.length} new definitions."
            }
        end

        # String keys -> symbols; show_summary forced false unless given.
        def self.na_symbolised_options(params)
            raw = Na__Params.Na__Params__Hash(params, 'options', {}) || {}
            options = raw.each_with_object({}) { |(key, value), symbolised| symbolised[key.to_s.delete_prefix(':').to_sym] = value }
            options[:show_summary] = false unless options.key?(:show_summary)
            options
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | DXF Import (dxf_import, 1.0.43)
# -----------------------------------------------------------------------------

        # Dedicated DXF/DWG import: reads the ASCII DXF header ($INSUNITS,
        # $MEASUREMENT, $EXTMIN, $EXTMAX) before importing in one undo step,
        # reports every added entity with world mm bounds, and warns on unit
        # header mismatches (e.g. $INSUNITS=1 inches with mm coordinates).
        def self.Na__Handlers__ModelFile__DxfImport(params, ctx)
            raw_path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            if File.extname(raw_path).casecmp?('.skp')
                raise Na__McpError.new('invalid_params', 'A .skp file is placed as a component, not imported with dxf_import.',
                                       'Use component_place with skp_path.')
            end
            path = na_existing_path(params, NA_DXF_EXTENSIONS)
            show_summary = Na__Params.Na__Params__Boolean(params, 'show_summary', false)
            check_header = Na__Params.Na__Params__Boolean(params, 'check_dxf_header', true)
            raw_op_name = Na__Params.Na__Params__String(params, 'operation_name', 'Import DXF')
            undo_label = raw_op_name.start_with?('MCP:') ? raw_op_name : "MCP: #{raw_op_name}"

            dxf_header = check_header ? self.Na__Handlers__ModelFile__ParseDxfHeader(path) : nil

            model = ctx[:model]
            definitions_before = model.definitions.to_a.dup
            active_before = model.active_entities.to_a.dup
            root_before = model.entities.to_a.dup

            ok = Na__CommandRouter.Na__CommandRouter__WithOperation(ctx, undo_label) do
                model.import(path, { show_summary: show_summary })
            end
            na_require_success(ok, "dxf_import #{File.extname(path)}")

            new_definitions = model.definitions.to_a - definitions_before
            new_entities = model.active_entities.to_a - active_before
            if new_entities.empty? && model.active_entities != model.entities
                new_entities = model.entities.to_a - root_before
            end

            added = new_entities.first(200).map { |entity| na_dxf_added_entry(entity, ctx) }
            unit_warning = check_header ? self.Na__Handlers__ModelFile__CheckDxfUnits(dxf_header, added) : nil
            ctx[:warnings] << unit_warning if unit_warning

            active_tool = model.tools.active_tool_name.to_s
            if new_entities.empty? && !new_definitions.empty?
                ctx[:warnings] << "SketchUp may be waiting for you to click to place the import (active tool: #{active_tool}). " \
                                  'Place it in the model, or press Esc and use component_place with the new definition.'
            end

            {
                'ok'              => true,
                'path'            => path,
                'added'           => added,
                'added_total'     => new_entities.length,
                'new_definitions' => new_definitions.map { |definition| { 'id' => definition.persistent_id, 'name' => definition.name } },
                'dxf_header'      => dxf_header,
                'unit_warning'    => unit_warning,
                'active_tool'     => active_tool,
                'summary'         => na_dxf_summary(path, new_entities.length, added, unit_warning)
            }
        end

        def self.na_dxf_added_entry(entity, ctx)
            container_path = Na__Serializer.Na__Serializer__ContainerPath(ctx, entity)
            world = Na__Serializer.Na__Serializer__ToWorld(ctx, container_path)
            corners = entity.is_a?(Sketchup::Drawingelement) ? Na__Serializer.Na__Serializer__TightWorldBounds(entity, ctx, world) : nil
            min_mm = corners ? corners[0].map { |value| Na__Units.Na__Units__FromInches(value, 'mm') } : nil
            max_mm = corners ? corners[1].map { |value| Na__Units.Na__Units__FromInches(value, 'mm') } : nil
            size_mm = corners ? [0, 1, 2].map { |axis| Na__Units.Na__Units__FromInches(corners[1][axis] - corners[0][axis], 'mm') } : nil
            {
                'id'       => Na__Serializer.na_persistent_id(entity),
                'type'     => Na__EntityResolver.Na__EntityResolver__TypeName(entity),
                'name'     => entity.respond_to?(:name) ? entity.name.to_s : '',
                'def_name' => entity.respond_to?(:definition) && entity.definition ? entity.definition.name.to_s : nil,
                'min_mm'   => min_mm,
                'max_mm'   => max_mm,
                'size_mm'  => size_mm
            }
        end

        def self.na_dxf_summary(path, added_total, added, unit_warning)
            size_note = ''
            first_sized = added.find { |entry| entry['size_mm'] }
            if first_sized
                sx, sy, sz = first_sized['size_mm']
                size_note = " (size #{sx.round(1)} x #{sy.round(1)} x #{sz.round(1)} mm)"
            end
            warn_note = unit_warning ? ' [UNIT WARNING]' : ''
            "Imported #{File.basename(path)}: #{added_total} added#{size_note}#{warn_note}."
        end

        # Pure Ruby: parses $INSUNITS, $MEASUREMENT, $EXTMIN and $EXTMAX from
        # an ASCII DXF HEADER section. Stops at ENDSEC so large files are fast.
        def self.Na__Handlers__ModelFile__ParseDxfHeader(path)
            ext = File.extname(path).downcase
            unless ext == '.dxf'
                return { 'format' => ext.delete('.'), 'parsed' => false,
                         'note' => 'Header parsing applies to ASCII .dxf files only.' }
            end

            probe = File.open(path, 'rb') { |handle| handle.read(32) } || ''
            if probe.start_with?('AutoCAD Binary DXF')
                return { 'format' => 'dxf_binary', 'parsed' => false,
                         'note' => 'Binary DXF: ASCII header parser skipped.' }
            end

            in_section = false
            in_header = false
            found_header = false
            current_var = nil
            insunits = nil
            measurement = nil
            extmin = [nil, nil, nil]
            extmax = [nil, nil, nil]
            lines_read = 0

            File.open(path, 'r:ISO-8859-1') do |handle|
                first_line = true
                while lines_read < NA_DXF_HEADER_MAX_LINES
                    code_line = handle.gets
                    break unless code_line
                    if first_line
                        code_line = code_line.delete_prefix("\xEF\xBB\xBF")
                        first_line = false
                    end
                    val_line = handle.gets
                    break unless val_line

                    lines_read += 2
                    code = code_line.strip
                    val = val_line.strip

                    if code == '0' && val == 'EOF'
                        break
                    elsif code == '0' && val == 'SECTION'
                        in_section = true
                        next
                    elsif in_section && code == '2'
                        in_section = false
                        if val == 'HEADER'
                            in_header = true
                            found_header = true
                        else
                            break if found_header
                        end
                        next
                    elsif in_header && code == '0' && val == 'ENDSEC'
                        break
                    end

                    next unless in_header

                    if code == '9'
                        current_var = val
                    elsif current_var == '$INSUNITS' && code == '70'
                        insunits = val.to_i
                    elsif current_var == '$MEASUREMENT' && code == '70'
                        measurement = val.to_i
                    elsif current_var == '$EXTMIN'
                        na_assign_dxf_point(extmin, code, val)
                    elsif current_var == '$EXTMAX'
                        na_assign_dxf_point(extmax, code, val)
                    end
                end
            end

            clean_min = na_clean_dxf_point(extmin)
            clean_max = na_clean_dxf_point(extmax)
            span = nil
            if clean_min && clean_max
                diffs = [0, 1, 2].map { |axis| (clean_max[axis] - clean_min[axis]).round(3) }
                span = diffs if diffs.all? { |delta| delta >= 0.0 }
            end

            {
                'format'           => 'dxf_ascii',
                'parsed'           => found_header,
                'insunits'         => insunits,
                'insunits_name'    => insunits.nil? ? nil : NA_DXF_INSUNITS_NAMES.fetch(insunits, "code_#{insunits}"),
                'measurement'      => measurement,
                'measurement_name' => measurement.nil? ? nil : NA_DXF_MEASUREMENT_NAMES.fetch(measurement, "code_#{measurement}"),
                'extmin'           => clean_min,
                'extmax'           => clean_max,
                'extents_span'     => span
            }
        end

        def self.na_assign_dxf_point(point, code, val)
            case code
            when '10' then point[0] = val.to_f
            when '20' then point[1] = val.to_f
            when '30' then point[2] = val.to_f
            end
        end

        def self.na_clean_dxf_point(point)
            return nil if point[0].nil? || point[1].nil?

            z = point[2].nil? ? 0.0 : point[2]
            coords = [point[0], point[1], z]
            return nil unless coords.all? { |value| value.finite? && value.abs < NA_DXF_SENTINEL_EXTENT }

            coords.map { |value| value.round(3) }
        end

        # Pure Ruby: detects DXF unit header mismatches between $INSUNITS,
        # $MEASUREMENT, raw $EXTMIN/$EXTMAX extents and imported size_mm.
        def self.Na__Handlers__ModelFile__CheckDxfUnits(header, added_items = [])
            return nil unless header.is_a?(Hash) && header['parsed'] == true

            insunits = header['insunits']
            measurement = header['measurement']
            span = header['extents_span']
            header_max_xy = span ? [span[0].to_f, span[1].to_f].max : nil
            header_max_xy = nil if header_max_xy && header_max_xy <= 0.0

            imported_sizes = Array(added_items).map { |entry| entry['size_mm'] }.compact
            imported_max_xy = imported_sizes.map { |size| [size[0].to_f, size[1].to_f].max }.max
            imported_max_xy = nil if imported_max_xy && imported_max_xy <= 0.0

            span_text = span ? "#{span[0].round(1)} x #{span[1].round(1)}" : 'unknown'
            meas_text = measurement.nil? ? '' : ", $MEASUREMENT=#{measurement} (#{header['measurement_name']})"
            imp_text = imported_max_xy ? "#{imported_max_xy.round(1)} mm max XY" : nil

            warnings = []

            if insunits == 1 && header_max_xy && header_max_xy >= 5000.0
                if imported_max_xy
                    ratio = imported_max_xy / header_max_xy
                    if ratio.between?(20.0, 30.0)
                        warnings << "DXF unit header mismatch: $INSUNITS=1 (inches#{meas_text}) while raw extents span #{span_text} (likely mm), " \
                                    "and SketchUp imported it at #{ratio.round(1)}x scale (#{imp_text}). Verify a known dimension; scale by 1/25.4 or set SketchUp DXF import units to mm."
                    elsif ratio.between?(0.8, 1.25)
                        warnings << "DXF unit header mismatch: $INSUNITS=1 (inches#{meas_text}) while raw extents span #{span_text} and imported size is #{imp_text} (1:1 mm). " \
                                    'Verify a known dimension against the drawing.'
                    else
                        warnings << "DXF unit header mismatch: $INSUNITS=1 (inches#{meas_text}) while raw extents span #{span_text} (likely mm); imported #{imp_text}. " \
                                    'Verify a known dimension against the drawing.'
                    end
                else
                    warnings << "DXF unit header mismatch: $INSUNITS=1 (inches#{meas_text}) while raw extents span #{span_text} (over 5,000 raw units, likely mm). " \
                                'Verify imported bounds in mm immediately.'
                end
            elsif insunits == 2 && header_max_xy && header_max_xy >= 2000.0
                warnings << "DXF unit header mismatch: $INSUNITS=2 (feet#{meas_text}) while raw extents span #{span_text} (likely mm). " \
                            'Verify imported bounds in mm against a known dimension.'
            elsif insunits == 6 && header_max_xy && imported_max_xy && (imported_max_xy / header_max_xy).between?(800.0, 1200.0) && imported_max_xy >= 2_000_000.0
                warnings << "DXF unit header mismatch: $INSUNITS=6 (metres#{meas_text}) with raw span #{span_text}, imported at 1000x (#{imp_text}); coordinates may be mm mis-tagged as metres."
            elsif insunits == 4 && header_max_xy && header_max_xy < 200.0 && (imported_max_xy.nil? || imported_max_xy < 200.0)
                warnings << "DXF unit header mismatch: $INSUNITS=4 (mm#{meas_text}) while raw extents span only #{span_text} (under 200 raw units, may be metres or feet mis-tagged as mm)."
            elsif insunits == 0
                warnings << "DXF header declares $INSUNITS=0 (unitless#{meas_text}): SketchUp uses its last DXF import unit setting. Verify imported size_mm against a known dimension."
            end

            if warnings.empty? && !insunits.nil? && !measurement.nil?
                if [1, 2].include?(insunits) && measurement == 1
                    warnings << "DXF header conflict: $INSUNITS=#{insunits} (#{header['insunits_name']}) conflicts with $MEASUREMENT=1 (metric). Verify imported size_mm."
                elsif [4, 5, 6].include?(insunits) && measurement == 0
                    warnings << "DXF header conflict: $INSUNITS=#{insunits} (#{header['insunits_name']}) conflicts with $MEASUREMENT=0 (imperial). Verify imported size_mm."
                end
            end

            warnings.empty? ? nil : warnings.join(' ')
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Path Checks
# -----------------------------------------------------------------------------

        # Public: a writable output path, refusing overwrite unless overwrite:true.
        def self.Na__Handlers__ModelFile__TargetPath(params, required_extension)
            na_target_path(params, required_extension)
        end

        def self.na_target_path(params, required_extension)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            if required_extension && !File.extname(path).casecmp?(required_extension)
                raise Na__McpError.new('invalid_params', "path must end in #{required_extension}.", nil)
            end
            unless File.directory?(File.dirname(path))
                raise Na__McpError.new('file_error', "Folder does not exist: #{File.dirname(path)}.", 'Create the folder first or choose another path.')
            end
            if File.exist?(path) && !Na__Params.Na__Params__Boolean(params, 'overwrite', false)
                raise Na__McpError.new('file_error', "#{path} already exists.", 'Pass overwrite: true only if the user wants it replaced, or choose another name.')
            end

            path
        end

        def self.na_existing_path(params, allowed_extensions)
            path = File.expand_path(Na__Params.Na__Params__String(params, 'path', nil, required: true))
            raise Na__McpError.new('file_error', "File not found: #{path}.", 'Check the path; use forward slashes or escaped backslashes.') unless File.file?(path)
            if allowed_extensions && !allowed_extensions.include?(File.extname(path).downcase)
                raise Na__McpError.new('invalid_params', "Expected a #{allowed_extensions.join('/')} file, got #{File.extname(path)}.", nil)
            end

            path
        end

        def self.na_require_success(result, action_label)
            return if result

            raise Na__McpError.new('operation_failed', "SketchUp returned false for #{action_label}.",
                                   'The file may be locked, the format unsupported by this SketchUp licence, or the path invalid.')
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__ModelFile
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
