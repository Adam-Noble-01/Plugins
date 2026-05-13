# =============================================================================
# NA MESH TOOLS - BATCHED QUADRIC DECIMATOR - NATIVE ORCHESTRATOR
# =============================================================================
#
# FILE       : Na__MeshDecimator__Orchestrator__RunNativeDecimation__.rb
# NAMESPACE  : Na__MeshDecimator::Na__Orchestrator::Na__RunNativeDecimation
# AUTHOR     : Adam Noble / Noble Architecture
# PURPOSE    : Side-by-side advanced pipeline that keeps SketchUp API work in
#              Ruby while offloading QEM mesh simplification to the C++ engine.
#
# @delegate: 04__GroupSelection/Na__MeshDecimator__GroupSelection__Collector__.rb
# @delegate: 03__Decimation/Na__MeshDecimator__Decimation__MeshExtractor__.rb
# @delegate: 08__NativeEngine/Na__MeshDecimator__NativeEngine__Bridge__.rb
# @delegate: 08__NativeEngine/Na__MeshDecimator__NativeEngine__EntitiesBuilderWriter__.rb
#
# =============================================================================

require 'sketchup.rb'

module Na__MeshDecimator
    module Na__Orchestrator
        module Na__RunNativeDecimation

            Collector      = Na__MeshDecimator::Na__GroupSelection::Na__Collector
            MeshExtractor  = Na__MeshDecimator::Na__Decimation::Na__MeshExtractor
            MeshSimplifier = Na__MeshDecimator::Na__Decimation::Na__MeshSimplifier
            NativeBridge   = Na__MeshDecimator::Na__NativeEngine::Na__Bridge
            NativeWriter   = Na__MeshDecimator::Na__NativeEngine::Na__EntitiesBuilderWriter

            # -----------------------------------------------------------------
            # REGION | Public Entry Point
            # -----------------------------------------------------------------

            def self.na_run(options)
                return {
                    :success => false,
                    :error   => NativeBridge.na_load_error || 'Native decimator binary is not available.'
                } unless NativeBridge.na_available?

                model = Sketchup.active_model

                groups = na_resolve_groups(model, options)
                return { :success => false, :error => 'No unlocked groups available to process.' } if groups.empty?

                group_meshes = na_extract_meshes(groups, options)
                return { :success => false, :error => 'No groups contained enough triangular face data to simplify.' } if group_meshes.empty?

                na_run_operation(model, group_meshes, options)
            end

            # -----------------------------------------------------------------
            # REGION | Group Resolution
            # -----------------------------------------------------------------

            def self.na_resolve_groups(model, options)
                raw = Collector.na_collect_groups_from_selection_or_context(model)

                if options[:process_nested_groups]
                    raw = Collector.na_collect_groups_including_nested(raw)
                end

                Collector.na_filter_processable_groups(raw)
            end
            private_class_method :na_resolve_groups

            # -----------------------------------------------------------------
            # REGION | Mesh Extraction Pass
            # -----------------------------------------------------------------

            def self.na_extract_meshes(groups, options)
                pairs = []

                groups.each_with_index do |group, index|
                    input_stats = na_capture_input_stats(group, index + 1)

                    mesh_data = MeshExtractor.na_extract_triangulated_mesh(
                        group,
                        options[:weld_tolerance_inches]
                    )
                    next if mesh_data[:triangles].length < 4

                    pairs << [group, mesh_data, input_stats]
                end

                pairs
            end
            private_class_method :na_extract_meshes

            def self.na_capture_input_stats(group, fallback_number)
                raw_name = group.name.to_s.strip
                {
                    :name  => raw_name.empty? ? "Group #{fallback_number}" : raw_name,
                    :faces => group.entities.grep(Sketchup::Face).length,
                    :edges => group.entities.grep(Sketchup::Edge).length
                }
            end
            private_class_method :na_capture_input_stats

            # -----------------------------------------------------------------
            # REGION | Operation
            # -----------------------------------------------------------------

            def self.na_run_operation(model, group_meshes, options)
                report_lines = []

                model.start_operation('Na Batched Native Quadric Decimator', true)

                begin
                    group_meshes.each_with_index do |trio, index|
                        group, mesh_data, input_stats = trio
                        line = na_process_one_group(group, mesh_data, input_stats, options, index + 1)
                        report_lines << line
                    end

                    model.commit_operation
                    { :success => true, :report => report_lines }

                rescue StandardError => error
                    model.abort_operation
                    {
                        :success => false,
                        :error   => "#{error.class}: #{error.message}",
                        :trace   => error.backtrace.first.to_s
                    }
                end
            end
            private_class_method :na_run_operation

            # -----------------------------------------------------------------
            # REGION | Single-Group Processing
            # -----------------------------------------------------------------

            def self.na_process_one_group(group, mesh_data, input_stats, options, group_number)
                started_at   = Time.now
                source_count = mesh_data[:triangles].length

                target_count = MeshSimplifier.na_calculate_target_triangle_count(
                    source_count,
                    options[:percentage_decimation]
                )

                simplified = NativeBridge.na_simplify_mesh(mesh_data, target_count, options)

                written = NativeWriter.na_replace_group_geometry(group, simplified, options)

                output_faces = group.entities.grep(Sketchup::Face).length
                output_edges = group.entities.grep(Sketchup::Edge).length

                actual_pct = if source_count > 0
                    (((source_count - written).to_f / source_count.to_f) * 100.0).round(1)
                else
                    0.0
                end

                status = simplified[:stopped_early] ? 'stopped early' : 'complete'
                elapsed_seconds = Time.now - started_at

                {
                    :engine           => 'Native C++',
                    :elapsed_seconds  => elapsed_seconds.round(3),
                    :group_number     => group_number,
                    :group_name       => input_stats[:name],
                    :source_triangles => source_count,
                    :input_faces      => input_stats[:faces],
                    :input_edges      => input_stats[:edges],
                    :result_triangles => written,
                    :output_faces     => output_faces,
                    :output_edges     => output_edges,
                    :actual_pct       => actual_pct,
                    :status           => status
                }
            end
            private_class_method :na_process_one_group

        end
    end
end
