Ndex = require('ndex')
Connection = require('../lib/ndex/connection')
Adapter = require('../lib/ndex/adapter')
BrowserAdapter = require('../lib/ndex/adapters/browser_adapter')
WorkerAdapter = require('../lib/ndex/adapters/worker_adapter')

{ simple, expect } = require('./spec_helper.coffee')

describe 'Ndex', ->
  describe '#connect', ->
    it 'returns a connection promise', ->
      promise = Ndex.connect('foo', require('./fixtures/migrations'))
      expect(promise).to.be.an.instanceof(Promise)
      expect(promise).to.eventually.be.an.instanceof(Adapter)

    it 'handles multiple connection', (done) ->
      promises = []
      connection1 = null
      connection2 = null

      promises.push(Ndex.connect('connection1', {}).then (connection) -> connection1 = connection)
      promises.push(Ndex.connect('connection2', {}).then (connection) -> connection2 = connection)

      Promise.all(promises).then ->
        expect(Object.keys(Ndex.connections).length).to.equal(2)
        expect(Ndex.connections.connection1).to.equal(connection1)
        expect(Ndex.connections.connection2).to.equal(connection2)
        done()

    describe 'when trying to connect to the same database twice', ->
      it 'rejects the connection promise', ->
        expect(Ndex.connect('foo', {})).to.be.fulfilled
        expect(Ndex.connect('foo', {})).to.be.rejectedWith('Already connected to “foo”')

  describe '#getAdapter', ->
    beforeEach -> @connection = new Connection('foo', {})

    describe 'when workers are supported', ->
      beforeEach -> simple.mock(Ndex, 'workersAreSupported', -> true)

      it 'returns WorkerAdapter instance', ->
        adapter = Ndex.getAdapter(@connection)
        expect(adapter).to.be.an.instanceof(WorkerAdapter)

    describe 'when workers are not supported', ->
      beforeEach -> simple.mock(Ndex, 'workersAreSupported', -> false)

      it 'returns BrowserAdapter instance', ->
        adapter = Ndex.getAdapter(@connection)
        expect(adapter).to.be.an.instanceof(BrowserAdapter)

  describe '#getAdapterClass', ->
    describe 'when workers are supported', ->
      beforeEach -> simple.mock(Ndex, 'workersAreSupported', -> true)

      it 'returns WorkerAdapter class', ->
        adapterClass = Ndex.getAdapterClass()
        expect(adapterClass).to.equal(WorkerAdapter)

    describe 'when workers are not supported', ->
      beforeEach -> simple.mock(Ndex, 'workersAreSupported', -> false)

      it 'returns BrowserAdapter class', ->
        adapterClass = Ndex.getAdapterClass()
        expect(adapterClass).to.equal(BrowserAdapter)

  describe '#workersAreSupported',  ->
    afterEach -> delete Ndex._workersAreSupported

    describe 'when workers are supported', ->
      it 'returns true', -> expect(Ndex.workersAreSupported({ Worker: true })).to.be.true

    describe 'when workers are not supported', ->
      it 'returns false', -> expect(Ndex.workersAreSupported({})).to.be.false
