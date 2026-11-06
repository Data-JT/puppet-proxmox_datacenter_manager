# frozen_string_literal: true

require 'puppet/resource_api/simple_provider'
require_relative '../../puppet_x/proxmox_datacenter_manager/secret_store' # see secret_store.rb: a bare require breaks in puppetserver
require 'uri'
require 'yaml'

# Shared mapping and transport helpers for PDM Resource API providers.
class Puppet::Provider::PdmBaseProvider < Puppet::ResourceApi::SimpleProvider
  MISSING_TRANSPORT_RESULT = [].freeze

  # Stable 'is' value reported for a managed secret. Must not vary between
  # runs -- a changing placeholder would itself read as drift. It is never
  # compared, because insync? intercepts first; it exists so Puppet has an 'is'
  # to report against and so `puppet resource` distinguishes "a secret is set"
  # from "none is set".
  SECRET_PLACEHOLDER = '[secret managed]'
  # Change notice for a rotated secret. Carries no value of its own, so a
  # rotation cannot leak the secret into the log even before Puppet's own
  # redaction applies.
  SECRET_CHANGE_MESSAGE = 'changed to the configured secret'

  def initialize
    super
    reset_transport_cache
  end

  def self.attribute_map
    {}
  end

  def self.boolean_attributes
    []
  end

  # Attributes compared through the secret machinery rather than by ordinary
  # equality. Providers listing an attribute here must implement stored_secret.
  def self.secret_attributes
    []
  end

  # The subset of secret_attributes PDM does return over the API, so their
  # comparison needs no access to the node. They are exempt from the
  # fail-closed store check, which would otherwise make them unmanageable from
  # an agent running anywhere but the PDM host.
  def self.api_secret_attributes
    []
  end

  def self.config_path
    File.join(Puppet.settings[:confdir], 'pdm_transport.yaml')
  end

  def self.build_transport(context)
    require 'puppet/transport/proxmox_datacenter_manager'
    config = YAML.safe_load_file(config_path).transform_keys(&:to_sym)
    Puppet::Transport::ProxmoxDatacenterManager.new(context, config)
  rescue Errno::ENOENT
    raise Puppet::ResourceError,
          "PDM transport config not found at #{config_path}; apply the proxmox_datacenter_manager class first"
  end

  def pdm_transport(context)
    signature = transport_config_signature
    unless @pdm_transport && signature == @transport_config_signature
      @pdm_transport = self.class.build_transport(context)
      @transport_config_signature = signature
    end
    @pdm_transport
  end

  # State discovery happens before catalog resources are applied. Treat a
  # missing managed transport file as an empty result; set() refreshes state
  # after the transport class has been applied.
  def transport_get(context, path, query = nil)
    request_transport(context, path, query)
  rescue Puppet::ResourceError => error
    raise unless error.message.start_with?('PDM transport config not found at ')

    @transport_config_missing = true
    MISSING_TRANSPORT_RESULT
  end

  def set(context, changes)
    changes = refresh_changes(context, changes) if @transport_config_missing
    super
  end

  # Returning nil is the Resource API insync? contract: it signals "I do not
  # handle this property, fall back to the default comparison". It is not a
  # boolean, so it must not be collapsed to false.
  #
  # Requires `features: ['custom_insync']` on the type. Without it the hook is
  # silently skipped and nothing warns (resource_api/property.rb:28).
  def insync?(_context, title, attribute_name, is, should)
    return delete_properties_insync?(is, should) if attribute_name == :delete_properties
    return nil unless self.class.secret_attributes.include?(attribute_name) # rubocop:disable Style/ReturnNilInPredicateMethodDefinition

    secret_insync?(title, attribute_name, should)
  end

  # A secret is in sync when the copy PDM holds matches the declared one.
  #
  # An undeclared secret is always in sync: Puppet is not managing it, so
  # whatever PDM holds is by definition correct.
  #
  # Fails closed when the store cannot be read. A false "in sync" there would
  # silently disable enforcement, which is the failure mode this whole
  # mechanism exists to remove.
  def secret_insync?(title, attribute_name, should)
    desired = unwrap_secret(should[attribute_name])
    return true unless desired

    PuppetX::ProxmoxDatacenterManager::SecretStore.assert_available!(attribute_name) if store_required?(attribute_name)
    secret_verdict(stored_secret(title, attribute_name), desired)
  end

  def store_required?(attribute_name)
    !self.class.api_secret_attributes.include?(attribute_name)
  end

  def secret_verdict(stored, desired)
    return true if stored && secret_matches?(stored, desired)

    [false, SECRET_CHANGE_MESSAGE]
  end

  # The 'is' value get() reports for a secret. Never raises: get() runs during
  # discovery for every resource in the catalog, including ones managing no
  # secrets at all, so it must survive an agent that is not on a PDM node or
  # not running as root. The fail-closed assertion lives in insync?, which only
  # runs for attributes actually declared.
  def secret_placeholder(title, attribute_name)
    return nil if store_required?(attribute_name) && !PuppetX::ProxmoxDatacenterManager::SecretStore.available?

    SECRET_PLACEHOLDER if stored_secret(title, attribute_name)
  rescue Puppet::ResourceError
    nil
  end

  def stored_secret(_title, _attribute_name)
    raise NotImplementedError,
          "#{self.class} declares secret_attributes but does not implement stored_secret"
  end

  # Plaintext against plaintext, which covers three of the four secrets.
  # pdm_user overrides this to verify a plaintext against a crypt(3) hash.
  def secret_matches?(stored, desired)
    stored == desired
  end

  # A Hiera or eyaml lookup yields a plain String; a Sensitive() declaration
  # and the Resource API's own re-wrapping both yield something with #unwrap.
  def unwrap_secret(value)
    value.respond_to?(:unwrap) ? value.unwrap : value
  end

  def pdm_to_puppet(hash)
    provider_class = self.class
    provider_class.attribute_map.each_with_object({}) do |(pdm_key, puppet_key), mapped|
      pdm_key = pdm_key.to_s
      next unless hash.key?(pdm_key)

      value = hash[pdm_key]
      value = to_bool(value) if provider_class.boolean_attributes.include?(puppet_key)
      mapped[puppet_key] = value
    end
  end

  def puppet_to_pdm(hash)
    provider_class = self.class
    provider_class.attribute_map.each_with_object({}) do |(pdm_key, puppet_key), result|
      next unless hash.key?(puppet_key)

      value = hash[puppet_key]
      next if value.nil?

      value = unwrap_secret(value)
      value = to_bool(value) if provider_class.boolean_attributes.include?(puppet_key)
      result[pdm_key.to_s] = value
    end
  end

  # Body for create requests. Never carries 'delete': a resource being created
  # has no properties to delete, and the API rejects the parameter on POST.
  def create_request_body(should)
    body = should.dup
    body.delete(:ensure)
    puppet_to_pdm(body).except('delete')
  end

  def update_request_body(context, should)
    body = should.dup
    body.delete(:ensure)
    context.type.namevars.each { |namevar| body.delete(namevar) }
    normalize_delete_properties(puppet_to_pdm(body))
  end

  # Clearing optional properties: `delete_properties` names API properties to
  # remove on update. A provider opts in by mapping 'delete' => :delete_properties
  # in attribute_map, which passes the list to the endpoint's `delete` parameter.
  #
  # Whether that parameter is sent as a JSON list rather than a comma-separated
  # string. PVE's Perl API takes the string on most endpoints; the Rust APIs of
  # PBS and PDM take the list.
  def self.delete_properties_as_array?
    true
  end

  # GET never reports delete_properties, so it is in sync once none of the
  # named properties is present any more: the delete is sent only while one
  # still is. A name outside attribute_map could never be observed as gone and
  # would re-send the delete on every run, so it is rejected instead.
  def delete_properties_insync?(current, desired)
    requested = Array(desired[:delete_properties])
    reject_unobservable_deletions(requested)
    attribute_map = self.class.attribute_map
    requested.none? { |api_key| current.key?(attribute_map[api_key]) }
  end

  def pdm_path(path, path_params = {})
    path_params.reduce(path) do |expanded, (key, value)|
      expanded.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
    end
  end

  private

  def request_transport(context, path, query)
    transport = pdm_transport(context)
    return transport.get(context, path, query) if query

    transport.get(context, path)
  end

  def reset_transport_cache
    @pdm_transport = nil
    @transport_config_signature = nil
    @transport_config_missing = false
  end

  def transport_config_signature
    stat = File.stat(self.class.config_path)
    [stat.mtime.to_f, stat.size]
  rescue Errno::ENOENT, Errno::ENOTDIR
    nil
  end

  def missing_transport_result?(value)
    value.equal?(MISSING_TRANSPORT_RESULT)
  end

  def refresh_changes(context, changes)
    reset_transport_cache
    current = get(context) || []

    changes.transform_values { |change| refresh_change(context, current, change) }
  end

  def refresh_change(context, current, change)
    should = change[:should]
    actual = current.find { |resource| same_resource?(context, resource, should) }
    change.merge(is: actual || absent_state(context, should))
  end

  def same_resource?(context, resource, should)
    context.type.namevars.all? { |namevar| resource[namevar] == should[namevar] }
  end

  def absent_state(context, should)
    context.type.namevars.to_h { |namevar| [namevar, should[namevar]] }.merge(ensure: 'absent')
  end

  def normalize_delete_properties(body)
    return body unless body.key?('delete')

    values = Array(body['delete'])
    body['delete'] = self.class.delete_properties_as_array? ? values : values.join(',')
    body
  end

  def reject_unobservable_deletions(requested)
    unknown = requested.reject { |api_key| self.class.attribute_map.key?(api_key) }
    return if unknown.empty?

    raise Puppet::ResourceError, "Cannot observe deleted PDM properties: #{unknown.join(', ')}"
  end

  def to_bool(value)
    return true if [true, 1, '1', 'true', :true].include?(value)
    return false if [false, 0, '0', 'false', :false].include?(value)

    value
  end
end
