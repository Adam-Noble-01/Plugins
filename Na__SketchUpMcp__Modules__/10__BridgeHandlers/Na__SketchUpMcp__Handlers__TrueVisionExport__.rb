# =============================================================================
# NA SKETCHUP MCP - HANDLERS - TRUEVISION GLB BUILDER
# =============================================================================
#
# FILE       : Na__SketchUpMcp__Handlers__TrueVisionExport__.rb
# NAMESPACE  : Na__SketchUpMcp::Na__Handlers__TrueVisionExport
# PURPOSE    : truevision_export, truevision_export_edit, truevision_publish
# CREATED    : 09-Nov-2026 (1.0.21)
#
# A THIN SEAM:
# The rules live in Adam's TrueVision GLB Builder (its folder
# 07__Plugin__McpOperations, 2.14.0 or newer). These handlers only check the
# action, call TrueVision3D::GlbBuilderUtility::Na__McpOperations, move its
# warnings onto the response and turn its refusals (Na__McpOperationsError:
# code, message, hint, details) into Na__McpError. If the GLB Builder or its
# seam is not loaded, all three tools refuse and name the fix.
#
# THE SPLIT, SO PERMISSIONS CAN BE SET PER TOOL:
# - truevision_export        reads only (fetch_r2 starts a job that lists R2)
# - truevision_export_edit   this model's settings and this computer's files
# - truevision_publish       the live site: R2 pushes, the R2 purge, the
#                            build pipeline; every action but push_dry_run
#                            needs confirm = the linked project's code
#
# UNDO AND BATCHES:
# The edit and publish tools have "operation": false. The seam opens its own
# "TrueVision: ..." steps (and the Scene Sync and point cloud settings open
# theirs), and SketchUp does not nest operations, so neither tool is allowed
# in batch_execute.
#
# JOBS:
# R2 work and point cloud renders run as the GLB Builder's CloudJob on a UI
# timer. The call that starts one answers at once; truevision_export
# {action: "job"} follows it. Never wait inside SketchUp for it: the bridge and
# the job share SketchUp's one thread.
#
# =============================================================================

module Na__SketchUpMcp
    module Na__Handlers__TrueVisionExport

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_READ_ACTIONS = %w[status manifest project site_plan scenes point_clouds job r2_inventory fetch_r2 logs python config].freeze
        NA_EDIT_ACTIONS = %w[export_folder export_project select_files link_project unlink_project dismiss_link_prompt set_portal_root
                             set_target create_scheme duplicate_scheme delete_scheme set_site_plan_store create_site_plan_store
                             export_site_plan switch_scenes set_scene_type detach_scene write_scenes switch_point_clouds
                             select_point_cloud_scenes set_point_cloud_scene order_point_cloud_scenes reload_point_cloud
                             export_point_clouds open_dialog reload].freeze
        NA_PUBLISH_ACTIONS = %w[push_dry_run push export_and_push write_scenes_and_push export_point_clouds_and_push
                                purge_r2_folder open_pipeline].freeze
        NA_SLOW_ACTIONS = %w[export_folder export_project export_site_plan reload export_and_push].freeze
        NA_PARTNER_ERROR = 'TrueVision3D::GlbBuilderUtility::Na__McpOperationsError'.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | truevision_export / truevision_export_edit / truevision_publish
# -----------------------------------------------------------------------------

        def self.Na__Handlers__TrueVisionExport__Read(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_READ_ACTIONS, nil, required: true)
            operations = na_operations
            na_forward(ctx) { operations.Na__GlbBuilder__McpRead(action, na_arguments(params)) }
        end

        def self.Na__Handlers__TrueVisionExport__Edit(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_EDIT_ACTIONS, nil, required: true)
            operations = na_operations
            ctx[:slow_reported] = true if NA_SLOW_ACTIONS.include?(action)
            na_forward(ctx) { operations.Na__GlbBuilder__McpEdit(action, na_arguments(params)) }
        end

        def self.Na__Handlers__TrueVisionExport__Publish(params, ctx)
            action = Na__Params.Na__Params__Enum(params, 'action', NA_PUBLISH_ACTIONS, nil, required: true)
            operations = na_operations
            ctx[:slow_reported] = true if NA_SLOW_ACTIONS.include?(action)
            na_forward(ctx) { operations.Na__GlbBuilder__McpPublish(action, na_arguments(params)) }
        end

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Helpers
# -----------------------------------------------------------------------------

        # The GLB Builder seam, or a refusal that names the fix.
        def self.na_operations
            if defined?(::TrueVision3D::GlbBuilderUtility::Na__McpOperations) &&
               ::TrueVision3D::GlbBuilderUtility::Na__McpOperations.respond_to?(:Na__GlbBuilder__McpRead)
                return ::TrueVision3D::GlbBuilderUtility::Na__McpOperations
            end

            loaded = defined?(::TrueVision3D::GlbBuilderUtility) ? 'is loaded, but without its MCP seam' : 'is not loaded in this SketchUp'
            raise Na__McpError.new('unsupported', "The TrueVision tools need the TrueVision GLB Builder 2.14.0 or newer; it #{loaded}.",
                                   'Update the GLB Builder (its 07__Plugin__McpOperations folder), then use its Reload Scripts or restart SketchUp.')
        end

        # The call's arguments without 'action', and without keys sent as null.
        def self.na_arguments(params)
            params.each_with_object({}) do |(key, value), arguments|
                next if key.to_s == 'action' || !Na__Params.Na__Params__Has(params, key)

                arguments[key.to_s] = value
            end
        end

        # Runs the seam call, moves its warnings onto the response and turns
        # its refusals into Na__McpError.
        def self.na_forward(ctx)
            result = yield
            if result.is_a?(Hash)
                Array(result.delete('warnings')).each { |text| ctx[:warnings] << text.to_s }
            end
            result
        rescue Na__McpError
            raise
        rescue StandardError => error
            raise unless error.class.name.to_s == NA_PARTNER_ERROR

            raise Na__McpError.new(error.na_code, error.message, error.na_hint, error.na_details)
        end

# endregion -------------------------------------------------------------------

    end # module Na__Handlers__TrueVisionExport
end # module Na__SketchUpMcp

# =============================================================================
# END OF FILE
# =============================================================================
