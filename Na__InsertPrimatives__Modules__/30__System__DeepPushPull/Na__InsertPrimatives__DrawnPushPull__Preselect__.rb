# Selected faces own the gesture, even when groups are selected beside them.
# A batch uses each face's own normal/slope and the same signed measured size.
# All faces are in the user's open context: no context switches or nested ops.
#
# A LARGE SELECTION ASKS FIRST (5.1.22): more than NA_LARGE_SELECTION_FACES
# (10) selected faces and the user is asked before a single one is read or
# previewed, because CTRL+A and the shortcut would otherwise push a whole
# model, and preview every face of it on every mouse move. Yes pushes them
# all; No leaves the selection alone and faces are picked one at a time;
# Cancel leaves the tool. A batch that size reaching a commit unconfirmed is
# asked about again there. See DrawnLargeSelection.
#
# Each face's preview geometry is cached between frames (keyed by the face,
# checked by the same fingerprint the hover uses), so a confirmed batch does
# not re-triangulate every face on every mouse move.
require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnLargeSelection__'

module Na__InsertPrimatives
    module DrawnPushPullPreselect
        NA_PPS_TARGET_STATE = %i[@na_pp_target @na_pp_triangles @na_pp_loop @na_pp_area @na_pp_fingerprint
                                 @na_pp_slope @na_pp_follow @na_pp_follow_lookup].freeze

        def activate
            super
            na_pps__read_selection(true)
        end

        # ask is true only as the tool starts: re-reading after a push keeps
        # the same faces, which were confirmed (or small) already.
        def na_pps__read_selection(ask = false)
            model = Sketchup.active_model
            path = Na__InsertPrimatives.Na__DeepPick__ContextPath
            faces = model.selection.grep(Sketchup::Face).select(&:valid?)
            @na_pps_cache = {}
            if ask && !na_pps__confirm_large(faces.length)
                @na_pps_targets = []
                return @na_pps_targets
            end
            @na_pps_targets = faces.map do |face|
                Na__InsertPrimatives.Na__DeepPick__BuildTarget(face, path, nil)
            end
        end

        # true to take the selection on. No leaves it alone (hover a face as
        # usual); Cancel does the same and leaves the tool a beat later, from a
        # timer, because this runs inside activate.
        def na_pps__confirm_large(count)
            return true if count <= NA_LARGE_SELECTION_FACES
            answer = Na__InsertPrimatives.Na__LargeSelection__Ask(:faces, count, na_drawn__tool_title, 'pushed', 'Push')
            return true if answer == :yes
            if answer == :cancel
                na_drawn__schedule_exit_tool
            else
                na_revise__notice("The #{Na__InsertPrimatives.Na__LargeSelection__Count(count)} selected faces are left alone — hover a face to push it")
            end
            false
        end

        # The backstop before a commit. Never during a retype's rebuild: that
        # batch was pushed once already, so it was confirmed.
        def na_pps__commit_confirmed?
            count = @na_pps_targets.length
            return true if count <= NA_LARGE_SELECTION_FACES || na_revise__replaying?
            return true if Na__InsertPrimatives.Na__LargeSelection__Confirmed?(:faces, count)
            Na__InsertPrimatives.Na__LargeSelection__Ask(:faces, count, na_drawn__tool_title, 'pushed', 'Push') == :yes
        end

        def na_pps__active?
            !@na_pps_targets.nil? && !@na_pps_targets.empty?
        end

        def na_pps__nearest(view, x, y)
            @na_pps_targets.select { |target| target[:face].valid? }.min_by do |target|
                points = Na__InsertPrimatives.Na__DeepPick__WorldOuterLoop(target[:face], target[:transformation])
                points.each_with_index.map do |point, index|
                    Na__InsertPrimatives.Na__QuadRings__ScreenDistance(view, point, points[(index + 1) % points.length], x, y)
                end.min || Float::INFINITY
            end
        end

        def na_pps__hover(view, x, y)
            na_qo__clear_hover
            target = na_pps__nearest(view, x, y)
            target ? na_drawn__adopt_target(target) : na_drawn__clear_target
            !target.nil?
        end

        def na_pps__anchor(target, view, x, y)
            origin = Na__InsertPrimatives.Na__SlopePush__InteriorPoint(target[:face]).transform(target[:transformation])
            Geom.intersect_line_plane(view.pickray(x, y), [origin, target[:world_normal]]) || origin
        end

        # Cache switching is scoped so previewing another member cannot change
        # the driver, its measurement, or the cached FOLLOW rails. Each member's
        # own state is kept between frames: restored before the adopt, whose
        # fingerprint check then reuses it unless the face has moved.
        def na_pps__with_target(target)
            names = NA_PPS_TARGET_STATE
            saved = names.map { |name| instance_variable_get(name) }
            face  = target[:face]
            key   = face && face.valid? ? face.entityID : nil
            cache = (@na_pps_cache ||= {})
            names.zip(cache[key]).each { |name, value| instance_variable_set(name, value) } if key && cache[key]
            na_drawn__adopt_target(target)
            cache[key] = names.map { |name| instance_variable_get(name) } if key
            yield
        ensure
            names.zip(saved).each { |name, value| instance_variable_set(name, value) }
        end

        def na_pps__draw(view)
            @na_pps_targets.each do |target|
                next unless target[:face].valid?
                na_pps__with_target(target) do
                    if @na_state == :picking_depth
                        DrawnPushPullTool.instance_method(:na_drawn__draw_push_preview).bind(self).call(view)
                    else
                        DrawnPushPullTool.instance_method(:na_drawn__draw_hover).bind(self).call(view)
                    end
                end
            end
        end

        def na_pps__preview_points
            @na_pps_targets.flat_map do |target|
                next [] unless target[:face].valid?
                na_pps__with_target(target) do
                    points = @na_pp_loop || []
                    offset = na_drawn__push_offset_vector if @na_state == :picking_depth
                    offset ? points + points.map { |point| na_drawn__move_world_point(point, offset) } : points
                end
            end
        end

        def na_pps__status
            count = @na_pps_targets.length
            verb = @na_state == :picking_depth ? 'release or click to place' : 'press and drag to push/pull'
            "#{count} preselected face#{count == 1 ? '' : 's'} — #{verb}#{na_revise__status_hint}"
        end

        def na_drawn__commit_push(view)
            return super unless na_pps__active? && @na_pps_targets.length > 1
            na_pps__commit(view)
        end

        def na_pps__commit(view)
            model = Sketchup.active_model
            opened = false
            records = []
            unless Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
                raise ArgumentError, 'Drag further or type a nonzero distance'
            end
            raise 'that many faces were not confirmed — nothing pushed' unless na_pps__commit_confirmed?
            # Prepare every recipe before any push can alter a neighbouring face.
            recipes = @na_pps_targets.map do |target|
                raise 'A selected face is no longer available' unless target[:face].valid?
                raise 'A selected face is locked' if target[:locked]
                raise 'The editing context changed — reselect the faces' unless Na__InsertPrimatives.Na__DeepPick__InOpenContext?(target[:face])
                na_pps__with_target(target) do
                    raise 'A selected face cannot travel along the locked axis' unless na_drawn__axis_lock_usable?
                    problem = na_drawn__follow_problem
                    raise problem if problem
                    snapshot = na_revise__snapshot(target, model)
                    offset = na_drawn__local_offset_vector(target)
                    raise 'A selected face could not be measured' unless snapshot && offset
                    [target, snapshot, offset, na_drawn__slope_mode?, na_drawn__loop_cut_mode?, na_revise__build_ghost(target)]
                end
            end
            model.start_operation('Deep Push Pull (Selected Faces)', true)
            opened = true
            @na_pps_transaction = true
            recipes.each do |target, snapshot, offset, sloped, cutting, ghost|
                raise 'A push removed another selected face; the batch was cancelled' unless target[:face].valid?
                na_pps__with_target(target) do
                    raise(@na_pp_last_error || 'Push failed') unless na_drawn__execute_push(model, target, offset)
                    if cutting && (@na_pp_quad_stats.nil? || @na_pp_quad_stats[:kept].to_i.zero?)
                        raise 'A selected face could not produce a loop cut'
                    end
                    na_revise__capture(target, snapshot, offset, sloped, cutting)
                    raise 'Could not record a selected face' unless @na_revise_record
                    records << @na_revise_record.merge(:ghost => ghost)
                end
            end
            model.commit_operation
            opened = false
            counts = recipes.map { |recipe| recipe[1][:entities] }.uniq.map { |entities| [entities, na_revise__entity_count(entities)] }
            record = records.first.merge(:kind => :face_batch, :members => records, :counts => counts,
                                         :ghost => { :members => records.map { |member| member[:ghost] } })
            na_revise__arm(record)
            na_drawn__reset_pick_state
            na_pps__read_selection
            view.invalidate if view
            true
        rescue StandardError => error
            model.abort_operation if opened
            na_revise__forget
            na_revise__load_memory
            UI.beep
            na_revise__notice("Selected faces not placed — #{error.message}")
            false
        ensure
            @na_pps_transaction = false
        end

        def na_revise__reacquire(record)
            return super unless record[:kind] == :face_batch
            targets = record[:members].map { |member| super(member) }
            targets.all? ? targets : nil
        end

        def na_revise__rebuild(record, target, value, view)
            return super unless record[:kind] == :face_batch
            @na_pps_targets = target
            na_revise__wearing(record, target.first, value) { na_pps__commit(view) }
        end

        def na_revise__parse_retype(text, record)
            return super unless record[:kind] == :face_batch
            # A face batch is a push-distance record, not a single ring layout.
            DrawnPushPullRevise.instance_method(:na_revise__parse_retype).bind(self).call(text, record)
        end

        def na_revise__draw_ghost(view, ghost, value, from_value, to_value)
            return super unless ghost[:members]
            ghost[:members].each { |member| super(view, member, value, from_value, to_value) }
            true
        end

        def na_revise__ghost_points(ghost, value)
            return super unless ghost[:members]
            ghost[:members].flat_map { |member| super(member, value) }
        end
    end
end
