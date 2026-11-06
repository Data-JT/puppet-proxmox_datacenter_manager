# frozen_string_literal: true

require 'spec_helper'
require 'puppet/transport/proxmox_datacenter_manager'

RSpec.describe Puppet::Transport::ProxmoxDatacenterManager do
  subject(:transport) { described_class.new(context, connection_info) }

  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', debug: nil) }
  let(:connection_info) do
    {
      host: 'pdm.example.com',
      token_id: 'user@pdm!puppet',
      token_secret: 'secret',
      ssl_verify: false,
    }
  end
  let(:base_url) { 'https://pdm.example.com:8443/api2/json' }
  let(:headers) { { 'Authorization' => 'PDMAPIToken=user@pdm!puppet:secret', 'Content-Type' => 'application/json' } }

  it 'uses PDM token authentication and unwraps data' do
    stub_request(:get, "#{base_url}/resources/list")
      .with(headers: headers)
      .to_return(status: 200, body: '{"data":[{"id":"r1"}]}')

    expect(transport.get(context, '/resources/list')).to eq([{ 'id' => 'r1' }])
  end

  it 'uses port 8443 by default' do
    stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')
    expect { transport.get(context, '/version') }.not_to raise_error
  end

  it 'enables TLS verification when the setting is omitted' do
    connection_info.delete(:ssl_verify)
    expect(transport.instance_variable_get(:@ssl_verify)).to be(true)
  end

  it 'raises a ResourceError for API failures' do
    stub_request(:get, "#{base_url}/version").to_return(status: 403, body: 'Forbidden')
    expect { transport.get(context, '/version') }.to raise_error(Puppet::ResourceError, %r{PDM API error 403})
  end

  it 'sends POST requests with a JSON body' do
    stub_request(:post, "#{base_url}/access/users")
      .with(headers: headers, body: '{"userid":"automation@pdm"}')
      .to_return(status: 200, body: '{"data":null}')

    expect(transport.post(context, '/access/users', 'userid' => 'automation@pdm')).to be_nil
  end

  it 'sends PUT requests with a JSON body' do
    stub_request(:put, "#{base_url}/access/users/automation%40pdm")
      .with(headers: headers, body: '{"comment":"updated"}')
      .to_return(status: 200, body: '{"data":null}')

    transport.put(context, '/access/users/automation%40pdm', 'comment' => 'updated')

    expect(WebMock).to have_requested(:put, "#{base_url}/access/users/automation%40pdm")
  end

  it 'sends DELETE requests, optionally with a body' do
    stub_request(:delete, "#{base_url}/access/users/automation%40pdm")
      .with(headers: headers, body: '')
      .to_return(status: 200, body: '')

    expect(transport.delete(context, '/access/users/automation%40pdm')).to be_nil
  end

  it 'omits the request body when it is nil or empty' do
    stub_request(:post, "#{base_url}/config/notes").with(headers: headers, body: '').to_return(status: 200, body: '')

    transport.post(context, '/config/notes', {})

    expect(WebMock).to(have_requested(:post, "#{base_url}/config/notes").with { |req| req.body.to_s.empty? })
  end

  describe '#call' do
    it 'dispatches to the HTTP method named by a string or symbol' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{"version":"1.0"}}')
      expect(transport.call(context, 'get', '/version')).to eq('version' => '1.0')

      stub_request(:post, "#{base_url}/access/users")
        .with(body: '{"userid":"automation@pdm"}')
        .to_return(status: 200, body: '{"data":null}')
      transport.call(context, :post, '/access/users', body: { 'userid' => 'automation@pdm' })
      expect(WebMock).to have_requested(:post, "#{base_url}/access/users")
    end

    it 'expands and escapes path parameters before issuing the request' do
      stub_request(:get, "#{base_url}/access/users/user%3Fname%40pdm/token/token%23name").to_return(status: 200, body: '{"data":{}}')

      transport.call(
        context, 'get', '/access/users/{userid}/token/{token-name}',
        path_params: { userid: 'user?name@pdm', 'token-name': 'token#name' }
      )

      expect(WebMock).to have_requested(:get, "#{base_url}/access/users/user%3Fname%40pdm/token/token%23name")
    end

    it 'passes query parameters through to the request' do
      stub_request(:get, "#{base_url}/cluster/resources")
        .with(query: { 'type' => 'vm' })
        .to_return(status: 200, body: '{"data":[]}')

      expect(transport.call(context, 'get', '/cluster/resources', query: { 'type' => 'vm' })).to eq([])
    end

    it 'raises a ResourceError for unsupported HTTP methods' do
      expect { transport.call(context, 'PATCH', '/version') }
        .to raise_error(Puppet::ResourceError, 'Unsupported PDM API method PATCH')
    end
  end

  describe 'response handling' do
    it 'returns nil for empty response bodies' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '')
      expect(transport.get(context, '/version')).to be_nil
    end

    it 'returns the raw body when the response is not JSON' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: 'plain text')
      expect(transport.get(context, '/version')).to eq('plain text')
    end

    it 'returns parsed JSON as-is when it is not a Hash with a data key' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '[1,2,3]')
      expect(transport.get(context, '/version')).to eq([1, 2, 3])
    end
  end

  describe 'timeouts' do
    it 'opens connections within 10 seconds and waits up to 60 seconds for a response' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')

      transport.get(context, '/version')
      http = transport.send(:http_connection)

      expect([http.open_timeout, http.read_timeout]).to eq([10, 60])
    end
  end

  describe 'TLS configuration' do
    it 'verifies certificates and sets the CA file when ssl_verify is enabled' do
      connection_info[:ssl_verify] = true
      connection_info[:ssl_ca_file] = '/etc/ssl/pdm-ca.pem'
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')

      transport.get(context, '/version')
      http = transport.send(:http_connection)

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
      expect(http.ca_file).to eq('/etc/ssl/pdm-ca.pem')
    end

    it 'disables certificate verification and ignores the CA file when ssl_verify is false' do
      connection_info[:ssl_verify] = false
      connection_info[:ssl_ca_file] = '/etc/ssl/pdm-ca.pem'
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')

      transport.get(context, '/version')
      http = transport.send(:http_connection)

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
      expect(http.ca_file).to be_nil
    end
  end

  describe 'authentication' do
    it 'unwraps a Sensitive token secret' do
      connection_info[:token_secret] = Puppet::Pops::Types::PSensitiveType::Sensitive.new('wrapped-secret')
      stub_request(:get, "#{base_url}/version")
        .with(headers: { 'Authorization' => 'PDMAPIToken=user@pdm!puppet:wrapped-secret' })
        .to_return(status: 200, body: '{"data":{}}')

      expect { transport.get(context, '/version') }.not_to raise_error
    end
  end
end
