# frozen_string_literal: true

module Na__Noble3dModellingTools
  module Na__VegetationSketcher
    # Observers only schedule a refresh. The controller reads selection and
    # dictionaries on the next UI loop, outside SketchUp's transaction callbacks.
    class SelectionObserver < Sketchup::SelectionObserver
      def initialize(owner); @owner = owner; end
      def onSelectionBulkChange(_selection); @owner.queue_sync; end
      def onSelectionAdded(_selection, _entity); @owner.queue_sync; end
      def onSelectionRemoved(_selection, _entity); @owner.queue_sync; end
      def onSelectionCleared(_selection); @owner.queue_sync; end
    end

    class ModelObserver < Sketchup::ModelObserver
      def initialize(owner); @owner = owner; end
      def onTransactionCommit(_model); @owner.queue_sync; end
      def onTransactionUndo(_model); @owner.queue_sync; end
      def onTransactionRedo(_model); @owner.queue_sync; end
      def onTransactionAbort(_model); @owner.queue_sync; end
      def onActivePathChanged(_model); @owner.queue_sync; end
      def onDeleteModel(_model); @owner.queue_sync; end
    end

    class EntityObserver < Sketchup::EntityObserver
      def initialize(owner); @owner = owner; end
      def onChangeEntity(_entity); @owner.queue_sync; end
      def onEraseEntity(_entity); @owner.queue_sync; end
    end

    class AppObserver < Sketchup::AppObserver
      def initialize(owner); @owner = owner; end
      def onNewModel(_model); @owner.queue_sync; end
      def onOpenModel(_model); @owner.queue_sync; end
      def onActivateModel(_model); @owner.queue_sync; end
    end
  end
end
