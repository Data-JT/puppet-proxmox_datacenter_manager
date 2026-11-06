# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_node_config'

RSpec.describe 'pdm_node_config type' do
  let(:type) { Puppet::Type.type(:pdm_node_config) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :node as the namevar' do
    expect(type.key_attributes).to contain_exactly(:node)
  end

  describe 'node attribute' do
    it 'accepts the singleton title localhost' do
      expect { type.new(node: 'localhost') }.not_to raise_error
    end

    it 'rejects any other title' do
      expect { type.new(node: 'pve01') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(node: 'localhost')[:ensure]).to eq(:present)
    end

    it 'accepts absent (a no-op for this always-present object)' do
      expect(type.new(node: 'localhost', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'optional attributes' do
    [:email_from, :http_proxy, :default_lang, :ciphers_tls_1_2, :ciphers_tls_1_3].each do |attr|
      it "#{attr} is nil when not set" do
        expect(type.new(node: 'localhost')[attr]).to be_nil
      end
    end
  end

  describe 'delete_properties attribute' do
    it 'accepts PDM API property names to remove' do
      expect(type.new(node: 'localhost', delete_properties: ['http-proxy'])[:delete_properties]).to eq(['http-proxy'])
    end

    it 'rejects a non-array value' do
      expect { type.new(node: 'localhost', delete_properties: 'http-proxy') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'all attributes are settable' do
    subject(:resource) do
      type.new(
        node: 'localhost',
        email_from: 'pdm@example.com',
        http_proxy: 'http://proxy.example.com:3128',
        default_lang: 'en',
        ciphers_tls_1_2: 'HIGH:!aNULL',
        ciphers_tls_1_3: 'TLS_AES_256_GCM_SHA384',
      )
    end

    it { expect(resource[:email_from]).to eq('pdm@example.com') }
    it { expect(resource[:http_proxy]).to eq('http://proxy.example.com:3128') }
    it { expect(resource[:default_lang]).to eq('en') }
    it { expect(resource[:ciphers_tls_1_2]).to eq('HIGH:!aNULL') }
    it { expect(resource[:ciphers_tls_1_3]).to eq('TLS_AES_256_GCM_SHA384') }
  end
end
