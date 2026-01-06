# frozen_string_literal: true

require_relative "js_regex_to_ruby/version"
require_relative "js_regex_to_ruby/result"
require_relative "js_regex_to_ruby/js_regexp"
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
  # @example With JS regex literal (starts with /)
  #   JsRegexToRuby.try_convert('/^foo$/i')  #=> /\Afoo\z/i
  #   JsRegexToRuby.try_convert('/invalid[/')  #=> nil (invalid regex syntax)
  #
  # @example With pattern source (no / delimiter) - treated as raw pattern
  #   JsRegexToRuby.try_convert('cat')  #=> /cat/
  #   JsRegexToRuby.try_convert('[invalid')  #=> nil (invalid regex syntax)
  #
  # @example With literal_only: true - only accept /.../ format
  #   JsRegexToRuby.try_convert('cat', literal_only: true)  #=> nil (doesn't start with /)
  #   JsRegexToRuby.try_convert('/cat/', literal_only: true)  #=> /cat/
  #
  # @param input [String, #to_s] Either a JS literal `/.../flags` or a JS pattern source.
  # @param flags [String, nil] JS flags if input is not a literal.
  # @param literal_only [Boolean] If true, returns nil for inputs that don't look like
  #   JS regex literals (i.e., don't start with "/"). Useful when you want to treat
  #   plain strings like "cat" as non-regex values rather than pattern sources.
  # @return [Regexp, nil] The compiled Ruby Regexp, or nil if conversion/compilation failed.
  def self.try_convert(input, flags: nil, literal_only: false)
    if literal_only
      input = input.to_s
      return nil unless input.start_with?("/")
    end

    Converter.convert(input, flags: flags, compile: true).regexp
  rescue
    nil
  end

  def self.parse_literal(literal)
    Converter.parse_literal(literal)
  end
end
