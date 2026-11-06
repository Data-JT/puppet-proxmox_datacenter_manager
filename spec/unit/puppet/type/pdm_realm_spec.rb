# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/pdm_realm'

RSpec.describe 'pdm_realm type' do
  let(:type) { Puppet::Type.type(:pdm_realm) }

  it 'is registered with Puppet' do
    expect(type).not_to be_nil
  end

  it 'has :realm as the namevar' do
    expect(type.key_attributes).to contain_exactly(:realm)
  end

  describe 'ensure attribute' do
    it 'defaults to present' do
      expect(type.new(realm: 'corp', type: 'ldap')[:ensure]).to eq(:present)
    end

    it 'accepts absent' do
      expect(type.new(realm: 'corp', type: 'ldap', ensure: 'absent')[:ensure]).to eq(:absent)
    end
  end

  describe 'type attribute' do
    it 'has behaviour :init_only (cannot change after creation)' do
      expect(type.type_definition.attributes[:type][:behaviour]).to eq(:init_only)
    end

    ['ldap', 'ad', 'openid'].each do |realm_type|
      it "accepts #{realm_type}" do
        expect { type.new(realm: 'corp', type: realm_type) }.not_to raise_error
      end
    end

    it 'rejects an unknown realm type' do
      expect { type.new(realm: 'corp', type: 'radius') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'mode attribute' do
    ['ldap', 'ldap+starttls', 'ldaps'].each do |mode|
      it "accepts #{mode}" do
        expect { type.new(realm: 'corp', type: 'ldap', mode: mode) }.not_to raise_error
      end
    end

    it 'rejects an unsupported mode' do
      expect { type.new(realm: 'corp', type: 'ldap', mode: 'plain') }.to raise_error(Puppet::ResourceError)
    end
  end

  # Without custom_insync the provider's insync? hook is silently skipped
  # (resource_api/property.rb:28) and every secret comparison is ignored.
  it 'enables custom insync so secrets can be compared' do
    expect(type.type_definition.feature?('custom_insync')).to be(true)
  end

  describe 'sensitive secret properties' do
    [:bind_password, :client_key].each do |attr|
      it "#{attr} is a property so a rotation is detected and enforced" do
        expect(type.attrtype(attr)).to eq(:property)
      end

      it "#{attr} is marked sensitive" do
        expect(type.type_definition.attributes[attr][:sensitive]).to be(true)
      end

      it "#{attr} accepts a plain String" do
        resource = type.new(realm: 'corp', type: 'ldap', attr => 'hunter2')
        expect(resource[attr]).to eq('hunter2')
      end

      it "#{attr} accepts a Sensitive-wrapped String" do
        sensitive = Puppet::Pops::Types::PSensitiveType::Sensitive.new('hunter2')
        resource = type.new(realm: 'corp', type: 'ldap', attr => sensitive)
        expect(resource[attr]).to be_a(Puppet::Pops::Types::PSensitiveType::Sensitive)
      end
    end
  end

  describe 'username_claim attribute' do
    it 'has behaviour :init_only' do
      expect(type.type_definition.attributes[:username_claim][:behaviour]).to eq(:init_only)
    end
  end

  describe 'boolean attributes' do
    [:default, :verify, :autocreate].each do |attr|
      it "#{attr} accepts true and false" do
        expect(type.new(realm: 'corp', type: 'ldap', attr => true)[attr]).to eq(:true)
        expect(type.new(realm: 'corp', type: 'ldap', attr => false)[attr]).to eq(:false)
      end
    end
  end

  it 'rejects the former absent sentinel for port' do
    expect { type.new(realm: 'corp', type: 'ldap', port: 'absent') }.to raise_error(Puppet::ResourceError)
  end

  describe 'delete_properties attribute' do
    it 'accepts PDM API property names to remove' do
      expect(type.new(realm: 'corp', type: 'ldap', delete_properties: ['bind-dn', 'filter'])[:delete_properties]).to eq(['bind-dn', 'filter'])
    end

    it 'rejects a non-array value' do
      expect { type.new(realm: 'corp', type: 'ldap', delete_properties: 'comment') }.to raise_error(Puppet::ResourceError)
    end
  end

  describe 'LDAP realm' do
    subject(:resource) do
      type.new(
        realm: 'corp-ldap', type: 'ldap', server1: 'ldap.example.com', base_dn: 'dc=example,dc=com',
        user_attr: 'uid', bind_dn: 'cn=search,dc=example,dc=com', mode: 'ldap+starttls', verify: true
      )
    end

    it { expect(resource[:server1]).to eq('ldap.example.com') }
    it { expect(resource[:base_dn]).to eq('dc=example,dc=com') }
    it { expect(resource[:user_attr]).to eq('uid') }
    it { expect(resource[:bind_dn]).to eq('cn=search,dc=example,dc=com') }
    it { expect(resource[:mode]).to eq('ldap+starttls') }
    it { expect(resource[:verify]).to eq(:true) }
  end

  describe 'OpenID realm' do
    subject(:resource) do
      type.new(
        realm: 'corp-oidc', type: 'openid', issuer_url: 'https://issuer.example.com', client_id: 'pdm',
        username_claim: 'preferred_username', autocreate: true, scopes: 'openid email profile'
      )
    end

    it { expect(resource[:issuer_url]).to eq('https://issuer.example.com') }
    it { expect(resource[:client_id]).to eq('pdm') }
    it { expect(resource[:username_claim]).to eq('preferred_username') }
    it { expect(resource[:autocreate]).to eq(:true) }
    it { expect(resource[:scopes]).to eq('openid email profile') }
  end

  describe 'optional attributes default to nil' do
    subject(:resource) { type.new(realm: 'corp', type: 'ldap') }

    [:comment, :default, :server1, :server2, :port, :bind_dn, :bind_password, :mode, :verify, :capath, :filter, :sync_defaults_options, :sync_attributes, :user_classes, :base_dn, :user_attr,
     :issuer_url, :client_id, :client_key, :username_claim, :autocreate, :scopes, :prompt, :acr_values, :audiences].each do |attr|
      it "#{attr} is nil when not set" do
        expect(resource[attr]).to be_nil
      end
    end
  end
end
