# frozen_string_literal: true

# =============================================================================
# NA SELECTION STATISTICS - GENERATE REPORT (MARKDOWN FILE)
# =============================================================================
#
# FILE       : Na__SelectionStats__GenerateReport__MarkdownFile__Main__.rb
# PURPOSE    : Build a structured Markdown snapshot of current stats; save via UI.savepanel.
#
# =============================================================================

# -----------------------------------------------------------------------------
# REGION | Dependencies
# -----------------------------------------------------------------------------

require 'sketchup.rb'
require 'time'

# endregion -------------------------------------------------------------------

module Na__SelectionStats
    module Na__GenerateReport
        module Na__MarkdownFile
            extend self

# -----------------------------------------------------------------------------
# REGION | Public Export Pipeline
# -----------------------------------------------------------------------------

            def na_export_current_selection_report
                dm = Na__SelectionStats::Na__DialogManager
                dm.na_push_report_status('busy', 'Preparing Markdown report…')

                model = Sketchup.active_model
                unless model
                    dm.na_push_report_status('error', 'No active model.')
                    puts "#{Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME}: Markdown export aborted (no active model)."
                    return nil
                end

                stats = Na__SelectionStats::Na__StatsBuilder.na_build_stats(model)
                markdown_body = na_build_markdown_report(stats)

                suggested = na_suggested_report_filename(stats)
                path = UI.savepanel('Save Selection Statistics Report (.md)', '', suggested)

                if path.nil? || path.to_s.strip.empty?
                    dm.na_push_report_status('muted', 'Save cancelled.')
                    return nil
                end

                path = na_ensure_md_extension(path)
                dir = File.dirname(path)
                unless File.directory?(dir)
                    dm.na_push_report_status('error', 'Destination folder does not exist.')
                    return nil
                end

                File.write(path, markdown_body, encoding: 'UTF-8')

                dm.na_push_report_status('success', "Saved Markdown report:\\n#{path}")
                puts "[+] #{Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME}: Markdown report saved: #{path}"
                nil
            rescue StandardError => error
                msg = "#{error.class}: #{error.message}"
                Na__SelectionStats::Na__DialogManager.na_push_report_status('error', "Export failed:\\n#{msg}")
                puts "[!] #{Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME} Markdown export error: #{msg}"
                puts error.backtrace.join("\n")
                nil
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Filename Helpers
# -----------------------------------------------------------------------------

            def na_suggested_report_filename(stats)
                base_title = stats.is_a?(Hash) ? stats[:model_title].to_s : ''
                slug = na_sanitize_filename_fragment(base_title)
                slug = 'Untitled_Model' if slug.empty?

                ts = Time.now.strftime('%Y%m%d_%H%M%S')

                "#{slug}__Na__SelectionStats_Report__#{ts}.md"
            end

            def na_sanitize_filename_fragment(raw)
                s = raw.to_s.gsub(%r{[<>:"/\\|?*\x00-\x1f]}, '_').squeeze('_').strip
                s.gsub(/\A\.+/, '')
            end

            def na_ensure_md_extension(path)
                pth = path.to_s
                return pth if pth.downcase.end_with?('.md')

                "#{pth}.md"
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Markdown Document Assembly
# -----------------------------------------------------------------------------

            def na_build_markdown_report(stats)
                stats = stats.is_a?(Hash) ? stats : {}

                meta_lines = []
                meta_lines << "- Extension: #{Na__SelectionStats::Na__AppData::Na__Constants::EXTENSION_NAME}"
                meta_lines << "- SketchUp: #{Sketchup.version}"
                meta_lines << "- Model: #{na_markdown_inline(stats[:model_title].to_s)}"
                meta_lines << "- Panel clock (HUD): #{na_markdown_inline(stats[:last_updated].to_s)}"
                meta_lines << "- Report UTC: #{na_markdown_inline(Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC'))}"
                meta_lines << "- Recursive selection roots: #{stats[:selection_count].to_i}"

                parts = []
                parts << '# NA Selection Statistics Report'
                parts << ''
                parts.concat(meta_lines)
                parts << ''
                parts << '## Summary'
                parts << '| Metric | Count |'
                parts << '| --- | ---: |'

                pairs = na_summary_metric_pairs(stats)
                pairs.each do |label, num|
                    parts << "| #{label} | #{na_format_plain_integer(num)} |"
                end

                parts << ''

                mats = na_render_materials_markdown(stats[:materials])
                mats.each { |line| parts << line }

                ents = na_render_name_count_section('Entity Type Breakdown', stats[:entity_types], 'No selected entities.')
                parts << ''
                ents.each { |line| parts << line }

                names = na_render_sketchup_names_section(stats[:sketchup_names])
                parts << ''
                names.each { |line| parts << line }

                dynamic_attrs = na_render_dynamic_attributes_section(stats[:dynamic_attributes])
                parts << ''
                dynamic_attrs.each { |line| parts << line }

                mdict = na_render_dictionary_section(
                    'Model Attribute Dictionaries',
                    stats[:model_dictionaries],
                    'No model-level attribute dictionaries found.'
                )
                parts << ''
                mdict.each { |line| parts << line }

                edict = na_render_dictionary_section(
                    'Selection / Entity Attribute Dictionaries',
                    stats[:entity_dictionaries],
                    'No selection/entity attribute dictionaries found.'
                )
                parts << ''
                edict.each { |line| parts << line }

                warns = na_render_warnings_section(stats[:warnings])
                parts << ''
                warns.each { |line| parts << line }

                parts.join("\n") << "\n"
            end

            def na_summary_metric_pairs(stats)
                [
                    ['Triangles (triangulated mesh)', stats[:triangles]],
                    ['Edges (unique per instance path)', stats[:edges]],
                    ['Faces (recursive total)', stats[:faces]],
                    ['Vertices (unique per instance path)', stats[:vertices]],
                    ['Quads (simple native)', stats[:quads]],
                    ['Native triangular faces', stats[:native_triangular_faces]],
                    ['Groups', stats[:groups]],
                    ['Component instances', stats[:component_instances]],
                    ['Images', stats[:images]],
                    ['Curves', stats[:curves]],
                    ['Nested containers', stats[:nested_containers]]
                ]
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Markdown Table Renderers
# -----------------------------------------------------------------------------

            def na_render_name_count_section(title, rows, empty_text)
                lines = []
                lines << "## #{title}"
                lines << ''

                list = rows.is_a?(Array) ? rows : []
                list = na_symbolize_hashes_in_array(list)

                if list.empty?
                    lines << na_markdown_blockquote(empty_text)
                    return lines
                end

                lines << '| Name | Count |'
                lines << '| --- | ---: |'

                list.each do |item|
                    next unless item.is_a?(Hash)

                    name = item[:name].to_s
                    count = item[:count].to_i
                    lines << "| #{na_markdown_escape_cell(name)} | #{na_format_plain_integer(count)} |"
                end

                lines
            end

            def na_render_materials_markdown(rows)
                lines = []
                lines << '## Materials'
                lines << ''

                list = rows.is_a?(Array) ? rows : []
                list = na_symbolize_hashes_in_array(list)

                if list.empty?
                    lines << na_markdown_blockquote('No materials found in the current selection.')
                    return lines
                end

                lines << '| Material | Assignments | Slots |'
                lines << '| --- | ---: | --- |'

                list.each do |item|
                    next unless item.is_a?(Hash)

                    slots = item[:slots].is_a?(Array) ? item[:slots] : []
                    slots = na_symbolize_hashes_in_array(slots)

                    slots_text = slots.map do |s|
                        label = na_markdown_escape_cell(s[:name].to_s)
                        "#{label}: #{na_format_plain_integer(s[:count])}"
                    end.join('; ')

                    lines << "| #{na_markdown_escape_cell(item[:name].to_s)} | #{na_format_plain_integer(item[:count])} | #{slots_text.empty? ? "\u2014" : slots_text} |"
                end

                lines
            end

            def na_render_sketchup_names_section(rows)
                lines = []
                lines << '## SketchUp Names'
                lines << ''

                list = rows.is_a?(Array) ? rows : []
                list = na_symbolize_hashes_in_array(list)

                omitted_note = nil
                filtered = []

                list.each do |item|
                    next unless item.is_a?(Hash)

                    if truthy_truncation_marker?(item)
                        omit = item[:omitted_count].to_i
                        omitted_note = "List truncated (#{omit} further name rows omitted)." if omit.positive?
                        next
                    end

                    filtered << item
                end

                if filtered.empty?
                    lines << na_markdown_blockquote('No named groups, component definitions, or component instances found.')
                    unless omitted_note.nil?
                        lines << ''
                        lines << na_markdown_blockquote(omitted_note)
                    end
                    return lines
                end

                lines << '| Owner | Type | Name role | Name |'
                lines << '| --- | --- | --- | --- |'

                filtered.each do |item|
                    owner = na_markdown_escape_cell(item[:owner].to_s)
                    otype = na_markdown_escape_cell(item[:owner_type].to_s)
                    role = na_markdown_escape_cell(item[:role].to_s)
                    name = na_markdown_escape_cell(item[:name].to_s)
                    lines << "| #{owner} | #{otype} | #{role} | #{name} |"
                end

                unless omitted_note.nil?
                    lines << ''
                    lines << na_markdown_blockquote(omitted_note)
                end

                lines
            end

            def na_render_dynamic_attributes_section(rows)
                lines = []
                lines << '## Dynamic Component Attributes'
                lines << ''

                list = rows.is_a?(Array) ? rows : []
                list = na_symbolize_hashes_in_array(list)

                omitted_note = nil
                filtered = []

                list.each do |item|
                    next unless item.is_a?(Hash)

                    if truthy_truncation_marker?(item)
                        omit = item[:omitted_count].to_i
                        omitted_note = "List truncated (#{omit} further dynamic attribute rows omitted)." if omit.positive?
                        next
                    end

                    filtered << item
                end

                if filtered.empty?
                    lines << na_markdown_blockquote('No Dynamic Component attribute keys or values found.')
                    unless omitted_note.nil?
                        lines << ''
                        lines << na_markdown_blockquote(omitted_note)
                    end
                    return lines
                end

                lines << '| Owner | Type | Dictionary | Key | Value |'
                lines << '| --- | --- | --- | --- | --- |'

                filtered.each do |item|
                    owner = na_markdown_escape_cell(item[:owner].to_s)
                    otype = na_markdown_escape_cell(item[:owner_type].to_s)
                    dictionary = na_markdown_escape_cell(item[:dictionary].to_s)
                    key = na_markdown_escape_cell(item[:key].to_s)
                    value = na_markdown_escape_cell(item[:value].to_s)
                    lines << "| #{owner} | #{otype} | #{dictionary} | #{key} | #{value} |"
                end

                unless omitted_note.nil?
                    lines << ''
                    lines << na_markdown_blockquote(omitted_note)
                end

                lines
            end

            def na_render_dictionary_section(title, rows, empty_text)
                lines = []
                lines << "## #{title}"
                lines << ''

                list = rows.is_a?(Array) ? rows : []
                list = na_symbolize_hashes_in_array(list)

                omitted_note = nil
                filtered = []

                list.each do |item|
                    next unless item.is_a?(Hash)

                    if truthy_truncation_marker?(item)
                        omit = item[:omitted_count].to_i
                        omitted_note = "List truncated (#{omit} further dictionary rows omitted)." if omit.positive?
                        next
                    end

                    filtered << item
                end

                if filtered.empty?
                    lines << na_markdown_blockquote(empty_text)
                    unless omitted_note.nil?
                        lines << ''
                        lines << na_markdown_blockquote(omitted_note)
                    end
                    return lines
                end

                lines << '| Owner | Type | Dictionary | Keys (preview) | Key count |'
                lines << '| --- | --- | --- | --- | ---: |'

                filtered.each do |item|
                    owner = na_markdown_escape_cell(item[:owner].to_s)
                    otype = na_markdown_escape_cell(item[:owner_type].to_s)
                    dname = na_markdown_escape_cell(item[:name].to_s)
                    kcount = item[:key_count].to_i
                    keys = item[:keys].is_a?(Array) ? item[:keys] : []
                    keys_preview = keys.map { |key| na_markdown_escape_cell(key.to_s) }.join(', ')
                    keys_preview = "\u2014" if keys_preview.empty?

                    lines << "| #{owner} | #{otype} | #{dname} | #{keys_preview} | #{na_format_plain_integer(kcount)} |"
                end

                unless omitted_note.nil?
                    lines << ''
                    lines << na_markdown_blockquote(omitted_note)
                end

                lines
            end

            def na_render_warnings_section(rows)
                lines = []
                lines << '## Warnings'
                lines << ''

                list = rows.is_a?(Array) ? rows : []
                list = na_symbolize_hashes_in_array(list)

                omitted_suffix = nil
                strings = []

                list.each do |item|
                    if item.is_a?(Hash) && truthy_truncation_marker?(item)
                        extra = item[:omitted_count].to_i
                        omitted_suffix = "Truncation marker: #{extra} warning rows omitted from this report." if extra.positive?
                        next
                    end

                    next if item.is_a?(Hash)

                    strings << item.to_s
                end

                if strings.reject(&:empty?).empty?
                    lines << na_markdown_blockquote('No warnings.')
                    unless omitted_suffix.nil?
                        lines << ''
                        lines << na_markdown_blockquote(omitted_suffix)
                    end
                    return lines
                end

                strings.each do |warn|
                    next if warn.to_s.strip.empty?

                    lines << "- #{na_markdown_inline(warn)}"
                end

                unless omitted_suffix.nil?
                    lines << ''
                    lines << na_markdown_blockquote(omitted_suffix)
                end

                lines
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Markdown Primitives & Text Normalisation
# -----------------------------------------------------------------------------

            def na_markdown_escape_cell(value)
                s = na_markdown_inline(value.to_s).gsub("\n", ' ')
                s.tr("\r\t", '  ')
            end

            def na_markdown_inline(str)
                str.to_s.gsub("\r\n", "\n").strip.gsub('|', '\\|')
            rescue StandardError
                ''
            end

            def na_markdown_blockquote(str)
                s = na_markdown_escape_cell(str.to_s.gsub("\r\n", "\n"))
                q = '> '
                "#{q}#{s.gsub("\n", "\n#{q}")}"
            end

            def na_format_plain_integer(value)
                n = Integer(value)
                n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
            rescue ArgumentError, TypeError
                '0'
            end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Hash Normalisers
# -----------------------------------------------------------------------------

            def truthy_truncation_marker?(hash)
                return false unless hash.is_a?(Hash)

                flag = hash[:truncated]
                !!flag || flag.to_s == 'true'
            end

            def na_symbolize_hashes_in_array(list)
                list.map { |element| na_symbolize_shallow(element) }
            end

            def na_symbolize_shallow(item)
                return item unless item.is_a?(Hash)

                item.each_with_object({}) do |(key, val), memo|
                    k = key.is_a?(Symbol) ? key : key.to_s.to_sym
                    memo[k] = val
                end
            end

# endregion -------------------------------------------------------------------

        end
    end
end
