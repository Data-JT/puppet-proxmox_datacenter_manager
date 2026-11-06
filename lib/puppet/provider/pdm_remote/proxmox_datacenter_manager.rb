# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmRemote; end

# Provider for PDM remote definitions.
class Puppet::Provider::PdmRemote::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  def self.attribute_map
    {
      'id' => :id,
      'type' => :type,
      'nodes' => :nodes,
      'authid' => :authid,
      'token' => :token,
      'create-token' => :create_token,
      'web-url' => :web_url,
      'delete' => :delete_properties,
    }
  end

  def self.secret_attributes
    [:token]
  end

  def get(context)
    (transport_get(context, '/remotes/remote') || []).map { |remote| map_remote(remote) }
  end

  def stored_secret(title, _attribute_name)
    PuppetX::ProxmoxDatacenterManager::SecretStore.remote_token(title)
  end

  def create(context, name, should)
    raise Puppet::ResourceError, 'pdm_remote requires token when ensure => present' unless should[:token]

    context.notice("Creating PDM remote '#{name}'")
    pdm_transport(context).post(context, '/remotes/remote', create_request_body(should))
  end

  def update(context, name, should)
    context.notice("Updating PDM remote '#{name}'")
    body = should.reject { |key, _| [:type, :create_token].include?(key) }
    pdm_transport(context).put(context, remote_path(name), update_request_body(context, body))
  end

  def delete(context, name)
    context.notice("Deleting PDM remote '#{name}'")
    pdm_transport(context).delete(context, remote_path(name))
  end

  private

  # The API's own 'token' field always comes back blank, so it is dropped and
  # replaced with a placeholder derived from what PDM actually stored.
  def map_remote(remote)
    mapped = pdm_to_puppet(remote).reject { |key, _| [:token, :create_token].include?(key) }
    placeholder = secret_placeholder(remote['id'], :token)
    mapped[:token] = placeholder if placeholder
    mapped.merge(ensure: 'present')
  end

  def remote_path(name)
    pdm_path('/remotes/remote/{id}', id: name)
  end
end
