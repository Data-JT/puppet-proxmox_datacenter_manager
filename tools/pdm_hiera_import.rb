#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'optparse'
require 'uri'
require 'yaml'

MAPPINGS = {
  remotes: ['/remotes/remote', 'id', {
    'type' => 'type', 'nodes' => 'nodes', 'authid' => 'authid', 'web-url' => 'web_url',
  }],
  users: ['/access/users', 'userid', {
    'comment' => 'comment', 'email' => 'email', 'enable' => 'enable', 'expire' => 'expire',
    'firstname' => 'firstname', 'lastname' => 'lastname',
  }],
  views: ['/config/views', 'id', {
    'include' => 'include', 'exclude' => 'exclude', 'include-all' => 'include_all', 'layout' => 'layout',
  }],
}.freeze

REALM_FIELDS = {
  'comment' => 'comment', 'default' => 'default', 'server1' => 'server1', 'server2' => 'server2',
  'port' => 'port', 'bind-dn' => 'bind_dn', 'mode' => 'mode', 'verify' => 'verify', 'capath' => 'capath',
  'filter' => 'filter', 'sync-defaults-options' => 'sync_defaults_options', 'sync-attributes' => 'sync_attributes',
  'user-classes' => 'user_classes', 'base-dn' => 'base_dn', 'user-attr' => 'user_attr',
  'issuer-url' => 'issuer_url', 'client-id' => 'client_id', 'username-claim' => 'username_claim',
  'autocreate' => 'autocreate', 'scopes' => 'scopes', 'prompt' => 'prompt', 'acr-values' => 'acr_values',
  'audiences' => 'audiences',
}.freeze

# Minimal PDM API client used by the Hiera importer.
class PdmClient
  def initialize(options)
    @options = options
  end

  def get(path, query = nil)
    uri = URI("https://#{@options[:host]}:#{@options[:port]}/api2/json#{path}")
    uri.query = URI.encode_www_form(query) if query
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "PDMAPIToken=#{@options[:token_id]}:#{@options[:token_secret]}"
    response = http.request(request)
    raise "PDM API error #{response.code} on #{path}: #{response.body}" unless response.code.to_i.between?(200, 299)

    parsed = JSON.parse(response.body)
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
  end

  private

  def http
    @http ||= Net::HTTP.new(@options[:host], @options[:port]).tap do |connection|
      connection.use_ssl = true
      connection.verify_mode = @options[:ssl_verify] ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      connection.ca_file = @options[:ssl_ca_file] if @options[:ssl_ca_file]
    end
  end
end

# Puppet attribute names whose types are Boolean. The PDM API commonly returns these as
# integer 1/0, which would fail Boolean type validation; normalize them like the providers.
BOOLEAN_KEYS = ['enable', 'verify', 'default', 'autocreate', 'include_all', 'propagate'].freeze

def to_bool(value)
  return true if [true, 1, '1', 'true'].include?(value)
  return false if [false, 0, '0', 'false'].include?(value)

  value
end

def mapped_attributes(entry, fields)
  fields.each_with_object({ 'ensure' => 'present' }) do |(api, puppet), attributes|
    next unless entry.key?(api)

    value = entry[api]
    value = to_bool(value) if BOOLEAN_KEYS.include?(puppet)
    attributes[puppet] = value
  end
end

def build_hiera_data(client)
  data = {}

  MAPPINGS.each do |resource_name, (endpoint, key, fields)|
    resources = Array(client.get(endpoint)).each_with_object({}) do |entry, result|
      result[entry.fetch(key)] = mapped_attributes(entry, fields)
    end
    data["proxmox_datacenter_manager::resources::#{resource_name}"] = resources unless resources.empty?
  end

  acls = Array(client.get('/access/acl')).each_with_object({}) do |entry, result|
    role = entry.fetch('roleid')
    key = "#{entry.fetch('path')}|#{entry.fetch('ugid')}|#{role}"
    result[key] = {
      'ensure'    => 'present',
      'ugid_type' => entry['ugid_type'],
      'propagate' => to_bool(entry.fetch('propagate', true)),
    }.compact
  end
  data['proxmox_datacenter_manager::resources::acls'] = acls unless acls.empty?

  tokens = Array(client.get('/access/users', 'include_tokens' => true)).each_with_object({}) do |user, result|
    Array(user['tokens']).each do |token|
      result[token.fetch('tokenid')] = mapped_attributes(
        token,
        { 'comment' => 'comment', 'enable' => 'enable', 'expire' => 'expire' },
      )
    end
  end
  data['proxmox_datacenter_manager::resources::api_tokens'] = tokens unless tokens.empty?

  realms = ['ldap', 'ad', 'openid'].each_with_object({}) do |realm_type, result|
    Array(client.get("/config/access/#{realm_type}")).each do |realm|
      result[realm.fetch('realm')] = mapped_attributes(realm, REALM_FIELDS).merge('type' => realm_type)
    end
  end
  data['proxmox_datacenter_manager::resources::realms'] = realms unless realms.empty?

  node_config = mapped_attributes(
    client.get('/nodes/localhost/config') || {},
    {
      'email-from' => 'email_from', 'http-proxy' => 'http_proxy', 'default-lang' => 'default_lang',
      'ciphers-tls-1.2' => 'ciphers_tls_1_2', 'ciphers-tls-1.3' => 'ciphers_tls_1_3',
    },
  )
  data['proxmox_datacenter_manager::resources::node_config'] = { 'localhost' => node_config }
  data['proxmox_datacenter_manager::resources::notes'] = {
    'global' => { 'ensure' => 'present', 'notes' => client.get('/config/notes') || '' },
  }

  data
end

def parse_options(argv)
  options = { host: 'localhost', port: 8443, ssl_verify: true, token_secret: ENV['PDM_TOKEN_SECRET'] }

  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: pdm_hiera_import.rb [options]'
    opts.on('--host HOST') { |value| options[:host] = value }
    opts.on('--port PORT', Integer) { |value| options[:port] = value }
    opts.on('--token-id TOKEN_ID') { |value| options[:token_id] = value }
    opts.on('--no-ssl-verify') { options[:ssl_verify] = false }
    opts.on('--ssl-ca-file PATH') { |value| options[:ssl_ca_file] = value }
    opts.on('--output PATH') { |value| options[:output] = value }
    opts.on('-h', '--help') do
      puts opts
      exit
    end
  end

  parser.parse!(argv)
  raise OptionParser::MissingArgument, '--token-id' unless options[:token_id]
  raise OptionParser::MissingArgument, 'set PDM_TOKEN_SECRET' unless options[:token_secret]

  options
end

def run(argv)
  options = parse_options(argv.dup)
  client = PdmClient.new(options)
  yaml = build_hiera_data(client).to_yaml
  options[:output] ? File.write(options[:output], yaml) : puts(yaml)
end

if $PROGRAM_NAME == __FILE__
  begin
    run(ARGV)
  rescue OptionParser::ParseError => error
    warn error.message
    exit 1
  end
end
