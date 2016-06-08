# -*- coding: utf-8 -*-

module Vnet::NodeApi
  class Segment < EventBase
    valid_update_fields []

    class << self
      private

      def dispatch_created_item_events(model)
      end

      def dispatch_deleted_item_events(model)
        dispatch_event(SEGMENT_DELETED_ITEM, id: model.id)

        filter = { segment_id: model.id }

        # XXXX_segment
        # Foo.dispatch_deleted_where(filter, model.deleted_at)
      end

    end
  end
end
