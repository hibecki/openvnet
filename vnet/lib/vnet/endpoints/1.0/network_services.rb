# -*- coding: utf-8 -*-

Vnet::Endpoints::V10::VnetAPI.namespace '/network_services' do
  def self.put_post_shared_params
    param_uuid M::Interface, :interface_uuid
    param :incoming_port, :Integer
    param :outgoing_port, :Integer
    param :display_name, :String
  end

  fill_options = [ :interface ]

  put_post_shared_params
  param_uuid M::NetworkService
  param :mode, :String, required: false, in: C::NetworkService::MODES
  param :type, :String, required: false, in: C::NetworkService::MODES
  param :replace_uuid, ::Boolean
  post do
    uuid_to_id(M::Interface, "interface_uuid", "interface_id") if params["interface_uuid"]

    # The 'type' field is deprecated.
    if params.include? :type
      params[:mode] = params.delete(:type)
    end

    post_new(:NetworkService, fill_options)
  end

  get do
    get_all(:NetworkService, fill_options)
  end

  get '/:uuid' do
    get_by_uuid(:NetworkService, fill_options)
  end

  delete '/:uuid' do
    delete_by_uuid(:NetworkService)
  end

  put_post_shared_params
  put '/:uuid' do
    uuid_to_id(M::Interface, "interface_uuid", "interface_id") if params["interface_uuid"]

    update_by_uuid(:NetworkService, fill_options)
  end
end
