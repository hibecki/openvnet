# -*- coding: utf-8 -*-

module Vnet::Openflow::Routes

  class Base < Vnet::Openflow::ItemBase
    include Celluloid::Logger
    include Vnet::Openflow::FlowHelpers

    attr_reader :uuid

    attr_reader :interface_id
    attr_reader :route_link_id

    attr_reader :network_id
    attr_reader :ipv4_address
    attr_reader :ipv4_prefix

    attr_reader :ingress
    attr_reader :egress

    def initialize(params)
      super

      map = params[:map]

      @id = map.id
      @uuid = map.uuid

      @interface_id = map.interface_id
      @route_link_id = map.route_link_id

      @network_id = map.network_id
      @ipv4_address = IPAddr.new(map.ipv4_network, Socket::AF_INET)
      @ipv4_prefix = map.ipv4_prefix

      @ingress = map.ingress
      @egress = map.egress
    end    
    
    def cookie
      @id | COOKIE_TYPE_ROUTE
    end

    def is_default_route
      is_ipv4_broadcast(@ipv4_address, @ipv4_prefix)
    end

    # Update variables by first duplicating to avoid memory
    # consistency issues with values passed to other actors.
    def to_hash
      Vnet::Openflow::Route.new(id: @id,
                                uuid: @uuid,

                                interface_id: @interface_id,
                                route_link_id: @route_link_id,
                                
                                network_id: @network_id,
                                ipv4_address: @ipv4_address,
                                ipv4_prefix: @ipv4_prefix,

                                ingress: @ingress,
                                egress: @egress)
    end

    #
    # Events:
    #

    def install
      return if
        @interface_id.nil? ||
        @network_id.nil? ||
        @route_link_id.nil?

      flows = []

      subnet_dst = match_ipv4_subnet_dst(@ipv4_address, @ipv4_prefix)
      subnet_src = match_ipv4_subnet_src(@ipv4_address, @ipv4_prefix)

      # Currently create these two flows even if the interface isn't
      # on this datapath. Should not cause any issues as the interface
      # id will never be matched.
      flows << flow_create(:default,
                           table: TABLE_INTERFACE_EGRESS_ROUTES,
                           goto_table: TABLE_INTERFACE_EGRESS_MAC,
                           priority: self.is_default_route ? 20 : 30,

                           match: subnet_dst,
                           match_interface: @interface_id,
                           write_network: @network_id)

      if @ingress == true
        flows << flow_create(:default,
                             table: TABLE_ROUTER_INGRESS,
                             goto_table: TABLE_ROUTER_CLASSIFIER,
                             priority: self.is_default_route ? 20 : 30,

                             match: subnet_src,
                             match_interface: @interface_id,
                             write_route_link: @route_link_id,
                             write_reflection: true)
      end

      # In order to know what interface to egress from this flow needs
      # to be created even on datapaths where the interface is remote.
      [true, false].each { |reflection|
        if @egress == true
          flows << flow_create(:default,
                               table: TABLE_ROUTER_EGRESS,
                               goto_table: TABLE_ROUTE_EGRESS_LOOKUP,
                               priority: self.is_default_route ? 20 : 30,

                               match: subnet_dst,
                               match_route_link: @route_link_id,

                               write_value_pair_flag: reflection,
                               write_value_pair_first: @interface_id,
                               write_value_pair_second: @route_link_id)
        end
      }

      @dp_info.add_flows(flows)
    end

    def uninstall
    end

    #
    # Internal methods:
    #

    private

    def log_format(message, values = nil)
      "#{@dp_info.dpid_s} routes/base: #{message}" + (values ? " (#{values})" : '')
    end

  end

end
