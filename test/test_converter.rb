# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/js_regex_to_ruby"

class TestJsRegexToRubyConverter < Minitest::Test
  def test_anchor_conversion_without_m
    res = JsRegexToRuby.convert("/^foo$/")
    assert_equal '\\Afoo\\z', res.ruby_source
    assert res.regexp.match?("foo")
    refute res.regexp.match?('foo\n')
  end

  def test_anchor_kept_with_m
    res = JsRegexToRuby.convert("/^foo$/m")
    assert_equal "^foo$", res.ruby_source
    assert res.regexp.match?("foo")
    assert res.regexp.match?("foo\nbar")
  end

  def test_dotall_s_maps_to_ruby_m
    res = JsRegexToRuby.convert("a.c", flags: "s")
    assert (res.ruby_options & Regexp::MULTILINE) != 0
    assert res.regexp.match?("a\nc")
  end

  def test_inline_modifier_m_only_affects_anchor_rewrite
    # Inside the group, m is enabled so ^/$ stay ^/$.
    res = JsRegexToRuby.convert("(?m:^foo$)bar$")
    assert_equal '(?:^foo$)bar\\z', res.ruby_source
  end

  def test_inline_modifier_s_maps_to_ruby_m
    res = JsRegexToRuby.convert("(?s:a.c)")
    assert_equal "(?m:a.c)", res.ruby_source
  end

  def test_inline_modifier_disable_s
    # Global dotAll, but disabled inside group.
    res = JsRegexToRuby.convert("/(?-s:a.c)/s")
    assert_equal "(?-m:a.c)", res.ruby_source
    assert (res.ruby_options & Regexp::MULTILINE) != 0
  end

  def test_control_escape
    res = JsRegexToRuby.convert('\\cA')
    assert_equal 1, res.ruby_source.bytes.first
  end

  def test_parse_literal_with_escaped_slash
    pat, fl = JsRegexToRuby.parse_literal('/foo\\/bar/i')
    assert_equal 'foo\\/bar', pat
    assert_equal "i", fl
  end

  def test_ignored_flags
    res = JsRegexToRuby.convert("/foo/giy")
    assert_includes res.ignored_js_flags, "g"
    assert_includes res.ignored_js_flags, "y"
    refute_includes res.ignored_js_flags, "i"
  end

  # [^] conversion tests
  def test_any_char_class_conversion
    # JS [^] matches any character including newline
    res = JsRegexToRuby.convert("/[^]/")
    assert_equal "[\\s\\S]", res.ruby_source
    assert res.success?
  end

  def test_any_char_class_matches_newline
    res = JsRegexToRuby.convert("/a[^]b/")
    assert_equal "a[\\s\\S]b", res.ruby_source
    assert res.regexp.match?("a\nb")
    assert res.regexp.match?("axb")
    assert res.regexp.match?("a b")
  end

  def test_any_char_class_matches_any_character
    res = JsRegexToRuby.convert("[^]")
    # Should match any single character
    assert res.regexp.match?("a")
    assert res.regexp.match?("\n")
    assert res.regexp.match?(" ")
    assert res.regexp.match?("\t")
    assert res.regexp.match?("日")
  end

  def test_negated_char_class_not_converted
    # [^abc] is a negated character class, should NOT be converted
    res = JsRegexToRuby.convert("/[^abc]/")
    assert_equal "[^abc]", res.ruby_source
    assert res.regexp.match?("x")
    refute res.regexp.match?("a")
  end

  def test_multiple_any_char_classes
    res = JsRegexToRuby.convert("/[^][^][^]/")
    assert_equal "[\\s\\S][\\s\\S][\\s\\S]", res.ruby_source
    assert res.regexp.match?("abc")
    assert res.regexp.match?("a\nc")
  end

  def test_any_char_class_with_quantifier
    res = JsRegexToRuby.convert("/[^]+/")
    assert_equal "[\\s\\S]+", res.ruby_source
    assert res.regexp.match?("hello\nworld")
  end

  def test_mixed_char_classes
    # Mix of [^] and [^abc]
    res = JsRegexToRuby.convert("/[^][^abc][^]/")
    assert_equal "[\\s\\S][^abc][\\s\\S]", res.ruby_source
    assert res.regexp.match?("xxz")
    refute res.regexp.match?("xax")
  end

  # try_convert tests
  def test_try_convert_success
    regexp = JsRegexToRuby.try_convert("/^foo$/i")
    assert_instance_of Regexp, regexp
    assert regexp.match?("FOO")
  end

  def test_try_convert_with_flags
    regexp = JsRegexToRuby.try_convert("test", flags: "i")
    assert_instance_of Regexp, regexp
    assert regexp.match?("TEST")
  end

  def test_try_convert_plain_pattern_works
    # Plain pattern (not a literal) is valid and gets compiled
    regexp = JsRegexToRuby.try_convert("foo")
    assert_instance_of Regexp, regexp
    assert regexp.match?("foo")
  end

  def test_try_convert_unterminated_returns_nil
    # Unterminated regex literal
    assert_nil JsRegexToRuby.try_convert("/foo")
  end

  def test_try_convert_invalid_pattern_returns_nil
    # Invalid regex pattern that would cause RegexpError
    assert_nil JsRegexToRuby.try_convert("/(?/")
    assert_nil JsRegexToRuby.try_convert("(?")
  end

  def test_try_convert_non_string_returns_nil
    assert_nil JsRegexToRuby.try_convert(123)
    assert_nil JsRegexToRuby.try_convert(nil)
  end
end
