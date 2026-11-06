# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'yaml'
require 'tempfile'

# The importer exposes a run method and only executes automatically when invoked as
# a script. Each example reloads its definitions, then calls run with ARGV/ENV/stdout
# stubbed and the PDM API mocked through WebMock. Constants such as MAPPINGS get
# redefined on every reload, so $VERBOSE is silenced to avoid noise.
RSpec.describe 'pdm_hiera_import tool' do
  tool_path = File.expand_path('../../../tools/pdm_hiera_import.rb', __dir__)
  base_url = 'https://pdm.example.com:8443/api2/json'
  headers = { 'Authorization' => 'PDMAPIToken=automation@pdm!ci:topsecret' }

  default_argv = ['--host', 'pdm.example.com', '--token-id', 'automation@pdm!ci']
  default_env = { 'PDM_TOKEN_SECRET' => 'topsecret' }

  def run_tool(tool_path, argv, env)
    output = StringIO.new
    original_argv = ARGV.dup
    original_stdout = $stdout
    original_verbose = $VERBOSE
    original_env = {}
    env.each_key { |key| original_env[key] = ENV[key] }

    ARGV.replace(argv)
    env.each { |key, value| ENV[key] = value }
    $stdout = output
    $VERBOSE = nil
    begin
      load tool_path
      run(argv)
    ensure
      ARGV.replace(original_argv)
      original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      $stdout = original_stdout
      $VERBOSE = original_verbose
    end
    output.string
  end

  def stub_get(base_url, path, body, headers, query: nil)
    stub = stub_request(:get, "#{base_url}#{path}").with(headers: headers)
    stub = stub.with(query: query) if query
    stub.to_return(status: 200, body: body.to_json)
  end

  def stub_default_endpoints(base_url, headers)
    stub_get(base_url, '/remotes/remote', [
               { 'id' => 'prod', 'type' => 'pve', 'nodes' => ['pve01'], 'authid' => 'pdm@pve!manager', 'web-url' => 'https://pve01:8006' },
             ], headers)
    stub_get(base_url, '/access/users', [
               {
                 'userid' => 'automation@pdm', 'comment' => 'CI', 'email' => 'auto@example.com',
                 'enable' => true, 'expire' => 0, 'firstname' => 'Auto', 'lastname' => 'Mation',
               },
             ], headers)
    stub_get(base_url, '/config/views', [
               { 'id' => 'production', 'include' => ['remote=prod'], 'exclude' => [], 'include-all' => false, 'layout' => 'grid' },
             ], headers)
    stub_get(base_url, '/access/acl', [
               { 'path' => '/', 'ugid' => 'automation@pdm!ci', 'ugid_type' => 'token', 'roleid' => 'Auditor', 'propagate' => true },
             ], headers)
    stub_get(base_url, '/access/users', [
               { 'userid' => 'automation@pdm', 'tokens' => [{ 'tokenid' => 'automation@pdm!ci', 'comment' => 'CI token', 'enable' => true, 'expire' => 0 }] },
             ], headers, query: { 'include_tokens' => 'true' })
    stub_get(base_url, '/config/access/ldap', [
               { 'realm' => 'corp-ldap', 'comment' => 'Corp', 'server1' => 'ldap.example.com', 'base-dn' => 'dc=example,dc=com', 'mode' => 'ldaps', 'verify' => true },
             ], headers)
    stub_get(base_url, '/config/access/ad', [], headers)
    stub_get(base_url, '/config/access/openid', [
               { 'realm' => 'corp-oidc', 'issuer-url' => 'https://issuer.example.com', 'client-id' => 'pdm', 'username-claim' => 'preferred_username' },
             ], headers)
    stub_get(base_url, '/nodes/localhost/config', { 'email-from' => 'pdm@example.com', 'http-proxy' => 'http://proxy:3128' }, headers)
    stub_get(base_url, '/config/notes', 'Managed by Puppet', headers)
  end

  it 'requires --token-id' do
    expect { run_tool(tool_path, ['--host', 'pdm.example.com'], default_env) }
      .to raise_error(OptionParser::MissingArgument, %r{--token-id})
  end

  it 'requires a token secret' do
    expect { run_tool(tool_path, default_argv, {}) }
      .to raise_error(OptionParser::MissingArgument, %r{PDM_TOKEN_SECRET})
  end

  it 'raises when a PDM endpoint returns an error' do
    stub_default_endpoints(base_url, headers)
    stub_request(:get, "#{base_url}/config/notes").with(headers: headers).to_return(status: 500, body: 'boom')

    expect { run_tool(tool_path, default_argv, default_env) }
      .to raise_error(RuntimeError, %r{PDM API error 500 on /config/notes: boom})
  end

  describe 'a successful import' do
    let(:data) do
      stub_default_endpoints(base_url, headers)
      YAML.safe_load(run_tool(tool_path, default_argv, default_env), permitted_classes: [Symbol])
    end

    it 'imports remotes' do
      expect(data['proxmox_datacenter_manager::resources::remotes']).to eq(
        'prod' => {
          'ensure' => 'present', 'type' => 'pve', 'nodes' => ['pve01'],
          'authid' => 'pdm@pve!manager', 'web_url' => 'https://pve01:8006',
        },
      )
    end

    it 'imports users without secrets' do
      expect(data['proxmox_datacenter_manager::resources::users']).to eq(
        'automation@pdm' => {
          'ensure' => 'present', 'comment' => 'CI', 'email' => 'auto@example.com',
          'enable' => true, 'expire' => 0, 'firstname' => 'Auto', 'lastname' => 'Mation',
        },
      )
    end

    it 'imports views' do
      expect(data['proxmox_datacenter_manager::resources::views']).to eq(
        'production' => {
          'ensure' => 'present', 'include' => ['remote=prod'], 'exclude' => [],
          'include_all' => false, 'layout' => 'grid',
        },
      )
    end

    it 'imports ACLs keyed by path, subject, and role' do
      expect(data['proxmox_datacenter_manager::resources::acls']).to eq(
        '/|automation@pdm!ci|Auditor' => { 'ensure' => 'present', 'ugid_type' => 'token', 'propagate' => true },
      )
    end

    it 'imports API tokens nested under users without secrets' do
      expect(data['proxmox_datacenter_manager::resources::api_tokens']).to eq(
        'automation@pdm!ci' => { 'ensure' => 'present', 'comment' => 'CI token', 'enable' => true, 'expire' => 0 },
      )
    end

    it 'imports realms across all realm types and omits write-only secrets' do
      realms = data['proxmox_datacenter_manager::resources::realms']
      expect(realms).to eq(
        'corp-ldap' => {
          'ensure' => 'present', 'comment' => 'Corp', 'server1' => 'ldap.example.com',
          'base_dn' => 'dc=example,dc=com', 'mode' => 'ldaps', 'verify' => true, 'type' => 'ldap',
        },
        'corp-oidc' => {
          'ensure' => 'present', 'issuer_url' => 'https://issuer.example.com', 'client_id' => 'pdm',
          'username_claim' => 'preferred_username', 'type' => 'openid',
        },
      )
      realms.each_value do |realm|
        expect(realm).not_to have_key('bind_password')
        expect(realm).not_to have_key('client_key')
      end
    end

    it 'imports the singleton node config and notes' do
      expect(data['proxmox_datacenter_manager::resources::node_config']).to eq(
        'localhost' => { 'ensure' => 'present', 'email_from' => 'pdm@example.com', 'http_proxy' => 'http://proxy:3128' },
      )
      expect(data['proxmox_datacenter_manager::resources::notes']).to eq(
        'global' => { 'ensure' => 'present', 'notes' => 'Managed by Puppet' },
      )
    end
  end

  describe 'empty collections' do
    let(:data) do
      stub_get(base_url, '/remotes/remote', [], headers)
      stub_get(base_url, '/access/users', [], headers)
      stub_get(base_url, '/config/views', [], headers)
      stub_get(base_url, '/access/acl', [], headers)
      stub_get(base_url, '/access/users', [], headers, query: { 'include_tokens' => 'true' })
      stub_get(base_url, '/config/access/ldap', [], headers)
      stub_get(base_url, '/config/access/ad', [], headers)
      stub_get(base_url, '/config/access/openid', [], headers)
      stub_get(base_url, '/nodes/localhost/config', nil, headers)
      stub_get(base_url, '/config/notes', nil, headers)
      YAML.safe_load(run_tool(tool_path, default_argv, default_env), permitted_classes: [Symbol])
    end

    it 'omits sections for empty resource collections' do
      ['remotes', 'users', 'views', 'acls', 'api_tokens', 'realms'].each do |resource|
        expect(data).not_to have_key("proxmox_datacenter_manager::resources::#{resource}")
      end
    end

    it 'still emits the always-present singleton sections' do
      expect(data['proxmox_datacenter_manager::resources::node_config']).to eq('localhost' => { 'ensure' => 'present' })
      expect(data['proxmox_datacenter_manager::resources::notes']).to eq('global' => { 'ensure' => 'present', 'notes' => '' })
    end
  end

  describe 'TLS settings' do
    it 'verifies certificates and sets the CA file by default unless disabled' do
      stub_default_endpoints(base_url, headers)
      http = nil
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        http = original.call(*args)
      end

      run_tool(tool_path, default_argv + ['--ssl-ca-file', '/etc/ssl/pdm-ca.pem'], default_env)

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
      expect(http.ca_file).to eq('/etc/ssl/pdm-ca.pem')
    end

    it 'disables verification when --no-ssl-verify is given' do
      stub_default_endpoints(base_url, headers)
      http = nil
      allow(Net::HTTP).to receive(:new).and_wrap_original do |original, *args|
        http = original.call(*args)
      end

      run_tool(tool_path, default_argv + ['--no-ssl-verify'], default_env)

      expect(http.verify_mode).to eq(OpenSSL::SSL::VERIFY_NONE)
    end
  end

  describe 'output-file handling' do
    it 'prints YAML to stdout when --output is omitted' do
      stub_default_endpoints(base_url, headers)
      output = run_tool(tool_path, default_argv, default_env)
      expect(YAML.safe_load(output, permitted_classes: [Symbol])).to have_key('proxmox_datacenter_manager::resources::remotes')
    end

    it 'writes YAML to the given file and prints nothing when --output is set' do
      stub_default_endpoints(base_url, headers)
      file = Tempfile.new('pdm-hiera-import')
      path = file.path
      file.close
      File.delete(path)

      begin
        output = run_tool(tool_path, default_argv + ['--output', path], default_env)
        expect(output).to eq('')
        expect(YAML.safe_load_file(path, permitted_classes: [Symbol])).to have_key('proxmox_datacenter_manager::resources::remotes')
      ensure
        File.delete(path) if File.exist?(path)
      end
    end
  end
end
