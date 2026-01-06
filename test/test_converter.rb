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
    res = JsRegexToRuby.convert("/foo/giyu")
    refute_includes res.ignored_js_flags, "g"
    refute_includes res.ignored_js_flags, "y"
    refute_includes res.ignored_js_flags, "i"
    assert_includes res.ignored_js_flags, "u"
  end

  # g/y runtime semantics via JsRegExp
  def test_global_regexp_is_js_regexp
    res = JsRegexToRuby.convert("/foo/g")
    assert_instance_of JsRegexToRuby::JsRegExp, res.regexp
    assert_kind_of Regexp, res.regexp
    assert_equal 0, res.regexp.last_index
    assert res.regexp.global?
    refute res.regexp.sticky?
  end

  def test_global_exec_uses_and_updates_last_index
    re = JsRegexToRuby.convert("/foo/g").regexp

    re.last_index = 2
    m = re.exec("foo foo")
    assert_equal "foo", m[0]
    assert_equal 4, m.begin(0)
    assert_equal 7, re.last_index

    assert_nil re.exec("foo foo")
    assert_equal 0, re.last_index
  end

  def test_global_match_without_pos_acts_like_exec
    re = JsRegexToRuby.convert("/foo/g").regexp

    re.last_index = 4
    m = re.match("foo foo")
    assert_equal 4, m.begin(0)
    assert_equal 7, re.last_index
  end

  def test_global_match_with_pos_does_not_touch_last_index
    re = JsRegexToRuby.convert("/foo/g").regexp

    re.last_index = 5
    m = re.match("foo foo", 0)
    assert_equal 0, m.begin(0)
    assert_equal 5, re.last_index
  end

  def test_string_match_uses_last_index_for_global
    re = JsRegexToRuby.convert("/foo/g").regexp

    re.last_index = 4
    m = "foo foo".match(re)
    assert_equal 4, m.begin(0)
    assert_equal 7, re.last_index
  end

  def test_global_case_equality_updates_last_index
    re = JsRegexToRuby.convert("/foo/g").regexp

    re.last_index = 4
    assert(re === "foo foo")
    assert_equal 7, re.last_index
  end

  def test_global_tilde_updates_last_index
    re = JsRegexToRuby.convert("/foo/g").regexp

    re.last_index = 4
    assert_equal 4, (re =~ "foo foo")
    assert_equal 7, re.last_index
  end

  def test_sticky_prefix_and_semantics
    res = JsRegexToRuby.convert("/foo/y")
    assert_equal "\\G(?:foo)", res.ruby_source

    re = res.regexp
    assert_instance_of JsRegexToRuby::JsRegExp, re
    refute re.global?
    assert re.sticky?

    re.last_index = 2
    assert_nil re.exec("foo foo")
    assert_equal 0, re.last_index

    re.last_index = 4
    m = re.exec("foo foo")
    assert_equal 4, m.begin(0)
    assert_equal 7, re.last_index

    assert_nil re.exec("foo foo")
    assert_equal 0, re.last_index
  end

  def test_sticky_and_global_combo_is_sticky
    re = JsRegexToRuby.convert("/foo/gy").regexp
    assert re.global?
    assert re.sticky?

    re.last_index = 2
    assert_nil re.exec("foo foo")
    assert_equal 0, re.last_index
  end

  def test_identity_escapes_do_not_trigger_ruby_special_sequences
    res = JsRegexToRuby.convert("\\A")
    assert_equal "A", res.ruby_source
    assert res.regexp.match?("A")
    refute res.regexp.match?("foo")

    res = JsRegexToRuby.convert("\\z")
    assert_equal "z", res.ruby_source
    assert res.regexp.match?("z")
    refute res.regexp.match?("foo")

    res = JsRegexToRuby.convert("\\G")
    assert_equal "G", res.ruby_source
    assert res.regexp.match?("G")
    refute res.regexp.match?("foo")

    res = JsRegexToRuby.convert("\\Qfoo\\E")
    assert_equal "QfooE", res.ruby_source
    assert res.regexp.match?("QfooE")
    refute res.regexp.match?("foo")

    res = JsRegexToRuby.convert("\\h")
    assert_equal "h", res.ruby_source
    assert res.regexp.match?("h")
    refute res.regexp.match?("a")

    res = JsRegexToRuby.convert("[\\h]")
    assert_equal "[h]", res.ruby_source
    assert res.regexp.match?("h")
    refute res.regexp.match?("a")

    res = JsRegexToRuby.convert("\\e")
    assert_equal "e", res.ruby_source
    assert res.regexp.match?("e")
    refute res.regexp.match?("\e")

    res = JsRegexToRuby.convert("\\a")
    assert_equal "a", res.ruby_source
    assert res.regexp.match?("a")
    refute res.regexp.match?("\a")

    res = JsRegexToRuby.convert("\\C")
    assert_equal "C", res.ruby_source
    assert res.success?
    assert res.regexp.match?("C")

    res = JsRegexToRuby.convert("\\M")
    assert_equal "M", res.ruby_source
    assert res.success?
    assert res.regexp.match?("M")
  end

  def test_match_all_is_safe_and_restores_last_index
    re = JsRegexToRuby.convert("/.*/g").regexp
    re.last_index = 4
    matches = re.match_all("a").map { |m| [m[0], m.begin(0)] }
    assert_equal [["a", 0], ["", 1]], matches
    assert_equal 4, re.last_index
  end

  def test_match_all_advances_on_empty_matches
    re = JsRegexToRuby.convert("/(?:)/g").regexp
    assert_equal [0, 1], re.match_all("a").map { |m| m.begin(0) }
    assert_equal [0], re.match_all("").map { |m| m.begin(0) }
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
