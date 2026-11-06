# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_remote'

RSpec.describe 'pdm_remote type' do
  let(:type) { Puppet::Type.type(:pdm_remote) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :id as the namevar' do
    expect(type.key_attributes).to contain_exactly(:id)
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager')[:ensure]).to eq(:present)
    end

    it 'accepts absent' do
      expect(type.new(id: 'prod', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'type attribute' do
    it 'has behaviour :init_only (cannot change after creation)' do
      expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
    end

    ['pve', 'pbs'].each do |remote_type|
      it "accepts #{remote_type}" do
        expect { type.new(id: 'prod', type: remote_type, nodes: ['node01'], authid: 'pdm@x!y') }.not_to raise_error
      end
    end

    it 'rejects an unknown remote type' do
      expect { type.new(id: 'prod', type: 'vmware', nodes: ['node01'], authid: 'pdm@x!y') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'nodes attribute' do
    it 'accepts a non-empty array of strings' do
      resource = type.new(id: 'prod', type: 'pve', nodes: ['pve01', 'pve02'], authid: 'pdm@pve!manager')
      expect(resource[:nodes]).to eq(['pve01', 'pve02'])
    end

    it 'rejects an empty array' do
      expect { type.new(id: 'prod', type: 'pve', nodes: [], authid: 'pdm@pve!manager') }.to raise_error(Puppet::ResourceError)
    end
  end

  # Without custom_insync the provider's insync? hook is silently skipped
  # (resource_api/property.rb:28) and every secret comparison is ignored.
  it 'enables custom insync so secrets can be compared' do
    expect(type.type_definition.feature?('custom_insync')).to be(true)
  end

  describe 'token property' do
    it 'is a property so a rotation is detected and enforced' do
      expect(type.attrtype(:token)).to eq(:property)
    end

    it 'is marked sensitive' do
      expect(type.type_definition.attributes[:token][:sensitive]).to be(true)
    end

    it 'accepts a plain String' do
      resource = type.new(id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager', token: 'hunter2')
      expect(resource[:token]).to eq('hunter2')
    end

    it 'accepts a Sensitive-wrapped String' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      resource = type.new(id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager', token: sensitive)
      expect(resource[:token]).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
    end
  end

  describe 'web_url attribute' do
    it 'accepts a URL' do
      resource = type.new(id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager', web_url: 'https://pve.example.com:8006')
      expect(resource[:web_url]).to eq('https://pve.example.com:8006')
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager') }

    [:token, :create_token, :web_url].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        id: 'prod', type: 'pve', nodes: ['pve01', 'pve02'], authid: 'pdm@pve!manager',
        token: 'hunter2', create_token: 'puppet', web_url: 'https://pve01:8006'
      )
    end

    it { expect(resource[:id]).to eq('prod') }
    it { expect(resource[:type]).to eq('pve') }
    it { expect(resource[:nodes]).to eq(['pve01', 'pve02']) }
    it { expect(resource[:authid]).to eq('pdm@pve!manager') }
    it { expect(resource[:create_token]).to eq('puppet') }
    it { expect(resource[:web_url]).to eq('https://pve01:8006') }
  end
end
