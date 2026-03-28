# Railsmith

Railsmith is an all-in-one service-layer gem for Rails applications. It aims to standardize domain-oriented service boundaries with sensible defaults for CRUD, bulk operations, routing, and result handling.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add railsmith
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install railsmith
```

## Usage

```ruby
require "railsmith"
```

## Result and Error Contract

Railsmith uses a small, stable `Result` object that is easy to serialize and test.

### Success

```ruby
result = Railsmith::Result.success(value: { id: 123 }, meta: { request_id: "abc" })

result.success? # => true
result.value    # => { id: 123 }
result.meta     # => { request_id: "abc" }
result.to_h
# => { success: true, value: { id: 123 }, meta: { request_id: "abc" } }
```

### Failure

```ruby
error = Railsmith::Errors.not_found(message: "User not found", details: { model: "User", id: 1 })
result = Railsmith::Result.failure(error:, meta: { request_id: "abc" })

result.failure? # => true
result.code     # => "not_found"
result.error.to_h
# => { code: "not_found", message: "User not found", details: { model: "User", id: 1 } }
result.to_h
# => { success: false, error: { ... }, meta: { request_id: "abc" } }
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/samaswin/railsmith.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
