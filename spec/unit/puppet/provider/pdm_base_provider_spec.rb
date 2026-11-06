# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_base_provider'
require 'tempfile'

class Puppet::Provider::PdmBootstrapTestProvider < Puppet::Provider::PdmBaseProvider
  attr_reader :updated

  def get(_context)
    [{ tokenid: 'existing', ensure: 'present', enable: false }]
  end

  def update(_context, name, should)
    @updated = [name, should]
  end
end

RSpec.describe Puppet::Provider::PdmBaseProvider do
  # A minimal concrete provider exercising the shared mapping helpers.
  subject(:provider) { provider_class.new }

  let(:provider_class) do
    Class.new(described_class) do
      def self.attribute_map
        { 'comment' => :comment, 'enable' => :enable, 'tokenid' => :tokenid, 'delete' => :delete_properties }
      end

      def self.boolean_attributes
        [:enable]
      end
    end
  end
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:tokenid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, debug: nil) }

  describe '.config_path' do
    it 'is located in the confdir' do
      expect(described_class.config_path).to eq(File.join(Puppet.settings[:confdir], 'pdm_transport.yaml'))
    end
  end

  describe '.build_transport' do
    it 'loads the YAML config with symbol keys and builds a transport' do
      config = Tempfile.new(['pdm_transport', '.yaml'])
      begin
        config.write({ 'host' => 'pdm.example.com', 'token_id' => 'user@pdm', 'token_secret' => 'secret' }.to_yaml)
        config.close
        allow(described_class).to receive(:config_path).and_return(config.path)

        transport = described_class.build_transport(context)

        expect(transport).to be_a(Puppet::Transport::ProxmoxDatacenterManager)
        expect(transport.instance_variable_get(:@host)).to eq('pdm.example.com')
        expect(transport.instance_variable_get(:@token_id)).to eq('user@pdm')
      ensure
        config.unlink
      end
    end

    it 'raises a ResourceError when the config file is missing' do
      allow(described_class).to receive(:config_path).and_return('/nonexistent/pdm_transport.yaml')

      expect { described_class.build_transport(context) }.to raise_error(
        Puppet::ResourceError, %r{PDM transport config not found at /nonexistent/pdm_transport\.yaml}
      )
    end

    it 'propagates errors for malformed YAML config' do
      config = Tempfile.new(['pdm_transport', '.yaml'])
      begin
        config.write("host: [unterminated\n")
        config.close
        allow(described_class).to receive(:config_path).and_return(config.path)

        expect { described_class.build_transport(context) }.to raise_error(Psych::SyntaxError)
      ensure
        config.unlink
      end
    end
  end

  describe '#pdm_transport' do
    it 'memoizes the transport built from the class configuration' do
      transport = instance_double('Puppet::Transport::ProxmoxDatacenterManager')
      expect(provider_class).to receive(:build_transport).with(context).once.and_return(transport)

      expect(provider.pdm_transport(context)).to be(transport)
      expect(provider.pdm_transport(context)).to be(transport)
    end
  end

  describe '#pdm_to_puppet' do
    it 'maps known PDM keys, ignores unknown ones, and converts booleans' do
      result = provider.pdm_to_puppet('comment' => 'hi', 'enable' => 1, 'tokenid' => 'user@pdm!ci', 'extra' => 'ignored')

      expect(result).to eq(comment: 'hi', enable: true, tokenid: 'user@pdm!ci')
    end

    it 'omits attributes PDM does not return' do
      expect(provider.pdm_to_puppet('tokenid' => 'x')).to eq(tokenid: 'x')
    end

    it 'normalizes boolean-like values and leaves others untouched' do
      expect(provider.pdm_to_puppet('enable' => '1', 'tokenid' => 'x')[:enable]).to be(true)
      expect(provider.pdm_to_puppet('enable' => '0', 'tokenid' => 'x')[:enable]).to be(false)
      expect(provider.pdm_to_puppet('enable' => 'maybe', 'tokenid' => 'x')[:enable]).to eq('maybe')
    end
  end

  describe '#puppet_to_pdm' do
    it 'maps known puppet keys to PDM keys and skips unmapped ones' do
      expect(provider.puppet_to_pdm(comment: 'hi', enable: true, tokenid: 'x', other: 'ignored'))
        .to eq('comment' => 'hi', 'enable' => true, 'tokenid' => 'x')
    end

    it 'skips nil values' do
      expect(provider.puppet_to_pdm(comment: nil, tokenid: 'x')).to eq('tokenid' => 'x')
    end

    it 'passes the literal string absent through as a value' do
      expect(provider.puppet_to_pdm(comment: 'absent', tokenid: 'x')).to eq('comment' => 'absent', 'tokenid' => 'x')
    end

    it 'unwraps Sensitive values before sending them' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('s3cr3t')
      expect(provider.puppet_to_pdm(comment: sensitive, tokenid: 'x')).to eq('comment' => 's3cr3t', 'tokenid' => 'x')
    end

    it 'converts boolean attributes to API booleans' do
      expect(provider.puppet_to_pdm(enable: 'true', tokenid: 'x')).to eq('enable' => true, 'tokenid' => 'x')
    end
  end

  describe '#create_request_body' do
    it 'drops ensure and maps the remaining attributes to PDM keys' do
      expect(provider.create_request_body(ensure: 'present', comment: 'hi', tokenid: 'user@pdm!ci'))
        .to eq('comment' => 'hi', 'tokenid' => 'user@pdm!ci')
    end

    it 'never sends a delete parameter even when delete_properties are declared' do
      body = provider.create_request_body(ensure: 'present', tokenid: 'x', delete_properties: ['comment', 'enable'])

      expect(body).not_to have_key('delete')
    end
  end

  describe '#update_request_body' do
    it 'drops ensure and namevars' do
      body = provider.update_request_body(context, { ensure: 'present', tokenid: 'user@pdm!ci', enable: true })

      expect(body).to eq('enable' => true)
    end

    it 'sends delete_properties as the PDM delete list' do
      body = provider.update_request_body(context, { ensure: 'present', tokenid: 'x', delete_properties: ['comment', 'enable'] })

      expect(body).to eq('delete' => ['comment', 'enable'])
    end

    it 'omits the delete key when nothing needs deleting' do
      body = provider.update_request_body(context, { ensure: 'present', tokenid: 'user@pdm!ci', comment: 'hi' })

      expect(body).to eq('comment' => 'hi')
    end
  end

  describe '#insync? for delete_properties' do
    it 'requests deletion only while the targeted property still exists' do
      should = { delete_properties: ['comment'] }
      expect(provider.insync?(context, 'x', :delete_properties, { comment: 'hi' }, should)).to be(false)
      expect(provider.insync?(context, 'x', :delete_properties, {}, should)).to be(true)
    end

    it 'rejects deletion of properties the provider cannot observe' do
      expect {
        provider.insync?(context, 'x', :delete_properties, {}, delete_properties: ['unknown'])
      }.to raise_error(Puppet::ResourceError, %r{Cannot observe deleted PDM properties: unknown})
    end

    it 'falls back to the default comparison for ordinary properties' do
      expect(provider.insync?(context, 'x', :comment, { comment: 'a' }, comment: 'b')).to be_nil
    end
  end

  describe '#pdm_path' do
    it 'expands placeholders and escapes special characters' do
      expect(provider.pdm_path('/access/users/{userid}/token/{token-name}', userid: 'user?name@pdm', 'token-name': 'token#name'))
        .to eq('/access/users/user%3Fname%40pdm/token/token%23name')
    end

    it 'returns the path unchanged when there are no placeholders' do
      expect(provider.pdm_path('/config/notes')).to eq('/config/notes')
    end
  end

  describe 'transport bootstrap' do
    it 'treats a missing managed transport config as empty during discovery' do
      allow(provider_class).to receive(:build_transport).with(context)
                                                        .and_raise(Puppet::ResourceError, 'PDM transport config not found at /tmp/pdm_transport.yaml; apply class')

      expect(provider.transport_get(context, '/access/users')).to eq([])
    end

    it 'refreshes actual state before applying changes after first-run bootstrap' do
      bootstrap_provider = Puppet::Provider::PdmBootstrapTestProvider.new
      bootstrap_provider.instance_variable_set(:@transport_config_missing, true)
      bootstrap_type = instance_double(
        'Puppet::ResourceApi::Type',
        namevars: [:tokenid],
        ensurable?: true,
        feature?: false,
        attributes: {},
      )
      bootstrap_context = instance_double('Puppet::ResourceApi::BaseContext', type: bootstrap_type)
      allow(bootstrap_context).to receive(:updating).and_yield
      allow(bootstrap_context).to receive(:creating).and_yield
      allow(bootstrap_context).to receive(:deleting).and_yield
      allow(bootstrap_type).to receive(:check_schema)

      bootstrap_provider.set(
        bootstrap_context,
        'existing' => { should: { tokenid: 'existing', ensure: 'present', enable: true } },
      )

      expect(bootstrap_provider.updated).to eq(['existing', { tokenid: 'existing', ensure: 'present', enable: true }])
    end
  end

  describe 'secret comparison' do
    subject(:secret_provider) { secret_provider_class.new }

    let(:secret_provider_class) do
      Class.new(described_class) do
        attr_accessor :stored

        def self.secret_attributes
          [:token]
        end

        def stored_secret(_title, _attribute_name)
          stored
        end
      end
    end
    let(:store) { PuppetX::ProxmoxDatacenterManager::SecretStore }

    before(:each) { allow(store).to receive(:available?).and_return(true) }

    # nil is the Resource API contract for "I do not handle this property";
    # collapsing it to false would break every ordinary attribute.
    it 'declines attributes it does not own' do
      expect(secret_provider.insync?(context, 'Example', :authid, {}, { authid: 'x' })).to be_nil
    end

    it 'treats an undeclared secret as in sync' do
      expect(secret_provider.insync?(context, 'Example', :token, {}, {})).to be(true)
    end

    it 'is in sync when the stored secret matches the declared one' do
      secret_provider.stored = 'sekrit'
      expect(secret_provider.insync?(context, 'Example', :token, {}, { token: 'sekrit' })).to be(true)
    end

    it 'unwraps a Sensitive declared value before comparing' do
      secret_provider.stored = 'sekrit'
      declared = Puppet::Pops::Types::PSensitiveType::Sensitive.new('sekrit')
      expect(secret_provider.insync?(context, 'Example', :token, {}, { token: declared })).to be(true)
    end

    it 'reports drift when the stored secret differs' do
      secret_provider.stored = 'stale'
      expect(secret_provider.insync?(context, 'Example', :token, {}, { token: 'sekrit' })).to eq([false, 'changed to the configured secret'])
    end

    it 'reports drift when PDM holds no secret at all' do
      secret_provider.stored = nil
      expect(secret_provider.insync?(context, 'Example', :token, {}, { token: 'sekrit' })).to eq([false, 'changed to the configured secret'])
    end

    # The change message must carry no value, so a real rotation cannot leak
    # the secret into the log even before Puppet's own redaction applies.
    it 'never names the secret in the change message' do
      secret_provider.stored = 'stale'
      _insync, message = secret_provider.insync?(context, 'Example', :token, {}, { token: 'sekrit' })
      expect(message).not_to include('sekrit', 'stale')
    end

    # Fail closed: reporting in sync for a value we cannot see would silently
    # disable enforcement, which is the bug this mechanism removes.
    it 'raises rather than assuming a match when the store cannot be read' do
      allow(store).to receive(:available?).and_return(false)
      expect { secret_provider.insync?(context, 'Example', :token, {}, { token: 'sekrit' }) }
        .to raise_error(Puppet::ResourceError, %r{Cannot verify 'token'})
    end

    it 'refuses to guess for a provider that declares secrets without a reader' do
      incomplete_class = Class.new(described_class) do
        def self.secret_attributes
          [:token]
        end
      end

      expect { incomplete_class.new.insync?(context, 'Example', :token, {}, { token: 'sekrit' }) }
        .to raise_error(NotImplementedError, %r{stored_secret})
    end
  end

  describe '#secret_placeholder' do
    subject(:secret_provider) { secret_provider_class.new }

    let(:secret_provider_class) do
      Class.new(described_class) do
        attr_accessor :stored, :raising

        def stored_secret(_title, _attribute_name)
          raise Puppet::ResourceError, 'boom' if raising

          stored
        end
      end
    end
    let(:store) { PuppetX::ProxmoxDatacenterManager::SecretStore }

    before(:each) { allow(store).to receive(:available?).and_return(true) }

    it 'reports a fixed placeholder when PDM holds a secret' do
      secret_provider.stored = 'sekrit'
      expect(secret_provider.secret_placeholder('Example', :token)).to eq('[secret managed]')
    end

    it 'reports nothing when PDM holds no secret' do
      secret_provider.stored = nil
      expect(secret_provider.secret_placeholder('Example', :token)).to be_nil
    end

    # get() runs during discovery for every resource in the catalog, including
    # ones managing no secrets, so it must not raise off a PDM node.
    it 'reports nothing rather than raising when the store is unavailable' do
      allow(store).to receive(:available?).and_return(false)
      expect(secret_provider.secret_placeholder('Example', :token)).to be_nil
    end

    it 'reports nothing rather than raising when the store cannot be read' do
      secret_provider.raising = true
      expect(secret_provider.secret_placeholder('Example', :token)).to be_nil
    end
  end
end
