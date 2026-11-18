# =============================================================================
# ELEMENT ASSEMBLY STUDIO PRO - ASSEMBLY RUN SYSTEM - RUN PIPELINES
# =============================================================================
#
# FILE       : Na__AssemblyStudio__AssemblyRun__RunPipelines__.rb
# NAMESPACE  : Na__AssemblyStudio::Na__AssemblyRunSystem
# MODULE     : Na__RunPipelines
# AUTHOR     : Noble Architecture
# PURPOSE    : The one path for every create, rebuild and edit of a run,
#              whoever asks: the Assembly Run Studio tab (Na__DialogRouter) or
#              an agent (60__System__McpOperations, the assembly_run tools).
# CREATED    : 16-Nov-2026 (V2.7.0)
#
# EACH PIPELINE
# - Resolves the layout FIRST and refuses a configuration with errors
#   (Na__RunLayoutError names every one) before anything in the model changes.
# - Is ONE undo step, however many windows, doors or cabinets it builds: it
#   opens the step, then runs the element pipelines inside
#   Na__OperationScope.na_embed so they join it instead of opening their own.
# - Works on the run instance it is given, raises after aborting on failure
#   so nothing half-built is left, and touches no dialog state.
# - Returns a report: { :instance, :run_id, :root, :layout, :warnings, :counts }.
#
# A NEW STEP IN A RUN'S BUILD GOES HERE (or in Na__GeometryEngine), never in
# a dialog handler or the MCP seam, or the two would build different runs.
#
# COORDINATES
# - A run's path is stored in the run's own plan. A path picked or given in
#   the model (world points) is turned into the run's placement and its own
#   path by na_world_path_frame: the run's origin is the path's first point,
#   its X the first leg.
#
# NAMING CONVENTION:
# - All custom identifiers use Na__ or na_ prefix.
#
# =============================================================================

require 'sketchup.rb'
require 'json'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__DebugTools__'
require_relative '../03__AppUtils/Na__AssemblyStudio__AppUtils__TagManager__'
require_relative '../01__AppCore/Na__AssemblyStudio__AppCore__OperationScope__'
require_relative '../04__GeometryHelpers/Na__AssemblyStudio__ComponentNameSuffix__'
require_relative 'Na__AssemblyStudio__AssemblyRun__Defaults__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PathMath__'
require_relative 'Na__AssemblyStudio__AssemblyRun__LayoutResolver__'
require_relative 'Na__AssemblyStudio__AssemblyRun__DataSerializer__'
require_relative 'Na__AssemblyStudio__AssemblyRun__PanelTypes__'
require_relative 'Na__AssemblyStudio__AssemblyRun__RunEdits__'
require_relative 'Na__AssemblyStudio__AssemblyRun__GeometryEngine__'

module Na__AssemblyStudio
module Na__AssemblyRunSystem

# -----------------------------------------------------------------------------
# REGION | Refusal Type
# -----------------------------------------------------------------------------

    # CLASS | A Run Configuration the Resolver Found Errors In
    # ------------------------------------------------------------
    class Na__RunLayoutError < StandardError
        attr_reader :na_errors

        def initialize(errors)
            @na_errors = Array(errors)
            super("The run cannot be built: #{@na_errors.join(' | ')}")
        end
    end
    # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    module Na__RunPipelines

