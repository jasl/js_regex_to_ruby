# frozen_string_literal: true

require_relative "js_regex_to_ruby/version"
require_relative "js_regex_to_ruby/converter"

module JsRegexToRuby
  # Convenience API.
  #
  # @example
  #   JsRegexToRuby.convert('/^foo$/i').regexp #=> /\Afoo\z/i
  def self.convert(input, flags: nil, compile: true)
    Converter.convert(input, flags: flags, compile: compile)
  end

  # Try to convert a JS regex to Ruby Regexp.
  # Returns the compiled Regexp on success, or nil on failure.
  # Never raises exceptions for invalid input.
  #
  # @example
  #   JsRegexToRuby.try_convert('/^foo$/i')  #=> /\Afoo\z/i
  #   JsRegexToRuby.try_convert('not a regex')  #=> nil
  #   JsRegexToRuby.try_convert('/invalid[/') #=> nil
  #
  # @param input [String] Either a JS literal `/.../flags` or a JS pattern source.
  # @param flags [String, nil] JS flags if input is not a literal.
  # @return [Regexp, nil] The compiled Ruby Regexp, or nil if conversion/compilation failed.
  def self.try_convert(input, flags: nil)
    result = Converter.convert(input, flags: flags, compile: true)
    result.regexp
  rescue ArgumentError, RegexpError
    nil
  end

  def self.parse_literal(literal)
    Converter.parse_literal(literal)
  end
end
