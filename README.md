# Collar

Collar is a program that generates [Duktape][] boilerplate for [ooc][] code.

[Duktape]: http://duktape.org/
[ooc]: http://ooc-lang.org/

The basic idea is:

  - Have a `universe.ooc` file somewhere in your project that imports all the
    code you want to interact with from the JS side
  - Let rock generate JSON output for all modules recursively imported from
    `universe.ooc`
  - Let collar parse those JSON files and generate.. more ooc files! That
    contain wrapper functions so that they can be called from JavaScript via
    the [Duktape][] engine.
  - Import `autobindings.ooc` from your actual ooc app, compile all that (might
    want to `--blowup=256` or something so rock doesn't accidentally all over
    its loopy-pants) and hope somebody didn't royally F it up somewhere.

## Scope & Limitations

  - Binds static & non-static methods
  - Doesn't bind member variables yet
  - Doesn't bind covers yet
  - Probably doesn't do the right thing with methods that take ooc arrays

## Hopes & Dreams

It'd be awesome if collar could generate TypeScript headers so when scripting
ooc apps we would trade some amount of runtime errors (blergh) to compile-time
errors (yay!)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'collar'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install collar

## Usage

TODO: Write usage instructions here

(Hey I'm not even sure how to use it myself, so I'll write instructions
when I am.)

## Contributing

1. Fork it ( https://github.com/fasterthanlime/collar/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
