Helpers = require('../../lib/ndex/helpers')
{ expect } = require('../spec_helper.coffee')

describe 'Helpers', ->
  describe '#stringifyFunctions', ->
    describe 'when passing a function', ->
      it 'returns the stringified function', ->
        fn = -> console.log 'fn'
        result = Helpers.stringifyFunctions(fn)

        expect(result).to.equal "function () { return console.log('fn'); }"

    describe 'when passing an object', ->
      it 'returns the object with its functions stringified', ->
        obj = { foo: 'bar', fn: (-> console.log 'fn'), count: 1 }
        result = Helpers.stringifyFunctions(obj)

        expect(result).to.deep.equal { foo: 'bar', fn: "function () { return console.log('fn'); }", count: 1 }

      it 'recursively looks for functions to stringify', ->
        obj = { foo: { bar: { baz: -> console.log 'foo.bar.baz fn' } } }
        result = Helpers.stringifyFunctions(obj)

        expect(result).to.deep.equal { foo: { bar: { baz: "function () { return console.log('foo.bar.baz fn'); }" } } }

    describe 'when passing an array', ->
      it 'return the array with its functions stringified', ->
        arr = ['foo', (-> console.log 'fn'), bar: { baz: -> console.log 'bar.baz fn' }]
        result = Helpers.stringifyFunctions(arr)

        expect(result).to.deep.equal ['foo', "function () { return console.log('fn'); }", { bar: { baz: "function () { return console.log('bar.baz fn'); }" } }]
