# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_view/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmView::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:id]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'omits fields PDM does not return' do
    allow(transport).to receive(:get).and_return([{ 'id' => 'production' }])

    expect(provider.get(context)).to contain_exactly(id: 'production', ensure: 'present')
  end

  it 'sends delete_properties as the PDM delete list' do
    expect(transport).to receive(:put).with(
      context,
      '/config/views/production',
      { 'include-all' => false, 'delete' => ['layout'] },
    )
    provider.update(context, 'production', id: 'production', include_all: false, delete_properties: ['layout'], ensure: 'present')
  end

  it 'posts API-shaped fields when creating a view' do
    expect(transport).to receive(:post).with(
      context,
      '/config/views',
      { 'id' => 'production', 'include' => ['remote=prod'], 'include-all' => false },
    )
    provider.create(context, 'production', id: 'production', include: ['remote=prod'], include_all: false, ensure: 'present')
  end

  it 'deletes a view by ID' do
    expect(transport).to receive(:delete).with(context, '/config/views/production')
    provider.delete(context, 'production')
  end
end
