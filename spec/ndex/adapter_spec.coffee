Adapter = require('../../lib/ndex/adapter')
Connection = require('../../lib/ndex/connection')

{ simple, expect } = require('../spec_helper.coffee')

describe 'Adapter', ->
  beforeEach ->
    @connection = new Connection('foo', {})
    @adapter = new Adapter(@connection)

  it 'defines connection API methods', ->
    connectionMethods = (k for k, v of @connection when typeof v is 'function')
    for method in connectionMethods
      expect(@adapter[method]).to.be.defined

  it 'defines object stores namespace', ->
    @adapter.proxyObjectStoresNamespace(['foo', 'bar'])
    expect(@adapter.foo).to.be.defined
    for method in @connection.getMethodsForObjectStore()
      expect(@adapter.foo[method]).to.be.defined

  it 'defines index methods', ->
    methods = @adapter.index('foo', 'bar')
    expect(Object.keys(methods)).to.deep.equal(@connection.getMethodsForIndex())

  describe '#handleMethod', ->
    beforeEach -> simple.mock(@adapter, 'handleMethod', ->)

    it 'proxy connection', ->
      @adapter.add('foo', { id: 1 })

      expect(@adapter.handleMethod.calls.length).to.equal(1)
      expect(@adapter.handleMethod.calls[0].args).to.deep.equal(['add', 'foo', { id: 1 }])

      @adapter.index('foo', 'bar').get({ id: 1 })
      expect(@adapter.handleMethod.calls.length).to.equal(2)
      expect(@adapter.handleMethod.calls[1].args).to.deep.equal(['get', 'foo', { id: 1 }, 'bar'])
