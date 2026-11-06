# frozen_string_literal: true

require 'puppet/resource_api'
require_relative 'pdm_sensitive_parameters'
require_relative 'pdm_transport_autorequire'

Puppet::ResourceApi.register_type(
  name: 'pdm_realm',
  features: ['custom_insync'],
  docs: <<~DOC,
    @summary Manages a PDM LDAP, Active Directory, or OpenID realm.

    Both realm secrets are compared on every run. `client_key` is returned by the API,
    so it needs no node access; `bind_password` is compared against
    `/etc/proxmox-datacenter-manager/access/ldap-passwords.json` and therefore requires
    the agent to run on the PDM node as root. See the README.

    @example Configure an LDAP realm
      pdm_realm { 'corp-ldap':
        ensure        => present,
        type          => 'ldap',
        server1       => 'ldap.example.com',
        base_dn       => 'dc=example,dc=com',
        user_attr     => 'uid',
        bind_dn       => 'cn=search,dc=example,dc=com',
        bind_password => Sensitive(lookup('pdm::ldap_bind_password')),
        mode          => 'ldap+starttls',
        verify        => true,
      }
  DOC
  attributes: {
    ensure: { type: 'Enum[present, absent]', default: 'present', desc: 'Whether the realm exists.' },
    realm: { type: 'String', behaviour: :namevar, desc: 'Realm identifier.' },
    type: {
      type: "Enum['ldap', 'ad', 'openid']",
      behaviour: :init_only,
      desc: 'Realm type. Cannot be changed after creation.',
    },
    comment: { type: 'Optional[String]', desc: 'Comment.' },
    default: { type: 'Optional[Boolean]', desc: 'Whether this is the default login realm.' },
    server1: { type: 'Optional[String]', desc: 'Primary LDAP/AD server.' },
    server2: { type: 'Optional[String]', desc: 'Fallback LDAP/AD server.' },
    port: { type: 'Optional[Integer]', desc: 'LDAP/AD server port.' },
    bind_dn: { type: 'Optional[String]', desc: 'LDAP bind DN.' },
    bind_password: {
      type: 'Optional[Variant[String, Sensitive[String]]]',
      sensitive: true,
      desc: 'LDAP/AD bind password. Compared against ldap-passwords.json on the PDM node and re-sent when it differs.',
    },
    mode: { type: "Optional[Enum['ldap', 'ldap+starttls', 'ldaps']]", desc: 'LDAP connection mode.' },
    verify: { type: 'Optional[Boolean]', desc: 'Verify the LDAP server certificate.' },
    capath: { type: 'Optional[String]', desc: 'CA certificate or directory.' },
    filter: { type: 'Optional[String]', desc: 'LDAP user filter.' },
    sync_defaults_options: { type: 'Optional[String]', desc: 'Sync defaults.' },
    sync_attributes: { type: 'Optional[String]', desc: 'Attribute mapping.' },
    user_classes: { type: 'Optional[String]', desc: 'Comma-separated LDAP user object classes.' },
    base_dn: { type: 'Optional[String]', desc: 'LDAP/AD base DN.' },
    user_attr: { type: 'Optional[String]', desc: 'LDAP username attribute.' },
    issuer_url: { type: 'Optional[String]', desc: 'OpenID issuer URL.' },
    client_id: { type: 'Optional[String]', desc: 'OpenID client ID.' },
    client_key: {
      type: 'Optional[Variant[String, Sensitive[String]]]',
      sensitive: true,
      desc: 'OpenID client secret. PDM returns it verbatim, so drift is detected over the API without node access.',
    },
    username_claim: {
      type: 'Optional[String]',
      behaviour: :init_only,
      desc: 'OpenID username claim. PDM only accepts it during realm creation.',
    },
    autocreate: { type: 'Optional[Boolean]', desc: 'Automatically create OpenID users.' },
    scopes: { type: 'Optional[String]', desc: 'OpenID scopes.' },
    prompt: { type: 'Optional[String]', desc: 'OpenID prompt.' },
    acr_values: { type: 'Optional[String]', desc: 'OpenID ACR values.' },
    audiences: { type: 'Optional[String]', desc: 'OpenID audiences.' },
    delete_properties: { type: 'Optional[Array[String]]', desc: 'PDM API property names to remove during an update.' },
  },
)

Puppet::Type::PdmTransportAutorequire.register(:pdm_realm)
Puppet::Type::PdmSensitiveParameters.register(:pdm_realm)
