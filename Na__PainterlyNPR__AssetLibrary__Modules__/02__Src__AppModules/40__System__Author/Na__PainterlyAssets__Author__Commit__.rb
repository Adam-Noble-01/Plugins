# =============================================================================
# NA PAINTERLYNPR ASSETS - AUTHOR - COMMIT
# =============================================================================
#
# FILE       : Na__PainterlyAssets__Author__Commit__.rb
# NAMESPACE  : Na__PainterlyAssets::Na__AuthorCommit
# PURPOSE    : Files the selected component into the library as a new asset:
#              the component named exactly like its SKP file and marked with
#              its Id, its origin moved to the centre of its base if asked, the
#              asset's folder made, the SKP written by SketchUp and the DAT
#              written beside it. The validator then runs (ActionRouter).
# CREATED    : 30-Oct-2026
#
# UNDO CONTRACT:
#   One operation ("PainterlyNPR Assets: Author NPR_25_0011") holds every
#   change to the model: the group made a component, the re-seat, the rename,
#   the marks. Everything that can be checked is checked before it opens (the
#   plan, the target still selected, the DAT built in memory). Files are not
#   undone by SketchUp, so a failure after any was written aborts the
#   operation AND removes the files and folder this run made, newest first:
#   either the asset exists whole (SKP, DAT, renamed component) or not at all.
#
# COORDINATES (the coordinate rule):
#   The re-seat moves the definition's own entities by the base centre read
#   from its local bounds (the definition is closed: refused when open, see
#   Na__AuthorSelection), then puts every copy back where it was with
#   T * translation(centre). That is a right-multiplication in the
#   definition's own space, so it is right whichever context each copy sits
#   in: a copy in the open context (whose transformation reads and writes as
#   world) and a copy inside a closed component (local) both keep their place.
#   No edit_transform and no inverse are involved.
#
# =============================================================================

