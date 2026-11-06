# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmNodeConfig; end

# Provider for PDM node configuration.
class Puppet::Provider::PdmNodeConfig::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    {
      'email-from' => :email_from,
      'http-proxy' => :http_proxy,
      'default-lang' => :default_lang,
      'ciphers-tls-1.2' => :ciphers_tls_1_2,
      'ciphers-tls-1.3' => :ciphers_tls_1_3,
      'delete' => :delete_properties,
    }
  end

  def get(context)
    config = transport_get(context, '/nodes/localhost/config')
    return [] if missing_transport_result?(config)

    config ||= {}
    [pdm_to_puppet(config).merge(ensure: 'present', node: 'localhost')]
  end

  def create(context, name, should)
    update(context, name, should)
  end

  def update(context, name, should)
    context.notice("Updating PDM node config '#{name}'")
    path = pdm_path('/nodes/{node}/config', node: name)
    pdm_transport(context).put(context, path, update_request_body(context, should))
  end

  def delete(context, name)
    context.notice("pdm_node_config '#{name}': ensure => absent is a no-op")
  end
end
