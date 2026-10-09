# =============================================================================
# NA INSERT PRIMATIVES - LARGE SELECTION GUARD
# =============================================================================
#
# FILE       : Na__InsertPrimatives__DrawnLargeSelection__.rb
# NAMESPACE  : Na__InsertPrimatives
# AUTHOR     : Noble Architecture
# PURPOSE    : Ask before a modifier tool takes on a very large preselection
# CREATED    : 2026
#
# DESCRIPTION:
# - Deep Push/Pull pushes every face selected before it starts, and Deep
#   Chamfer, Fillet, Ogee and Ovolo cut every selected loose edge. That is the
#   point of preselecting — and it is one CTRL+A and a shortcut away from
#   pushing every face of a model at once. Each selected face or edge is also
#   previewed on every mouse move, so a big enough selection stops SketchUp
#   responding before the user has done anything at all.
# - So above a threshold the tool asks, in plain words, before it takes the
#   selection on:
#     Yes     use the whole selection
#     No      leave the selection alone and pick one at a time, as usual
#     Cancel  leave the tool
#   Asked when the tool starts, before anything is solved or previewed, and
#   asked again before a commit if a batch that size somehow arrives there
#   unconfirmed.
#
# NOT ASKED TWICE:
# - A Yes is remembered for that many faces (or edges) in that model for ten
#   minutes, so swapping profiles from the menu, the 2D/3D hand-over on a
#   camera change, a retype and a fresh start of the same tool on the same
#   selection all go through without the question again.
# - A No is remembered for half a minute, long enough that the 2D/3D
#   hand-over (a new tool, started by orbiting) does not ask again straight
#   away, short enough that starting the tool again later asks afresh.
#
# =============================================================================

require 'sketchup.rb'

module Na__InsertPrimatives

    # -----------------------------------------------------------------------------
    # REGION | Constants
    # -----------------------------------------------------------------------------

    NA_LARGE_SELECTION_FACES = 10                                             # <-- More selected faces than this and Deep Push/Pull asks
    NA_LARGE_SELECTION_EDGES = 48                                             # <-- More selected edges than this and the edge tools ask
    NA_LARGE_SELECTION_MEMO_S = 600                                           # <-- A Yes holds for the same count in the same model this long
    NA_LARGE_SELECTION_NO_S   = 30                                            # <-- A No holds this long: just the 2D/3D hand-over

    # endregion -------------------------------------------------------------------


    # -----------------------------------------------------------------------------
    # REGION | The Question
    # -----------------------------------------------------------------------------

    # FUNCTION | 1234 as "1,234"
    # ------------------------------------------------------------
    def self.Na__LargeSelection__Count(count)
        count.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    end
    # ---------------------------------------------------------------

    # FUNCTION | The Answer Last Given for This Many in This Model, While It Holds
    # :yes, :no or nil.
    # ------------------------------------------------------------
    def self.Na__LargeSelection__Recalled(kind, count)
        memo  = @na_large_selection_memo
        model = Sketchup.active_model
        return nil unless memo && model
        return nil unless memo[:model] == model.object_id && memo[:kind] == kind && memo[:count] == count.to_i

        hold = memo[:answer] == :yes ? NA_LARGE_SELECTION_MEMO_S : NA_LARGE_SELECTION_NO_S
        (Time.now - memo[:at]).to_f < hold ? memo[:answer] : nil
    rescue StandardError
        nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Has This Many Been Confirmed in This Model Lately?
    # ------------------------------------------------------------
    def self.Na__LargeSelection__Confirmed?(kind, count)
        Na__InsertPrimatives.Na__LargeSelection__Recalled(kind, count) == :yes
    end
    # ---------------------------------------------------------------

    # FUNCTION | Remember an Answer (a Yes Unless Told Otherwise)
    # ------------------------------------------------------------
    def self.Na__LargeSelection__Remember(kind, count, answer = :yes)
        model = Sketchup.active_model
        @na_large_selection_memo =
            model ? { :model => model.object_id, :kind => kind, :count => count.to_i, :answer => answer, :at => Time.now } : nil
    end
    # ---------------------------------------------------------------

    # FUNCTION | Ask Whether to Take On a Large Selection
    # ------------------------------------------------------------
    # kind   :faces or :edges (the memo key and the threshold)
    # count  how many are selected
    # tool   the tool's title, e.g. "Deep Push/Pull"
    # verb   what happens to them, e.g. "pushed" or "chamfered"
    # ask    the question's own verb, e.g. "Push" or "Chamfer"
    # Returns :yes, :no or :cancel. At or under the threshold, or already
    # confirmed, it is :yes without asking.
    # ------------------------------------------------------------
    def self.Na__LargeSelection__Ask(kind, count, tool, verb, ask)
        limit = kind == :faces ? NA_LARGE_SELECTION_FACES : NA_LARGE_SELECTION_EDGES
        return :yes if count.to_i <= limit

        recalled = Na__InsertPrimatives.Na__LargeSelection__Recalled(kind, count)
        return recalled if recalled

        noun   = kind == :faces ? 'faces' : 'edges'
        single = kind == :faces ? 'face' : 'edge'
        number = Na__InsertPrimatives.Na__LargeSelection__Count(count)

        message =
            "#{tool}\n\n" \
            "#{number} #{noun} are selected.\n\n" \
            "Every one of them would be #{verb} together, in one operation, and each is " \
            "previewed while you drag. With this many #{noun} SketchUp can stop responding " \
            "for a long time, and a single drag changes the whole selection.\n\n" \
            "#{ask} all #{number} selected #{noun}?\n\n" \
            "Yes  —  use the whole selection\n" \
            "No  —  leave the selection, and pick one #{single} at a time\n" \
            "Cancel  —  leave #{tool}"

        answer = UI.messagebox(message, MB_YESNOCANCEL)

        case answer
        when IDYES
            Na__InsertPrimatives.Na__LargeSelection__Remember(kind, count)
            :yes
        when IDNO
            Na__InsertPrimatives.Na__LargeSelection__Remember(kind, count, :no)
            :no
        else
            :cancel
        end
    rescue StandardError => error
        Na__InsertPrimatives.Na__Debug__Puts "NA LARGE SELECTION: could not ask (#{error.message}) — the selection is left alone"
        :no
    end
    # ---------------------------------------------------------------

    # endregion -------------------------------------------------------------------

end # End Na__InsertPrimatives module

# =============================================================================
# END OF LARGE SELECTION GUARD
# =============================================================================
