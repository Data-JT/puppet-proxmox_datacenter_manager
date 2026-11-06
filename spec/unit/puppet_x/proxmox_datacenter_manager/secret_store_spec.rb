# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/proxmox_datacenter_manager/secret_store'
require 'tmpdir'

RSpec.describe PuppetX::ProxmoxDatacenterManager::SecretStore do
  around(:each) do |example|
    Dir.mktmpdir do |dir|
      described_class.config_dir = dir
      FileUtils.mkdir_p(File.join(dir, 'access'))
      @config_dir = dir
      example.run
    ensure
      described_class.config_dir = nil
    end
  end

  attr_reader :config_dir

  def write(relative_path, contents)
    path = File.join(config_dir, relative_path)
    File.write(path, contents)
    path
  end

  describe '.config_dir' do
    it 'defaults to PDM\'s configuration directory' do
      described_class.config_dir = nil
      expect(described_class.config_dir).to eq('/etc/proxmox-datacenter-manager')
    end
  end

  describe '.available?' do
    it 'is true when the configuration directory can be read' do
      expect(described_class).to be_available
    end

    it 'is false when the configuration directory is absent' do
      described_class.config_dir = File.join(config_dir, 'nope')
      expect(described_class).not_to be_available
    end
  end

  describe '.assert_available!' do
    it 'passes when the configuration directory can be read' do
      expect { described_class.assert_available!(:token) }.not_to raise_error
    end

    it 'names the attribute and the path when the store cannot be read' do
      described_class.config_dir = File.join(config_dir, 'nope')
      expect { described_class.assert_available!(:token) }
        .to raise_error(Puppet::ResourceError, %r{'token'.*#{Regexp.escape(config_dir)}/nope}m)
    end
  end

  describe '.remote_token' do
    # PDM writes the real token to remotes.shadow; remotes.cfg keeps a literal
    # '-' placeholder, so reading the wrong file reports permanent drift.
    let(:shadow) do
      <<~SHADOW
        pve: Example
        \ttoken pve-secret

        pbs: Backups
        \ttoken pbs-secret
      SHADOW
    end

    it 'reads the token of a pve remote' do
      write('remotes.shadow', shadow)
      expect(described_class.remote_token('Example')).to eq('pve-secret')
    end

    it 'reads the token of a pbs remote from the same file' do
      write('remotes.shadow', shadow)
      expect(described_class.remote_token('Backups')).to eq('pbs-secret')
    end

    it 'returns nil for a remote with no stored token' do
      write('remotes.shadow', shadow)
      expect(described_class.remote_token('Absent')).to be_nil
    end

    it 'returns nil when no remote has a stored token yet' do
      expect(described_class.remote_token('Example')).to be_nil
    end

    it 'ignores the placeholder in remotes.cfg' do
      write('remotes.cfg', "pve: Example\n\ttoken -\n")
      expect(described_class.remote_token('Example')).to be_nil
    end

    # A read failure that is not ENOENT must never be mistaken for "no secret
    # stored". Provoked with a directory rather than a mode-000 file so the
    # test holds when the suite runs as root, as it does in CI.
    it 'raises when the path exists but cannot be read' do
      FileUtils.mkdir_p(File.join(config_dir, 'remotes.shadow'))
      expect { described_class.remote_token('Example') }
        .to raise_error(Puppet::ResourceError, %r{Failed to read remotes\.shadow})
    end
  end

  describe '.realm_bind_password' do
    it 'reads the bind password of an ldap realm' do
      write('access/ldap-passwords.json', '{"corp-ldap":"s3cret"}')
      expect(described_class.realm_bind_password('corp-ldap')).to eq('s3cret')
    end

    it 'reads the bind password of an ad realm from the same store' do
      write('access/ldap-passwords.json', '{"corp-ad":"ad-s3cret"}')
      expect(described_class.realm_bind_password('corp-ad')).to eq('ad-s3cret')
    end

    it 'returns nil for a realm with no stored password' do
      write('access/ldap-passwords.json', '{"other":"s3cret"}')
      expect(described_class.realm_bind_password('corp-ldap')).to be_nil
    end

    # PDM leaves the file behind as {} once its last realm is deleted.
    it 'returns nil when the store has been emptied' do
      write('access/ldap-passwords.json', '{}')
      expect(described_class.realm_bind_password('corp-ldap')).to be_nil
    end

    it 'returns nil when no realm has ever stored a password' do
      expect(described_class.realm_bind_password('corp-ldap')).to be_nil
    end

    it 'raises when the store holds malformed JSON' do
      write('access/ldap-passwords.json', 'not json')
      expect { described_class.realm_bind_password('corp-ldap') }
        .to raise_error(Puppet::ResourceError, %r{Failed to parse .*ldap-passwords\.json})
    end

    it 'raises when the store holds valid JSON that is not an object' do
      write('access/ldap-passwords.json', '["corp-ldap"]')
      expect { described_class.realm_bind_password('corp-ldap') }
        .to raise_error(Puppet::ResourceError, %r{Unexpected content in .*ldap-passwords\.json})
    end
  end

  describe '.user_password_hash' do
    # shadow.json is keyed by the bare username with the realm stripped.
    it 'strips the realm from the user ID' do
      write('access/shadow.json', '{"puppet":"$y$hash"}')
      expect(described_class.user_password_hash('puppet@pdm')).to eq('$y$hash')
    end

    # PDM user names may contain dots, so the split must be on '@' only.
    it 'keeps dots in the user name' do
      write('access/shadow.json', '{"pdm.example.com":"$y$dotted"}')
      expect(described_class.user_password_hash('pdm.example.com@pdm')).to eq('$y$dotted')
    end

    it 'returns nil for a user with no password set' do
      write('access/shadow.json', '{"puppet":"$y$hash"}')
      expect(described_class.user_password_hash('other@pdm')).to be_nil
    end

    it 'returns nil when no user has a password set' do
      expect(described_class.user_password_hash('puppet@pdm')).to be_nil
    end
  end

  describe 'object name validation' do
    it 'refuses a remote ID containing a path separator' do
      expect { described_class.remote_token('../../etc/shadow') }
        .to raise_error(Puppet::ResourceError, %r{invalid PDM object name})
    end

    it 'refuses a realm containing a path separator' do
      expect { described_class.realm_bind_password('../secrets') }
        .to raise_error(Puppet::ResourceError, %r{invalid PDM object name})
    end
  end
end
