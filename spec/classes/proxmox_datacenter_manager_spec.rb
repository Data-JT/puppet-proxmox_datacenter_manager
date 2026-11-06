# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'proxmox_datacenter_manager', type: :class do
  let(:default_config_file) { File.join(Puppet.settings[:confdir], 'pdm_transport.yaml') }
  let(:params) do
    {
      token_id: 'root@pam!puppet',
      token_secret: sensitive('supersecret'),
    }
  end

  it { is_expected.to compile.with_all_deps }

  it do
    is_expected.to contain_file(default_config_file).with(
      'ensure' => 'file',
      'owner' => 'root',
      'group' => 'root',
      'mode' => '0600',
    )
  end

  it 'marks the transport content sensitive' do
    expect(catalogue.resource('File', default_config_file).sensitive_parameters).to include(:content)
  end

  context 'with custom connection settings' do
    let(:params) do
      super().merge(host: 'pdm.example.com', port: 9443, ssl_verify: true, ssl_ca_file: '/etc/pdm-ca.pem')
    end

    it { is_expected.to compile.with_all_deps }
  end

  context 'with a custom config file' do
    let(:params) { super().merge(config_file: '/etc/puppetlabs/puppet/custom-pdm.yaml') }

    it { is_expected.to compile.with_all_deps }

    it do
      is_expected.to contain_file(default_config_file).with(
        'ensure' => 'link',
        'target' => '/etc/puppetlabs/puppet/custom-pdm.yaml',
      )
    end
  end

  # The default path follows the AGENT's confdir (fact), not the compiling
  # server's $settings::confdir: an AIO server compiling for a Debian agent
  # must not place the file, or a link, under /etc/puppetlabs/puppet there.
  context 'when the agent reports a different confdir than the server' do
    let(:facts) { {}.merge(proxmox_datacenter_manager_confdir: '/etc/puppet') }

    it { is_expected.to contain_file('/etc/puppet/pdm_transport.yaml').with('ensure' => 'file', 'mode' => '0600') }
    it { is_expected.not_to contain_file(default_config_file) }

    context 'with custom config_file' do
      let(:params) { super().merge(config_file: '/opt/pdm_transport.yaml') }

      it { is_expected.to contain_file('/etc/puppet/pdm_transport.yaml').with('ensure' => 'link', 'target' => '/opt/pdm_transport.yaml') }
      it { is_expected.not_to contain_file(default_config_file) }
    end
  end

  context 'with a malformed token_id' do
    let(:params) { super().merge(token_id: 'root-pam-puppet') }

    it { is_expected.to compile.and_raise_error(%r{token_id}) }
  end

  context 'with a relative ssl_ca_file' do
    let(:params) { super().merge(ssl_ca_file: 'certs/ca.crt') }

    it { is_expected.to compile.and_raise_error(%r{ssl_ca_file}) }
  end

  context 'with a relative config_file' do
    let(:params) { super().merge(config_file: 'relative/pdm_transport.yaml') }

    it { is_expected.to compile.and_raise_error(%r{config_file}) }
  end

  it 'enables TLS certificate verification by default' do
    content = catalogue.resource('File', default_config_file)[:content]
    expect(content).to include('ssl_verify: true')
  end
end
