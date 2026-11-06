# frozen_string_literal: true

require 'json'
require 'puppet'

# @api private
module PuppetX; end
# @api private
module PuppetX::ProxmoxDatacenterManager; end

# Read-only reader for the secrets PDM persists under
# /etc/proxmox-datacenter-manager.
#
# PDM's API withholds three of the four secrets this module manages: it blanks
# the remote token it claims to return, and never returns a realm bind
# password or a user password at all. It does write every one of them to the
# node, though -- two in plaintext and one as a crypt(3) hash. Reading them
# here is what makes drift detection possible.
#
# Two failure modes, deliberately distinguished:
#
#   * a missing file, or one holding no entry for the object -> nil
#   * a file that exists but cannot be read or parsed        -> raise
#
# Reporting "in sync" for a value that cannot be seen would silently disable
# enforcement, which is the exact bug this mechanism exists to remove. So the
# second case fails closed.
#
# ALWAYS require this file with `require_relative` from module code. Module
# lib/ is never on $LOAD_PATH inside puppetserver, so a bare require breaks
# type autoloading there.
#
# config_dir is writable purely as a test seam, so specs can point the store at
# a fixture tree instead of a real /etc/proxmox-datacenter-manager.
module PuppetX::ProxmoxDatacenterManager::SecretStore
  DEFAULT_CONFIG_DIR = '/etc/proxmox-datacenter-manager'
  # The real remote tokens. remotes.cfg keeps a literal '-' placeholder in its
  # own token field, so reading that file instead reports permanent drift.
  REMOTES_SHADOW = 'remotes.shadow'
  # One store shared by ldap and ad realms, keyed by the bare realm name.
  LDAP_PASSWORDS = 'access/ldap-passwords.json'
  # Keyed by the bare user name with the realm stripped.
  SHADOW = 'access/shadow.json'
  # PDM object names never contain a path separator. Anything that does is a
  # traversal attempt or a bug, and must not reach File.read.
  SAFE_NAME = %r{\A[^/\\\0]+\z}

  class << self
    attr_writer :config_dir

    def config_dir
      @config_dir || DEFAULT_CONFIG_DIR
    end

    # Non-raising probe. get() runs during discovery for every resource in the
    # catalog, including ones managing no secrets at all, so nothing on that
    # path may raise merely because the agent is not on a PDM node.
    def available?
      File.directory?(config_dir) && File.readable?(config_dir)
    end

    # Fail-closed guard, called from insync? and therefore only for attributes
    # actually being managed.
    def assert_available!(attribute_name)
      return if available?

      raise Puppet::ResourceError,
            "Cannot verify '#{attribute_name}': #{config_dir} is not readable. " \
            'Managing PDM secrets requires the Puppet agent to run on the PDM node as root.'
    end

    def remote_token(id)
      stored_token(read_file(REMOTES_SHADOW), safe(id))
    end

    def realm_bind_password(realm)
      json_entry(LDAP_PASSWORDS, safe(realm))
    end

    # shadow.json is keyed by the bare user name. PDM user names may contain
    # dots (pdm.example.com is real), so split on '@' and never on '.'.
    def user_password_hash(userid)
      username = userid.to_s.split('@').first.to_s
      return nil if username.empty?

      json_entry(SHADOW, username)
    end

    private

    def safe(name)
      value = name.to_s
      return value if SAFE_NAME.match?(value)

      raise Puppet::ResourceError, "invalid PDM object name: #{value.inspect}"
    end

    # nil means "PDM holds nothing here". A read error that is not ENOENT
    # (EACCES on a non-root agent, EIO on a failing disk) must not be mistaken
    # for that, so it raises.
    def read_file(relative_path)
      File.read(File.join(config_dir, relative_path))
    rescue Errno::ENOENT
      nil
    rescue SystemCallError => error
      raise Puppet::ResourceError, "Failed to read #{relative_path}: #{error.message}"
    end

    def json_entry(relative_path, key)
      contents = read_file(relative_path)
      return nil if contents.nil?

      parse_json(relative_path, contents)[key]
    end

    def parse_json(relative_path, contents)
      parsed = JSON.parse(contents)
      return parsed if parsed.is_a?(Hash)

      raise Puppet::ResourceError, "Unexpected content in #{relative_path}: expected a JSON object"
    rescue JSON::ParserError => error
      raise Puppet::ResourceError, "Failed to parse #{relative_path}: #{error.message}"
    end

    # PDM section config: a "<type>: <name>" header followed by indented
    # "<field> <value>" lines. A remote ID is unique across the pve and pbs
    # sections because it is the type's namevar, so the type is not needed to
    # find the right section. 'token' is the only field remotes.shadow holds.
    def stored_token(contents, name)
      return nil if contents.nil?

      section(contents, name).each do |line|
        field, value = line.strip.split(' ', 2)
        return value if field == 'token' && !value.nil?
      end
      nil
    end

    def section(contents, name)
      wanted = false
      contents.each_line.with_object([]) do |line, lines|
        if line.match?(%r{\A\S})
          wanted = line.strip.split(':', 2).last.to_s.strip == name
        elsif wanted
          lines << line
        end
      end
    end
  end
end
