# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_user/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmUser::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:userid]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'escapes user IDs and sends delete_properties as the PDM delete list' do
    expect(transport).to receive(:put).with(
      context,
      '/access/users/user%3Fname%40pdm',
      { 'delete' => ['comment', 'email'] },
    )
    provider.update(
      context,
      'user?name@pdm',
      userid: 'user?name@pdm', delete_properties: ['comment', 'email'], ensure: 'present',
    )
  end

  describe 'password drift detection' do
    # crypt(3) output for 'correct horse' under yescrypt, the scheme PDM 1.1.1
    # writes into access/shadow.json.
    let(:stored_hash) { '$y$j9T$n/LNXBLMgFrQkJqMn34Po/$zQdXAUX7H8xv2LzjQOFsT3SKk5gumoqKc6t0.fhRZe7' }
    let(:store) { PuppetX::ProxmoxDatacenterManager::SecretStore }

    before(:each) { allow(store).to receive(:available?).and_return(true) }

    it 'reports a placeholder rather than the stored hash' do
      allow(store).to receive(:user_password_hash).with('automation@pdm').and_return(stored_hash)
      allow(transport).to receive(:get).with(context, '/access/users')
                                       .and_return([{ 'userid' => 'automation@pdm', 'enable' => true }])

      expect(provider.get(context).first[:password]).to eq('[secret managed]')
    end

    it 'omits the password when the user has none set' do
      allow(store).to receive(:user_password_hash).with('automation@pdm').and_return(nil)
      allow(transport).to receive(:get).with(context, '/access/users')
                                       .and_return([{ 'userid' => 'automation@pdm', 'enable' => true }])

      expect(provider.get(context).first).not_to have_key(:password)
    end

    it 'is in sync when the declared password produced the stored hash' do
      allow(store).to receive(:user_password_hash).with('automation@pdm').and_return(stored_hash)
      expect(provider.insync?(context, 'automation@pdm', :password, {}, { password: 'correct horse' })).to be(true)
    end

    it 'reports drift when the declared password does not produce the stored hash' do
      allow(store).to receive(:user_password_hash).with('automation@pdm').and_return(stored_hash)
      expect(provider.insync?(context, 'automation@pdm', :password, {}, { password: 'wrong horse' }))
        .to eq([false, 'changed to the configured secret'])
    end

    it 'reports drift when the user has no password at all' do
      allow(store).to receive(:user_password_hash).with('automation@pdm').and_return(nil)
      expect(provider.insync?(context, 'automation@pdm', :password, {}, { password: 'correct horse' }))
        .to eq([false, 'changed to the configured secret'])
    end

    it 'fails closed when the node store cannot be read' do
      allow(store).to receive(:available?).and_return(false)
      expect { provider.insync?(context, 'automation@pdm', :password, {}, { password: 'correct horse' }) }
        .to raise_error(Puppet::ResourceError, %r{Cannot verify 'password'})
    end
  end
end
