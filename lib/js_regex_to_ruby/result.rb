# frozen_string_literal: true

module JsRegexToRuby
  # A conversion outcome.
  #
  # - ruby_source: String (Ruby regex source, not wrapped with /.../)
  # - ruby_options: Integer (Regexp option bits; IGNORECASE/MULTILINE, etc.)
  # - regexp: Regexp (compiled Regexp) or nil if compile: false or compilation failed
  # - warnings: Array<String>
  # - ignored_js_flags: Array<String> (flags that have no direct Ruby Regexp equivalent)
  # - js_source: original JS pattern source
  # - js_flags: original JS flags string
  Result = Struct.new(
    :ruby_source,
    :ruby_options,
    :regexp,
    :warnings,
    :ignored_js_flags,
    :js_source,
    :js_flags,
    keyword_init: true
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
      "/#{ruby_source.gsub('/', '\\/')}/#{ruby_flags_string}"
    end
  end
end
