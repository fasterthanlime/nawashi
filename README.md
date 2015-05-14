# Nawashi

Nawashi (縄師): (noun) literally, "rope master", "rope teacher" or "maker of string".

Nawashi makes [ooc][] code usable from [Duktape][] by generating bindings.

[Duktape]: http://duktape.org/
[ooc]: http://ooc-lang.org/

The basic idea is:

  - Have a `universe.ooc` file somewhere in your project that imports all the
    code you want to interact with from the JS side
  - Let rock generate JSON output for all modules recursively imported from
    `universe.ooc`
  - Let nawashi parse those JSON files and generate.. more ooc files! That
    contain wrapper functions so that they can be called from JavaScript via
    the [Duktape][] engine.
  - Import `autobindings.ooc` from your actual ooc app, compile all that (might
    want to `--blowup=128` or something so rock doesn't accidentally all over
    its loopy-pants) and hope somebody didn't royally F it up somewhere.

## Scope & Limitations

  - Binds static & non-static methods
  - Binds properties with ES5 Object.defineProperty
  - Returns covers as JS objects
  - Allows raw interfacing with Duktape

But:

  - Ignores: references, ooc arrays, generics, varargs

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'nawashi'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install nawashi

## Usage

TODO :( It's being used internally at [@NevarGames][] right
now, will take the time to document its usage properly at some point.

[@NevarGames]: https://twitter.com/nevargames

## Contributing

1. Fork it ( https://github.com/fasterthanlime/nawashi/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
