# JsRegexToRuby

A Ruby gem that converts ECMAScript (JavaScript) regular expressions to Ruby `Regexp` objects, preserving behavior as closely as Ruby's regex engine allows.

## Why This Gem?

JavaScript and Ruby regular expressions have subtle but important differences:

| Feature | JavaScript | Ruby |
|---------|-----------|------|
| `^` and `$` anchors | Match start/end of **string** by default | Match start/end of **line** by default |
| `/s` flag (dotAll) | Makes `.` match newlines | N/A (use `/m` in Ruby) |
| `/m` flag (multiline) | Makes `^`/`$` match line boundaries | N/A (already default behavior) |
| `[^]` (any character) | Matches any char including `\n` | Invalid syntax (use `[\s\S]`) |
| `/g`, `/y` flags | Global / sticky runtime semantics | Supported via `JsRegexToRuby::JsRegExp` (stateful `Regexp` subclass) |
| `/d`, `/u`, `/v` flags | Various features | No direct equivalents |

This gem handles these conversions automatically, emitting warnings when perfect conversion isn't possible.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "js_regex_to_ruby"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install js_regex_to_ruby
```

## Usage

### Basic Conversion

```ruby
require "js_regex_to_ruby"

# From a JS regex literal
result = JsRegexToRuby.convert("/^foo$/i")
result.regexp        #=> /\Afoo\z/i
result.success?      #=> true

# From pattern + flags separately
result = JsRegexToRuby.convert("^hello$", flags: "im")
result.regexp        #=> /^hello$/i
result.ruby_source   #=> "^hello$"
result.ruby_options  #=> 1 (Regexp::IGNORECASE)
```

### Quick Conversion with `try_convert`

If you just need the `Regexp` and want `nil` on failure (no exceptions):

```ruby
# Returns Regexp on success
JsRegexToRuby.try_convert("/^foo$/i")  #=> /\Afoo\z/i

# Returns nil on invalid input (never raises)
JsRegexToRuby.try_convert("/unterminated")  #=> nil
JsRegexToRuby.try_convert("/(?invalid/")    #=> nil
JsRegexToRuby.try_convert(nil)              #=> nil
```

#### `literal_only` Option

By default, strings without `/` delimiters are treated as raw pattern sources:

```ruby
JsRegexToRuby.try_convert("cat")  #=> /cat/ (compiled as pattern)
```

If you only want to accept JS regex literals (strings starting with `/`), use `literal_only: true`:

```ruby
# Only accept /pattern/flags format
JsRegexToRuby.try_convert("cat", literal_only: true)   #=> nil (not a literal)
JsRegexToRuby.try_convert("/cat/", literal_only: true) #=> /cat/
JsRegexToRuby.try_convert("/cat/i", literal_only: true) #=> /cat/i
```

This is useful when you want to distinguish between plain strings (like keywords) and regex patterns in user input.

### Parsing JS Literal Without Converting

```ruby
pattern, flags = JsRegexToRuby.parse_literal('/foo\\/bar/gi')
pattern  #=> "foo\\/bar"
flags    #=> "gi"
```

### Handling Warnings

```ruby
result = JsRegexToRuby.convert("/test/guy")

result.warnings
#=> ["JS flag(s) not representable as Ruby Regexp options: u"]

result.ignored_js_flags
#=> ["u"]
```

### Global / Sticky (`g` / `y`) Runtime Semantics

When the JS flags include `g` and/or `y`, `convert` returns a `JsRegexToRuby::JsRegExp` (a `Regexp` subclass) that tracks `last_index` and provides JS-like methods:

```ruby
res = JsRegexToRuby.convert("/foo/g")
re = res.regexp

