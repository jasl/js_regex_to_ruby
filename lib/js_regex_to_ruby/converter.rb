# frozen_string_literal: true

module JsRegexToRuby
  # Convert an ECMAScript-style regular expression (pattern + flags) into a Ruby Regexp.
  #
  # The goal is to preserve behavior as much as Ruby's regex engine allows.
  #
  # Key conversions implemented:
  # - JS /s (dotAll) => Ruby /m (dot-all in Ruby)
  # - JS /m (multiline anchors) => Ruby has ^/$ multiline by default, so we rewrite ^/$
  #   to \A/\z when JS multiline is NOT enabled.
  # - JS inline modifiers (?ims-ims:...) are supported, with mapping s->m and special handling for m.
  # - JS [^] (match any character including newline) => Ruby [\s\S]
  # - JS /g, /y, /u, /v, /d have no direct Regexp equivalent; we report them in Result#ignored_js_flags.
  class Converter
    JS_KNOWN_FLAGS = %w[d g i m s u v y].freeze
    JS_GROUP_MOD_FLAGS = %w[i m s].freeze

    # Tracks modifier state during source rewriting (immutable).
    Context = Data.define(:js_multiline_anchors, :ruby_ignorecase, :ruby_dotall)

    # Parse a JS regex literal like `/foo\\/bar/i`.
    # Returns [pattern, flags].
    def self.parse_literal(literal)
      raise ArgumentError, "literal must be a String" unless literal.is_a?(String)

      s = literal.strip
      raise ArgumentError, "JS RegExp literal must start with /" unless s.start_with?("/")

      in_class = false
      escaped = false
      i = 1
      while i < s.length
        ch = s[i]
        if escaped
          escaped = false
          i += 1
          next
        end

        if ch == "\\"
          escaped = true
          i += 1
          next
        end

        if in_class
          in_class = false if ch == "]"
          i += 1
          next
        end

        case ch
        when "["
          in_class = true
        when "/"
          pattern = s[1...i]
          flags = s[(i + 1)..] || ""
          return [pattern, flags]
        end
        i += 1
      end

      raise ArgumentError, "Unterminated JS RegExp literal (missing closing /)"
    end

    # Convert a JS regex into a Ruby regex.
    #
    # @param input [String] Either a JS literal `/.../flags` or a JS pattern source.
    # @param flags [String, nil] JS flags if input is not a literal.
    # @param compile [Boolean] Whether to compile and return a Regexp in the result.
    # @return [JsRegexToRuby::Result]
    def self.convert(input, flags: nil, compile: true)
      warnings = []

      js_source, js_flags = if flags.nil? && looks_like_literal?(input)
                              parse_literal(input)
      else
                              raise ArgumentError, "input must be a String" unless input.is_a?(String)
                              [input, (flags || "")]
      end

      js_flags = js_flags.to_s
      seen_flags, unknown_flags, duplicate_flags = normalize_flags(js_flags)

      warnings << "Unknown JS RegExp flag(s): #{unknown_flags.uniq.join(', ')}" unless unknown_flags.empty?
      warnings << "Duplicate JS RegExp flag(s) ignored: #{duplicate_flags.uniq.join(', ')}" unless duplicate_flags.empty?

      ignored_js_flags = (seen_flags.keys - %w[i m s]).sort

      unless ignored_js_flags.empty?
        warnings << "JS flag(s) not representable as Ruby Regexp options: #{ignored_js_flags.join(', ')}"
      end

      base_js_multiline = seen_flags["m"]
      base_js_ignorecase = seen_flags["i"]
      base_js_dotall = seen_flags["s"]

      ruby_options = 0
      ruby_options |= Regexp::IGNORECASE if base_js_ignorecase
      ruby_options |= Regexp::MULTILINE if base_js_dotall # Ruby /m is dot-all

      base_ctx = Context.new(
        js_multiline_anchors: base_js_multiline,
        ruby_ignorecase: base_js_ignorecase,
        ruby_dotall: base_js_dotall
      )

      ruby_source = rewrite_source(js_source, base_ctx, warnings)

      regexp = nil
      if compile
        begin
          regexp = Regexp.new(ruby_source, ruby_options)
        rescue RegexpError => e
          warnings << "Ruby RegexpError: #{e.message}"
          regexp = nil
        end
      end

      Result.new(
        ruby_source: ruby_source,
        ruby_options: ruby_options,
        regexp: regexp,
        warnings: warnings,
        ignored_js_flags: ignored_js_flags,
        js_source: js_source,
        js_flags: js_flags
      )
    end

    def self.looks_like_literal?(s)
      s.is_a?(String) && s.lstrip.start_with?("/")
    end

    def self.normalize_flags(flags)
      seen = {}
      unknown = []
      duplicates = []

      flags.each_char do |c|
        if seen.key?(c)
          duplicates << c
          next
        end
        if JS_KNOWN_FLAGS.include?(c)
          seen[c] = true
        else
          unknown << c
          seen[c] = true
        end
      end

      [seen, unknown, duplicates]
    end

    # Rewrite JS source to Ruby source.
    #
    # - Converts ^/$ depending on whether JS multiline-anchors mode is enabled in the current scope.
    # - Converts inline modifiers (?ims-ims:...) into Ruby equivalents (i and m only; s->m).
    # - Converts JS control escapes (\cA ... \cZ) to the actual control character.
    # - Converts JS [^] (any character) to Ruby [\s\S].
    def self.rewrite_source(src, base_ctx, warnings)
      out = +""
      in_class = false
      stack = [base_ctx]

      i = 0
      while i < src.length
        ch = src[i]

        if in_class
          if ch == "\\"
            # handle escapes inside class
            if control_escape_at?(src, i)
              out << control_char(src[i + 2])
              i += 3
              next
            end

            out << ch
            if i + 1 < src.length
              out << src[i + 1]
              i += 2
            else
              i += 1
            end
            next
          end

          out << ch
          in_class = false if ch == "]"
          i += 1
          next
        end

        case ch
        when "\\"
          if control_escape_at?(src, i)
            out << control_char(src[i + 2])
            i += 3
          else
            out << ch
            if i + 1 < src.length
              out << src[i + 1]
              i += 2
            else
              i += 1
            end
          end

        when "["
          # Check for [^] which matches any character (including newline) in JS
          # This is invalid syntax in Ruby, so convert to [\s\S]
          if src[i + 1] == "^" && src[i + 2] == "]"
            out << "[\\s\\S]"
            i += 3
          else
            in_class = true
            out << ch
            i += 1
          end

        when "("
          # Try parse JS modifier group: (?ims-ims:...)
          mod = parse_js_modifier_group(src, i)
          if mod
            current = stack.last
            desired = apply_js_group_modifiers(current, mod[:enable], mod[:disable])

            ruby_prefix = build_ruby_modifier_prefix(current, desired)
            out << ruby_prefix

            stack << desired
            i = mod[:after_colon]
          else
            out << "("
            stack << stack.last
            i += 1
          end

        when ")"
          out << ")"
          if stack.length > 1
            stack.pop
          else
            warnings << "Unbalanced ) in source; continuing"
          end
          i += 1

        when "^"
          if stack.last.js_multiline_anchors
            out << "^"
          else
            out << '\\A'
          end
          i += 1

        when "$"
          if stack.last.js_multiline_anchors
            out << "$"
          else
            out << '\\z'
          end
          i += 1

        else
          out << ch
          i += 1
        end
      end

      warnings << "Unbalanced ( in source: #{stack.length - 1} group(s) not closed" if stack.length > 1
      warnings << "Unterminated character class ([...) in source" if in_class

      out
    end

    def self.control_escape_at?(src, index)
      return false unless src[index] == "\\"
      return false unless src[index + 1] == "c"
      letter = src[index + 2]
      !!(letter && letter.match?(/[A-Za-z]/))
    end

    def self.control_char(letter)
      # MDN: \cX where X is A-Z maps to the character code of X modulo 32.
      # (A->1, B->2, ... Z->26)
      (letter.ord & 0x1F).chr
    end

    # If a modifier group begins at src[index] (which should be '('),
    # returns { enable: 'im', disable: 's', after_colon: <index after ':'> }.
    # Otherwise returns nil.
    def self.parse_js_modifier_group(src, index)
      return nil unless src[index] == "("
      return nil unless src[index + 1] == "?"

      j = index + 2
      enable = +""
      while (c = src[j]) && JS_GROUP_MOD_FLAGS.include?(c)
        enable << c
        j += 1
      end

      disable = +""
      if src[j] == "-"
        j += 1
        while (c = src[j])
          break unless JS_GROUP_MOD_FLAGS.include?(c)
          disable << c
          j += 1
        end
      end

      return nil unless src[j] == ":"
      return nil if enable.empty? && disable.empty?

      {
        enable: enable,
        disable: disable,
        after_colon: j + 1,
      }
    end

    def self.apply_js_group_modifiers(current, enable, disable)
      js_m = current.js_multiline_anchors
      ruby_i = current.ruby_ignorecase
      ruby_dotall = current.ruby_dotall

      enable.each_char do |f|
        case f
        when "m" then js_m = true
        when "i" then ruby_i = true
        when "s" then ruby_dotall = true
        end
      end

      disable.each_char do |f|
        case f
        when "m" then js_m = false
        when "i" then ruby_i = false
        when "s" then ruby_dotall = false
        end
      end

      current.with(
        js_multiline_anchors: js_m,
        ruby_ignorecase: ruby_i,
        ruby_dotall: ruby_dotall
      )
    end

    def self.build_ruby_modifier_prefix(current, desired)
      enable = +""
      disable = +""

      if desired.ruby_ignorecase != current.ruby_ignorecase
        (desired.ruby_ignorecase ? enable : disable) << "i"
      end

      # JS dotAll (s) maps to Ruby /m (dot-all)
      if desired.ruby_dotall != current.ruby_dotall
        (desired.ruby_dotall ? enable : disable) << "m"
      end

      if enable.empty? && disable.empty?
        "(?:"
      elsif disable.empty?
        "(?#{enable}:"
      elsif enable.empty?
        "(?-#{disable}:"
      else
        "(?#{enable}-#{disable}:"
      end
    end

    private_class_method :looks_like_literal?, :normalize_flags,
                         :rewrite_source, :control_escape_at?, :control_char,
                         :parse_js_modifier_group, :apply_js_group_modifiers,
                         :build_ruby_modifier_prefix
  end
end
