# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmNotes; end

# Provider for global PDM notes.
class Puppet::Provider::PdmNotes::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    { 'notes' => :notes }
  end

  def get(context)
    notes = transport_get(context, '/config/notes')
    return [] if missing_transport_result?(notes)

    [{ name: 'global', notes: notes || '', ensure: 'present' }]
  end

  def create(context, name, should)
    update(context, name, should)
  end

  def update(context, name, should)
    context.notice("Updating PDM global notes '#{name}'")
    pdm_transport(context).put(context, '/config/notes', update_request_body(context, should))
  end

  def delete(context, name)
    context.notice("pdm_notes '#{name}': ensure => absent is a no-op")
  end
end