# -----------------------------------------------------------------------------
# REGION | Module References
# -----------------------------------------------------------------------------

        DebugTools     = Na__AssemblyStudio::Na__AppUtils::Na__DebugTools
        TagManager     = Na__AssemblyStudio::Na__AppUtils::Na__TagManager
        OperationScope = Na__AssemblyStudio::Na__AppCore::Na__OperationScope
        NameSuffix     = Na__AssemblyStudio::Na__GeometryHelpers::Na__ComponentNameSuffix
        Defaults       = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__Defaults
        PathMath       = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PathMath
        LayoutResolver = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__LayoutResolver
        DataSerializer = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__DataSerializer
        PanelTypes     = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__PanelTypes
        RunEdits       = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__RunEdits
        GeometryEngine = Na__AssemblyStudio::Na__AssemblyRunSystem::Na__GeometryEngine

        NA_KEY_METADATA      = Defaults::NA_KEY_METADATA
        NA_KEY_COMPONENTS    = Defaults::NA_KEY_COMPONENTS
        NA_KEY_CONFIGURATION = Defaults::NA_KEY_CONFIGURATION

        NA_MODE_TAG_ROLES = {
            Defaults::NA_MODE_FRAMES   => :proposed_windows,
            Defaults::NA_MODE_CABINETS => :proposed_fixtures
        }.freeze

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Layout (Nothing in the Model Changes)
# -----------------------------------------------------------------------------

        # FUNCTION | A Root Payload's Layout, Problems and All
        # ------------------------------------------------------------
        def self.na_layout(root)
            LayoutResolver.na_resolve(na_config(root))
        end
        # ---------------------------------------------------------------

        # FUNCTION | A Root Payload's Layout, or a Refusal Naming Every Error
        # ------------------------------------------------------------
        def self.na_checked_layout(root)
            layout = na_layout(root)
            raise Na__RunLayoutError.new(layout[:errors]) unless layout[:errors].empty?
            layout
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | The Configuration Block of a Root (Made When Absent)
        # ------------------------------------------------------------
        def self.na_config(root)
            root[NA_KEY_CONFIGURATION] = {} unless root[NA_KEY_CONFIGURATION].is_a?(Hash)
            root[NA_KEY_CONFIGURATION]
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Create and Rebuild
# -----------------------------------------------------------------------------

        # FUNCTION | Build a New Run From a Full Payload
        # ------------------------------------------------------------
        # @param root      [Hash] { Na__AssemblyRunMetadata, Na__AssemblyRunComponents, Na__AssemblyRunConfiguration }
        # @param transform [Geom::Transformation] the run's placement: its
        #                  origin is the path's first point, its X the first leg
        # @param name      [String] name tail ("" leaves it bare)
        # @return [Hash] the report (see the file header)
        def self.na_pipeline_create(root, transform, name: "", operation_name: "Create Assembly Run")
            layout  = na_checked_layout(root)
            config  = na_config(root)
            model   = Sketchup.active_model
            na_leave_any_run_context                                             # <-- A run is never built inside another run's definition
            started = OperationScope.na_start(model, operation_name, true)
            report  = nil

            OperationScope.na_embed do
                PanelTypes.na_adopt_derived!(config, layout)
                run_id     = DataSerializer.na_generate_next_id
                definition = model.definitions.add(Defaults.na_name_head(run_id))
                instance   = model.active_entities.add_instance(definition, transform)
                DataSerializer.na_apply_identity(instance, run_id, name.to_s)
                TagManager.na_apply_tag_to_entity(instance, NA_MODE_TAG_ROLES[layout[:mode]])

                built = GeometryEngine.na_build_run(definition, config, layout, run_id)
                na_stamp_metadata(root, run_id, instance, created: true)
                root[NA_KEY_COMPONENTS] = built[:components]
                raise "The run's data could not be saved on #{definition.name}." unless DataSerializer.na_save(definition, run_id, root)
                report = na_report(instance, run_id, root, layout, built)
            end

            OperationScope.na_commit(model)
            report
        rescue StandardError
            begin; OperationScope.na_abort(model) if started; rescue StandardError; end
            raise
        end
        # ---------------------------------------------------------------

        # FUNCTION | Rebuild a Run With a Full Payload
        # ------------------------------------------------------------
        # The run keeps its place, its id and its definition; every copy of
        # it placed in the model follows.
        # @param name [String, Symbol] a new name tail, or NA_KEEP
        # @return [Hash] the report
        def self.na_pipeline_update(instance, root, name: NameSuffix::NA_KEEP, operation_name: "Update Assembly Run")
            raise "No run to update." unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
            run_id = DataSerializer.na_get_id_from_instance(instance)
            raise "#{instance.definition.name} is not an assembly run." unless run_id

            layout  = na_checked_layout(root)
            config  = na_config(root)
            model   = Sketchup.active_model
            na_leave_run_context(instance)                                       # <-- Before the operation: a rebuild inside the open run lands in world space
            started = OperationScope.na_start(model, operation_name, true)
            report  = nil

            OperationScope.na_embed do
                PanelTypes.na_adopt_derived!(config, layout)
                built = GeometryEngine.na_build_run(instance.definition, config, layout, run_id)
                DataSerializer.na_apply_identity(instance, run_id, name)
                na_stamp_metadata(root, run_id, instance, created: false)
                root[NA_KEY_COMPONENTS] = built[:components]
                raise "The run's data could not be saved on #{instance.definition.name}." unless DataSerializer.na_save(instance.definition, run_id, root)
                report = na_report(instance, run_id, root, layout, built)
            end

            OperationScope.na_commit(model)
            report
        rescue StandardError
            begin; OperationScope.na_abort(model) if started; rescue StandardError; end
            raise
        end
        # ---------------------------------------------------------------

        # FUNCTION | Step Out of a Run That Is Open for Editing
        # ------------------------------------------------------------
        # In the open context (and its parents) SketchUp reads and writes
        # every coordinate in WORLD space. The engine places spans, posts
        # and columns in the run's own frame, so a rebuild made while the
        # run was open stood them as if the run were at the model origin:
        # Make Panel Unique from the banner, with the panel selected inside
        # its run, moved the run's whole contents by the run's placement
        # (found 16-Nov-2026). The path is closed back to the run's parent
        # before anything is built. Call it OUTSIDE any operation, as
        # Model#active_path= must be; the caller selects the span again
        # afterwards, which opens the run once more.
        # @return [Boolean] true when a context was closed
        def self.na_leave_run_context(instance)
            return false if OperationScope.na_embedded?
            model = Sketchup.active_model
            path  = Array(model.active_path)
            index = path.index { |entity| entity.respond_to?(:definition) && entity.definition == instance.definition }
            return false unless index
            model.active_path = index.zero? ? nil : path[0...index]
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | Step Out of Whichever Run Is Open (Before Building a New One)
        # ------------------------------------------------------------
        # With a span selected the user is inside its run. A new run built
        # then would go into that run's definition, and be erased by its
        # next rebuild. The path is closed back to the run's parent first.
        # @return [Boolean] true when a context was closed
        def self.na_leave_any_run_context
            return false if OperationScope.na_embedded?
            model = Sketchup.active_model
            path  = Array(model.active_path)
            index = path.index { |entity| DataSerializer.na_get_id_from_instance(entity) }
            return false unless index
            model.active_path = index.zero? ? nil : path[0...index]
            true
        end
        # ---------------------------------------------------------------

        # FUNCTION | What a Placed Run Holds (No Dialog)
        # ------------------------------------------------------------
        # @return [Hash, nil] { :id, :root } with the live name stamped into
        #     the metadata, or nil when the instance is no run
        def self.na_pipeline_load(instance)
            return nil unless instance.is_a?(Sketchup::ComponentInstance) && instance.valid?
            run_id = DataSerializer.na_get_id_from_instance(instance)
            return nil unless run_id

            root = DataSerializer.na_load_from_instance(instance, run_id) || Defaults.na_default_config
            metadata = na_metadata(root)
            metadata["Na__Run__UniqueId"]      = run_id
            metadata["Na__Run__ComponentName"] = DataSerializer.na_current_tail(instance, run_id)
            { :id => run_id, :root => root }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give a Run a Name Tail (the Head Stays)
        # ------------------------------------------------------------
        # @return [String] the component's full new name
        def self.na_pipeline_rename(instance, name)
            loaded = na_pipeline_load(instance)
            raise "#{instance.respond_to?(:definition) ? instance.definition.name : 'That'} is not an assembly run." unless loaded

            model   = Sketchup.active_model
            started = OperationScope.na_start(model, "Rename Assembly Run", true)
            full    = DataSerializer.na_apply_identity(instance, loaded[:id], name.to_s)
            na_metadata(loaded[:root])["Na__Run__ComponentName"] = DataSerializer.na_current_tail(instance, loaded[:id])
            DataSerializer.na_save(instance.definition, loaded[:id], loaded[:root])
            OperationScope.na_commit(model)
            full
        rescue StandardError
            begin; OperationScope.na_abort(model) if started; rescue StandardError; end
            raise
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Edits (Each a Change to the Stored Data, Then One Rebuild)
# -----------------------------------------------------------------------------

        # FUNCTION | Change a Run's Stored Configuration and Rebuild It
        # ------------------------------------------------------------
        # @yield [config, layout, root] change config in place; the layout is
        #     the run's present one (before the change)
        # @return [Hash] the report, with whatever the block returned as :edit
        def self.na_pipeline_edit(instance, operation_name)
            loaded = na_pipeline_load(instance)
            raise "That is not an assembly run." unless loaded
            root   = PanelTypes.na_deep_copy(loaded[:root])
            layout = na_layout(root)
            edit   = yield(na_config(root), layout, root)
            report = na_pipeline_update(instance, root, operation_name: operation_name)
            report[:edit] = edit
            report
        end
        # ---------------------------------------------------------------

        # FUNCTION | Make One Span's Panel Unique (a New Type and Code)
        # ------------------------------------------------------------
        # The new type's element starts as a copy of the present one.
        # @param leg_index, span_index [Integer] zero-based
        # @return [Hash] the report; :edit is the new code
        def self.na_pipeline_make_unique(instance, leg_index, span_index, new_code = nil)
            member = na_member_at(instance, leg_index, span_index)
            raise "Leg #{leg_index + 1} has no span #{span_index + 1} standing in this run." unless member
            element = Na__AssemblyStudio::Na__McpOperations.na_element_of(member)
            raise "That span's element could not be read." unless element

            na_pipeline_edit(instance, "Make Panel Unique") do |config, layout, _root|
                RunEdits.na_make_unique!(config, layout, leg_index, span_index, element["root"], new_code)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give a Panel Type Another Code
        # ------------------------------------------------------------
        def self.na_pipeline_recode(instance, from_code, to_code)
            na_pipeline_edit(instance, "Recode Panel Type") { |config, _layout, _root| RunEdits.na_recode!(config, from_code, to_code) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give One Span Another Panel Type Already on the Run
        # ------------------------------------------------------------
        def self.na_pipeline_set_span_type(instance, leg_index, span_index, code)
            na_pipeline_edit(instance, "Change Panel Type") do |config, layout, _root|
                RunEdits.na_set_span_type!(config, layout, leg_index, span_index, code)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give One Span Another Product (V2.7.2)
        # ------------------------------------------------------------
        # A span that shares its panel type takes a new type; one with its
        # type to itself changes that type. Either way its element is built
        # again from the new product's starting values.
        # @param product [String] a key of Na__Defaults::NA_MODE_PRODUCTS
        # @return [Hash] the report; :edit is { :code, :made }
        def self.na_pipeline_set_span_product(instance, leg_index, span_index, product, new_code = nil)
            na_pipeline_edit(instance, "Change Panel to #{RunEdits.na_product_label(product.to_s.strip.downcase)}") do |config, layout, _root|
                RunEdits.na_set_span_product!(config, layout, leg_index, span_index, product, new_code)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give a Panel Type Another Product: Every Span of It (V2.7.2)
        # ------------------------------------------------------------
        # @return [Hash] the report; :edit is the type's code
        def self.na_pipeline_set_type_product(instance, code, product)
            label = RunEdits.na_product_label(product.to_s.strip.downcase)
            na_pipeline_edit(instance, "Change Panel Type #{code.to_s.strip.upcase} to #{label}") do |config, _layout, _root|
                RunEdits.na_set_type_product!(config, code, product)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Turn a Run Inside Out (V2.7.2)
        # ------------------------------------------------------------
        # The run keeps its place; its path is stored the other way round
        # (Na__RunEdits.na_flip_side!), so its elements face the other way.
        # @return [Hash] the report; :edit is the SideFlipped switch as it now stands
        def self.na_pipeline_flip_side(instance)
            na_pipeline_edit(instance, "Flip Run Inside Out") { |config, _layout, _root| RunEdits.na_flip_side!(config) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | Give a Run a New Path (the Run's Own Plan, mm)
        # ------------------------------------------------------------
        def self.na_pipeline_set_path(instance, points, closed, operation_name = "Edit Run Path")
            na_pipeline_edit(instance, operation_name) { |config, _layout, _root| RunEdits.na_set_path!(config, points, closed) }
        end
        # ---------------------------------------------------------------

        # FUNCTION | The Element Standing in One Span of a Run
        # ------------------------------------------------------------
        # @return [Sketchup::ComponentInstance, nil]
        def self.na_member_at(instance, leg_index, span_index)
            DataSerializer.na_members(instance.definition).find do |member|
                member.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_LEG).to_i == leg_index &&
                    member.get_attribute(Defaults::NA_MEMBER_DICT, Defaults::NA_MEMBER_KEY_SPAN).to_i == span_index
            end
        end
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | A Path in the Model -> the Run's Placement and Its Own Path
# -----------------------------------------------------------------------------

        # FUNCTION | Turn World Path Points Into a Placement and a Local Path
        # ------------------------------------------------------------
        # The elements are seen from the RIGHT of the path (the outside of a
        # framework, the room for cabinets). With a side point on the left,
        # the path is turned round so that side is on the right.
        # @param world_points [Array<Geom::Point3d>] the path, in order
        # @param side_point   [Geom::Point3d, nil] any point on the side the
        #                     elements are seen from
        # @param closed       [Boolean]
        # @return [Hash] { :transform, :points => [[x, y] mm], :closed, :reversed }
        def self.na_world_path_frame(world_points, side_point = nil, closed = false)
            raise ArgumentError, "A path needs at least two points." if world_points.length < 2
            up     = Sketchup.active_model ? Sketchup.active_model.axes.zaxis : Geom::Vector3d.new(0, 0, 1)
            points = world_points.map { |point| Geom::Point3d.new(point.x, point.y, point.z) }
            frame  = na_frame_on(points, up)
            plan   = na_plan_points(points, frame)

            reversed = false
            if side_point
                side = (side_point - frame[:origin])
                side_plan = [side.dot(frame[:xaxis]).to_mm, side.dot(frame[:yaxis]).to_mm]
                if PathMath.na_side_of(PathMath.na_clean_points(plan, closed), closed, side_plan) == :left
                    points   = points.reverse
                    frame    = na_frame_on(points, up)
                    plan     = na_plan_points(points, frame)
                    reversed = true
                end
            end
            {
                :transform => Geom::Transformation.axes(frame[:origin], frame[:xaxis], frame[:yaxis], up),
                :points    => PathMath.na_clean_points(plan, closed).map { |point| [point[0].round(2), point[1].round(2)] },
                :closed    => closed,
                :reversed  => reversed
            }
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | A Frame on a Path's First Point and First Leg
        # ------------------------------------------------------------
        def self.na_frame_on(points, up)
            origin = points.first
            along  = nil
            points.drop(1).each do |point|
                delta = point - origin
                flat  = delta - Geom::Vector3d.new(up.x * delta.dot(up), up.y * delta.dot(up), up.z * delta.dot(up))
                next if flat.length < 0.001
                along = flat.normalize
                break
            end
            raise ArgumentError, "The path's points are one above the other: it must run along the floor." unless along
            { :origin => origin, :xaxis => along, :yaxis => up.cross(along).normalize }
        end
        private_class_method :na_frame_on
        # ---------------------------------------------------------------

        # HELPER FUNCTION | World Points as mm in a Frame's Plan
        # ------------------------------------------------------------
        def self.na_plan_points(points, frame)
            points.map do |point|
                delta = point - frame[:origin]
                [delta.dot(frame[:xaxis]).to_mm, delta.dot(frame[:yaxis]).to_mm]
            end
        end
        private_class_method :na_plan_points
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Internal Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | The First Metadata Entry of a Root Payload
        # ------------------------------------------------------------
        def self.na_metadata(root)
            list = root[NA_KEY_METADATA]
            root[NA_KEY_METADATA] = list = [{}] unless list.is_a?(Array) && list.first.is_a?(Hash)
            list.first
        end
        # ---------------------------------------------------------------

        # HELPER FUNCTION | Id, Name and Timestamps on the Metadata
        # ------------------------------------------------------------
        def self.na_stamp_metadata(root, run_id, instance, created:)
            metadata = na_metadata(root)
            now      = Time.now.strftime("%Y-%m-%d %H:%M:%S")
            metadata["Na__Run__UniqueId"]      = run_id
            metadata["Na__Run__ComponentName"] = DataSerializer.na_current_tail(instance, run_id)
            metadata["Na__Run__CreatedDate"]   = now if created || metadata["Na__Run__CreatedDate"].nil?
            metadata["Na__Run__LastModified"]  = now
        end
        private_class_method :na_stamp_metadata
        # ---------------------------------------------------------------

        # HELPER FUNCTION | What a Pipeline Hands Back
        # ------------------------------------------------------------
        def self.na_report(instance, run_id, root, layout, built)
            {
                :instance => instance,
                :run_id   => run_id,
                :root     => root,
                :layout   => layout,
                :warnings => (layout[:warnings] + built[:warnings]).uniq,
                :counts   => built[:counts],
                :worktops => built[:worktops] || []                              # <-- V2.7.4: each worktop as built, its sizes in mm
            }
        end
        private_class_method :na_report
        # ---------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__RunPipelines
end # module Na__AssemblyRunSystem
end # module Na__AssemblyStudio

# =============================================================================
# END OF FILE
# =============================================================================