module Na__PainterlyAssets
    module Na__AuthorCommit

    # -------------------------------------------------------------------------
    # REGION | Constants
    # -------------------------------------------------------------------------

        NA_RESEAT_MIN_INCH = 0.001 unless defined?(NA_RESEAT_MIN_INCH)                                # <-- SketchUp's own merge distance: nothing smaller is a move

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Public Surface
    # -------------------------------------------------------------------------

        # FUNCTION | Plan Afresh (a new Id from the utility), Then File the Asset
        # ------------------------------------------------------------
        # @yield [Hash] { 'ok', 'level', 'message', 'plan', 'assetId' }
        def self.Na__Author__Commit(raw_form, &on_done)
            Na__AuthorPlan.Na__Author__Plan(raw_form) do |plan|
                result = if plan['ok']
                             Na__PainterlyAssets::Na__AuthorCommit.Na__Author__Apply(plan)
                         else
                             { 'ok' => false, 'level' => 'error', 'plan' => plan, 'message' => "Not authored: #{Array(plan['errors']).first}" }
                         end
                on_done.call(result)
            end
        end
        # ---------------------------------------------------------------

        # FUNCTION | Write the Asset From a Checked Plan
        # ------------------------------------------------------------
        def self.Na__Author__Apply(plan)
            model  = Sketchup.active_model
            target = Na__AuthorSelection.Na__Author__FindTarget(model, plan['selection']['persistentId'])
            return self.na_fail(plan, 'The component that was checked is no longer the one selected. Select it and Check again.') unless target

            dat        = Na__DatRecord.Na__Dat__BuildNew(plan)                                         # <-- Built before anything changes
            folder     = plan['folderAbs']
            skp_path   = File.join(folder, plan['files']['SKP'])
            dat_path   = File.join(folder, plan['files']['DAT'])
            created    = []
            started    = false

            begin
                model.start_operation("PainterlyNPR Assets: Author #{plan['assetId']}", true)
                started = true

                instance   = self.na_as_component(target)
                definition = instance.definition
                self.na_reseat(definition, plan['selection']['originInches']) if plan['form']['reseat']

                definition.name = plan['skpStem']
                unless definition.name == plan['skpStem']
                    raise "SketchUp named it #{definition.name}: #{plan['skpStem']} is reserved in this model. Save the model, open it again, and Author again."
                end
                definition.description = "#{plan['form']['displayName']} (#{plan['assetId']}), from the PainterlyNPR asset library"
                Na__Placement.Na__Place__Stamp(definition, self.na_asset_view(plan), 'Authored')

                unless File.directory?(folder)
                    FileUtils.mkdir_p(folder)
                    created << folder
                end
                saved = definition.save_as(skp_path)
                created << skp_path if File.file?(skp_path)
                raise "SketchUp could not write #{plan['files']['SKP']}." unless saved && File.file?(skp_path)

                Na__DatRecord.Na__Dat__Write(dat_path, dat)
                created << dat_path

                model.commit_operation
                started = false
                {
                    'ok'      => true,
                    'level'   => 'success',
                    'assetId' => plan['assetId'],
                    'plan'    => plan,
                    'message' => "Authored #{plan['assetId']} #{plan['form']['displayName']}: #{plan['folderRel']} (SKP and DAT). " \
                                 'The factory renders its MOD, PXY and RND in PainterlyNPR (Assets drawer, Pictures, Render missing).'
                }
            rescue StandardError => error
                model.abort_operation if started
                removed = self.na_remove_created(created)
                Na__DebugTools.Na__Debug__Error("Authoring #{plan['assetId']} failed.", error)
                self.na_fail(plan, "Not authored: #{error.message}#{removed.empty? ? '' : " The #{removed.length} file(s) and folder it had written were removed again."} The model is as it was.")
            end
        end
        # ---------------------------------------------------------------

    # endregion ----------------------------------------------------------------

    # -------------------------------------------------------------------------
    # REGION | Internals
    # -------------------------------------------------------------------------

        # A group becomes a component; to_component drops the name and lock and
        # may not keep tag and material, so those are carried across.
        def self.na_as_component(entity)
            return entity if entity.is_a?(Sketchup::ComponentInstance)

            layer    = entity.layer
            material = entity.material
            name     = entity.name.to_s
            instance = entity.to_component
            raise 'The group could not be made a component.' unless instance && instance.valid?

            instance.layer    = layer if layer
            instance.material = material if material
            instance.name     = name unless name.empty?
            instance
        end

        # Moves the definition's geometry so its origin is the centre of its
        # base, and every copy back by the same amount (see COORDINATES).
        def self.na_reseat(definition, centre)
            seat = Geom::Vector3d.new(*Array(centre).map(&:to_f))
            return if seat.length.to_f < NA_RESEAT_MIN_INCH

            definition.entities.transform_entities(Geom::Transformation.translation(seat.reverse), definition.entities.to_a)
            back = Geom::Transformation.translation(seat)
            definition.instances.each { |instance| instance.transformation = instance.transformation * back }
        end

        # What Na__Placement's stamp reads, from the plan.
        def self.na_asset_view(plan)
            {
                'AssetId'        => plan['assetId'],
                'SkpStem'        => plan['skpStem'],
                'DisplayName'    => plan['form']['displayName'],
                'CollectionName' => plan['collectionName'],
                'Type'           => plan['form']['type']
            }
        end

        def self.na_remove_created(created)
            removed = []
            created.reverse_each do |path|
                begin
                    if File.directory?(path)
                        Dir.rmdir(path)                                                                # <-- Only an EMPTY folder: never anything this run did not make
                    elsif File.file?(path)
                        File.delete(path)
                    end
                    removed << path
                rescue SystemCallError => error
                    Na__DebugTools.Na__Debug__Warn("Could not remove #{path} after a failed author: #{error.message}")
                end
            end
            removed
        end

        def self.na_fail(plan, message)
            { 'ok' => false, 'level' => 'error', 'plan' => plan, 'message' => message }
        end

    # endregion ----------------------------------------------------------------

    end
end

# =============================================================================
# END OF FILE
# =============================================================================
