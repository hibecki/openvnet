# -*- coding: utf-8 -*-

module Vnet::Openflow

  class RouteManager
    include Celluloid
    include Celluloid::Logger
    include FlowHelpers

    ROUTE_COMMIT = {:fill => [:route_link]}

    def initialize(dp)
      @datapath = dp

      @dpid = @datapath.dpid
      @dpid_s = "0x%016x" % @datapath.dpid

      @route_links = {}
      @vifs = {}
    end

    def insert(route_map)
      route_link = prepare_link(route_map.route_link)

      return if route_link.nil?
      return if route_link[:routes].has_key? route_map.id

      info log_format("insert #{route_map.uuid}/#{route_map.id}", "vif_id:#{route_map.interface_id}")
      # info log_format('insert', "route.route_type:#{route_map.route_type}")
      # info log_format('insert', "route.route_link: id:#{route_map.route_link.id} uuid:#{route_map.route_link.uuid}")

      route = {
        :id => route_map.id,
        :uuid => route_map.uuid,
        :vif => nil,
        :ipv4_address => IPAddr.new(route_map.ipv4_address, Socket::AF_INET),
        :ipv4_prefix => route_map.ipv4_prefix,
        :ingress => route_map.ingress,
        :egress => route_map.egress,
      }

      route_link[:routes][route[:id]] = route

      route[:vif] = prepare_interface(route_map.interface_id)

      if route[:vif].nil?
        warn log_format('couldn\'t prepare router vif', "#{route_map.uuid}")
        return
      end

      create_route_flows(route_link, route)
    end

    def prepare_network(network_map, dp_map)
      network_map.batch.routes.commit(ROUTE_COMMIT).each { |route_map|
        if !@route_links.has_key?(route_map.route_link.id)
          route_map.batch.on_other_networks.commit(ROUTE_COMMIT).each { |other_route_map|
            # Replace with a lightweight methods.
            self.insert(other_route_map)
          }
        end

        self.insert(route_map)
      }
    end

    #
    # Internal methods:
    #

    private

    def log_format(message, values = nil)
      "#{@dpid_s} route_manager: #{message}" + (values ? " (#{values})" : '')
    end

    def datapath_route_link(rl_map)
      @datapath.datapath_batch.datapath_route_links_dataset.where(:route_link_id => rl_map.id).all.commit
    end

    def dp_rl_on_segment(rl_map)
      rl_map.batch.datapath_route_links_dataset.on_segment(@datapath.datapath_map).all.commit
    end

    def prepare_link(rl_map)
      link = @route_links[rl_map.id]
      return link if link

      mac_address = Trema::Mac.new(rl_map.mac_address)
      packet_handler = Routers::RouteLink.new(datapath: @datapath,
                                              route_link_id: rl_map.id,
                                              route_link_uuid: rl_map.uuid,
                                              mac_address: mac_address)

      link = {
        :id => rl_map.id,
        :uuid => rl_map.uuid,
        :mac_address => mac_address,
        :routes => {},
        :packet_handler => packet_handler
      }

      cookie = link[:id] | (COOKIE_PREFIX_ROUTE_LINK << COOKIE_PREFIX_SHIFT)

      @route_links[rl_map.id] = link
      @datapath.packet_manager.insert(packet_handler, nil, cookie)

      tunnel_md = md_create(:tunnel => nil)
      route_link_md = md_create(:route_link => link[:id])

      # TODO: Move flow creation to Routers::RouteLink...

      flows = []
      flows << Flow.create(TABLE_TUNNEL_NETWORK_IDS, 30, {
                             :tunnel_id => TUNNEL_ROUTE_LINK,
                             :eth_dst => link[:mac_address]
                           }, nil,
                           route_link_md.merge({ :cookie => cookie,
                                                 :goto_table => TABLE_ROUTER_EGRESS
                                               }))
      flows << Flow.create(TABLE_NETWORK_SRC_CLASSIFIER, 90, {
                             :eth_dst => link[:mac_address]
                           }, nil, {
                             :cookie => cookie
                           })
      flows << Flow.create(TABLE_NETWORK_SRC_CLASSIFIER, 90, {
                             :eth_src => link[:mac_address]
                           }, nil, {
                             :cookie => cookie
                           })
      flows << Flow.create(TABLE_NETWORK_DST_CLASSIFIER, 90, {
                             :eth_dst => link[:mac_address]
                           }, nil, {
                             :cookie => cookie
                           })
      flows << Flow.create(TABLE_NETWORK_DST_CLASSIFIER, 90, {
                             :eth_src => link[:mac_address]
                           }, nil, {
                             :cookie => cookie
                           })
      flows << Flow.create(TABLE_OUTPUT_DP_ROUTE_LINK, 4, {
                             :eth_dst => mac_address
                           }, {
                             :tunnel_id => TUNNEL_ROUTE_LINK
                           }, tunnel_md.merge({ :goto_table => TABLE_OUTPUT_DATAPATH,
                                                :cookie => cookie
                                              }))

      # Handle MAC2MAC packets for this route link using a unique MAC
      # address for this datapath, route link pair.
      datapath_route_link(rl_map).each { |dp_rl_map|
        flows << Flow.create(TABLE_HOST_PORTS, 30, {
                               :eth_dst => Trema::Mac.new(dp_rl_map.mac_address)
                             }, nil,
                             route_link_md.merge({ :cookie => cookie,
                                                   :goto_table => TABLE_ROUTER_EGRESS
                                                 }))
        flows << Flow.create(TABLE_NETWORK_SRC_CLASSIFIER, 90, {
                               :eth_dst => Trema::Mac.new(dp_rl_map.mac_address)
                             }, nil, {
                               :cookie => cookie
                             })
        flows << Flow.create(TABLE_NETWORK_DST_CLASSIFIER, 90, {
                               :eth_dst => Trema::Mac.new(dp_rl_map.mac_address)
                             }, nil, {
                               :cookie => cookie
                             })
      }

      # Use the datapath id in the metadata field and the route link
      # MAC address in the destination field to figure out the MAC2MAC
      # datapath, route link pair MAC address to use.
      #
      # If not found it is assumed to be using a tunnel where the
      # route link MAC address is to be used.
      dp_rl_on_segment(rl_map).each { |dp_rl_map|
        datapath_md = md_create(:datapath => dp_rl_map.datapath_id)
        mac2mac_md = md_create(:mac2mac => nil)

        flows << Flow.create(TABLE_OUTPUT_DP_ROUTE_LINK, 5,
                             datapath_md.merge(:eth_dst => mac_address), {
                               :eth_dst => Trema::Mac.new(dp_rl_map.mac_address)
                             }, mac2mac_md.merge({ :goto_table => TABLE_OUTPUT_DATAPATH,
                                                   :cookie => cookie
                                                 }))
      }

      # ROUTER_DST catch unknown subnets. ??? (or load all subnets)

      @datapath.add_flows(flows)
      link
    end

    def prepare_interface(interface_id)
      interface = @datapath.interface_manager.item(id: interface_id)
      return nil if interface.nil?

      info log_format('from interface_manager' , "#{interface.uuid}/#{interface_id}")

      vif = interface && @vifs[interface.id]
      return vif if vif

      if interface.mode != :simulated && interface.mode != :remote
        info log_format('only vifs with mode \'simulated\' are supported', "uuid:#{interface.uuid} mode:#{interface.mode}")
        return
      end

      mac_info = interface.mac_addresses.first

      if mac_info.nil? ||
          mac_info[1][:ipv4_addresses].first.nil?
        warn log_format('could not find ipv4 address')
        return nil
      end

      ipv4_info = mac_info[1][:ipv4_addresses].first

      vif = {
        :id => interface.id,
        :use_datapath_id => nil,

        :mac_address => mac_info[0],
        :mode => interface.mode,

        :network_id => ipv4_info[:network_id],
        :ipv4_address => ipv4_info[:ipv4_address],
      }

      case ipv4_info[:network_type]
      when :physical
        vif[:require_vif] = false
        vif[:network_type] = :physical_network
      when :virtual
        vif[:require_vif] = true
        vif[:network_type] = :virtual_network
      else
        warn log_format('vif does not have a known network type', "#{interface.uuid}")
        return nil
      end

      @vifs[interface.id] = vif

      if interface.mode == :remote
        vif[:use_datapath_id] = interface.owner_datapath_ids && interface.owner_datapath_ids.first

        return vif
      end

      datapath_id = @datapath.datapath_map.id

      # Fix this...
      if interface.owner_datapath_ids
        if interface.owner_datapath_ids.include? datapath_id
          @datapath.interface_manager.update_active_datapaths(id: interface.id,
                                                              datapath_id: datapath_id)
        else
          vif[:use_datapath_id] = interface.owner_datapath_ids.first
        end
      end

      create_vif_flows(vif) if vif[:use_datapath_id].nil?

      vif
    end

    def create_route_flows(route_link, route)
      cookie = route[:id] | (COOKIE_PREFIX_ROUTE << COOKIE_PREFIX_SHIFT)

      flows = []
      route_link_md = md_create(:route_link => route_link[:id])

      if is_ipv4_broadcast(route[:ipv4_address], route[:ipv4_prefix])
        priority = 30
      else
        priority = 31
      end

      subnet_dst = match_ipv4_subnet_dst(route[:ipv4_address], route[:ipv4_prefix])
      subnet_src = match_ipv4_subnet_src(route[:ipv4_address], route[:ipv4_prefix])

      if route[:vif][:use_datapath_id].nil?
        network_md = md_create(network: route[:vif][:network_id])

        rl_reflection_md = md_create({ :route_link => route_link[:id],
                                       :reflection => nil
                                     })

        flows << Flow.create(TABLE_CONTROLLER_PORT, priority,
                             subnet_dst.merge(:eth_src => route[:vif][:mac_address]),
                             nil,
                             network_md.merge(cookie: cookie,
                                              goto_table: TABLE_ROUTER_DST))

        if route[:ingress] == true
          flows << Flow.create(TABLE_ROUTER_INGRESS, priority,
                               network_md.merge(subnet_src).merge(:eth_dst => route[:vif][:mac_address]),
                               nil,
                               rl_reflection_md.merge({ :cookie => cookie,
                                                        :goto_table => TABLE_ROUTER_EGRESS
                                                      }))
        end

        if route[:egress] == true
          flows << Flow.create(TABLE_ROUTER_EGRESS, priority,
                               route_link_md.merge(subnet_dst), {
                                 :eth_src => route[:vif][:mac_address]
                               },
                               network_md.merge({ :cookie => cookie,
                                                  :goto_table => TABLE_ROUTER_DST
                                                }))

          install_route_handler(route_link, route)
        end

        @datapath.add_flows(flows)

      else
        datapath_md = md_create(:datapath => route[:vif][:use_datapath_id])

        if route[:egress] == true
          flows << Flow.create(TABLE_ROUTER_EGRESS, priority,
                               route_link_md.merge(subnet_dst), {
                                 :eth_dst => route_link[:mac_address]
                               },
                               datapath_md.merge({ :cookie => cookie,
                                                   :goto_table => TABLE_OUTPUT_DP_ROUTE_LINK
                                                 }))
        end

        @datapath.add_flows(flows)
      end
    end

    def create_vif_flows(vif)
      cookie = vif[:id] | (COOKIE_PREFIX_VIF << COOKIE_PREFIX_SHIFT)
      network_md = md_create(:network => vif[:network_id])

      goto_table = TABLE_NETWORK_DST_CLASSIFIER
      controller_md = md_create({ :network => vif[:network_id],
                                  :no_controller => nil
                                })

      flows = []
      flows << Flow.create(TABLE_ROUTER_CLASSIFIER, 40,
                           network_md.merge({ :eth_dst => vif[:mac_address],
                                              :eth_type => 0x0800,
                                              :ipv4_dst => vif[:ipv4_address]
                                            }),
                           nil, {
                             :cookie => cookie,
                             :goto_table => goto_table
                           })
      flows << Flow.create(TABLE_CONTROLLER_PORT, 40, {
                             :eth_dst => vif[:mac_address],
                             :eth_type => 0x0800,
                             :ipv4_dst => vif[:ipv4_address]
                           },
                           nil,
                           network_md.merge(cookie: cookie,
                                            goto_table: TABLE_ROUTER_CLASSIFIER))
      flows << Flow.create(TABLE_CONTROLLER_PORT, 40, {
                             :eth_dst => vif[:mac_address],
                             :eth_type => 0x0806
                           },
                           nil,
                           network_md.merge(cookie: cookie,
                                            goto_table: TABLE_ROUTER_CLASSIFIER))
      flows << Flow.create(TABLE_ROUTER_CLASSIFIER, 30,
                           network_md.merge({ :eth_dst => vif[:mac_address],
                                              :eth_type => 0x0800
                                            }),
                           nil, {
                             :cookie => cookie,
                             :goto_table => TABLE_ROUTER_INGRESS
                           })

      @datapath.add_flows(flows)
    end

    def install_route_handler(route_link, route)
      link_cookie = route_link[:id] | (COOKIE_PREFIX_ROUTE_LINK << COOKIE_PREFIX_SHIFT)

      pm = @datapath.packet_manager
      pm.dispatch(link_cookie) { |key, handler|
        route_cookie = handler.insert_route(route)
        pm.link_cookies(key, route_cookie) if route_cookie
      }
    end

  end

end