# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require 'puppet/provider/pdm_api_token/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmApiToken::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:tokenid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil, warning: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'stores the one-time generated secret with mode 0600' do
    secret_file = Tempfile.new('pdm-token')
    secret_path = secret_file.path
    secret_file.close
    allow(transport).to receive(:post).and_return('tokenid' => 'automation@pdm!ci', 'value' => 'generated-secret')

    provider.create(
      context,
      'automation@pdm!ci',
      tokenid: 'automation@pdm!ci', enable: true, secret_file: secret_path, ensure: 'present',
    )

    expect(File.read(secret_path)).to eq("generated-secret\n")
    expect(File.stat(secret_path).mode & 0o777).to eq(0o600)
  ensure
    File.delete(secret_path) if secret_path && File.exist?(secret_path)
  end

  it 'escapes user and token names in API paths' do
    expect(transport).to receive(:delete).with(context, '/access/users/user%3Fname%40pdm/token/token%23name')
    provider.delete(context, 'user?name@pdm!token#name')
  end

  it 'sends delete_properties as the PDM delete list' do
    expect(transport).to receive(:put).with(
      context,
      '/access/users/automation%40pdm/token/ci',
      { 'delete' => ['comment'] },
    )
    provider.update(
      context,
      'automation@pdm!ci',
      tokenid: 'automation@pdm!ci', delete_properties: ['comment'], ensure: 'present',
    )
  end

  it 'never sends a delete parameter on create' do
    expect(transport).to receive(:post).with(
      context,
      '/access/users/automation%40pdm/token/ci',
      { 'enable' => true },
    ).and_return(nil)
    provider.create(
      context,
      'automation@pdm!ci',
      tokenid: 'automation@pdm!ci', enable: true, delete_properties: ['comment'], ensure: 'present',
    )
  end

  it 'warns and discards the secret when no secret_file is configured' do
    allow(transport).to receive(:post).and_return('tokenid' => 'automation@pdm!ci', 'value' => 'generated-secret')
    expect(context).to receive(:warning).with(%r{secret_file is not configured})

    provider.create(context, 'automation@pdm!ci', tokenid: 'automation@pdm!ci', enable: true, ensure: 'present')
  end

  describe '#get' do
    it 'discovers tokens nested under each user' do
      allow(transport).to receive(:get).with(context, '/access/users').and_return(
        [{ 'userid' => 'automation@pdm' }, { 'userid' => 'user@pve' }],
      )
      allow(transport).to receive(:get).with(context, '/access/users/automation%40pdm/token').and_return(
        [{ 'tokenid' => 'automation@pdm!ci', 'comment' => 'CI', 'enable' => true }],
      )
      allow(transport).to receive(:get).with(context, '/access/users/user%40pve/token').and_return([])

      expect(provider.get(context)).to contain_exactly(
        tokenid: 'automation@pdm!ci', comment: 'CI', enable: true, ensure: 'present',
      )
    end

    it 'returns nothing when no users have tokens' do
      allow(transport).to receive(:get).with(context, '/access/users').and_return([{ 'userid' => 'user@pve' }])
      allow(transport).to receive(:get).with(context, '/access/users/user%40pve/token').and_return(nil)

      expect(provider.get(context)).to eq([])
    end
  end

  describe 'tokenid validation' do
    ['not-a-token-id', 'user@pdm', 'user@pdm!', '!ci'].each do |invalid|
      it "rejects #{invalid.inspect} as a malformed token ID" do
        expect { provider.delete(context, invalid) }
          .to raise_error(Puppet::ResourceError, %r{tokenid must be in user@realm!tokenname format, got: #{Regexp.escape(invalid.inspect)}})
      end
    end
  end
end
