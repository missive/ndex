WorkerAdapter = require('../../../lib/ndex/adapters/worker_adapter')
Connection = require('../../../lib/ndex/connection')

{ simple, expect, helpers } = require('../../spec_helper.coffee')
{ delay } = helpers

describe 'WorkerAdapter < Adapter', ->
  mockWorker = ->
    simple.restore()
    simple.mock(Worker.prototype, 'postMessage', ->)

  beforeEach ->
    mockWorker()
    @connection = new Connection('foo', { foo_migration: -> this.doSomething() })
    @adapter = new WorkerAdapter(@connection)

  describe 'Worker', ->
    it 'spawns a worker on initialization', ->
      expect(@adapter.worker).to.be.an.instanceof(Worker)

    it 'init worker with db name and migrations', ->
      expect(@adapter.worker.postMessage.calls.length).to.equal(1)

      args = @adapter.worker.postMessage.firstCall.args[0]
      expect(args).to.have.deep.property('method', 'init')
      expect(args).to.have.deep.property('args')
      expect(args).to.have.deep.property('args.name', 'foo')
      expect(args).to.have.deep.property('args.migrations')

    it 'transfers migrations function as string', ->
      args = @adapter.worker.postMessage.firstCall.args[0]
      expect(args.args.migrations).to.deep.equal
        foo_migration: 'function () { return this.doSomething(); }'

  describe '#handleMethod', ->
    beforeEach -> mockWorker()

    it 'schedules 1 #postMessage per event loop', (done) ->
      @adapter.get('foo', 1)
      @adapter.get('foo', 2)
      @adapter.get('foo', 3)

      delay 0, =>
        @adapter.get('foo', 4)
        @adapter.get('foo', 5)

        delay 0, done, =>
          expect(@adapter.worker.postMessage.calls.length).to.equal(2)

    it 'caches promises’ resolve/reject functions', ->
      length = Object.keys(@adapter.promises).length
      expect(length).to.equal(0)

      @adapter.open()
      @adapter.get()
      @adapter.getAll()

      length = Object.keys(@adapter.promises).length
      expect(length).to.equal(3)

      for i in [1..length]
        expect(@adapter.promises[i]).to.be.defined
        expect(@adapter.promises[i].id).to.equal(i)
        expect(@adapter.promises[i].resolve).to.be.defined
        expect(@adapter.promises[i].reject).to.be.defined

  describe '#handleMessage', ->
    it 'resolves promise when worker response is resolved', ->
      promise = @adapter.open()

      length = Object.keys(@adapter.promises).length
      expect(length).to.equal(1)

      @adapter.handleMessage(data: { id: 1, resolve: { foo: 'bar' } })
      expect(promise).to.be.fulfilled

      length = Object.keys(@adapter.promises).length
      expect(length).to.equal(0)

    it 'rejects promise when worker response is rejected', ->
      promise = @adapter.open()

      length = Object.keys(@adapter.promises).length
      expect(length).to.equal(1)

      @adapter.handleMessage(data: { id: 1, reject: 'There was an error' })
      expect(promise).to.be.rejectedWith('There was an error')

      length = Object.keys(@adapter.promises).length
      expect(length).to.equal(0)
