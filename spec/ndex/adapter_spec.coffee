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

  describe '#handleLog', ->
    describe 'when handler is console', ->
      beforeEach ->
        simple.mock(console, 'groupCollapsed', ->)
        simple.mock(console, 'log', ->)
        simple.mock(console, 'groupEnd', ->)
        @adapter.handler = console

      it 'group-logs to console', ->
        @adapter.handleLog({ type: 'transaction.start', data: 'Group' })
        @adapter.handleLog({ type: 'request', data: 'Log 1' })
        @adapter.handleLog({ type: 'request', data: 'Log 2' })
        @adapter.handleLog({ type: 'transaction.end' })

        expect(console.groupCollapsed.calls.length).to.equal(1)
        expect(console.groupCollapsed.calls[0].arg).to.equal('Group')

        expect(console.log.calls.length).to.equal(2)
        expect(console.log.calls[0].arg).to.equal('Log 1')
        expect(console.log.calls[1].arg).to.equal('Log 2')

        expect(console.groupEnd.calls.length).to.equal(1)
        expect(console.groupEnd.calls[0].arg).to.equal()
