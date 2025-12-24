# frozen_string_literal: true

module JsRegexToRuby
  # A conversion outcome (immutable value object).
  #
  # @!attribute [r] ruby_source
  #   @return [String] Ruby regex source (not wrapped with /.../)
  # @!attribute [r] ruby_options
  #   @return [Integer] Regexp option bits (IGNORECASE, MULTILINE, etc.)
  # @!attribute [r] regexp
  #   @return [Regexp, nil] Compiled Regexp, or nil if compile: false or compilation failed
  # @!attribute [r] warnings
  #   @return [Array<String>] Warning messages from conversion
  # @!attribute [r] ignored_js_flags
  #   @return [Array<String>] Flags that have no direct Ruby Regexp equivalent
  # @!attribute [r] js_source
  #   @return [String] Original JS pattern source
  # @!attribute [r] js_flags
  #   @return [String] Original JS flags string
  Result = Data.define(
    :ruby_source,
    :ruby_options,
    :regexp,
    :warnings,
    :ignored_js_flags,
    :js_source,
    :js_flags
  ) do
    def success?
      !regexp.nil?
    end

    def ruby_flags_string
      s = +""
      s << "i" if (ruby_options & Regexp::IGNORECASE) != 0
      s << "m" if (ruby_options & Regexp::MULTILINE) != 0
      s
    end

    # Best-effort Ruby literal representation (not necessarily re-escapable).
    def ruby_literal
      "/#{ruby_source.gsub("/", "\\/")}/#{ruby_flags_string}"
    end
  end
end
