# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'proxmox_datacenter_manager::resources', type: :class do
  let(:params) do
    {
      remotes: {
        'production' => {
          'type' => 'pve',
          'nodes' => ['pve01.example.com'],
          'authid' => 'pdm@pve!manager',
          'token' => sensitive('secret'),
        },
      },
      realms: {
        'corp' => {
          'type' => 'ldap',
          'server1' => 'ldap.example.com',
          'base_dn' => 'dc=example,dc=com',
          'user_attr' => 'uid',
        },
      },
      users: {
        'automation@corp' => {
          'enable' => true,
        },
      },
      api_tokens: {
        'automation@corp!ci' => {
          'enable' => true,
        },
      },
      acls: {
        '/|automation@corp!ci|Auditor' => {
          'ugid_type' => 'token',
          'propagate' => true,
        },
      },
      views: {
        'production' => {
          'include' => ['remote=production'],
          'delete_properties' => ['layout'],
        },
      },
      notes: {
        'global' => {
          'notes' => 'Managed by Puppet',
        },
      },
    }
  end

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_pdm_remote('production').with_type('pve') }
  it { is_expected.to contain_pdm_view('production') }
  it { is_expected.to contain_pdm_notes('global') }
  it { is_expected.to contain_pdm_user('automation@corp').that_requires('Pdm_realm[corp]') }
  it { is_expected.to contain_pdm_api_token('automation@corp!ci').that_requires('Pdm_user[automation@corp]') }
  it { is_expected.to contain_pdm_acl('/|automation@corp!ci|Auditor').that_requires('Pdm_api_token[automation@corp!ci]') }
  it { is_expected.to contain_pdm_view('production').that_requires('Pdm_remote[production]') }
end
