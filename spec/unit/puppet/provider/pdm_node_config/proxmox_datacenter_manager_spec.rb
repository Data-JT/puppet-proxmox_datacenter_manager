# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_node_config/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmNodeConfig::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:node]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'sends delete_properties as the PDM delete list' do
    expect(transport).to receive(:put).with(
      context,
      '/nodes/localhost/config',
      { 'delete' => ['http-proxy'] },
    )
    provider.update(context, 'localhost', node: 'localhost', delete_properties: ['http-proxy'], ensure: 'present')
  end

  it 'discovers the singleton node config and omits unset settings' do
    allow(transport).to receive(:get).with(context, '/nodes/localhost/config').and_return(
      'email-from' => 'pdm@example.com', 'http-proxy' => 'http://proxy.example.com:3128',
    )

    expect(provider.get(context)).to eq(
      [
        {
          email_from: 'pdm@example.com', http_proxy: 'http://proxy.example.com:3128',
          ensure: 'present', node: 'localhost',
        },
      ],
    )
  end

  it 'reports an empty config as present with no settings' do
    allow(transport).to receive(:get).with(context, '/nodes/localhost/config').and_return(nil)

    expect(provider.get(context)).to eq(
      [
        { ensure: 'present', node: 'localhost' },
      ],
    )
  end

  it 'creates by delegating to update' do
    expect(transport).to receive(:put).with(context, '/nodes/localhost/config', { 'email-from' => 'pdm@example.com' })
    provider.create(context, 'localhost', node: 'localhost', email_from: 'pdm@example.com', ensure: 'present')
  end

  it 'treats ensure => absent as a no-op because PDM cannot delete the singleton' do
    expect(transport).not_to receive(:delete)
    expect(transport).not_to receive(:put)
    expect { provider.delete(context, 'localhost') }.not_to raise_error
  end
end