re.last_index = 2
re.exec("foo foo")&.begin(0) #=> 4
re.last_index               #=> 7
```

For safe global iteration (avoids empty-match infinite loops), use `match_all`:

```ruby
re = JsRegexToRuby.convert("/.*/g").regexp
re.match_all("a").map { |m| [m[0], m.begin(0)] }
#=> [["a", 0], ["", 1]]
```

### Result Object

The `Result` struct provides comprehensive information:

| Method | Description |
|--------|-------------|
| `regexp` | The compiled `Regexp` object (or `JsRegexToRuby::JsRegExp` when `g`/`y` are present), or `nil` if compilation failed |
| `success?` | Returns `true` if `regexp` is not `nil` |
| `ruby_source` | The converted Ruby regex pattern string |
| `ruby_options` | Integer flags (`Regexp::IGNORECASE`, `Regexp::MULTILINE`, etc.) |
| `ruby_flags_string` | Human-readable flags string (e.g., `"im"`) |
| `ruby_literal` | Best-effort Ruby literal representation (e.g., `/pattern/im`) |
| `warnings` | Array of warning messages about the conversion |
| `ignored_js_flags` | Array of JS flags with no Ruby equivalent |
| `js_source` | Original JS pattern |
| `js_flags` | Original JS flags string |

### Without Compilation

If you only need the converted source without compiling:

```ruby
result = JsRegexToRuby.convert("/^test$/", compile: false)
result.ruby_source  #=> "\\Atest\\z"
result.regexp       #=> nil
```

## Conversion Details

### Flag Mapping

| JS Flag | Ruby Equivalent | Notes |
|---------|-----------------|-------|
| `i` | `Regexp::IGNORECASE` | Case-insensitive matching |
| `s` | `Regexp::MULTILINE` | JS dotAll → Ruby multiline (`.` matches `\n`) |
| `m` | *(behavior change)* | Keeps `^`/`$` as-is instead of converting to `\A`/`\z` |
| `g` | `JsRegexToRuby::JsRegExp` | JS-like `lastIndex`/`exec`/`test` behavior (not a Ruby Regexp option) |
| `y` | `\G` + `JsRegexToRuby::JsRegExp` | Sticky matching via `\G` prefix + `lastIndex` runtime behavior |
| `u` | *(ignored)* | Unicode mode - Ruby handles Unicode differently |
| `v` | *(ignored)* | Unicode sets mode - no equivalent |
| `d` | *(ignored)* | Indices for matches - no equivalent |

### Anchor Conversion

By default (without JS `m` flag):
- `^` → `\A` (start of string)
- `$` → `\z` (end of string)

With JS `m` flag:
- `^` and `$` are preserved (matching line boundaries, which is Ruby's default behavior)

### Inline Modifiers

JavaScript's inline modifier groups are converted:

```ruby
# JS: (?s:a.c) - dotAll only inside group
result = JsRegexToRuby.convert("(?s:a.c)")
result.ruby_source  #=> "(?m:a.c)"

# JS: (?m:^foo$) - multiline anchors inside group
result = JsRegexToRuby.convert("(?m:^foo$)bar$")
result.ruby_source  #=> "(?:^foo$)bar\\z"
```

### Control Character Escapes

JavaScript's `\cX` control escapes are converted to the actual control character:

```ruby
result = JsRegexToRuby.convert('\\cA')
result.ruby_source.bytes.first  #=> 1 (Ctrl+A)
```

### Any Character Class `[^]`

JavaScript's `[^]` matches any character including newlines (equivalent to `[\s\S]`). This is invalid syntax in Ruby, so it's automatically converted:

```ruby
result = JsRegexToRuby.convert("/a[^]b/")
result.ruby_source  #=> "a[\\s\\S]b"

# Matches any character including newline
result.regexp.match?("a\nb")  #=> true
result.regexp.match?("axb")   #=> true
```

Note: Negated character classes like `[^abc]` are NOT affected and work as expected.

### Ruby-Only Escape Sequences

JavaScript allows many "identity escapes" where `\X` means `"X"` (outside Unicode modes).
Ruby has additional special sequences like `\A`, `\z`, `\G`, and `\Q...\E`.
To preserve JS behavior, the converter rewrites these to literal characters where appropriate (e.g., JS `\A` becomes Ruby `A`).

## Limitations

1. **Runtime flags (`g`, `y`) are stateful**: When present, `convert` returns a `JsRegexToRuby::JsRegExp` (subclass of `Regexp`) that tracks `last_index` and provides JS-like `exec`/`test`/`match` behavior. Use `match_all` for safe iteration. Note: `String#match?`, `String#scan`, and `String#=~` bypass `Regexp` method dispatch and will not update `last_index`.

2. **Unicode properties**: `\p{...}` syntax exists in both JS and Ruby but with different property names and semantics. No automatic conversion is performed.

3. **Named capture groups**: Both languages support named groups with identical syntax (`(?<name>...)`), so no conversion is needed.

4. **Backreferences**: Numbered backreferences (`\1`, `\2`) work similarly, but behavior edge cases may differ.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests.

```bash
git clone https://github.com/jasl/js_regex_to_ruby.git
cd js_regex_to_ruby
bin/setup
rake test
```

You can also run `bin/console` for an interactive prompt to experiment with the gem.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jasl/js_regex_to_ruby.

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## See Also

- [MDN: Regular Expressions](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Regular_Expressions)
- [Ruby Regexp Documentation](https://ruby-doc.org/core/Regexp.html)
- [js_regex](https://github.com/jaynetics/js_regex) - A similar gem with a different approach

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
