# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_view'

RSpec.describe 'pdm_view type' do
  let(:type) { Puppet::Type.type(:pdm_view) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :id as the namevar' do
    expect(type.key_attributes).to contain_exactly(:id)
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(id: 'production')[:ensure]).to eq(:present)
    end

    it 'accepts absent' do
      expect(type.new(id: 'production', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'include and exclude attributes' do
    [:include, :exclude].each do |attr|
      it "#{attr} accepts an array of strings" do
        resource = type.new(id: 'production', attr => ['remote=prod', 'remote=staging'])
        expect(resource[attr]).to eq(['remote=prod', 'remote=staging'])
      end

      it "#{attr} rejects the former absent sentinel" do
        expect { type.new(id: 'production', attr => 'absent') }.to raise_error(Puppet::ResourceError)
      end
    end
  end

  describe 'include_all attribute' do
    it 'accepts true and false' do
      expect(type.new(id: 'production', include_all: true)[:include_all]).to eq(:true)
      expect(type.new(id: 'production', include_all: false)[:include_all]).to eq(:false)
    end

    it 'rejects the former absent sentinel' do
      expect { type.new(id: 'production', include_all: 'absent') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'layout attribute' do
    it 'accepts a JSON string' do
      resource = type.new(id: 'production', layout: '{"rows":[]}')
      expect(resource[:layout]).to eq('{"rows":[]}')
    end
  end

  describe 'delete_properties attribute' do
    it 'accepts PDM API property names to remove' do
      expect(type.new(id: 'production', delete_properties: ['layout', 'include-all'])[:delete_properties]).to eq(['layout', 'include-all'])
    end

    it 'rejects a non-array value' do
      expect { type.new(id: 'production', delete_properties: 'comment') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(id: 'production') }

    [:include, :exclude, :include_all, :layout].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        id: 'production', include: ['remote=prod'], exclude: ['remote=staging'],
        include_all: false, layout: '{"rows":[]}'
      )
    end

    it { expect(resource[:id]).to eq('production') }
    it { expect(resource[:include]).to eq(['remote=prod']) }
    it { expect(resource[:exclude]).to eq(['remote=staging']) }
    it { expect(resource[:include_all]).to eq(:false) }
    it { expect(resource[:layout]).to eq('{"rows":[]}') }
  end
end
