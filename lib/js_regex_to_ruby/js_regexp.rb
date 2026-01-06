# frozen_string_literal: true

module JsRegexToRuby
  # A Regexp subclass that emulates JavaScript's runtime RegExp semantics for:
  # - g (global): searches from last_index and updates it on success; resets to 0 on failure
  # - y (sticky): requires a match at last_index (implemented via a leading \G)
  #
  # Note: Some Ruby String methods (e.g., String#match?, String#=~, String#scan) do not dispatch
  # to Regexp methods and therefore cannot update last_index.
  class JsRegExp < Regexp
    POS_UNSET = Object.new
    private_constant :POS_UNSET

    attr_reader :js_flags

    def initialize(source, options = 0, js_flags: "")
      @js_flags = js_flags.to_s
      @global = @js_flags.include?("g")
      @sticky = @js_flags.include?("y")
      @last_index = 0
      super(source, options)
    end

    def global?
      @global
    end

    def sticky?
      @sticky
    end

    def last_index
      @last_index
    end

    def last_index=(value)
      i = value.to_i
      @last_index = i < 0 ? 0 : i
    end

    alias lastIndex last_index

    def lastIndex=(value)
      self.last_index = value
    end

    def reset
      @last_index = 0
      self
    end

    # JS-like exec: returns MatchData (or nil) and updates last_index for g/y.
    def exec(str)
      match_internal(str, POS_UNSET)
    end

    # JS-like test: boolean wrapper around exec.
    def test(str)
      !exec(str).nil?
    end

    alias test? test

    # Safe global iteration (similar to JS String#matchAll):
    # - does not permanently mutate last_index
    # - avoids infinite loops for empty-string matches by advancing 1 char
    def match_all(str)
      return enum_for(:match_all, str) unless block_given?

      str = str.to_s
      saved_last_index = @last_index

      begin
        @last_index = 0
        while (m = exec(str))
          yield m
          if m[0].empty?
            @last_index += 1
            @last_index = str.length + 1 if @last_index > str.length
          end
        end
      ensure
        @last_index = saved_last_index
      end
    end

    # If g/y and pos is omitted, behaves like #exec (uses last_index and updates it).
    # If pos is provided, behaves like Ruby Regexp#match and does not touch last_index.
    def match(str, pos = POS_UNSET, &block)
      m = match_internal(str, pos)
      return yield(m) if block && m
      m
    end

    # If g/y and pos is omitted, behaves like #test (uses last_index and updates it).
    # If pos is provided, behaves like Ruby Regexp#match? and does not touch last_index.
    def match?(str, pos = POS_UNSET)
      !!match_internal(str, pos)
    end

    # Used by `case`/`when`.
    def ===(other)
      !!match_internal(other, POS_UNSET)
    end

    # JS-like semantics when regexp is on the LHS.
    def =~(other)
      m = match_internal(other, POS_UNSET)
      m ? m.begin(0) : nil
    end

    private

    def uses_last_index?
      @global || @sticky
    end

    def raw_match(str, pos)
      Regexp.instance_method(:match).bind_call(self, str, pos)
    end

    def match_internal(str, pos)
      str = str.to_s

      if uses_last_index?
        if pos == POS_UNSET
          start = @last_index
          if start < 0 || start > str.length
            @last_index = 0
            return nil
          end

          m = raw_match(str, start)
          if m
            @last_index = m.end(0)
            return m
          end

          @last_index = 0
          return nil
        end

        return raw_match(str, pos)
      end

      pos = 0 if pos == POS_UNSET
      raw_match(str, pos)
    end
  end
end
