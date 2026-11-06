# frozen_string_literal: true

# Registers the managed PDM transport file as an automatic dependency.
module Puppet::Type::PdmTransportAutorequire
  def self.register(type_name)
    Puppet::Type.type(type_name).autorequire(:file) do
      File.join(Puppet.settings[:confdir], 'pdm_transport.yaml')
    end
  end
end
