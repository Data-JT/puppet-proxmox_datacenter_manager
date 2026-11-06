# frozen_string_literal: true

require_relative '../pdm_base_provider'

# @api private
module Puppet::Provider::PdmRealm; end

# Provider for PDM authentication realms.
class Puppet::Provider::PdmRealm::ProxmoxDatacenterManager < Puppet::Provider::PdmBaseProvider
  REALM_TYPES = ['ldap', 'ad', 'openid'].freeze unless const_defined?(:REALM_TYPES)

  def self.attribute_map
    {
      'realm' => :realm, 'comment' => :comment, 'default' => :default,
      'server1' => :server1, 'server2' => :server2, 'port' => :port,
      'bind-dn' => :bind_dn, 'password' => :bind_password, 'mode' => :mode,
      'verify' => :verify, 'capath' => :capath, 'filter' => :filter,
      'sync-defaults-options' => :sync_defaults_options, 'sync-attributes' => :sync_attributes,
      'user-classes' => :user_classes, 'base-dn' => :base_dn, 'user-attr' => :user_attr,
      'issuer-url' => :issuer_url, 'client-id' => :client_id, 'client-key' => :client_key,
      'username-claim' => :username_claim, 'autocreate' => :autocreate, 'scopes' => :scopes,
      'prompt' => :prompt, 'acr-values' => :acr_values, 'audiences' => :audiences,
      'delete' => :delete_properties,
    }
  end

  def self.boolean_attributes
    [:default, :verify, :autocreate]
  end

  def self.secret_attributes
    [:bind_password, :client_key]
  end

  # PDM stores the OpenID client secret in cleartext in access/domains.cfg and
  # hands it back over the API, so comparing it needs no node access.
  def self.api_secret_attributes
    [:client_key]
  end

  def get(context)
    @type_by_realm = {}
    @client_key_by_realm = {}
    REALM_TYPES.flat_map do |realm_type|
      (transport_get(context, "/config/access/#{realm_type}") || []).map do |realm|
        map_realm(realm, realm_type)
      end
    end
  end

  def create(context, name, should)
    realm_type = should[:type]
    raise Puppet::ResourceError, 'pdm_realm requires type when ensure => present' unless realm_type

    context.notice("Creating PDM #{realm_type} realm '#{name}'")
    pdm_transport(context).post(context, "/config/access/#{realm_type}", create_request_body(should))
  end

  def update(context, name, should)
    realm_type = should[:type] || type_by_realm[name]
    raise Puppet::ResourceError, "Unable to determine type for realm #{name}" unless realm_type

    context.notice("Updating PDM #{realm_type} realm '#{name}'")
    body = should.reject { |key, _| key == :username_claim }
    pdm_transport(context).put(context, realm_path(realm_type, name), update_request_body(context, body))
  end

  def stored_secret(title, attribute_name)
    return client_key_by_realm[title] if attribute_name == :client_key

    PuppetX::ProxmoxDatacenterManager::SecretStore.realm_bind_password(title)
  end

  def delete(context, name)
    realm_type = type_by_realm[name]
    raise Puppet::ResourceError, "Unable to determine type for realm #{name}" unless realm_type

    context.notice("Deleting PDM realm '#{name}'")
    pdm_transport(context).delete(context, realm_path(realm_type, name))
  end

  private

  # Both secrets are replaced with a placeholder rather than reported as-is:
  # the API returns the OpenID client key in full, and it has no business
  # reaching the RAL resource. It is cached here instead, for insync? to
  # compare against.
  def map_realm(realm, realm_type)
    name = realm['realm']
    type_by_realm[name] = realm_type
    client_key_by_realm[name] = realm['client-key']
    result = pdm_to_puppet(realm).reject { |key, _| [:bind_password, :client_key].include?(key) }
    result.merge(ensure: 'present', type: realm_type).merge(secret_placeholders(name))
  end

  def secret_placeholders(name)
    self.class.secret_attributes.each_with_object({}) do |attribute, placeholders|
      placeholder = secret_placeholder(name, attribute)
      placeholders[attribute] = placeholder if placeholder
    end
  end

  def realm_path(realm_type, name)
    pdm_path("/config/access/#{realm_type}/{realm}", realm: name)
  end

  def type_by_realm
    @type_by_realm ||= {}
  end

  def client_key_by_realm
    @client_key_by_realm ||= {}
  end
end
