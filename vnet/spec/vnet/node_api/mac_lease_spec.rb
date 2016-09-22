# -*- coding: utf-8 -*-

require 'spec_helper'

Dir["#{File.dirname(__FILE__)}/shared_examples/*.rb"].map {|f| require f }

describe Vnet::NodeApi::MacLease do
  before(:each) { use_mock_event_handler }

  let(:events) { MockEventHandler.handled_events }

  let(:interface) { Fabricate(:interface) }
  let(:segment) { Fabricate(:segment) }

  let(:random_mac_address) { random_mac_i }

  describe 'create' do
    let(:create_filter) {
      { interface_id: interface.id,
        segment_id: mac_segment_id,
        mac_address: random_mac_address
      }
    }
    let(:create_events) {
      [ [ Vnet::Event::INTERFACE_LEASED_MAC_ADDRESS, {
            id: create_filter[:interface_id],
            segment_id: mac_segment_id,
            mac_lease_id: :model__id,
            mac_address: random_mac_address
          }]]
    }
    let(:create_result) { create_filter }
    let(:query_result) { create_result }

    context 'without segment' do
      let(:mac_segment_id) { nil }
      include_examples 'create item on node_api', :mac_lease, [:mac_address]
    end

    context 'with segment' do
      let(:mac_segment_id) { segment.id }
      include_examples 'create item on node_api', :mac_lease, [:mac_address]
    end
  end

  describe 'destroy' do
    let(:delete_item) { Fabricate(:mac_lease) }
    let(:delete_filter) { delete_item.canonical_uuid }
    let(:delete_events) {
      [ [ Vnet::Event::INTERFACE_RELEASED_MAC_ADDRESS, {
            id: delete_item.interface_id,
            mac_lease_id: delete_item.id
          }]]
    }

    context 'without segment' do
      let(:mac_segment_id) { nil }
      include_examples 'delete item on node_api', :mac_lease, [:mac_address]
    end

    context 'with segment' do
      let(:mac_segment_id) { segment.id }
      include_examples 'delete item on node_api', :mac_lease, [:mac_address]
    end
  end
end
