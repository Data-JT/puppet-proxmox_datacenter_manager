# frozen_string_literal: true

require 'spec_helper'

# The task script defines its helpers as top-level methods. Its executable statement is
# guarded by `$PROGRAM_NAME`, so loading it from this spec makes the helpers available
# without performing a request.
RSpec.describe 'pdm_api_request task' do
  task_path = File.expand_path('../../../tasks/pdm_api_request.rb', __dir__)
  load task_path

  let(:base_input) do
    {
      'host' => 'pdm.example.com',
      'token_id' => 'user@pdm!ci',
      'token_secret' => 'secret',
      'method' => 'GET',
      'path' => '/version',
    }
  end
  let(:base_url) { 'https://pdm.example.com:8443/api2/json' }
  let(:headers) { { 'Authorization' => 'PDMAPIToken=user@pdm!ci:secret', 'Content-Type' => 'application/json' } }

  describe 'task_input' do
    it 'parses JSON given on stdin' do
      allow(STDIN).to receive(:read).and_return('{"host":"pdm.example.com","port":8443}')
      expect(task_input).to eq('host' => 'pdm.example.com', 'port' => 8443)
    end

    it 'falls back to PT_ environment variables when stdin is empty' do
      allow(STDIN).to receive(:read).and_return("  \n")
      ENV['PT_host'] = 'pdm.example.com'
      ENV['PT_method'] = 'GET'
      begin
        expect(task_input).to eq('host' => 'pdm.example.com', 'method' => 'GET')
      ensure
        ENV.delete('PT_host')
        ENV.delete('PT_method')
      end
    end
  end

  describe 'hash_param' do
    it 'returns an empty hash for nil or blank values' do
      expect(hash_param({}, 'query')).to eq({})
      expect(hash_param({ 'query' => '' }, 'query')).to eq({})
    end

    it 'returns hashes as-is' do
      expect(hash_param({ 'query' => { 'limit' => 5 } }, 'query')).to eq('limit' => 5)
    end

    it 'parses JSON-encoded strings' do
      expect(hash_param({ 'query' => '{"limit":5}' }, 'query')).to eq('limit' => 5)
    end
  end

  describe 'method_class' do
    it 'maps supported HTTP methods to Net::HTTP classes' do
      expect(method_class('get')).to eq(Net::HTTP::Get)
      expect(method_class('POST')).to eq(Net::HTTP::Post)
      expect(method_class('Put')).to eq(Net::HTTP::Put)
      expect(method_class('DELETE')).to eq(Net::HTTP::Delete)
    end

    it 'raises for unsupported HTTP methods' do
      expect { method_class('PATCH') }.to raise_error(ArgumentError, %r{Unsupported PDM API method PATCH})
    end
  end

  describe 'api_request' do
    it 'performs GET requests, authenticates, and unwraps data' do
      stub_request(:get, "#{base_url}/version")
        .with(headers: headers)
        .to_return(status: 200, body: '{"data":{"version":"1.0"}}')

      expect(api_request(base_input)).to eq(status: 200, success: true, data: { 'version' => '1.0' })
    end

    it 'sends POST, PUT, and DELETE requests with a JSON body' do
      stub_request(:post, "#{base_url}/access/users")
        .with(headers: headers, body: '{"userid":"automation@pdm"}')
        .to_return(status: 200, body: '{"data":null}')

      result = api_request(base_input.merge('method' => 'POST', 'path' => '/access/users', 'body' => { 'userid' => 'automation@pdm' }))
      expect(result).to eq(status: 200, success: true, data: nil)
    end

    it 'rejects paths that do not start with a slash' do
      expect(api_request(base_input.merge('path' => 'version'))).to eq(
        status: 'error', success: false, error: 'path must start with /',
      )
    end

    it 'reports an error for unsupported HTTP methods' do
      result = api_request(base_input.merge('method' => 'PATCH'))
      expect(result[:status]).to eq('error')
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(%r{PATCH})
    end

    it 'expands and escapes path parameters' do
      stub_request(:get, "#{base_url}/nodes/node%20a%40b/status")
        .with(headers: headers)
        .to_return(status: 200, body: '{"data":{}}')

      input = base_input.merge('path' => '/nodes/{node}/status', 'path_params' => { 'node' => 'node a@b' })
      expect(api_request(input)[:status]).to eq(200)
    end

    it 'encodes query parameters' do
      stub_request(:get, "#{base_url}/cluster/resources")
        .with(query: { 'type' => 'vm', 'limit' => '5' }, headers: headers)
        .to_return(status: 200, body: '{"data":[]}')

      input = base_input.merge('path' => '/cluster/resources', 'query' => { 'type' => 'vm', 'limit' => 5 })
      expect(api_request(input)).to eq(status: 200, success: true, data: [])
    end

    it 'uses the configured port' do
      stub_request(:get, 'https://pdm.example.com:9443/api2/json/version').to_return(status: 200, body: '{"data":{}}')
      expect(api_request(base_input.merge('port' => 9443))[:status]).to eq(200)
    end

    it 'reports HTTP failures without raising' do
      stub_request(:get, "#{base_url}/version").to_return(status: 403, body: '{"errors":{"version":"Forbidden"}}')
      expect(api_request(base_input)).to eq(
        status: 403, success: false, data: { 'errors' => { 'version' => 'Forbidden' } },
      )
    end

    it 'reports an error for malformed JSON responses' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: 'not json')
      result = api_request(base_input)
      expect(result[:status]).to eq('error')
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(%r{unexpected|JSON}i)
    end

    it 'returns nil data for empty response bodies' do
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '')
      expect(api_request(base_input)).to eq(status: 200, success: true, data: nil)
    end

    it 'enables certificate verification by default' do
      http = nil
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        http = original.call(*args)
      end
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')

      api_request(base_input)

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
    end

    it 'sets the CA file when ssl_verify is enabled and ssl_ca_file is given' do
      http = nil
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        http = original.call(*args)
      end
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')

      api_request(base_input.merge('ssl_ca_file' => '/etc/ssl/pdm-ca.pem'))

      expect(http.ca_file).to eq('/etc/ssl/pdm-ca.pem')
    end

    it 'disables certificate verification when ssl_verify is false' do
      http = nil
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        http = original.call(*args)
      end
      stub_request(:get, "#{base_url}/version").to_return(status: 200, body: '{"data":{}}')

      api_request(base_input.merge('ssl_verify' => false))

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
    end
  end
end
