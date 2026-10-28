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
#
# SELECTED FACES THAT TOUCH PUSH AS ONE (5.2.14, Joint Surfaces on):
# Clicking a smoothed surface with the Select tool takes all of it, so the
# fifty faces of a curved fascia arrive here together, and pushing each on
# its own opened them into a fan of separate boxes. The selection is split
# into UNITS: faces sharing an edge are one unit, pushed as one surface by
# DrawnPushPullJoint (every face along its own normal, the corners mitred);
# a face touching no other selected face is a unit of its own and pushes
# exactly as before. Joint Surfaces off, every face is its own unit.
require 'sketchup.rb'
require_relative '../06__Tools__DrawnShared/Na__InsertPrimatives__DrawnLargeSelection__'
require_relative 'Na__InsertPrimatives__DrawnPushPull__JointGeometry__'

module Na__InsertPrimatives
    module DrawnPushPullPreselect
        NA_PPS_TARGET_STATE = %i[@na_pp_target @na_pp_triangles @na_pp_loop @na_pp_area @na_pp_fingerprint
                                 @na_pp_slope @na_pp_follow @na_pp_follow_lookup @na_pp_joint].freeze

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
            @na_pps_units = []
            if ask && !na_pps__confirm_large(faces.length)
                @na_pps_targets = []
                return @na_pps_targets
            end
            @na_pps_targets = faces.map do |face|
                Na__InsertPrimatives.Na__DeepPick__BuildTarget(face, path, nil)
            end
            na_pps__regroup
            @na_pps_targets
        end

        # The selection is in the open context, so the faces report world and
        # each surface's plan is read through the identity.
        def na_pps__regroup
            targets = @na_pps_targets || []
            @na_pps_units =
                if na_jp__enabled? && targets.length > 1
                    by_face = {}
                    targets.each { |target| by_face[target[:face]] = target }
                    Na__InsertPrimatives.Na__JointPush__Components(targets.map { |target| target[:face] }).map do |faces|
                        plan = faces.length > 1 ? Na__InsertPrimatives.Na__JointPush__Plan(faces, Geom::Transformation.new) : nil
                        { :targets => faces.map { |face| by_face[face] }, :joint => plan }
                    end
                else
                    targets.map { |target| { :targets => [target], :joint => nil } }
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

        # The units a stale read would draw from. Reading the selection again
        # is a few faces; a surface's plan is read only when it changed.
        def na_pps__units
            @na_pps_units ||= []
            na_pps__regroup if @na_pps_units.empty? && na_pps__active?
            @na_pps_units
        end

        def na_pps__draw(view)
            na_pps__units.each do |unit|
                plan = unit[:joint]
                if plan
                    next unless plan[:faces].all?(&:valid?)
                    @na_state == :picking_depth ? na_jp__draw_push(view, plan) : na_jp__draw_hover(view, plan)
                    next
                end
                target = unit[:targets].first
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
            na_pps__units.flat_map do |unit|
                plan = unit[:joint]
                next(plan[:faces].all?(&:valid?) ? na_jp__preview_points(plan) : []) if plan
                target = unit[:targets].first
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
            joined = na_pps__units.map { |unit| unit[:joint] }.compact
            surfaces = ''
            unless joined.empty?
                faces = joined.sum { |plan| plan[:count] }
                surfaces = " (#{faces} joined into #{joined.length} surface#{joined.length == 1 ? '' : 's'}, every face along its own normal)"
            end
            "#{count} preselected face#{count == 1 ? '' : 's'}#{surfaces} — #{verb}#{na_pps__problem_note(joined)}#{na_revise__status_hint}"
        end

        # A surface the live drag cannot push says so before the click.
        def na_pps__problem_note(plans)
            return '' unless @na_state == :picking_depth && Na__InsertPrimatives.Na__DrawnGeom__ValidDimension?(@na_size_d)
            distance = na_drawn__world_travel_distance
            problem = plans.map { |plan| Na__InsertPrimatives.Na__JointPush__Problem(plan, distance) }.compact.first
            problem ? " — NOT PLACEABLE: #{problem}" : ''
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
            distance = na_drawn__world_travel_distance                     # <-- The driver's; every surface moves by it
            # Prepare every recipe before any push can alter a neighbouring face.
            recipes = na_pps__units.map do |unit|
                next na_pps__joint_recipe(model, unit, distance) if unit[:joint]
                target = unit[:targets].first
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
                    { :kind => :face,
                      :data => [target, snapshot, offset, na_drawn__slope_mode?, na_drawn__loop_cut_mode?, na_revise__build_ghost(target)] }
                end
            end
            model.start_operation('Deep Push Pull (Selected Faces)', true)
            opened = true
            @na_pps_transaction = true
            recipes.each do |recipe|
                if recipe[:kind] == :joint
                    records << na_jp__apply_in_batch(model, recipe, distance)
                    next
                end
                target, snapshot, offset, sloped, cutting, ghost = recipe[:data]
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
            reselect = (@na_pps_reselect || []).select(&:valid?)
            model.selection.add(reselect) unless reselect.empty?
            counts = recipes.map { |recipe| na_pps__recipe_entities(recipe) }.compact.uniq.map { |entities| [entities, na_revise__entity_count(entities)] }
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
            @na_pps_reselect = nil
        end

        # A selected surface, checked and snapshotted before anything moves.
        def na_pps__joint_recipe(model, unit, distance)
            faces = unit[:joint][:faces]
            raise 'A selected face is no longer available' unless faces.all?(&:valid?)
            raise 'A selected face is locked' if unit[:targets].any? { |target| target[:locked] }
            raise 'The editing context changed — reselect the faces' unless faces.all? { |face| Na__InsertPrimatives.Na__DeepPick__InOpenContext?(face) }
            raise 'A selected face cannot travel along the locked axis' unless na_drawn__axis_lock_usable?
            plan = Na__InsertPrimatives.Na__JointPush__Plan(faces, Geom::Transformation.new)
            problem = Na__InsertPrimatives.Na__JointPush__Problem(plan, distance)
            raise problem if problem
            snapshot = na_jp__snapshot(plan, unit[:targets].first, model)
            raise 'A selected surface could not be measured' unless snapshot
            { :kind => :joint, :unit => unit, :plan => plan, :snapshot => snapshot,
              :ghost => na_jp__ghost(plan, na_jp__cut_for?(plan, distance)) }
        end

        def na_pps__recipe_entities(recipe)
            recipe[:kind] == :joint ? recipe[:snapshot][:entities] : recipe[:data][1][:entities]
        end

        def na_revise__reacquire(record)
            return super unless record[:kind] == :face_batch
            targets = record[:members].map { |member| super(member) }
            targets.all? ? targets : nil
        end

        # A batch comes back as units again: a surface member as its plan, a
        # face member as itself, the first member driving the distance.
        def na_revise__rebuild(record, target, value, view)
            return super unless record[:kind] == :face_batch
            @na_pps_units = target.map do |member|
                member[:kind] == :joint ? { :targets => member[:targets], :joint => member[:plan] } : { :targets => [member], :joint => nil }
            end
            @na_pps_targets = @na_pps_units.flat_map { |unit| unit[:targets] }
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
