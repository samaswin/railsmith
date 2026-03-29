# frozen_string_literal: true

module Railsmith
  module ArchChecks
    # A single architecture rule violation found by static analysis.
    #
    # @!attribute rule [r] Symbol identifying the detector rule (e.g. +:direct_model_access+).
    # @!attribute file [r] Path to the source file containing the violation.
    # @!attribute line [r] 1-based line number of the offending code.
    # @!attribute message [r] Human-readable description of the violation.
    # @!attribute severity [r] +:warn+ (default, non-blocking) or +:error+.
    Violation = Struct.new(:rule, :file, :line, :message, :severity)
  end
end
