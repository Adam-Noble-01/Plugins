# =============================================================================
# NA NOBLE3D MODELLING TOOLS - LATTICE MAKER - RUN ENTRYPOINT
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__LatticeMaker__Run__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__LatticeMaker
# PURPOSE    : Public execution entrypoints for LatticeMaker workflows
# CREATED    : 2026
#
# =============================================================================

module Na__Noble3dModellingTools
    module Na__LatticeMaker

# -----------------------------------------------------------------------------
# REGION | Constants
# -----------------------------------------------------------------------------

        NA_LATTICE_MAKER__PLUGIN_NAME     = 'Na Noble3d - Lattice Maker'
        NA_LATTICE_MAKER__PREF_NAMESPACE  = 'Na__Noble3dModellingTools__LatticeMaker'
        NA_LATTICE_MAKER__PREF_WIDTH      = 'width'
        NA_LATTICE_MAKER__PREF_DEPTH      = 'depth'
        NA_LATTICE_MAKER__PREF_MODE       = 'mode'

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Public Entry Points
# -----------------------------------------------------------------------------

        # FUNCTION | Run LatticeMaker with Prompt Values
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__RunWithPrompt
            width_default = self.Na__LatticeMaker__StoredWidth
            depth_default = self.Na__LatticeMaker__StoredDepth
            mode_default = self.Na__LatticeMaker__StoredMode

            requested_values = Na__LatticeMaker__Input.Na__LatticeMaker__RequestUserParameters(
                NA_LATTICE_MAKER__PLUGIN_NAME,
                width_default,
                depth_default,
                mode_default
            )
            return na_result(false, 'Lattice command cancelled.') unless requested_values

            width, depth, mode = requested_values
            self.Na__LatticeMaker__RunWithValues(width, depth, mode, true)
        end
        # ------------------------------------------------------------

        # FUNCTION | Run LatticeMaker with Stored Defaults
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__RunWithLastValues
            self.Na__LatticeMaker__RunWithValues(
                self.Na__LatticeMaker__StoredWidth,
                self.Na__LatticeMaker__StoredDepth,
                self.Na__LatticeMaker__StoredMode,
                false
            )
        end
        # ------------------------------------------------------------

        # FUNCTION | Execute LatticeMaker with Provided Runtime Values
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__RunWithValues(width, depth, mode, persist_values = true)
            model = Sketchup.active_model
            return na_result(false, 'No active model available.') unless model

            selected_edges = Na__LatticeMaker__Input.Na__LatticeMaker__CollectSelectedEdges(model.selection)
            if selected_edges.empty?
                return na_result(false, 'Select one or more edges first. Edges must be in the active editing context.')
            end

            Na__LatticeMaker__Input.Na__LatticeMaker__ValidateParameters(width, depth, mode)
            self.Na__LatticeMaker__StoreDefaults(width, depth, mode) if persist_values

            selected_segments = Na__LatticeMaker__Input.Na__LatticeMaker__ConvertEdgesToSegments(selected_edges)
            working_plane = Na__LatticeMaker__PlaneMath.Na__LatticeMaker__CalculateWorkingPlane(selected_segments)
            Na__LatticeMaker__PlaneMath.Na__LatticeMaker__ValidateCoplanarSegments(selected_segments, working_plane, 0.5.mm)

            operation_started = false
            model.start_operation(NA_LATTICE_MAKER__PLUGIN_NAME, true)
            operation_started = true

            lattice_group = model.active_entities.add_group
            lattice_group.name = "NA Lattice - #{Time.now.strftime('%Y-%m-%d %H-%M-%S')}"
            lattice_entities = lattice_group.entities

            lattice_bars = Na__LatticeMaker__PlaneMath.Na__LatticeMaker__CreateLatticeBarData(
                selected_segments,
                working_plane,
                width / 2.0
            )
            raise 'No usable lattice bars were created. Selected edges may be too short.' if lattice_bars.empty?

            created_faces = Na__LatticeMaker__PlaneMath.Na__LatticeMaker__CreateRectangleFaces(
                lattice_entities,
                lattice_bars.map { |bar_data| bar_data[:world_rectangle] },
                working_plane[:zaxis]
            )
            raise 'SketchUp could not create closed lattice faces from the selected edges.' if created_faces.empty?

            Na__LatticeMaker__SolidOps.Na__LatticeMaker__ForceGroupSelfIntersection(lattice_group)
            Na__LatticeMaker__SolidOps.Na__LatticeMaker__CleanStragglerEdges(lattice_entities)

            surface_faces = Na__LatticeMaker__SolidOps.Na__LatticeMaker__FindPlanarSurfaceFaces(
                lattice_entities,
                working_plane[:zaxis]
            )
            raise 'No valid closed lattice surface was found after cleanup.' if surface_faces.empty?

            Na__LatticeMaker__SolidOps.Na__LatticeMaker__OrientFacesToNormal(surface_faces, working_plane[:zaxis])

            if mode == '3D'
                solid_prisms = Na__LatticeMaker__PlaneMath.Na__LatticeMaker__CreateSolidPrismsFromBarData(lattice_bars, depth)
                Na__LatticeMaker__SolidOps.Na__LatticeMaker__PushPullSurfaceFaces(surface_faces, depth, working_plane[:zaxis])
                Na__LatticeMaker__SolidOps.Na__LatticeMaker__ForceGroupSelfIntersection(lattice_group)

                removed_internal_faces = Na__LatticeMaker__SolidOps.Na__LatticeMaker__RemoveInternalFacesFromGeneratedSolid(
                    lattice_entities,
                    working_plane,
                    solid_prisms,
                    depth
                )
                removed_straggler_edges = Na__LatticeMaker__SolidOps.Na__LatticeMaker__CleanStragglerEdges(lattice_entities)

                Na__LatticeMaker__SolidOps.Na__LatticeMaker__ForceGroupSelfIntersection(lattice_group)
                removed_internal_faces += Na__LatticeMaker__SolidOps.Na__LatticeMaker__RemoveInternalFacesFromGeneratedSolid(
                    lattice_entities,
                    working_plane,
                    solid_prisms,
                    depth
                )
                removed_straggler_edges += Na__LatticeMaker__SolidOps.Na__LatticeMaker__CleanStragglerEdges(lattice_entities)
            else
                removed_internal_faces = 0
                removed_straggler_edges = Na__LatticeMaker__SolidOps.Na__LatticeMaker__CleanStragglerEdges(lattice_entities)
            end

            model.selection.clear
            model.selection.add(lattice_group)

            manifold_text = 'Not checked'
            if mode == '3D' && lattice_group.respond_to?(:manifold?)
                manifold_text = lattice_group.manifold? ? 'Yes' : 'No'
            end

            model.commit_operation
            operation_started = false

            na_result(
                true,
                "Lattice created. Width: #{width}, Depth: #{mode == '3D' ? depth : '2D only'}, Mode: #{mode}, " \
                "Internal faces removed: #{removed_internal_faces}, Straggler edges removed: #{removed_straggler_edges}, " \
                "Manifold: #{manifold_text}"
            )
        rescue => error
            model.abort_operation if operation_started
            na_result(false, "Lattice failed: #{error.class}: #{error.message}")
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Stored Defaults
# -----------------------------------------------------------------------------

        # FUNCTION | Return Stored Width Value
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__StoredWidth
            stored_value = Sketchup.read_default(NA_LATTICE_MAKER__PREF_NAMESPACE, NA_LATTICE_MAKER__PREF_WIDTH, 25.mm)
            Na__LatticeMaker__Input.Na__LatticeMaker__LengthFromInput(stored_value, 25.mm)
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Stored Depth Value
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__StoredDepth
            stored_value = Sketchup.read_default(NA_LATTICE_MAKER__PREF_NAMESPACE, NA_LATTICE_MAKER__PREF_DEPTH, 5.mm)
            Na__LatticeMaker__Input.Na__LatticeMaker__LengthFromInput(stored_value, 5.mm)
        end
        # ------------------------------------------------------------

        # FUNCTION | Return Stored Mode Value
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__StoredMode
            mode = Sketchup.read_default(NA_LATTICE_MAKER__PREF_NAMESPACE, NA_LATTICE_MAKER__PREF_MODE, '3D')
            mode_text = mode.to_s.upcase
            %w[2D 3D].include?(mode_text) ? mode_text : '3D'
        end
        # ------------------------------------------------------------

        # FUNCTION | Persist Width/Depth/Mode Defaults
        # ------------------------------------------------------------
        def self.Na__LatticeMaker__StoreDefaults(width, depth, mode)
            Sketchup.write_default(NA_LATTICE_MAKER__PREF_NAMESPACE, NA_LATTICE_MAKER__PREF_WIDTH, width.to_s)
            Sketchup.write_default(NA_LATTICE_MAKER__PREF_NAMESPACE, NA_LATTICE_MAKER__PREF_DEPTH, depth.to_s)
            Sketchup.write_default(NA_LATTICE_MAKER__PREF_NAMESPACE, NA_LATTICE_MAKER__PREF_MODE, mode.to_s)
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

# -----------------------------------------------------------------------------
# REGION | Result Helpers
# -----------------------------------------------------------------------------

        # HELPER FUNCTION | Build Standard Result Hash
        # ------------------------------------------------------------
        def self.na_result(success_flag, message_text)
            {
                success: !!success_flag,
                message: message_text.to_s
            }
        end
        # ------------------------------------------------------------

# endregion -------------------------------------------------------------------

    end # module Na__LatticeMaker
end # module Na__Noble3dModellingTools

# =============================================================================
# END OF FILE
# =============================================================================
