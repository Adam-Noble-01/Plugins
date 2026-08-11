# =============================================================================
# VALE LANTERN IMPORTER - TAG MANAGER
# =============================================================================
#
# FILE       : Na__ValeLantern__Importer__TagManager__.rb
# NAMESPACE  : Na__ValeLantern::Na__Importer
# MODULE     : Na__TagManager
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Create the SketchUp tags the payload declares and hand them back
#              by key, so a part record naming "glazeBarCap" lands on the tag
#              the exporter meant.
#
# DESCRIPTION:
# - The tag vocabulary is NOT held here. It arrives in the payload's Tags table,
#   which comes from Na__SketchUpExport__Config.json in the web application, so
#   a tag renamed or recoloured there is renamed and recoloured in SketchUp on
#   the next export with no plugin edit at all.
# - An existing tag of the same name is adopted rather than replaced. Importing
#   a second lantern into a model must not repaint the first one's tags, and a
#   colour the user has set by hand is a decision this tool has no business
#   overruling.
#
# NAMING CONVENTION:
# - Importer namespace Na__Importer / na_ prefixes.
#
# =============================================================================

require 'sketchup.rb'

module Na__ValeLantern
    module Na__Importer
        module Na__TagManager

# -----------------------------------------------------------------------------
# REGION | Module References and State
# -----------------------------------------------------------------------------

            DebugTools = Na__ValeLantern::Na__Importer::Na__DebugTools

            @na_tags_by_key = {}                                                                    # <-- Key from the payload, Sketchup::Layer out

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Tag Table Preparation — Public API
# -----------------------------------------------------------------------------

            # FUNCTION | Create or adopt every tag the payload declares
            # ------------------------------------------------------------
            # Run once, before any geometry is built, so a part can never be the
            # thing that creates a tag halfway through and end up on Untagged
            # because the table had not been read yet.
            #
            # @param tag_table [Array<Hash>] The payload's Model.Tags array
            # @return [Integer] How many tags are now available by key
            def self.na_prepare_tags(tag_table)
                @na_tags_by_key = {}
                return 0 unless tag_table.is_a?(Array)

                model = Sketchup.active_model
                return 0 unless model

                tag_table.each do |entry|
                    next unless entry.is_a?(Hash)

                    key   = entry['Key']
                    entry = na_apply_standard(entry)                                                # <-- DataLib wins over the payload where it can answer
                    name  = entry['Name']
                    next if key.nil? || name.nil? || name.to_s.empty?

                    layer = na_get_or_create_layer(model, name.to_s, entry)
                    @na_tags_by_key[key.to_s] = layer if layer
                end

                DebugTools.na_info("Tags prepared: #{@na_tags_by_key.length}")
                @na_tags_by_key.length
            end
            # ---------------------------------------------------------------

            # HELPER FUNCTION | Overlay the DataLib standard onto a payload tag row
            # ------------------------------------------------------------
            # Only setting out rows carry a StyleKey, so a part tag passes
            # through untouched. Where the standard knows the class, its tag
            # name, swatch colour and line style replace the payload's - which
            # is what makes three lantern exports made months apart land on the
            # same tags in the same colours.
            #
            # A class the standard has never heard of keeps the payload's own
            # values, so a setting out family added to the web application
            # imports correctly before the standard catches up.
            def self.na_apply_standard(entry)
                style_key = entry['StyleKey']
                return entry if style_key.nil? || style_key.to_s.empty?

                bridge = Na__ValeLantern::Na__Importer::Na__DataLibBridge
                return entry unless bridge.na_standard_available?

                standard_name  = bridge.na_tag_name_for(style_key)
                standard_style = bridge.na_line_style_for(style_key)
                standard_rgb   = bridge.na_tag_colour_for(style_key)
                return entry unless standard_name

                merged = entry.dup
                merged['Name']      = standard_name
                merged['LineStyle'] = standard_style if standard_style
                merged['ColorRgb']  = standard_rgb   if standard_rgb
                merged['Source']    = 'Na__DataLib'
                merged
            end
            private_class_method :na_apply_standard

            # FUNCTION | The tag registered against one payload key
            # ------------------------------------------------------------
            def self.na_tag_for_key(key)
                return nil if key.nil?
                @na_tags_by_key[key.to_s]
            end
            # ---------------------------------------------------------------

            # FUNCTION | Assign the tag for a key to an entity
            # ------------------------------------------------------------
            # A missing key leaves the entity on Untagged and says so once, which
            # is visible in the model and in the console — quieter than raising
            # and louder than doing nothing.
            def self.na_apply_tag(entity, key)
                return false unless entity && entity.respond_to?(:layer=)

                tag = na_tag_for_key(key)
                unless tag
                    DebugTools.na_detail("No tag registered for key '#{key}' - entity left untagged.")
                    return false
                end

                entity.layer = tag
                true
            end
            # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal — Layer Creation
# -----------------------------------------------------------------------------

            # HELPER FUNCTION | Fetch an existing layer or create it from the entry
            # ------------------------------------------------------------
            # Colour, visibility and line style are applied only to a layer this
            # import created. Every API call past the basics is respond_to-guarded
            # so an older SketchUp degrades to a plain named tag rather than
            # failing.
            def self.na_get_or_create_layer(model, layer_name, entry)
                existing = model.layers[layer_name]
                return existing if existing

                layer = model.layers.add(layer_name)
                return nil unless layer

                rgb = entry['ColorRgb']
                if rgb.is_a?(Array) && rgb.length >= 3 && layer.respond_to?(:color=)
                    begin
                        layer.color = Sketchup::Color.new(rgb[0].to_i, rgb[1].to_i, rgb[2].to_i)
                    rescue StandardError => e
                        DebugTools.na_detail("Tag '#{layer_name}' colour refused: #{e.message}")
                    end
                end

                if entry['Visible'] == false && layer.respond_to?(:visible=)
                    layer.visible = false
                end

                na_apply_line_style(model, layer, entry['LineStyle'])

                DebugTools.na_detail("Created tag '#{layer_name}'")
                layer
            end
            private_class_method :na_get_or_create_layer

            # HELPER FUNCTION | Apply a named dash pattern to a tag
            # ------------------------------------------------------------
            # Layer#line_style= arrived in SketchUp 2019 and the names in the
            # LineStyles collection are SketchUp's own, not ours. A name this
            # version does not carry is reported once and skipped, leaving the
            # tag solid: a datum drawn solid is a cosmetic loss, and a failed
            # import over it would be a real one.
            def self.na_apply_line_style(model, layer, style_name)
                return if style_name.nil? || style_name.to_s.empty?
                return unless layer.respond_to?(:line_style=)
                return unless model.respond_to?(:line_styles)

                styles = model.line_styles
                return unless styles && styles.respond_to?(:[])

                style = styles[style_name.to_s]
                unless style
                    DebugTools.na_detail("Line style '#{style_name}' is not in this SketchUp - tag '#{layer.name}' left solid.")
                    return
                end

                layer.line_style = style
                DebugTools.na_detail("Applied line style '#{style_name}' to tag '#{layer.name}'")
            rescue StandardError => e
                DebugTools.na_detail("Line style '#{style_name}' refused: #{e.message}")
            end
            private_class_method :na_apply_line_style

# endregion -------------------------------------------------------------------

        end
    end
end
