# =============================================================================
# NA NOBLE3D MODELLING TOOLS - MATERIAL UTILS - RUN ENTRYPOINTS
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__MaterialUtils__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__MaterialUtils
# PURPOSE    : Build standard SketchUp materials from SSOT materials index
# CREATED    : 2026
#
# =============================================================================

require 'json'
require 'fileutils'
require 'digest'
require 'net/http'
require 'uri'
require_relative '../../03__Plugin__CoreAppLogic/Na__Noble3dModellingTools__CoreAppLogic__StandardDataCache__'

module Na__Noble3dModellingTools
    module Na__MaterialUtils

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_MATERIALS_ROOT_KEY = 'Na__DataLib__CoreIndex__Materials'.freeze
        NA_META_KEY = 'meta'.freeze

        NA_DEFAULT_SERIES_KEY = 'MAT000__DefaultSeries__'.freeze
        NA_DEFAULT_MATERIAL_KEY = 'MAT001__Default'.freeze
        NA_DEFAULT_TEMPLATE_EXCLUDED_KEYS = [
            'SketchUpName',
            'Description',
            'IsDefault'
        ].freeze

        NA_MODELLING_UTILITY_SERIES_KEY = 'MAT010__ModelingUtilitySeries__'.freeze
        NA_TRUEVISION_PALETTE_SERIES_KEY = 'MAT100__BasicSeries__'.freeze

        NA_TEXTURE_CACHE_FOLDER_NAME = 'Na__Noble3dModellingTools__MaterialTextureCache'.freeze
        NA_TEXTURE_OPEN_TIMEOUT_SECONDS = 10
        NA_TEXTURE_READ_TIMEOUT_SECONDS = 20
        NA_MAX_REASON_ITEMS = 5

        NA_ATTRIBUTE_DICTIONARY_NAME = 'Na__Noble3dModellingTools__MaterialUtils'.freeze
        NA_ATTRIBUTE_KEY_MATERIAL_ID = 'Na__MaterialId'.freeze
        NA_ATTRIBUTE_KEY_SERIES_ID = 'Na__SeriesId'.freeze
        NA_ATTRIBUTE_KEY_SKETCHUP_NAME = 'Na__SketchUpName'.freeze
        NA_ATTRIBUTE_KEY_LIBRARY_VERSION = 'Na__LibraryVersion'.freeze
        NA_ATTRIBUTE_KEY_SOURCE_FILE = 'Na__SourceFile'.freeze
        NA_ATTRIBUTE_KEY_MATERIAL_JSON = 'Na__MaterialJson'.freeze
        NA_ATTRIBUTE_KEY_RAW_MATERIAL_JSON = 'Na__RawMaterialJson'.freeze
        NA_ATTRIBUTE_KEY_RENDERER_ONLY_JSON = 'Na__RendererOnlyJson'.freeze
        NA_ATTRIBUTE_KEY_WARNING_SUMMARY = 'Na__WarningSummary'.freeze

        NA_METADATA_ONLY_KEYS = [
            'Transparent',
            'IsDoubleSided',
            'DepthWrite',
            'AlphaTest',
            'EnvMapIntensity',
            'EmissiveFactor',
            'EmissiveIntensity'
        ].freeze

        NA_TEXTURE_MAP_SETTER_BY_KEY = {
            'BaseColorUrl' => :texture=,
            'NormalUrl' => :normal_texture=,
            'RoughnessUrl' => :roughness_texture=,
            'MetallicUrl' => :metallic_texture=,
            'OcclusionUrl' => :ao_texture=
        }.freeze

        @na_texture_download_cache = {}

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        def self.Na__MaterialUtils__LoadModelingUtilityMaterials
            na_load_material_set(
                'Load Modelling Utility Materials',
                [NA_MODELLING_UTILITY_SERIES_KEY]
            )
        end

        def self.Na__MaterialUtils__LoadTrueVisionMaterialsPalette
            na_load_material_set(
                'Load TrueVision Materials Palette',
                [NA_TRUEVISION_PALETTE_SERIES_KEY]
            )
        end

        def self.Na__MaterialUtils__LoadAllNobleArchitectureMaterials
            na_load_material_set(
                'Load All Noble Architecture Materials',
                :all_non_default
            )
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Loading Workflow
# -----------------------------------------------------------------------------

        def self.na_load_material_set(operation_name, series_selection)
            model = Sketchup.active_model
            return na_result(false, 'No active SketchUp model available.') unless model

            material_payload, source_label = na_load_material_payload(false)
            materials_root = na_materials_root_from_payload(material_payload)
            return na_result(false, "#{operation_name}: materials payload missing '#{NA_MATERIALS_ROOT_KEY}' [source: #{source_label}].") unless materials_root

            default_render_defaults = na_default_material_template(materials_root)
            series_resolution = na_resolve_series_selection(materials_root, series_selection)
            force_reload_attempted = false

            if series_resolution[:matched_keys].empty? && series_selection != :all_non_default
                force_reload_attempted = true
                forced_payload, forced_source_label = na_load_material_payload(true)
                forced_materials_root = na_materials_root_from_payload(forced_payload)
                if forced_materials_root
                    forced_series_resolution = na_resolve_series_selection(forced_materials_root, series_selection)
                    source_label = forced_source_label
                    if forced_series_resolution[:matched_keys].any?
                        material_payload = forced_payload
                        materials_root = forced_materials_root
                        default_render_defaults = na_default_material_template(materials_root)
                        series_resolution = forced_series_resolution
                    else
                        series_resolution = forced_series_resolution
                    end
                end

                if series_resolution[:matched_keys].empty?
                    local_payload, local_source_label = na_load_local_material_payload
                    local_materials_root = na_materials_root_from_payload(local_payload)
                    if local_materials_root
                        local_series_resolution = na_resolve_series_selection(local_materials_root, series_selection)
                        if local_series_resolution[:matched_keys].any?
                            material_payload = local_payload
                            materials_root = local_materials_root
                            default_render_defaults = na_default_material_template(materials_root)
                            series_resolution = local_series_resolution
                            source_label = local_source_label
                        end
                    end
                end
            end

            if series_resolution[:matched_keys].empty?
                no_series_message = na_build_no_matching_series_message(
                    operation_name,
                    source_label,
                    series_resolution,
                    force_reload_attempted
                )
                return na_result(false, no_series_message)
            end

            created_count = 0
            updated_count = 0
            skipped_count = 0
            failed_count = 0
            skipped_reasons = []
            failure_reasons = []
            warning_reasons = []
            operation_started = false

            model.start_operation(operation_name, true)
            operation_started = true

            series_resolution[:matched_keys].each do |series_key|
                series_materials = materials_root[series_key]
                unless series_materials.is_a?(Hash)
                    skipped_count += 1
                    na_append_reason(skipped_reasons, "series '#{series_key}' is not a material hash")
                    next
                end

                series_materials.each do |material_id, raw_material_props|
                    unless raw_material_props.is_a?(Hash)
                        skipped_count += 1
                        na_append_reason(skipped_reasons, "#{material_id}: material entry is not a hash")
                        next
                    end

                    skip_reason = na_skip_reason_for_raw_material(material_id, raw_material_props)
                    if skip_reason
                        skipped_count += 1
                        na_append_reason(skipped_reasons, skip_reason)
                        next
                    end

                    resolved_props = na_resolve_material_properties(default_render_defaults, raw_material_props)

                    create_update_result = na_create_or_update_material(
                        model.materials,
                        material_id,
                        series_key,
                        resolved_props,
                        raw_material_props,
                        material_payload[NA_META_KEY]
                    )

                    case create_update_result[:status]
                    when :created
                        created_count += 1
                    when :updated
                        updated_count += 1
                    when :skipped
                        skipped_count += 1
                        na_append_reason(skipped_reasons, create_update_result[:reason]) if create_update_result[:reason]
                    when :failed
                        failed_count += 1
                        na_append_reason(failure_reasons, create_update_result[:reason]) if create_update_result[:reason]
                    else
                        skipped_count += 1
                        na_append_reason(skipped_reasons, "#{material_id}: unknown apply status '#{create_update_result[:status]}'")
                    end

                    na_append_reason(warning_reasons, create_update_result[:warning]) if create_update_result[:warning]
                rescue => error
                    failed_count += 1
                    na_append_reason(
                        failure_reasons,
                        "#{material_id}: #{error.class}: #{error.message}"
                    )
                end
            end

            model.commit_operation
            operation_started = false

            message_text = na_build_result_message(
                operation_name,
                source_label,
                series_resolution,
                created_count,
                updated_count,
                skipped_count,
                failed_count,
                skipped_reasons,
                failure_reasons,
                warning_reasons,
                force_reload_attempted
            )

            loaded_count = created_count + updated_count
            success_flag = failed_count.zero? && loaded_count.positive?
            na_result(success_flag, message_text)
        rescue => error
            model.abort_operation if model && operation_started
            na_result(false, "#{operation_name} failed: #{error.class}: #{error.message}")
        end

        def self.na_load_material_payload(force_reload)
            payload = Na__StandardDataCache.Na__Noble3dModellingTools__LoadStandardData(:materials, force_reload)
            source_label = Na__StandardDataCache.Na__Noble3dModellingTools__LastSource(:materials) || :unknown
            [payload, source_label]
        rescue => error
            puts "[Na__Noble3dModellingTools] Material payload load warning: #{error.class}: #{error.message}"
            [nil, :failed]
        end

        def self.na_load_local_material_payload
            local_path = na_local_materials_json_path
            return [nil, :local_missing] unless local_path && File.exist?(local_path)

            raw_json = File.read(local_path, encoding: 'UTF-8')
            [JSON.parse(raw_json), :local_ssot]
        rescue => error
            puts "[Na__Noble3dModellingTools] Local materials SSOT load warning: #{error.class}: #{error.message}"
            [nil, :local_failed]
        end

        def self.na_local_materials_json_path
            return nil unless defined?(Na__PathResolver) &&
                Na__PathResolver.respond_to?(:Na__Noble3dModellingTools__PluginRoot)

            File.join(
                Na__PathResolver.Na__Noble3dModellingTools__PluginRoot,
                'Na__Common__DataLib__CoreSuEntityStandards',
                'Na__DataLib__CoreIndex__Materials__.json'
            )
        end

        def self.na_materials_root_from_payload(material_payload)
            return nil unless material_payload.is_a?(Hash)

            materials_root = material_payload[NA_MATERIALS_ROOT_KEY]
            materials_root.is_a?(Hash) ? materials_root : nil
        end

        def self.na_default_material_template(materials_root)
            default_series = materials_root[NA_DEFAULT_SERIES_KEY]
            return {} unless default_series.is_a?(Hash)

            default_material = default_series[NA_DEFAULT_MATERIAL_KEY]
            return {} unless default_material.is_a?(Hash)

            na_deep_copy_hash_without_keys(default_material, NA_DEFAULT_TEMPLATE_EXCLUDED_KEYS)
        end

        def self.na_resolve_series_selection(materials_root, series_selection)
            available_keys = materials_root.keys
                .select { |series_key| materials_root[series_key].is_a?(Hash) }
                .sort

            if series_selection == :all_non_default
                matched_keys = available_keys.reject { |series_key| series_key == NA_DEFAULT_SERIES_KEY }
                return {
                    requested_keys: ['all_non_default'],
                    matched_keys: matched_keys,
                    available_keys: available_keys,
                    match_strategy: 'all_non_default'
                }
            end

            requested_keys = Array(series_selection)
                .map(&:to_s)
                .reject(&:empty?)

            exact_keys = requested_keys
                .select { |series_key| materials_root[series_key].is_a?(Hash) }

            if exact_keys.any?
                return {
                    requested_keys: requested_keys,
                    matched_keys: exact_keys,
                    available_keys: available_keys,
                    match_strategy: 'exact'
                }
            end

            prefix_fallback_keys = requested_keys.flat_map do |requested_key|
                prefix_key = na_series_numeric_prefix(requested_key)
                next [] unless prefix_key

                available_keys.select { |available_key| available_key.start_with?(prefix_key) }
            end.uniq.sort

            {
                requested_keys: requested_keys,
                matched_keys: prefix_fallback_keys,
                available_keys: available_keys,
                match_strategy: prefix_fallback_keys.any? ? 'numeric_prefix_fallback' : 'none'
            }
        end

        def self.na_series_numeric_prefix(series_key)
            series_key.to_s[/\AMAT\d{3}__/]
        end

        def self.na_resolve_material_properties(default_render_defaults, material_props)
            return {} unless material_props.is_a?(Hash)

            na_deep_merge_hashes(default_render_defaults, material_props)
        end

        def self.na_skip_reason_for_raw_material(material_id, raw_material_props)
            return "#{material_id}: material entry is not a hash" unless raw_material_props.is_a?(Hash)
            return "#{material_id}: skipped default template entry (IsDefault=true)" if raw_material_props['IsDefault'] == true

            sketchup_name = raw_material_props.fetch('SketchUpName', '').to_s.strip
            return "#{material_id}: missing SketchUpName" if sketchup_name.empty?
            return "#{material_id}: reserved SketchUpName '__SKETCHUP_DEFAULT__'" if sketchup_name == '__SKETCHUP_DEFAULT__'

            nil
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Material Application
# -----------------------------------------------------------------------------

        def self.na_create_or_update_material(materials_collection, material_id, series_key, resolved_props, raw_material_props, meta_props)
            sketchup_name = raw_material_props.fetch('SketchUpName', '').to_s.strip
            return na_apply_result(:skipped, "#{material_id}: missing SketchUpName") if sketchup_name.empty?

            existing_material = materials_collection[sketchup_name]
            material = existing_material || materials_collection.add(sketchup_name)
            warning_items = []

            na_apply_base_color(material, resolved_props['BaseColor'], warning_items, material_id)
            na_apply_opacity(material, resolved_props['Opacity'], warning_items, material_id)
            texture_state = na_apply_texture_maps(material, resolved_props, warning_items, material_id)
            na_apply_best_effort_pbr_values(material, resolved_props, texture_state, warning_items, material_id)

            na_write_material_metadata(
                material,
                material_id,
                series_key,
                sketchup_name,
                resolved_props,
                raw_material_props,
                meta_props,
                warning_items
            )

            status_symbol = existing_material ? :updated : :created
            warning_summary = warning_items.empty? ? nil : "#{material_id}: #{warning_items.join('; ')}"
            na_apply_result(status_symbol, nil, warning_summary)
        rescue => error
            na_apply_result(:failed, "#{material_id}: #{error.class}: #{error.message}")
        end

        def self.na_apply_base_color(material, rgb_string, warning_items, material_id)
            return if rgb_string.nil?

            color_object = na_parse_rgb_string(rgb_string)
            unless color_object
                warning_items << "invalid BaseColor '#{rgb_string}'"
                return
            end

            material.color = color_object
        rescue => error
            warning_items << "BaseColor apply failed (#{error.class}: #{error.message})"
        end

        def self.na_apply_opacity(material, opacity_value, warning_items, _material_id)
            return if opacity_value.nil?

            opacity_float = na_float(opacity_value)
            unless opacity_float
                warning_items << "invalid Opacity '#{opacity_value}'"
                return
            end

            material.alpha = na_clamp(opacity_float, 0.0, 1.0)
        rescue => error
            warning_items << "Opacity apply failed (#{error.class}: #{error.message})"
        end

        def self.na_apply_texture_maps(material, material_props, warning_items, material_id)
            texture_maps = material_props['TextureMaps']
            return {
                normal_texture_applied: false,
                occlusion_texture_applied: false
            } unless texture_maps.is_a?(Hash)

            normal_texture_applied = false
            occlusion_texture_applied = false

            NA_TEXTURE_MAP_SETTER_BY_KEY.each do |map_key, setter_name|
                texture_reference = texture_maps[map_key]
                next if texture_reference.nil? || texture_reference.to_s.strip.empty?

                resolved_texture_path, resolve_warning = na_resolve_texture_path(texture_reference)
                if resolve_warning
                    warning_items << "#{map_key}: #{resolve_warning}"
                    next
                end

                unless resolved_texture_path && File.exist?(resolved_texture_path)
                    warning_items << "#{map_key}: resolved texture path not found"
                    next
                end

                unless material.respond_to?(setter_name)
                    warning_items << "#{map_key}: SketchUp Material missing setter '#{setter_name}'"
                    next
                end

                material.public_send(setter_name, resolved_texture_path)

                normal_texture_applied = true if map_key == 'NormalUrl'
                occlusion_texture_applied = true if map_key == 'OcclusionUrl'
            rescue => error
                warning_items << "#{map_key}: texture apply failed (#{error.class}: #{error.message})"
            end

            {
                normal_texture_applied: normal_texture_applied,
                occlusion_texture_applied: occlusion_texture_applied
            }
        end

        def self.na_apply_best_effort_pbr_values(material, material_props, texture_state, warning_items, _material_id)
            roughness_value = na_float(material_props['PbrRoughness'])
            metallic_value = na_float(material_props['PbrMetallic'])
            normal_scale_value = na_float(material_props['NormalScale'])
            occlusion_value = na_float(material_props['OcclusionStrength'])

            unless roughness_value.nil?
                na_apply_numeric_setter(
                    material,
                    :roughness_factor=,
                    na_clamp(roughness_value, 0.0, 1.0),
                    warning_items,
                    'PbrRoughness'
                )
                na_apply_boolean_setter(
                    material,
                    :roughness_enabled=,
                    true,
                    warning_items,
                    'PbrRoughness'
                )
            end

            unless metallic_value.nil?
                na_apply_numeric_setter(
                    material,
                    :metallic_factor=,
                    na_clamp(metallic_value, 0.0, 1.0),
                    warning_items,
                    'PbrMetallic'
                )
                na_apply_boolean_setter(
                    material,
                    :metalness_enabled=,
                    true,
                    warning_items,
                    'PbrMetallic'
                )
            end

            unless normal_scale_value.nil?
                na_apply_numeric_setter(
                    material,
                    :normal_scale=,
                    [normal_scale_value, 0.0].max,
                    warning_items,
                    'NormalScale'
                )
                if texture_state[:normal_texture_applied]
                    na_apply_boolean_setter(
                        material,
                        :normal_enabled=,
                        true,
                        warning_items,
                        'NormalScale'
                    )
                end
            end

            unless occlusion_value.nil?
                na_apply_numeric_setter(
                    material,
                    :ao_strength=,
                    na_clamp(occlusion_value, 0.0, 1.0),
                    warning_items,
                    'OcclusionStrength'
                )
                if texture_state[:occlusion_texture_applied]
                    na_apply_boolean_setter(
                        material,
                        :ao_enabled=,
                        true,
                        warning_items,
                        'OcclusionStrength'
                    )
                end
            end
        end

        def self.na_apply_numeric_setter(material, setter_name, numeric_value, warning_items, source_key)
            unless material.respond_to?(setter_name)
                warning_items << "#{source_key}: missing setter '#{setter_name}'"
                return
            end

            material.public_send(setter_name, numeric_value)
        rescue => error
            warning_items << "#{source_key}: setter '#{setter_name}' failed (#{error.class}: #{error.message})"
        end

        def self.na_apply_boolean_setter(material, setter_name, enabled, warning_items, source_key)
            return unless material.respond_to?(setter_name)
            material.public_send(setter_name, !!enabled)
        rescue => error
            warning_items << "#{source_key}: boolean setter '#{setter_name}' failed (#{error.class}: #{error.message})"
        end

        def self.na_resolve_texture_path(texture_reference)
            texture_reference_string = texture_reference.to_s.strip
            return [nil, 'empty texture reference'] if texture_reference_string.empty?

            if texture_reference_string.match?(/\Ahttps?:\/\//i)
                return na_download_remote_texture(texture_reference_string)
            end

            return [texture_reference_string, nil] if File.exist?(texture_reference_string)

            candidate_paths = na_texture_candidate_paths(texture_reference_string)
            existing_candidate = candidate_paths.find { |candidate_path| File.exist?(candidate_path) }
            return [existing_candidate, nil] if existing_candidate

            [nil, "unresolved texture '#{texture_reference_string}'"]
        rescue => error
            [nil, "texture path resolution failed (#{error.class}: #{error.message})"]
        end

        def self.na_texture_candidate_paths(texture_reference_string)
            candidate_roots = []

            if defined?(Na__PathResolver)
                if Na__PathResolver.respond_to?(:Na__Noble3dModellingTools__PluginRoot)
                    candidate_roots << Na__PathResolver.Na__Noble3dModellingTools__PluginRoot
                end
                if Na__PathResolver.respond_to?(:Na__Noble3dModellingTools__ModulesRoot)
                    candidate_roots << Na__PathResolver.Na__Noble3dModellingTools__ModulesRoot
                end
            end

            candidate_roots << File.dirname(__FILE__)
            candidate_roots.uniq.map { |root_path| File.expand_path(texture_reference_string, root_path) }
        end

        def self.na_download_remote_texture(texture_url)
            cached_path = @na_texture_download_cache[texture_url]
            return [cached_path, nil] if cached_path && File.exist?(cached_path)

            uri = URI.parse(texture_url)
            cache_directory = na_texture_cache_directory
            extension = File.extname(uri.path.to_s)
            extension = '.png' if extension.empty?
            output_filename = "tex_#{Digest::SHA1.hexdigest(texture_url)}#{extension}"
            output_path = File.join(cache_directory, output_filename)

            if File.exist?(output_path)
                @na_texture_download_cache[texture_url] = output_path
                return [output_path, nil]
            end

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = (uri.scheme == 'https')
            http.open_timeout = NA_TEXTURE_OPEN_TIMEOUT_SECONDS
            http.read_timeout = NA_TEXTURE_READ_TIMEOUT_SECONDS
            request = Net::HTTP::Get.new(uri.request_uri)
            response = http.request(request)

            return [nil, "HTTP #{response.code} #{response.message}"] unless response.is_a?(Net::HTTPSuccess)

            File.binwrite(output_path, response.body)
            @na_texture_download_cache[texture_url] = output_path
            [output_path, nil]
        rescue => error
            [nil, "remote download failed (#{error.class}: #{error.message})"]
        end

        def self.na_texture_cache_directory
            cache_directory = File.join(Sketchup.temp_dir, NA_TEXTURE_CACHE_FOLDER_NAME)
            FileUtils.mkdir_p(cache_directory) unless Dir.exist?(cache_directory)
            cache_directory
        end

        def self.na_write_material_metadata(material, material_id, series_key, sketchup_name, resolved_props, raw_material_props, meta_props, warning_items)
            dictionary = material.attribute_dictionary(NA_ATTRIBUTE_DICTIONARY_NAME, true)
            dictionary[NA_ATTRIBUTE_KEY_MATERIAL_ID] = material_id.to_s
            dictionary[NA_ATTRIBUTE_KEY_SERIES_ID] = series_key.to_s
            dictionary[NA_ATTRIBUTE_KEY_SKETCHUP_NAME] = sketchup_name.to_s
            dictionary[NA_ATTRIBUTE_KEY_LIBRARY_VERSION] = meta_props.is_a?(Hash) ? meta_props.fetch('version', '').to_s : ''
            dictionary[NA_ATTRIBUTE_KEY_SOURCE_FILE] = meta_props.is_a?(Hash) ? meta_props.fetch('fileName', '').to_s : ''
            dictionary[NA_ATTRIBUTE_KEY_MATERIAL_JSON] = JSON.generate(resolved_props)
            dictionary[NA_ATTRIBUTE_KEY_RAW_MATERIAL_JSON] = JSON.generate(raw_material_props)
            dictionary[NA_ATTRIBUTE_KEY_RENDERER_ONLY_JSON] = JSON.generate(na_renderer_only_payload(resolved_props))
            dictionary[NA_ATTRIBUTE_KEY_WARNING_SUMMARY] = warning_items.join(' | ')
        rescue => error
            warning_items << "metadata write failed (#{error.class}: #{error.message})"
        end

        def self.na_renderer_only_payload(resolved_props)
            payload = {}
            NA_METADATA_ONLY_KEYS.each do |key_name|
                payload[key_name] = resolved_props[key_name] if resolved_props.key?(key_name)
            end

            texture_maps = resolved_props['TextureMaps']
            payload['TextureMaps'] = texture_maps if texture_maps.is_a?(Hash)
            payload
        end

        def self.na_apply_result(status_symbol, reason_text = nil, warning_text = nil)
            {
                status: status_symbol,
                reason: reason_text,
                warning: warning_text
            }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Message and Diagnostics Helpers
# -----------------------------------------------------------------------------

        def self.na_build_no_matching_series_message(operation_name, source_label, series_resolution, force_reload_attempted)
            requested_preview = na_join_with_limit(series_resolution[:requested_keys], 4)
            available_preview = na_join_with_limit(series_resolution[:available_keys], 8)

            "#{operation_name}: No matching material series found. requested=#{requested_preview}; " \
            "available=#{available_preview}; strategy=#{series_resolution[:match_strategy]} " \
            "[source: #{source_label}; force_reload_attempted=#{force_reload_attempted}]."
        end

        def self.na_build_result_message(operation_name, source_label, series_resolution, created_count, updated_count, skipped_count, failed_count, skipped_reasons, failure_reasons, warning_reasons, force_reload_attempted)
            loaded_count = created_count + updated_count
            requested_preview = na_join_with_limit(series_resolution[:requested_keys], 4)
            matched_preview = na_join_with_limit(series_resolution[:matched_keys], 6)

            base_text = "#{operation_name}: #{loaded_count} loaded (#{created_count} created, #{updated_count} updated, " \
                "#{skipped_count} skipped, #{failed_count} failed) [source: #{source_label}; requested=#{requested_preview}; " \
                "matched=#{matched_preview}; strategy=#{series_resolution[:match_strategy]}; force_reload_attempted=#{force_reload_attempted}]."

            base_text += " SkipReasons: #{skipped_reasons.join(' | ')}." if skipped_reasons.any?
            base_text += " FailureReasons: #{failure_reasons.join(' | ')}." if failure_reasons.any?
            base_text += " Warnings: #{warning_reasons.join(' | ')}." if warning_reasons.any?
            base_text
        end

        def self.na_join_with_limit(items, limit_count)
            cleaned_items = Array(items).map(&:to_s).reject(&:empty?)
            return '(none)' if cleaned_items.empty?

            return cleaned_items.join(', ') if cleaned_items.length <= limit_count

            kept_items = cleaned_items.first(limit_count)
            "#{kept_items.join(', ')}, ...(+#{cleaned_items.length - limit_count} more)"
        end

        def self.na_append_reason(target_array, reason_text)
            return if reason_text.nil? || reason_text.to_s.strip.empty?
            return if target_array.length >= NA_MAX_REASON_ITEMS

            target_array << reason_text.to_s
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Utility Helpers
# -----------------------------------------------------------------------------

        def self.na_parse_rgb_string(rgb_string)
            return nil if rgb_string.nil?

            rgb_match = rgb_string.to_s.match(/\Argb\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)\z/)
            return nil unless rgb_match

            red = na_clamp(rgb_match[1].to_i, 0, 255)
            green = na_clamp(rgb_match[2].to_i, 0, 255)
            blue = na_clamp(rgb_match[3].to_i, 0, 255)
            Sketchup::Color.new(red, green, blue)
        end

        def self.na_float(value)
            return nil if value.nil?
            Float(value)
        rescue
            nil
        end

        def self.na_clamp(value, min_value, max_value)
            [[value, min_value].max, max_value].min
        end

        def self.na_deep_copy_hash_without_keys(source_hash, excluded_keys)
            return {} unless source_hash.is_a?(Hash)

            copied_hash = {}
            source_hash.each do |key_name, value|
                next if excluded_keys.include?(key_name.to_s)
                copied_hash[key_name] = na_deep_copy_value(value)
            end
            copied_hash
        end

        def self.na_deep_copy_value(value)
            case value
            when Hash
                value.each_with_object({}) do |(child_key, child_value), copy_hash|
                    copy_hash[child_key] = na_deep_copy_value(child_value)
                end
            when Array
                value.map { |child_value| na_deep_copy_value(child_value) }
            else
                value
            end
        end

        def self.na_deep_merge_hashes(base_hash, override_hash)
            return {} unless base_hash.is_a?(Hash) || override_hash.is_a?(Hash)

            merged_hash = base_hash.is_a?(Hash) ? na_deep_copy_value(base_hash) : {}
            override_hash.to_h.each do |key_name, override_value|
                base_value = merged_hash[key_name]
                merged_hash[key_name] = if base_value.is_a?(Hash) && override_value.is_a?(Hash)
                    na_deep_merge_hashes(base_value, override_value)
                else
                    na_deep_copy_value(override_value)
                end
            end
            merged_hash
        end

        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end

# endregion -------------------------------------------------------------------

    end # module Na__MaterialUtils
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
