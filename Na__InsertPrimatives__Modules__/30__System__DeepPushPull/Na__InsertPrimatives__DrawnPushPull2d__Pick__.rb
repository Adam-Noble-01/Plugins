# =============================================================================
# NA INSERT PRIMATIVES - PARALLEL CAMERA PUSH PULL PICK
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnPushPull2d__Pick__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Camera interrogation and edge-to-hidden-face resolution for 2d push/pull
# CREATED    : 2026
#
# =============================================================================

require 'sketchup.rb'
require_relative '../04__GeometryHelpers/Na__InsertPrimatives__DrawnDeepPick__'

module Na__InsertPrimatives

    # REGION | Camera Interrogation
    # -----------------------------------------------------------------------------

    # FUNCTION | Unit Direction the Camera Is Looking Along
    # ------------------------------------------------------------
    def self.Na__PushPull2d__CameraDirection(view)
        return nil unless view && view.camera

        direction = view.camera.direction
        return nil unless direction && direction.length > 0

        direction.normalize
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Is the Model Being Viewed Through a Parallel (2D) Camera?
    # ------------------------------------------------------------
    def self.Na__PushPull2d__ParallelCamera?(view)
        return false unless view && view.camera

        !view.camera.perspective?
    rescue StandardError
        false
    end
    # ---------------------------------------------------------------

    # FUNCTION | Which Push/Pull Class This Camera Wants
    # ------------------------------------------------------------
    def self.Na__PushPull2d__WantedToolClass(view)
        return Na__InsertPrimatives::DrawnPushPull2dTool if Na__InsertPrimatives.Na__PushPull2d__ParallelCamera?(view)

        Na__InsertPrimatives::DrawnPushPullTool
    end
    # ---------------------------------------------------------------

    # FUNCTION | Build the Push/Pull Tool the Current Camera Wants
    # Falls back to the 3D tool on any doubt: it is the one that has always
    # worked, and a camera that cannot be read is not a reason to hand the user
    # the specialised variant.
    # ------------------------------------------------------------
    def self.Na__PushPull2d__NewToolForCamera(model)
        return Na__InsertPrimatives::DrawnPushPullTool.new unless model

        Na__InsertPrimatives.Na__PushPull2d__WantedToolClass(model.active_view).new
    rescue StandardError
        Na__InsertPrimatives::DrawnPushPullTool.new
    end
    # ---------------------------------------------------------------

    # FUNCTION | Swap Tools When the Camera Mode No Longer Matches
    # ------------------------------------------------------------
    # Called from the idle branch of both tools' mouse move. Returns true when a
    # handover was scheduled, and the caller returns immediately — the tool it
    # belongs to is about to be replaced, so there is nothing worth drawing.
    #
    # THE STATE ARGUMENT IS PASSED IN, NOT READ:
    # - A handover mid-drag would drop a grabbed face on the floor, so it only
    #   ever runs while idle. The caller hands its own @na_state over rather
    #   than this function reaching into another object for it.
    #
    # THE SWAP IS DEFERRED BY A TIMER:
    # - select_tool inside a mouse callback tears down the very object whose
    #   callback is still on the stack. One tick later it is a plain tool
    #   change, indistinguishable from clicking the menu item.
    # ------------------------------------------------------------
    def self.Na__PushPull2d__HandoverIfCameraFlipped(tool, view, state)
        return false unless tool && view
        return false unless state == :idle
        return false if @na_pp2d_handover_pending

        wanted = Na__InsertPrimatives.Na__PushPull2d__WantedToolClass(view)
        return false if tool.instance_of?(wanted)

        @na_pp2d_handover_pending = true
        parallel = (wanted == Na__InsertPrimatives::DrawnPushPull2dTool)

        Sketchup::set_status_text(
            parallel ? 'Parallel camera — switching to the 2D edge push' :
                       'Perspective camera — switching back to the 3D face push',
            SB_PROMPT
        )
        Na__InsertPrimatives.Na__Debug__Puts "NA PUSH/PULL: camera is #{parallel ? 'parallel (2D)' : 'perspective (3D)'} — swapping tool"

        UI.start_timer(0, false) do
            begin
                model = Sketchup.active_model
                model.select_tool(wanted.new) if model
            rescue StandardError => swap_error
                Na__InsertPrimatives.Na__Debug__Puts "NA PUSH/PULL: camera handover failed — #{swap_error.message}"
            ensure
                @na_pp2d_handover_pending = false
            end
        end

        true
    rescue StandardError
        @na_pp2d_handover_pending = false
        false
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | Edge to Hidden Face Resolution
    # -----------------------------------------------------------------------------

    # FUNCTION | How Much of a Direction Lies in the Plane of the Screen
    # 1.0 is fully across the screen and fully draggable; 0.0 points straight at
    # or away from the camera and cannot be dragged at all.
    # ------------------------------------------------------------
    def self.Na__PushPull2d__ScreenFactor(direction, camera_dir)
        return 0.0 unless direction && camera_dir

        dot = direction.dot(camera_dir).to_f.abs
        dot = 1.0 if dot > 1.0
        Math.sqrt(1.0 - (dot * dot))
    rescue StandardError
        0.0
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Face an Edge Borders That Stands Perpendicular to the Screen
    # ------------------------------------------------------------
    # Returns the same target hash shape the 3D tool already consumes, wrapped
    # with the edge it came from. The path and transformation are taken straight
    # off the edge pick — an edge and the faces it bounds always live in the
    # same definition, so the same bridge to world space serves both, and no new
    # picking code is needed.
    # ------------------------------------------------------------
    def self.Na__PushPull2d__FaceBehindEdge(edge_target, camera_dir)
        return nil unless edge_target && camera_dir

        faces = edge_target[:faces]
        return nil if faces.nil? || faces.empty?

        xform     = edge_target[:transformation]
        best      = nil
        best_face = 0.0
        best_area = 0.0

        faces.each do |face|
            next unless face && face.valid?

            candidate = Na__InsertPrimatives.Na__DeepPick__BuildTarget(face, edge_target[:path], xform)
            factor    = Na__InsertPrimatives.Na__PushPull2d__ScreenFactor(candidate[:world_normal], camera_dir)
            next if factor < NA_PP2D_MIN_SCREEN_FACTOR

            area = face.area.to_f

            better =
                if best.nil?
                    true
                elsif factor > best_face + NA_PP2D_TIE_BAND
                    true
                elsif factor < best_face - NA_PP2D_TIE_BAND
                    false
                else
                    area > best_area                                          # <-- A genuine tie: the bigger wall wins
                end

            next unless better

            best      = candidate
            best_face = factor
            best_area = area
        end

        return nil unless best

        edge = edge_target[:edge]
        return nil unless edge && edge.valid?

        {
            :reason        => :edge,
            :face_target   => best,
            :edge_target   => edge_target,
            :edge_world    => [
                edge.start.position.transform(xform),
                edge.end.position.transform(xform)
            ],
            :screen_factor => best_face
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Decide What the Cursor Is Actually Offering to Push
    # Returns a resolution hash, or one carrying :refusal with the reason the
    # cursor cannot be used — so the tool can say something specific rather than
    # beeping at the user and leaving them to guess.
    # ------------------------------------------------------------
    def self.Na__PushPull2d__ResolveTargetAt(view, x, y)
        camera_dir = Na__InsertPrimatives.Na__PushPull2d__CameraDirection(view)
        return { :reason => :none, :refusal => 'The camera could not be read' } unless camera_dir

        edge_target = Na__InsertPrimatives.Na__DeepPick__EdgeAt(view, x, y)

        if edge_target
            resolved = Na__InsertPrimatives.Na__PushPull2d__FaceBehindEdge(edge_target, camera_dir)
            return resolved if resolved

            return {
                :reason      => :none,
                :edge_target => edge_target,
                :refusal     => 'Nothing this edge borders can be dragged from this camera angle'
            }
        end

        face_target = Na__InsertPrimatives.Na__DeepPick__FaceAt(view, x, y)

        unless face_target
            return {
                :reason  => :none,
                :refusal => 'Nothing under the cursor — hover the edge of the wall you want to pull'
            }
        end

        factor = Na__InsertPrimatives.Na__PushPull2d__ScreenFactor(face_target[:world_normal], camera_dir)

        if factor < NA_PP2D_FACE_MIN_SCREEN
            return {
                :reason      => :none,
                :face_target => face_target,
                :refusal     => 'That face points at the camera — hover the EDGE of the wall you want to pull'
            }
        end

        {
            :reason        => :face,
            :face_target   => face_target,
            :edge_target   => nil,
            :edge_world    => nil,
            :screen_factor => factor
        }
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF PARALLEL CAMERA PUSH PULL PICK
# =============================================================================
