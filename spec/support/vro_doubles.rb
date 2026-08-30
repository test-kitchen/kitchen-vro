#
# License:: Apache License, Version 2.0
#
# Verifying doubles for the small slice of the vcoworkflows API that this
# driver uses. Building them here keeps the specs honest -- if vcoworkflows
# renames `token` or drops `output_parameters`, every example that leans on
# these helpers fails loudly instead of passing against a stale stub.
#
module VroDoubles
  # @param value [Object] the value vRO returned for the parameter
  # @return [VcoWorkflows::WorkflowParameter] a verifying double
  def workflow_parameter(value)
    instance_double(VcoWorkflows::WorkflowParameter, value: value)
  end

  # @param output [Hash{String => Object}] output parameter names to raw values
  # @return [Hash{String => VcoWorkflows::WorkflowParameter}]
  def workflow_output(output)
    output.transform_values { |value| workflow_parameter(value) }
  end

  # @param state [String] the workflow run state vRO reports
  # @param alive [Boolean, Array<Boolean>] whether the run is still going; an
  #   array is returned one element per call, so a poll loop can be driven
  # @param output [Hash{String => Object}] output parameter names to raw values
  # @return [VcoWorkflows::WorkflowToken] a verifying double
  def workflow_token(state: "completed", alive: false, output: {})
    token = instance_double(VcoWorkflows::WorkflowToken,
      state: state,
      output_parameters: workflow_output(output))
    allow(token).to receive(:alive?).and_return(*Array(alive))
    token
  end

  # @param token [VcoWorkflows::WorkflowToken] the token the client hands back
  # @return [VcoWorkflows::Workflow] a verifying double
  def workflow_client(token: workflow_token)
    instance_double(VcoWorkflows::Workflow, execute: nil, parameter: nil, token: token)
  end
end
