# frozen_string_literal: true

require 'spec_helper'

# Puppet redacts a value in logs, in report events and in
# last_run_report.yaml only when the attribute instance reports #sensitive.
# Puppet::Type#set_sensitive_parameters derives that from #is_sensitive on the
# attribute class, which the Resource API never declares -- so a schema
# `sensitive: true` on its own leaks the value in full.
RSpec.describe 'Puppet::Type::PdmSensitiveParameters' do
  SENSITIVE_ATTRIBUTES = {
    pdm_realm: [:bind_password, :client_key],
    pdm_remote: [:token],
    pdm_user: [:password],
  }.freeze

  # Minimal valid declarations, so each type can be instantiated and the flag
  # checked on a real resource rather than only on the attribute class.
  MINIMAL_RESOURCES = {
    pdm_realm: { realm: 'corp', type: 'ldap', bind_password: 'x', client_key: 'y' },
    pdm_remote: { id: 'prod', type: 'pve', nodes: ['pve01'], authid: 'pdm@pve!manager', token: 'x' },
    pdm_user: { userid: 'automation@pdm', password: 'x' },
  }.freeze

  SENSITIVE_ATTRIBUTES.each do |type_name, attributes|
    describe type_name.to_s do
      let(:type) { Puppet::Type.type(type_name) }
      let(:resource) { type.new(MINIMAL_RESOURCES.fetch(type_name)) }

      attributes.each do |attribute|
        it "marks #{attribute} sensitive on the attribute class" do
          expect(type.attrclass(attribute).method_defined?(:is_sensitive)).to be(true)
        end

        # #sensitive on the instantiated attribute is what
        # ResourceHarness#create_change_event actually branches on to substitute
        # '[redacted]' for previous_value, desired_value and historical_value.
        it "reports #{attribute} as sensitive on a real resource" do
          expect(resource.parameter(attribute).sensitive).to be(true)
        end
      end
    end
  end

  it 'leaves a non-secret attribute unflagged on a real resource' do
    resource = Puppet::Type.type(:pdm_remote).new(MINIMAL_RESOURCES.fetch(:pdm_remote))
    expect(resource.parameter(:authid).sensitive).to be_nil
  end

  it 'leaves attributes that hold no secret unredacted' do
    expect(Puppet::Type.type(:pdm_user).attrclass(:comment).method_defined?(:is_sensitive)).to be(false)
  end

  # The registration must cover every type, so a future attribute marked
  # sensitive is protected without anyone remembering to add a call.
  it 'is registered on every type in the module' do
    unregistered = Dir[File.join(__dir__, '..', '..', '..', '..', 'lib', 'puppet', 'type', 'pdm_*.rb')]
                   .map { |path| File.basename(path, '.rb') }
                   .reject { |name| name.start_with?('pdm_transport_', 'pdm_sensitive_') }
                   .reject { |name| File.read(File.join(__dir__, '..', '..', '..', '..', 'lib', 'puppet', 'type', "#{name}.rb")).include?('PdmSensitiveParameters.register') }

    expect(unregistered).to be_empty
  end
end
