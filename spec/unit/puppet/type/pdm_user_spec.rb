# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_user'

RSpec.describe 'pdm_user type' do
  let(:type) { Puppet::Type.type(:pdm_user) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :userid as the namevar' do
    expect(type.key_attributes).to contain_exactly(:userid)
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(userid: 'automation@pdm')[:ensure]).to eq(:present)
    end

    it 'accepts absent' do
      expect(type.new(userid: 'automation@pdm', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'enable attribute' do
    it 'defaults to true' do
      expect(type.new(userid: 'automation@pdm')[:enable]).to eq(:true)
    end

    it 'accepts false' do
      expect(type.new(userid: 'automation@pdm', enable: false)[:enable]).to eq(:false)
    end
  end

  # Without custom_insync the provider's insync? hook is silently skipped
  # (resource_api/property.rb:28) and every secret comparison is ignored.
  it 'enables custom insync so secrets can be compared' do
    expect(type.type_definition.feature?('custom_insync')).to be(true)
  end

  describe 'password property' do
    it 'is a property so a rotation is detected and enforced' do
      expect(type.attrtype(:password)).to eq(:property)
    end

    it 'is marked sensitive' do
      expect(type.type_definition.attributes[:password][:sensitive]).to be(true)
    end

    it 'accepts a plain String' do
      resource = type.new(userid: 'automation@pdm', password: 'hunter2')
      expect(resource[:password]).to eq('hunter2')
    end

    it 'accepts a Sensitive-wrapped String' do
      sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
      resource = type.new(userid: 'automation@pdm', password: sensitive)
      expect(resource[:password]).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
    end
  end

  describe 'delete_properties attribute' do
    it 'accepts PDM API property names to remove' do
      expect(type.new(userid: 'automation@pdm', delete_properties: ['comment', 'email'])[:delete_properties]).to eq(['comment', 'email'])
    end

    it 'rejects a non-array value' do
      expect { type.new(userid: 'automation@pdm', delete_properties: 'comment') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'expire attribute' do
    it 'accepts an integer Unix timestamp' do
      expect(type.new(userid: 'automation@pdm', expire: 0)[:expire]).to eq(0)
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(userid: 'automation@pdm') }

    [:comment, :email, :expire, :firstname, :lastname, :password].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        userid: 'automation@pdm', comment: 'CI automation', email: 'auto@example.com', enable: true,
        expire: 0, firstname: 'Auto', lastname: 'Mation', password: 'hunter2'
      )
    end

    it { expect(resource[:userid]).to eq('automation@pdm') }
    it { expect(resource[:comment]).to eq('CI automation') }
    it { expect(resource[:email]).to eq('auto@example.com') }
    it { expect(resource[:enable]).to eq(:true) }
    it { expect(resource[:expire]).to eq(0) }
    it { expect(resource[:firstname]).to eq('Auto') }
    it { expect(resource[:lastname]).to eq('Mation') }
    it { expect(resource[:password]).to eq('hunter2') }
  end
end
