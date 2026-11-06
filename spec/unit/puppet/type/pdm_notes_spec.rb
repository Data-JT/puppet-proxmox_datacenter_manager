# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_notes'

RSpec.describe 'pdm_notes type' do
  let(:type) { Puppet::Type.type(:pdm_notes) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :name as the namevar' do
    expect(type.key_attributes).to contain_exactly(:name)
  end

  describe 'name attribute' do
    it 'accepts the singleton title global' do
      expect { type.new(name: 'global', notes: 'hello') }.not_to raise_error
    end

    it 'rejects any other title' do
      expect { type.new(name: 'notes', notes: 'hello') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(name: 'global', notes: 'hello')[:ensure]).to eq(:present)
    end

    it 'accepts absent (a no-op for this always-present object)' do
      expect(type.new(name: 'global', notes: 'hello', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'notes attribute' do
    it 'is declared as a required (non-Optional) String' do
      expect(type.type_definition.attributes[:notes][:type]).to eq('String')
    end

    it 'accepts Markdown content' do
      resource = type.new(name: 'global', notes: "# Datacenter\n\nManaged by Puppet.\n")
      expect(resource[:notes]).to eq("# Datacenter\n\nManaged by Puppet.\n")
    end
  end
end
