# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_api_token'

RSpec.describe 'pdm_api_token type' do
  let(:type) { Puppet::Type.type(:pdm_api_token) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :tokenid as the namevar' do
    expect(type.key_attributes).to contain_exactly(:tokenid)
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(tokenid: 'automation@pdm!ci')[:ensure]).to eq(:present)
    end

    it 'accepts absent' do
      expect(type.new(tokenid: 'automation@pdm!ci', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'tokenid attribute' do
    it 'accepts user@realm!tokenname format' do
      expect { type.new(tokenid: 'automation@pdm!ci') }.not_to raise_error
    end
  end

  describe 'comment attribute' do
    it 'accepts a plain string' do
      expect(type.new(tokenid: 'automation@pdm!ci', comment: 'CI automation')[:comment]).to eq('CI automation')
    end
  end

  describe 'delete_properties attribute' do
    it 'accepts PDM API property names to remove' do
      expect(type.new(tokenid: 'automation@pdm!ci', delete_properties: ['comment'])[:delete_properties]).to eq(['comment'])
    end

    it 'rejects a non-array value' do
      expect { type.new(tokenid: 'automation@pdm!ci', delete_properties: 'comment') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'enable attribute' do
    it 'is nil when not set' do
      expect(type.new(tokenid: 'automation@pdm!ci')[:enable]).to be_nil
    end

    it 'accepts true and false' do
      expect(type.new(tokenid: 'automation@pdm!ci', enable: true)[:enable]).to eq(:true)
      expect(type.new(tokenid: 'automation@pdm!ci', enable: false)[:enable]).to eq(:false)
    end
  end

  describe 'expire attribute' do
    it 'accepts an integer Unix timestamp' do
      expect(type.new(tokenid: 'automation@pdm!ci', expire: 1_893_456_000)[:expire]).to eq(1_893_456_000)
    end

    it 'rejects a non-integer value' do
      expect { type.new(tokenid: 'automation@pdm!ci', expire: 'never') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'secret_file parameter' do
    it 'has behaviour :parameter' do
      expect(type.attrtype(:secret_file)).to eq(:param)
    end

    it 'accepts a path' do
      expect(type.new(tokenid: 'automation@pdm!ci', secret_file: '/etc/puppetlabs/puppet/pdm-ci.secret')[:secret_file])
        .to eq('/etc/puppetlabs/puppet/pdm-ci.secret')
    end
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(tokenid: 'automation@pdm!ci') }

    [:comment, :enable, :expire, :secret_file].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        tokenid: 'automation@pdm!ci', comment: 'CI automation', enable: true,
        expire: 1_893_456_000, secret_file: '/etc/puppetlabs/puppet/pdm-ci.secret'
      )
    end

    it { expect(resource[:tokenid]).to eq('automation@pdm!ci') }
    it { expect(resource[:comment]).to eq('CI automation') }
    it { expect(resource[:enable]).to eq(:true) }
    it { expect(resource[:expire]).to eq(1_893_456_000) }
    it { expect(resource[:secret_file]).to eq('/etc/puppetlabs/puppet/pdm-ci.secret') }
  end
end
