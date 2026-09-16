# =============================================================================
# NA ARRAY BUILDER TOOLS - MODEL OBSERVERS
# =============================================================================
# FILE       : Na__ArrayBuilder__ModelObservers__.rb
# AUTHOR     : Noble Architecture
# PURPOSE    : Synchronise selection, Undo/Redo and active models without writes.
# =============================================================================

require 'sketchup.rb'
require_relative 'Na__ArrayBuilder__ObjectRegistry__'

module Na__ArrayBuilderTools
    module Na__ArrayBuilder__ModelObservers

        # FUNCTION | Install Once and Detach Old Registrations During Reload
        # ------------------------------------------------------------
        def self.Na__Observers__InstallOnce
            Sketchup.remove_observer(@na_app) if @na_app
            Na__Observers__Detach()
            @na_app = Na__ArrayBuilder__AppObserver.new
            Sketchup.add_observer(@na_app)
            Na__Observers__Attach(Sketchup.active_model)
        end

        def self.Na__Observers__Attach(na_model)
            Na__Observers__Detach()
            @na_model = na_model
            return unless na_model
            @na_selection = Na__ArrayBuilder__SelectionObserver.new
            @na_transactions = Na__ArrayBuilder__TransactionObserver.new
            na_model.selection.add_observer(@na_selection)
            na_model.add_observer(@na_transactions)
            Na__Observers__Queue()
        end

        def self.Na__Observers__Detach
            UI.stop_timer(@na_timer) if @na_timer
            @na_timer = nil
            if @na_model
                @na_model.selection.remove_observer(@na_selection) if @na_selection
                @na_model.remove_observer(@na_transactions) if @na_transactions
            end
            @na_model = @na_selection = @na_transactions = nil
        rescue StandardError => na_error
            Na__ArrayBuilderTools.na_debug_log(na_error.message)
        end

        # FUNCTION | Coalesce SketchUp Callbacks Outside the Observer Stack
        # ------------------------------------------------------------
        def self.Na__Observers__Queue
            return if @na_timer
            @na_timer = UI.start_timer(0.05, false) do
                @na_timer = nil
                if defined?(Na__ArrayBuilder__DialogManager)
                    Na__ArrayBuilder__DialogManager.Na__Dialog__Synchronise
                end
            end
        end
    end

    class Na__ArrayBuilder__AppObserver < Sketchup::AppObserver
        def expectsStartupModelNotifications
            true
        end

        def onNewModel(na_model)
            Na__ArrayBuilder__ObjectRegistry.Na__Registry__Clear
            Na__ArrayBuilder__ModelObservers.Na__Observers__Attach(na_model)
        end

        def onOpenModel(na_model)
            onNewModel(na_model)
        end

        def onActivateModel(na_model)
            onNewModel(na_model)
        end
    end

    class Na__ArrayBuilder__SelectionObserver < Sketchup::SelectionObserver
        def onSelectionBulkChange(_na_selection)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onSelectionAdded(_na_selection, _na_entity)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onSelectionRemoved(_na_selection, _na_entity)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onSelectionCleared(_na_selection)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end
    end

    class Na__ArrayBuilder__TransactionObserver < Sketchup::ModelObserver
        def onTransactionCommit(_na_model)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onTransactionUndo(_na_model)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onTransactionRedo(_na_model)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onTransactionAbort(_na_model)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end

        def onActivePathChanged(_na_model)
            Na__ArrayBuilder__ModelObservers.Na__Observers__Queue()
        end
    end
end # module Na__ArrayBuilderTools
