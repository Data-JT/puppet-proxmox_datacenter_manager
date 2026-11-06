# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

# @api private
module Puppet::Transport; end

# HTTPS transport for the Proxmox Datacenter Manager API.
#
# Recognized connection_info keys:
#   :host          (required) PDM host name or IP address
#   :port          (optional) API port, default 8443
#   :token_id      (required) API token ID, e.g. user@realm!token
#   :token_secret  (required) API token secret (String or Sensitive)
#   :ssl_verify    (optional) verify the TLS certificate, default true
#   :ssl_ca_file   (optional) CA bundle path used when ssl_verify is true
#
# No PDM endpoint the providers call runs as an async task, so unlike the PVE
# and PBS transports there is no task timeout.
class Puppet::Transport::ProxmoxDatacenterManager
  # Seconds to wait for the TCP and TLS connection to the API.
  OPEN_TIMEOUT = 10
  # Seconds to wait for a response once a request has been sent.
  READ_TIMEOUT = 60

  def initialize(context, connection_info)
    @host = connection_info[:host]
    @port = connection_info[:port] || 8443
    @token_id = connection_info[:token_id]
    secret = connection_info[:token_secret]
    @token_secret = secret.respond_to?(:unwrap) ? secret.unwrap : secret.to_s
    @ssl_verify = connection_info.fetch(:ssl_verify, true)
    @ssl_ca_file = connection_info[:ssl_ca_file]
    context.debug("Initialized PDM transport for #{@host}:#{@port}")
  end

  def get(context, path, query = nil)
    request(context, Net::HTTP::Get, path, nil, query)
  end

  def post(context, path, body = {}, query = nil)
    request(context, Net::HTTP::Post, path, body, query)
  end

  def put(context, path, body = {}, query = nil)
    request(context, Net::HTTP::Put, path, body, query)
  end

  def delete(context, path, body = nil, query = nil)
    request(context, Net::HTTP::Delete, path, body, query)
  end

  def call(context, method, path, body: nil, query: nil, path_params: nil)
    expanded_path = expand_path(path, Hash(path_params))
    request(context, http_method_class(method), expanded_path, body, query)
  end

  def expand_path(path, path_params)
    path_params.reduce(path) do |expanded, (key, value)|
      expanded.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
    end
  end

  private

  def request(context, method_class, path, body = nil, query = nil)
    uri = build_uri(path, query)
    req = method_class.new(uri)
    req['Authorization'] = "PDMAPIToken=#{@token_id}:#{@token_secret}"
    req['Content-Type'] = 'application/json'
    req.body = body.to_json if body && !body.empty?

    context.debug("PDM API #{method_class::METHOD} #{uri.request_uri}")
    response = http_connection.request(req)
    handle_response(response, path)
  end

  def build_uri(path, query)
    uri = URI("https://#{@host}:#{@port}/api2/json#{path}")
    uri.query = URI.encode_www_form(query) if query && !query.empty?
    uri
  end

  def http_method_class(method)
    {
      'GET'    => Net::HTTP::Get,
      'POST'   => Net::HTTP::Post,
      'PUT'    => Net::HTTP::Put,
      'DELETE' => Net::HTTP::Delete,
    }.fetch(method.to_s.upcase) do
      raise Puppet::ResourceError, "Unsupported PDM API method #{method}"
    end
  end

  def http_connection
    @http_connection ||= Net::HTTP.new(@host, @port).tap do |http|
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      if @ssl_verify
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.ca_file = @ssl_ca_file if @ssl_ca_file
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http.start
    end
  end

  def handle_response(response, path)
    code = response.code
    body = response.body
    raise Puppet::ResourceError, "PDM API error #{code} on #{path}: #{body}" unless code.to_i.between?(200, 299)
    return nil if body.nil? || body.empty?

    parsed = JSON.parse(body)
    (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed
  rescue JSON::ParserError
    body
  end
end
