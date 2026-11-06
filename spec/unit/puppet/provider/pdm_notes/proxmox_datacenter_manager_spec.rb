# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_notes/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmNotes::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:name]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'reads the singleton notes resource' do
    allow(transport).to receive(:get).with(context, '/config/notes').and_return('Managed')
    expect(provider.get(context)).to eq([{ name: 'global', notes: 'Managed', ensure: 'present' }])
  end

  it 'updates the singleton notes resource' do
    expect(transport).to receive(:put).with(context, '/config/notes', { 'notes' => 'Managed' })
    provider.update(context, 'global', notes: 'Managed')
  end

  it 'reports empty notes as an empty string' do
    allow(transport).to receive(:get).with(context, '/config/notes').and_return(nil)
    expect(provider.get(context)).to eq([{ name: 'global', notes: '', ensure: 'present' }])
  end

  it 'creates by delegating to update' do
    expect(transport).to receive(:put).with(context, '/config/notes', { 'notes' => 'Managed' })
    provider.create(context, 'global', notes: 'Managed')
  end

  it 'treats ensure => absent as a no-op because PDM cannot delete the singleton' do
    expect(transport).not_to receive(:delete)
    expect(transport).not_to receive(:put)
    expect { provider.delete(context, 'global') }.not_to raise_error
  end
end
