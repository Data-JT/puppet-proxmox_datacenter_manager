# frozen_string_literal: true

require 'spec_helper'
require 'puppet_x/proxmox_datacenter_manager/crypt'

RSpec.describe PuppetX::ProxmoxDatacenterManager::Crypt do
  # Generated with crypt_gensalt on a glibc/libxcrypt host. PDM 1.1.1 writes
  # yescrypt; the SHA-256 hash proves the helper does not depend on that.
  YESCRYPT_HASH = '$y$j9T$n/LNXBLMgFrQkJqMn34Po/$zQdXAUX7H8xv2LzjQOFsT3SKk5gumoqKc6t0.fhRZe7'
  SHA256_HASH = '$5$specsalt$RHv8wmcaZ1HC0o1ujDNMZ8.DWJbpyx3Jdh6uvg4Abv9'

  describe '.verify' do
    it 'accepts the password behind a yescrypt hash' do
      expect(described_class.verify('correct horse', YESCRYPT_HASH)).to be(true)
    end

    it 'rejects a different password' do
      expect(described_class.verify('wrong horse', YESCRYPT_HASH)).to be(false)
    end

    it 'accepts the password behind a SHA-256 crypt hash' do
      expect(described_class.verify('correct horse', SHA256_HASH)).to be(true)
    end

    it 'reports drift rather than raising on a malformed hash' do
      expect(described_class.verify('correct horse', '$z$not-a-scheme')).to be(false)
    end

    it 'reports drift for an empty stored hash' do
      expect(described_class.verify('correct horse', '')).to be(false)
    end

    it 'reports drift when no hash is stored' do
      expect(described_class.verify('correct horse', nil)).to be(false)
    end
  end
end
