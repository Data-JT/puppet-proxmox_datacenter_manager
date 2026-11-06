# frozen_string_literal: true

require 'spec_helper'
require 'puppet/provider/pdm_realm/proxmox_datacenter_manager'

RSpec.describe Puppet::Provider::PdmRealm::ProxmoxDatacenterManager do
  subject(:provider) { described_class.new }

  let(:transport) { instance_double('Puppet::Transport::ProxmoxDatacenterManager') }
  let(:type) { instance_double('Puppet::ResourceApi::Type', namevars: [:realm]) }
  let(:context) { instance_double('Puppet::ResourceApi::BaseContext', type: type, notice: nil) }

  before(:each) { allow(provider).to receive(:pdm_transport).and_return(transport) }

  it 'does not send the create-only username-claim during updates' do
    expect(transport).to receive(:put).with(
      context,
      '/config/access/openid/corp',
      { 'comment' => 'updated' },
    )
    provider.update(
      context,
      'corp',
      realm: 'corp', type: 'openid', username_claim: 'preferred_username', comment: 'updated', ensure: 'present',
    )
  end

  it 'sends delete_properties as the PDM delete list' do
    expect(transport).to receive(:put).with(
      context,
      '/config/access/ldap/corp',
      { 'delete' => ['bind-dn', 'filter'] },
    )
    provider.update(
      context,
      'corp',
      realm: 'corp', type: 'ldap', delete_properties: ['bind-dn', 'filter'], ensure: 'present',
    )
  end

  it 'never sends a delete parameter on create' do
    expect(transport).to receive(:post).with(
      context,
      '/config/access/ldap',
      { 'realm' => 'corp', 'server1' => 'ldap.example.com' },
    )
    provider.create(
      context,
      'corp',
      realm: 'corp', type: 'ldap', server1: 'ldap.example.com', delete_properties: ['comment'], ensure: 'present',
    )
  end

  it 'reports an unknown realm type when deleting before discovery' do
    expect { provider.delete(context, 'corp') }
      .to raise_error(Puppet::ResourceError, 'Unable to determine type for realm corp')
  end

  describe 'secret drift detection' do
    let(:store) { PuppetX::ProxmoxDatacenterManager::SecretStore }

    def discover(ldap: [], openid: [])
      allow(transport).to receive(:get).with(context, '/config/access/ldap').and_return(ldap)
      allow(transport).to receive(:get).with(context, '/config/access/ad').and_return([])
      allow(transport).to receive(:get).with(context, '/config/access/openid').and_return(openid)
      provider.get(context)
    end

    describe 'bind_password' do
      before(:each) { allow(store).to receive(:available?).and_return(true) }

      it 'reports a placeholder when the node holds a bind password' do
        allow(store).to receive(:realm_bind_password).with('corp').and_return('s3cret')
        result = discover(ldap: [{ 'realm' => 'corp', 'server1' => 'ldap.example.com' }])

        expect(result.first[:bind_password]).to eq('[secret managed]')
      end

      it 'is in sync when the node holds the declared bind password' do
        allow(store).to receive(:realm_bind_password).with('corp').and_return('s3cret')
        expect(provider.insync?(context, 'corp', :bind_password, {}, { bind_password: 's3cret' })).to be(true)
      end

      it 'reports drift when the node holds a different bind password' do
        allow(store).to receive(:realm_bind_password).with('corp').and_return('stale')
        expect(provider.insync?(context, 'corp', :bind_password, {}, { bind_password: 's3cret' }))
          .to eq([false, 'changed to the configured secret'])
      end

      it 'fails closed when the node store cannot be read' do
        allow(store).to receive(:available?).and_return(false)
        expect { provider.insync?(context, 'corp', :bind_password, {}, { bind_password: 's3cret' }) }
          .to raise_error(Puppet::ResourceError, %r{Cannot verify 'bind_password'})
      end
    end

    describe 'client_key' do
      # PDM returns the OpenID client secret verbatim, so this one needs no
      # node access at all. The store must never be consulted for it.
      before(:each) { allow(store).to receive(:available?).and_return(false) }

      it 'reports a placeholder rather than the value the API returned' do
        result = discover(openid: [{ 'realm' => 'corp-oidc', 'client-key' => 'oidc-secret' }])

        expect(result.first[:client_key]).to eq('[secret managed]')
      end

      it 'omits the client key when the realm has none' do
        result = discover(openid: [{ 'realm' => 'corp-oidc', 'issuer-url' => 'https://issuer.example.com' }])

        expect(result.first).not_to have_key(:client_key)
      end

      it 'is in sync when the API returns the declared client key' do
        discover(openid: [{ 'realm' => 'corp-oidc', 'client-key' => 'oidc-secret' }])

        expect(provider.insync?(context, 'corp-oidc', :client_key, {}, { client_key: 'oidc-secret' })).to be(true)
      end

      it 'reports drift when the API returns a different client key' do
        discover(openid: [{ 'realm' => 'corp-oidc', 'client-key' => 'rotated-away' }])

        expect(provider.insync?(context, 'corp-oidc', :client_key, {}, { client_key: 'oidc-secret' }))
          .to eq([false, 'changed to the configured secret'])
      end
    end
  end

  describe '#get' do
    it 'discovers realms across all types, and hides write-only secrets' do
      allow(PuppetX::ProxmoxDatacenterManager::SecretStore).to receive(:available?).and_return(false)
      allow(transport).to receive(:get).with(context, '/config/access/ldap').and_return(
        [{ 'realm' => 'corp', 'comment' => 'Corp LDAP', 'server1' => 'ldap.example.com', 'password' => 'hidden' }],
      )
      allow(transport).to receive(:get).with(context, '/config/access/ad').and_return([])
      allow(transport).to receive(:get).with(context, '/config/access/openid').and_return(
        [{ 'realm' => 'corp-oidc', 'issuer-url' => 'https://issuer.example.com', 'client-key' => 'hidden' }],
      )

      result = provider.get(context)

      ldap = result.find { |realm| realm[:realm] == 'corp' }
      expect(ldap).to include(type: 'ldap', ensure: 'present', comment: 'Corp LDAP')
      expect(ldap).not_to have_key(:server2)
      expect(ldap).not_to have_key(:bind_password)

      oidc = result.find { |realm| realm[:realm] == 'corp-oidc' }
      expect(oidc).to include(type: 'openid', ensure: 'present', issuer_url: 'https://issuer.example.com')
      expect(oidc).not_to have_key(:comment)
      expect(oidc[:client_key]).to eq('[secret managed]')
    end
  end

  describe '#create' do
    it 'requires a type when creating a realm' do
      expect { provider.create(context, 'corp', realm: 'corp', ensure: 'present') }
        .to raise_error(Puppet::ResourceError, 'pdm_realm requires type when ensure => present')
    end

    it 'posts to the type-specific endpoint without sending the immutable type field' do
      expect(transport).to receive(:post) do |_context, path, body|
        expect(path).to eq('/config/access/ldap')
        expect(body).to include('realm' => 'corp', 'server1' => 'ldap.example.com')
        expect(body).not_to have_key('type')
      end

      provider.create(context, 'corp', realm: 'corp', type: 'ldap', server1: 'ldap.example.com', ensure: 'present')
    end
  end

  describe '#delete' do
    it 'deletes a realm at the type-specific path discovered via get' do
      allow(transport).to receive(:get).with(context, '/config/access/ldap').and_return([{ 'realm' => 'corp' }])
      allow(transport).to receive(:get).with(context, '/config/access/ad').and_return([])
      allow(transport).to receive(:get).with(context, '/config/access/openid').and_return([])
      provider.get(context)

      expect(transport).to receive(:delete).with(context, '/config/access/ldap/corp')
      provider.delete(context, 'corp')
    end
  end
end
