# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_acl'

RSpec.describe 'pdm_acl type' do
  let(:type) { Puppet::Type.type(:pdm_acl) }

  def new_acl(path: '/', ugid: 'automation@pdm!ci', role: 'Auditor', **attrs)
    type.new(title: "#{path}|#{ugid}|#{role}", **attrs)
  end

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has acl_path, ugid, and role as namevars' do
    expect(type.key_attributes).to contain_exactly(:acl_path, :ugid, :role)
  end

  describe 'title_patterns' do
    it 'parses a pipe-separated title into all three namevars' do
      resource = type.new(title: '/vms|automation@pdm!ci|PVEVMUser')
      expect(resource[:acl_path]).to eq('/vms')
      expect(resource[:ugid]).to eq('automation@pdm!ci')
      expect(resource[:role]).to eq('PVEVMUser')
    end

    it 'rejects a title without three pipe-separated segments' do
      expect { type.new(title: '/vms|automation@pdm!ci') }.to raise_error(Puppet::Error, %r{No set of title patterns matched})
    end
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(new_acl[:ensure]).to eq(:present)
    end

    it 'accepts absent' do
      expect(new_acl(ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'ugid_type attribute' do
    it 'accepts user' do
      expect { new_acl(ugid_type: 'user') }.not_to raise_error
    end

    it 'accepts group' do
      expect { new_acl(ugid_type: 'group') }.not_to raise_error
    end

    it 'accepts token' do
      expect { new_acl(ugid_type: 'token') }.not_to raise_error
    end

    it 'is nil (inferred) when not set' do
      expect(new_acl[:ugid_type]).to be_nil
    end

    it 'rejects an unknown subject type' do
      expect { new_acl(ugid_type: 'service') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'role attribute' do
    it 'accepts an arbitrary free-form role name' do
      expect(new_acl(role: 'CustomRole')[:role]).to eq('CustomRole')
    end
  end

  describe 'propagate attribute' do
    it 'defaults to true' do
      expect(new_acl[:propagate]).to eq(:true)
    end

    it 'accepts false' do
      expect(new_acl(propagate: false)[:propagate]).to eq(:false)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) { type.new(title: '/vms|operators|Auditor', ugid_type: 'group', propagate: false) }

    it { expect(resource[:acl_path]).to eq('/vms') }
    it { expect(resource[:ugid]).to eq('operators') }
    it { expect(resource[:role]).to eq('Auditor') }
    it { expect(resource[:ugid_type]).to eq('group') }
    it { expect(resource[:propagate]).to eq(:false) }
  end
end
