#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

def task_input
  input = STDIN.read
  return JSON.parse(input) unless input.strip.empty?

  ENV.select { |key, _value| key.start_with?('PT_') }.transform_keys { |key| key.delete_prefix('PT_') }
end

def hash_param(input, key)
  value = input[key]
  return {} if value.nil? || value == ''
  return value if value.is_a?(Hash)

  JSON.parse(value)
end

def method_class(method)
  {
    'GET'    => Net::HTTP::Get,
    'POST'   => Net::HTTP::Post,
    'PUT'    => Net::HTTP::Put,
    'DELETE' => Net::HTTP::Delete,
  }.fetch(method.to_s.upcase) do
    raise ArgumentError, "Unsupported PDM API method #{method}"
  end
end

def api_request(input)
  host = input.fetch('host')
  port = Integer(input.fetch('port', 8443))
  method = input.fetch('method').upcase
  path = input.fetch('path')
  raise ArgumentError, 'path must start with /' unless path.start_with?('/')

  hash_param(input, 'path_params').each do |key, value|
    path = path.gsub("{#{key}}", URI::DEFAULT_PARSER.escape(value.to_s, %r{[^A-Za-z0-9_.~-]}))
  end
  uri = URI("https://#{host}:#{port}/api2/json#{path}")
  query = hash_param(input, 'query')
  uri.query = URI.encode_www_form(query) unless query.empty?

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  verify = [true, 'true', '1', 1].include?(input.fetch('ssl_verify', true))
  http.verify_mode = verify ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
  ssl_ca_file = input['ssl_ca_file']
  http.ca_file = ssl_ca_file if ssl_ca_file && ssl_ca_file != ''

  request = method_class(method).new(uri)
  request['Authorization'] = "PDMAPIToken=#{input.fetch('token_id')}:#{input.fetch('token_secret')}"
  request['Content-Type'] = 'application/json'
  body = hash_param(input, 'body')
  request.body = body.to_json unless body.empty?

  response = http.request(request)
  parsed = (response.body.nil? || response.body.empty?) ? nil : JSON.parse(response.body)
  {
    status: response.code.to_i,
    success: response.code.to_i.between?(200, 299),
    data: (parsed.is_a?(Hash) && parsed.key?('data')) ? parsed['data'] : parsed,
  }
rescue StandardError => error
  { status: 'error', success: false, error: error.message }
end

puts JSON.pretty_generate(api_request(task_input)) if $PROGRAM_NAME == __FILE__
