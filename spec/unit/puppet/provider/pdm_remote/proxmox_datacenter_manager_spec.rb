# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_remote/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmRemote::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:id]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil) }
  let(:store) { PuppetX::ProxmoxDatacenterManager::SecretStore }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  def stub_remotes(remotes)
    allow(transport).to receive(:get).with(context, '/remotes/remote').and_return(remotes)
  end

  it 'maps PDM remotes without returning token secrets' do
    allow(store).to receive(:available?).and_return(false)
    stub_remotes([{ 'id' => 'prod', 'type' => 'pve', 'nodes' => ['pve01'], 'authid' => 'pdm@pve!manager', 'token' => 'hidden' }])

    expect(provider.get(context)).to contain_exactly(
      id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager', ensure: 'present',
    )
  end

  describe 'token drift detection' do
    before(:each) { allow(store).to receive(:available?).and_return(true) }

    # PDM's API declares it returns the token and then blanks it, so the value
    # in the response is never a usable comparison source.
    it 'reports a fixed placeholder rather than anything the API returned' do
      allow(store).to receive(:remote_token).with('prod').and_return('stored-secret')
      stub_remotes([{ 'id' => 'prod', 'type' => 'pve', 'nodes' => ['pve01'], 'authid' => 'pdm@pve!manager', 'token' => '' }])

      expect(provider.get(context).first[:token]).to eq('[secret managed]')
    end

    it 'omits the token when PDM holds none for the remote' do
      allow(store).to receive(:remote_token).with('prod').and_return(nil)
      stub_remotes([{ 'id' => 'prod', 'type' => 'pve', 'nodes' => ['pve01'], 'authid' => 'pdm@pve!manager', 'token' => '' }])

      expect(provider.get(context).first).not_to have_key(:token)
    end

    it 'is in sync when remotes.shadow holds the declared token' do
      allow(store).to receive(:remote_token).with('prod').and_return('sekrit')
      expect(provider.insync?(context, 'prod', :token, {}, { token: 'sekrit' })).to be(true)
    end

    it 'reports drift when remotes.shadow holds a different token' do
      allow(store).to receive(:remote_token).with('prod').and_return('rotated-away')
      expect(provider.insync?(context, 'prod', :token, {}, { token: 'sekrit' })).to eq([false, 'changed to the configured secret'])
    end
  end

  it 'posts API-shaped fields when creating a remote' do
    should = {
      id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager',
      token: Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret'), ensure: 'present',
    }
    expect(transport).to receive(:post).with(
      context,
      '/remotes/remote',
      hash_including('id' => 'prod', 'type' => 'pve', 'token' => 'secret'),
    )
    provider.create(context, 'prod', should)
  end

  it 'does not send immutable type and can send a replacement token during update' do
    should = {
      id: 'prod', type: 'pve', nodes: ['pve02'], authid: 'pdm@pve!manager',
      token: Puppet::Pops::Types::PSensitiveType::Sensitive.new('secret'), ensure: 'present',
    }
    expect(transport).to receive(:put) do |_context, path, body|
      expect(path).to eq('/remotes/remote/prod')
      expect(body).not_to include('type')
      expect(body).to include('nodes' => ['pve02'], 'token' => 'secret')
    end
    provider.update(context, 'prod', should)
  end

  it 'requires a token when creating a remote' do
    expect {
      provider.create(context, 'prod', id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve')
    }.to raise_error(Puppet::ResourceError, %r{requires token})
  end

  it 'sends delete_properties as the PDM delete list' do
    expect(transport).to receive(:put).with(
      context,
      '/remotes/remote/prod',
      { 'nodes' => ['pve01'], 'authid' => 'pdm@pve', 'delete' => ['web-url'] },
    )
    provider.update(
      context,
      'prod',
      id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve', delete_properties: ['web-url'], ensure: 'present',
    )
  end
end
