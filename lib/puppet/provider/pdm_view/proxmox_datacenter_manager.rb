# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmView; end

# Provider for PDM resource views.
class Puppet::Provider::PdmView::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    {
      'id' => :id,
      'include' => :include,
      'exclude' => :exclude,
      'include-all' => :include_all,
      'layout' => :layout,
      'delete' => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:include_all]
  end

  def get(context)
    (transport_get(context, '/config/views') || []).map do |view|
      pdm_to_puppet(view).merge(ensure: 'present')
    end
  end

  def create(context, name, should)
    context.notice("Creating PDM view '#{name}'")
    pdm_transport(context).post(context, '/config/views', create_request_body(should))
  end

  def update(context, name, should)
    context.notice("Updating PDM view '#{name}'")
    pdm_transport(context).put(context, view_path(name), update_request_body(context, should))
  end

  def delete(context, name)
    context.notice("Deleting PDM view '#{name}'")
    pdm_transport(context).delete(context, view_path(name))
  end

  private

  def view_path(name)
    pdm_path('/config/views/{id}', id: name)
  end
end
