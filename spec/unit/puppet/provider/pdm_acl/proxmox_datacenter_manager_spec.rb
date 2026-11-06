# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_acl/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmAcl::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', notice: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'uses PDM auth-id and role fields' do
    expect(transport).to receive(:put).with(
      context,
      '/access/acl',
      { 'path' => '/', 'auth-id' => 'automation@pdm!ci', 'role' => 'Auditor', 'propagate' => true },
    )
    provider.create(context, '/', acl_path: '/', ugid: 'automation@pdm!ci', role: 'Auditor', propagate: true)
  end

  it 'uses the group field for group ACLs' do
    expect(transport).to receive(:put).with(
      context,
      '/access/acl',
      { 'path' => '/', 'group' => 'operators', 'role' => 'Auditor', 'propagate' => true },
    )
    provider.create(
      context,
      '/',
      acl_path: '/', ugid: 'operators', ugid_type: 'group', role: 'Auditor', propagate: true,
    )
  end

  it 'preserves the returned subject type when deleting an ACL' do
    allow(transport).to receive(:get).and_return(
      [{ 'path' => '/', 'ugid' => 'operators', 'ugid_type' => 'group', 'roleid' => 'Auditor' }],
    )
    provider.get(context)

    expect(transport).to receive(:put).with(
      context,
      '/access/acl',
      { 'path' => '/', 'group' => 'operators', 'role' => 'Auditor', 'delete' => true },
    )
    provider.delete(context, acl_path: '/', ugid: 'operators', role: 'Auditor')
  end

  describe '#get' do
    it 'derives a pipe-separated title from path, subject, and role' do
      allow(transport).to receive(:get).with(context, '/access/acl').and_return(
        [
          { 'path' => '/', 'ugid' => 'operators', 'ugid_type' => 'group', 'roleid' => 'Auditor', 'propagate' => true },
          { 'path' => '/vms', 'ugid' => 'automation@pdm!ci', 'roleid' => 'PVEVMUser' },
        ],
      )

      result = provider.get(context)

      expect(result).to contain_exactly(
        hash_including(title: '/|operators|Auditor', acl_path: '/', ugid: 'operators', role: 'Auditor', ensure: 'present'),
        hash_including(title: '/vms|automation@pdm!ci|PVEVMUser', acl_path: '/vms', ugid: 'automation@pdm!ci', role: 'PVEVMUser'),
      )
    end

    it 'returns an empty list when PDM reports no ACL entries' do
      allow(transport).to receive(:get).with(context, '/access/acl').and_return(nil)
      expect(provider.get(context)).to eq([])
    end
  end

  describe '#update' do
    it 'delegates to create' do
      expect(transport).to receive(:put).with(
        context,
        '/access/acl',
        { 'path' => '/', 'auth-id' => 'automation@pdm!ci', 'role' => 'Auditor', 'propagate' => false },
      )
      provider.update(context, '/', acl_path: '/', ugid: 'automation@pdm!ci', role: 'Auditor', propagate: false)
    end
  end
end
