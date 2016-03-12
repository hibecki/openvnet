# -*- coding: utf-8 -*-

module Vnet::NodeApi
  class IpLease < EventBase

    valid_update_fields ['enable_routing']

    class << self
      include Vnet::Helpers::Event

      def update(uuid, options)
        update_uuid(uuid, options)
      end

      def attach_uuid(uuid, options)
        model = model_class[uuid]
        release_model(model, options)
      end

      def release_uuid(uuid)
        release(uuid)
      end

      def release(uuid)
        model = model_class[uuid]
        release_model(model)
      end

      #
      # Internal methods:
      #

      private

      def dispatch_created_item_events(model)
        if model.interface_id
          dispatch_event(INTERFACE_LEASED_IPV4_ADDRESS, prepare_event_hash(model))
        end

        dispatch_security_group_item_events(model)
      end

      def dispatch_deleted_item_events(model)
        if model.interface_id
          dispatch_event(INTERFACE_RELEASED_IPV4_ADDRESS, id: model.interface_id, ip_lease_id: model.id)
        end

        filter = { ip_lease_id: model.id }

        # 0001_origin
        # datapath_networks: :destroy,
        # datapath_route_links: :destroy,
        # ip_address: :destroy,
        # ip_lease_container_ip_leases: :destroy,

        dispatch_security_group_item_events(model)

        # 0002_services
        IpRetention.dispatch_deleted_where(filter, model.deleted_at)
      end

      def dispatch_security_group_item_events(model)
        model.interface.tap { |interface|
          next if interface.nil?

          interface.security_groups.each { |group|
            dispatch_update_sg_ip_addresses(group)
          }
        }
      end

      def prepare_event_hash(model)
        model.to_hash.tap { |event_hash|
          event_hash[:ip_lease_id] = event_hash[:id]
          event_hash[:id] = event_hash[:interface_id]
        }
      end

      #
      # Attach / Detach:
      #

      # Use filter instead of 'model'?
      def attach_model(model, options)
        # Verify model is not nil.

        interface_id = options[:interface_id]
        mac_lease_id = options[:mac_lease_id]

        if interface_id.nil? && mac_lease_id.nil?
          return # raise error
        end

        if !model.interface_id.nil? || !model.mac_lease_id.nil?
          return # raise error or release
        end

        transaction do
          interface = interface_id && model_class(:interface)[id: interface_id]
          mac_lease = mac_lease_id && model_class(:mac_lease)[id: mac_lease_id]
          
          if interface && mac_lease.nil? && mac_lease_id.nil?
            # Error if the interface has more than one mac_lease?
            mac_lease = interface.mac_leases.first
          end

          if mac_lease && interface.nil? && interface_id.nil?
            interface = mac_lease.interface
          end

          if interface.nil? || mac_lease.nil?
            return # raise error
          end

          model.interface_id = interface.id
          model.mac_lease_id = mac_lease.id

          model.save_changes
          current_time = Time.now # Use updated_at instead?

          model.ip_retentions.each do |ip_retention|
            ip_retention.released_at = nil
            ip_retention.save_changes
          end
        end
        
        interface.security_groups.each do |group|
          dispatch_update_sg_ip_addresses(group)
        end

        dispatch_event(INTERFACE_LEASED_IPV4_ADDRESS, prepare_event_hash(model))
        model
      end

      def release_model(model)
        # Verify model is not nil.

        interface = model.interface

        # Check that interface_id and mac_lease_id are valid.

        transaction do
          # Refresh?

          if model.interface_id.nil? && model.mac_lease_id.nil?
            return # raise error or release
          end

          model.interface_id = nil
          model.mac_lease_id = nil

          model.save_changes
          current_time = Time.now # Use updated_at instead?

          model.ip_retentions.each do |ip_retention|
            ip_retention.released_at = current_time
            ip_retention.save_changes
          end
        end

        if interface
          interface.security_groups.each do |group|
            dispatch_update_sg_ip_addresses(group)
          end
        end

        dispatch_event(INTERFACE_RELEASED_IPV4_ADDRESS, id: interface.id, ip_lease_id: model.id)

        # re-add released ip_retentions
        model.ip_retentions.each do |ip_retention|
          dispatch_event(
            IP_RETENTION_CONTAINER_ADDED_IP_RETENTION,
            id: ip_retention.ip_retention_container_id,
            ip_retention_id: ip_retention.id,
            ip_lease_id: ip_retention.ip_lease_id,
            leased_at: ip_retention.leased_at,
            released_at: ip_retention.released_at
          )
        end

        model
      end

    end
  end
end
