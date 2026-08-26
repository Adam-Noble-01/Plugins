# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - CAPTURE
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Capture__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer__Capture
# AUTHOR     : Adam Noble - Noble Architecture
# PURPOSE    : Walk every scene in the source model, serialise the requested
#              domains, and write the payload to both the model dictionary and
#              the carrier component definition.
# CREATED    : 2026
#
# THIS IS THE MODEL B SIDE OF THE TOOL.
# The user opens the model they want to harvest scenes FROM, presses Capture,
# and then saves. The payload rides inside the .skp from that point on.
#
# READING SCENE STATE WITHOUT ACTIVATING SCENES:
# Every value here is read straight off the Sketchup::Page object. No scene is
# ever selected and the user's viewport is never moved, which avoids the
# asynchronous animated transition that Pages#selected_page= triggers - a
# transition that would otherwise let a mid-flight camera be captured.
#
# THE use_* FLAG CAVEAT:
# Page#camera, Page#rendering_options and Page#shadow_info return live objects
# even when their use_* flag is false, so they hand back plausible-looking
# values that the scene will never actually apply. The flags are therefore
# captured alongside the data, and the dialog marks any scene whose flag is off.
#
# =============================================================================

require 'json'

module Na__Noble3dModellingTools
    module Na__SceneDataTransfer__Capture

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_OPERATION_NAME = 'NA Capture Scene Data'.freeze

        # Predicate method name per domain key. Read defensively through
        # respond_to?, because several of these only exist on newer releases.
        NA_USE_FLAG_METHODS = {
            'camera'          => :use_camera?,
            'axes'            => :use_axes?,
            'style'           => :use_style?,
            'fog'             => :use_rendering_options?,
            'shadows'         => :use_shadow_info?,
            'sections'        => :use_section_planes?,
            'tags'            => :use_hidden_layers?,
            'hidden_geometry' => :use_hidden_geometry?,
            'environment'     => :use_environment?
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Capture API
# -----------------------------------------------------------------------------

        # FUNCTION | Capture Every Scene in the Model Into the Embedded Payload
        # ------------------------------------------------------------
        # domain_keys defaults to whatever this build actually implements.
        # Returns { success, message, scene_count, domains, byte_length }
        def self.Na__SceneDataTransfer__CaptureModel(model, domain_keys = nil)
            return na_result(false, 'No active SketchUp model.') unless model

            schema  = Na__SceneDataTransfer__Schema
            domains = na_resolve_domains(domain_keys)
            return na_result(false, 'No implemented capture domains were requested.') if domains.empty?

            if model.pages.count.zero?
                return na_result(false, 'This model has no scenes to capture.')
            end

            payload = na_build_payload(model, domains)
            scenes  = payload['scenes']

            model.start_operation(NA_OPERATION_NAME, true)
            begin
                carrier = Na__SceneDataTransfer__Carrier.Na__SceneDataTransfer__EnsureCarrier(model)
                raise 'Could not create the payload carrier component.' unless carrier

                codec = Na__SceneDataTransfer__Codec
                codec.Na__SceneDataTransfer__WritePayload(model,   payload)         # <-- Local copy, readable while this model is open
                codec.Na__SceneDataTransfer__WritePayload(carrier, payload)         # <-- The only copy another model can reach

                model.commit_operation
            rescue => error
                model.abort_operation
                return na_result(false, "Capture failed: #{error.class}: #{error.message}")
            end

            byte_length = JSON.generate(payload).length

            na_result(
                true,
                "Captured #{scenes.length} #{scenes.length == 1 ? 'scene' : 'scenes'} " \
                "(#{domains.join(', ')}). Save this model to store the data inside the .skp file.",
                'scene_count' => scenes.length,
                'domains'     => domains,
                'byte_length' => byte_length,
                'schema'      => schema::NA_SCHEMA_VERSION
            )
        rescue => error
            na_result(false, "Capture failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Delete Any Captured Payload From This Model
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ClearModelCapture(model)
            return na_result(false, 'No active SketchUp model.') unless model

            model.start_operation('NA Clear Captured Scene Data', true)
            begin
                Na__SceneDataTransfer__Codec.Na__SceneDataTransfer__ErasePayload(model)
                Na__SceneDataTransfer__Carrier.Na__SceneDataTransfer__RemoveCarrier(model)
                model.commit_operation
            rescue => error
                model.abort_operation
                return na_result(false, "Could not clear the captured data: #{error.message}")
            end

            na_result(true, 'Captured scene data removed from this model. Save to make it permanent.')
        rescue => error
            na_result(false, "Could not clear the captured data: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

        # FUNCTION | Summarise the Payload Currently Embedded in This Model
        # ------------------------------------------------------------
        def self.Na__SceneDataTransfer__ReadLocalCaptureHeader(model)
            return nil unless model

            Na__SceneDataTransfer__Codec.Na__SceneDataTransfer__ReadHeader(model)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Payload Construction
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Assemble the Complete Payload Hash
        # ------------------------------------------------------------
        def self.na_build_payload(model, domains)
            schema = Na__SceneDataTransfer__Schema
            view   = model.active_view

            {
                'schema_version'    => schema::NA_SCHEMA_VERSION,
                'captured_at'       => Time.now.strftime('%d-%b-%Y %H:%M'),
                'captured_at_epoch' => Time.now.to_i,
                'captured_by'       => "Na Noble3d Tools Scene Data Transfer #{schema::NA_TOOL_VERSION}",
                'domains_captured'  => domains,
                'source'            => na_source_summary(model, view),
                'model_level'       => na_capture_model_level(model, domains),
                'scenes'            => model.pages.map.with_index { |page, page_index| na_capture_page(page, page_index, domains, view) }
            }
        end
        private_class_method :na_build_payload
        # ------------------------------------------------------------

        # HELPER FUNCTION | Capture the Model-Wide State Some Domains Depend On
        # ------------------------------------------------------------
        # Captured ONCE per run, not once per scene. The tag inventory and the
        # section plane list are what let the importer create what it is missing
        # before any scene is built, and the geo block is model-wide by design.
        def self.na_capture_model_level(model, domains)
            model_level = {}

            if domains.include?('tags')
                captured = Na__SceneDataTransfer__TagDomain.Na__SceneDataTransfer__CaptureModelTags(model)
                model_level['tags'] = captured if captured
            end

            if domains.include?('sections')
                captured = Na__SceneDataTransfer__SectionDomain.Na__SceneDataTransfer__CaptureModelSections(model)
                model_level['sections'] = captured if captured
            end

            if domains.include?('shadows')
                captured = Na__SceneDataTransfer__ShadowDomain.Na__SceneDataTransfer__CaptureModelGeo(model)
                model_level['shadows'] = captured if captured
            end

            if domains.include?('style')
                captured = Na__SceneDataTransfer__StyleFactory.Na__SceneDataTransfer__CaptureModelStyles(model)
                model_level['styles'] = captured if captured
            end

            model_level
        rescue => error
            puts "[Na__SceneDataTransfer] Model-level capture warning: #{error.class}: #{error.message}"
            {}
        end
        private_class_method :na_capture_model_level
        # ------------------------------------------------------------

        # HELPER FUNCTION | Describe the Source Model
        # ------------------------------------------------------------
        def self.na_source_summary(model, view)
            model_path = model.path.to_s
            model_name = if model_path.empty?
                             model.title.to_s.empty? ? 'Untitled' : model.title.to_s
                         else
                             File.basename(model_path, '.skp')
                         end

            {
                'name'             => model_name,
                'path'             => model_path,
                'guid'             => (model.respond_to?(:guid) ? model.guid.to_s : ''),
                'sketchup_version' => Sketchup.version.to_s,
                'viewport'         => { 'width' => view.vpwidth.to_i, 'height' => view.vpheight.to_i }
            }
        rescue
            { 'name' => 'Untitled', 'path' => '', 'guid' => '', 'sketchup_version' => '', 'viewport' => {} }
        end
        private_class_method :na_source_summary
        # ------------------------------------------------------------

        # HELPER FUNCTION | Capture One Page
        # ------------------------------------------------------------
        def self.na_capture_page(page, page_index, domains, view)
            record = {
                'index'                => page_index,
                'name'                 => page.name.to_s,
                'description'          => page.description.to_s,
                'delay_time'           => na_float_or(page, :delay_time, 0.0),
                'transition_time'      => na_float_or(page, :transition_time, 0.0),
                'include_in_animation' => na_boolean_or(page, :include_in_animation?, true),
                'use_flags'            => na_capture_use_flags(page),
                'domains'              => {}
            }

            domains.each do |domain_key|
                captured = na_capture_domain(page, domain_key, view)
                record['domains'][domain_key] = captured unless captured.nil?
            end

            record
        rescue => error
            puts "[Na__SceneDataTransfer] Scene capture warning for index #{page_index}: #{error.message}"
            { 'index' => page_index, 'name' => page.name.to_s, 'domains' => {}, 'use_flags' => {} }
        end
        private_class_method :na_capture_page
        # ------------------------------------------------------------

        # HELPER FUNCTION | Dispatch a Single Domain to Its Serialiser
        # ------------------------------------------------------------
        # Every new domain gets one branch here plus its own serialiser file.
        def self.na_capture_domain(page, domain_key, view)
            case domain_key
            when 'camera'
                Na__SceneDataTransfer__CameraDomain.Na__SceneDataTransfer__CaptureCamera(page.camera, view)

            when 'axes'
                Na__SceneDataTransfer__AxesDomain.Na__SceneDataTransfer__CaptureAxes(page.axes)

            when 'style'
                Na__SceneDataTransfer__RenderingDomain.Na__SceneDataTransfer__CaptureStyle(page)

            when 'fog'
                Na__SceneDataTransfer__RenderingDomain.Na__SceneDataTransfer__CaptureFog(page)

            when 'shadows'
                Na__SceneDataTransfer__ShadowDomain.Na__SceneDataTransfer__CaptureShadows(page)

            when 'sections'
                Na__SceneDataTransfer__SectionDomain.Na__SceneDataTransfer__CaptureSections(page)

            when 'tags'
                Na__SceneDataTransfer__TagDomain.Na__SceneDataTransfer__CaptureTags(page)

            when 'hidden_geometry'
                Na__SceneDataTransfer__HiddenGeometryDomain.Na__SceneDataTransfer__CaptureHiddenGeometry(page)

            else
                nil                                                                 # <-- Domain not implemented in this build
            end
        rescue => error
            puts "[Na__SceneDataTransfer] Domain '#{domain_key}' capture warning: #{error.message}"
            nil
        end
        private_class_method :na_capture_domain
        # ------------------------------------------------------------

        # HELPER FUNCTION | Record Every use_* Predicate the Page Supports
        # ------------------------------------------------------------
        def self.na_capture_use_flags(page)
            NA_USE_FLAG_METHODS.each_with_object({}) do |(domain_key, method_name), flags|
                next unless page.respond_to?(method_name)

                flags[domain_key] = !!page.send(method_name)
            end
        rescue
            {}
        end
        private_class_method :na_capture_use_flags
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Small Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Filter Requested Domains Down to Implemented Ones
        # ------------------------------------------------------------
        def self.na_resolve_domains(domain_keys)
            schema     = Na__SceneDataTransfer__Schema
            implemented = schema.Na__SceneDataTransfer__ImplementedDomainKeys
            return implemented if domain_keys.nil?

            Array(domain_keys).map(&:to_s).select { |domain_key| implemented.include?(domain_key) }
        end
        private_class_method :na_resolve_domains
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a Float Property Defensively
        # ------------------------------------------------------------
        def self.na_float_or(page, method_name, fallback_value)
            return fallback_value unless page.respond_to?(method_name)

            page.send(method_name).to_f
        rescue
            fallback_value
        end
        private_class_method :na_float_or
        # ------------------------------------------------------------

        # HELPER FUNCTION | Read a Boolean Property Defensively
        # ------------------------------------------------------------
        def self.na_boolean_or(page, method_name, fallback_value)
            return fallback_value unless page.respond_to?(method_name)

            !!page.send(method_name)
        rescue
            fallback_value
        end
        private_class_method :na_boolean_or
        # ------------------------------------------------------------

        # HELPER FUNCTION | Build the Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text, extra = {})
            { 'success' => !!success_flag, 'message' => message_text.to_s }.merge(extra)
        end
        private_class_method :na_result
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__SceneDataTransfer__Capture
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
