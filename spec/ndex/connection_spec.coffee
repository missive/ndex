Ndex = require('ndex')
Connection = require('../../lib/ndex/connection')
BrowserAdapter = require('../../lib/ndex/adapters/browser_adapter')
WorkerAdapter = require('../../lib/ndex/adapters/worker_adapter')

{ simple, expect, helpers } = require('../spec_helper.coffee')
{ delay } = helpers

describe 'Connection', ->
  describe 'Migrations', ->
    beforeEach -> @connection = new Connection()

    it 'sorts migrations by key', ->
      migrations = @connection.parseMigrations({ 54321: (->), 12345: (->) })
      expect(migrations.map (m) -> m.key).to.deep.equal ['12345', '54321']

    it 'parses migrations', ->
      migrations = @connection.parseMigrations({ '54321_CreateFooBar': (->), '12345_CreateBarFoo': (->) })

      expected = [
        { version: 12345, title: "Create bar foo", key: "12345_CreateBarFoo" }
        { version: 54321, title: "Create foo bar", key: "54321_CreateFooBar" }
      ]

      for migration, i in migrations
        expect(migration).to.have.deep.property('version', expected[i].version)
        expect(migration).to.have.deep.property('title', expected[i].title)
        expect(migration).to.have.deep.property('key', expected[i].key)

    it 'creates a namespace for object stores', ->
      simple.mock(@connection, 'add', ->)
      expect(@connection.foozle).not.to.exist

      @connection.createNamespaceForObjectStore('foozle')
      expect(@connection.foozle).to.exist

      @connection.foozle.add({ foo: 'bar' })
      expect(@connection.add.firstCall.args).to.deep.equal(['foozle', { foo: 'bar' }])

  describe 'Requests', ->
    beforeEach ->
      @connection = new Connection('foo', {})
      simple.mock(@connection, 'createTransaction', ->)

    describe 'Queue', ->
      it 'enqueues requests', ->
        simple.mock(@connection, 'scheduleTransaction', ->)

        @connection.enqueue('write', 'foo') for i in [1..5]
        expect(@connection.queue.foo.length).to.equal(5)

      it 'clears requests on event loop', (done) ->
        @connection.enqueue('write', 'foo') for i in [1..5]
        expect(@connection.queue.foo.length).to.equal(5)

        delay 0, done, =>
          expect(@connection.queue.foo.length).to.equal(0)

      it 'schedules 1 transaction per event loop', (done) ->
        simple.mock(@connection, 'scheduleTransaction')

        @connection.enqueue('read', 'foo')
        @connection.enqueue('write', 'foo')

        delay 0, =>
          @connection.enqueue('read', 'foo')
          @connection.enqueue('write', 'foo')

        delay 1, done, =>
          expect(@connection.scheduleTransaction.calls.length).to.equal(2)

    describe 'Transaction', ->
      it 'handles readonly', (done) ->
        @connection.enqueue('read', 'foo')
        @connection.enqueue('read', 'bar')

        delay 0, done, =>
          expect(@connection.createTransaction.firstCall.args[0]).to.equal('readonly')

      it 'handles readwrite', (done) ->
        @connection.enqueue('read', 'foo')
        @connection.enqueue('write', 'foo')

        delay 0, done, =>
          expect(@connection.createTransaction.firstCall.args[0]).to.equal('readwrite')

      # https://github.com/missive/ndex/issues/1
      it 'creates 1 transaction per objectStore', (done) ->
        @connection.enqueue('read', 'foo')
        @connection.enqueue('write', 'foo')
        @connection.enqueue('read', 'bar')
        @connection.enqueue('write', 'bar')

        delay 0, done, =>
          expect(@connection.createTransaction.calls.length).to.equal(2)

  describe 'Logging', ->
    beforeEach ->
      @connection = new Connection('foo', require('../fixtures/migrations'))
      @connection.logging.handleLog = (@spy = simple.spy())

    it 'calls the handler', (done) ->
      expect(@spy.calls.length).to.equal(0)
      @connection.add('users', { id: 1 })
      @connection.add('users', { id: 2 })

      delay 100, done, =>
        expect(@spy.calls.length).to.equal(4)
        expect(@spy.calls[0].arg.type).to.equal('transaction.start')
        expect(@spy.calls[1].arg.type).to.equal('request')
        expect(@spy.calls[2].arg.type).to.equal('request')
        expect(@spy.calls[3].arg.type).to.equal('transaction.end')

  describe 'Methods', ->
    [BrowserAdapter, WorkerAdapter].forEach (AdapterClass) ->
      describe AdapterClass.name, ->
        beforeEach (done) ->
          connection = new Connection('foo', require('../fixtures/migrations'))
          adapter = new AdapterClass(connection)
          adapter.handleMethod('open').then (objectStoreNames) =>
            adapter.proxyObjectStoresNamespace(objectStoreNames)
            @connection = adapter
            @connection.clearAll()
              .then => Promise.all([
                @connection.add('users', { name: 'e', job: 'developer', id: 1 })
                @connection.add('users', { name: 'r', job: 'developer', id: 2 })
                @connection.add('users', { name: 'p', job: 'developer', id: 3 })
                @connection.add('users', { name: 't', job: 'designer' , id: 4 })
              ])
              .then -> done()

        describe '#get', ->
          it 'gets an item', ->
            promise = @connection.get('users', 2)
            expect(promise).to.eventually.deep.equal \
              { name: 'r', job: 'developer', id: 2 }

          it 'gets multiple items', ->
            promise = @connection.users.get([1, 3])
            expect(promise).to.eventually.deep.equal [
              { name: 'e', job: 'developer', id: 1 }
              { name: 'p', job: 'developer', id: 3 }
            ]

        describe '#getAll', ->
          it 'returns all items', ->
            promise = @connection.getAll('users')
            expect(promise).to.eventually.deep.equal [
              { name: 'e', job: 'developer', id: 1 }
              { name: 'r', job: 'developer', id: 2 }
              { name: 'p', job: 'developer', id: 3 }
              { name: 't', job: 'designer',  id: 4 }
            ]

        describe '#add', ->
          describe 'with a key', ->
            it 'adds an item', ->
              @connection.add('organizations', 'heliom', { name: 'heliom' })
              expect(@connection.organizations.get('heliom')).to.eventually.deep.equal({ name: 'heliom' })

            it 'adds multiple items', ->
              @connection.add('organizations', ['heliom', 'abrico'], [{ name: 'heliom' }, { name: 'abrico' }])
              expect(@connection.organizations.get('heliom')).to.eventually.deep.equal({ name: 'heliom' })
              expect(@connection.organizations.get('abrico')).to.eventually.deep.equal({ name: 'abrico' })

          describe 'without a key', ->
            it 'adds an item', ->
              @connection.add('users', { name: 'foo', id: 5 })
              expect(@connection.users.get(5)).to.eventually.deep.equal({ name: 'foo', id: 5 })

            it 'adds multiple items', ->
              @connection.add('users', [{ foo: 'bar1', id: 1 }, { foo: 'bar2', id: 2 }])
              expect(@connection.users.get(1)).to.eventually.deep.equal({ foo: 'bar1', id: 1 })
              expect(@connection.users.get(2)).to.eventually.deep.equal({ foo: 'bar2', id: 2 })

        describe '#update', ->
          describe 'with a key', ->
            it 'updates received params', ->
              @connection.organizations.add('missive', { est: 2014 })
              expect(@connection.organizations.get('missive')).to.eventually.deep.equal({ est: 2014 })

              @connection.organizations.add('missive', { name: 'missive' })
              expect(@connection.organizations.get('missive')).to.eventually.deep.equal({ name: 'missive' })

              @connection.organizations.update('missive', { est: 2014 }).then =>
                promise = @connection.organizations.get('missive')
                expect(promise).to.eventually.deep.equal({ name: 'missive', est: 2014 })

            it 'inserts a new entry', ->
              expect(@connection.organizations.get('missive')).to.eventually.be.null

              @connection.organizations.update('missive', { name: 'missive' }).then =>
                promise = @connection.organizations.get('missive')
                expect(promise).to.eventually.deep.equal({ name: 'missive' })

            it 'deeply updates object attributes', ->
              @connection.organizations.add('missive', { name: 'missive', employees: { count: 3, status: 'working' } })
              @connection.organizations.update('missive', { est: 2014, employees: { count: 4 } }).then =>
                promise = @connection.organizations.get('missive')
                expect(promise).to.eventually.deep.equal({ name: 'missive', est: 2014, employees: { count: 4, status: 'working' } })

          describe 'without a key', ->
            it 'updates received params', ->
              @connection.users.add({ id: 1337, name: 'Frodo' })
              expect(@connection.users.get(1337)).to.eventually.deep.equal({ id: 1337, name: 'Frodo' })

              @connection.users.add({ id: 1337, job: 'Ring-bearer' })
              expect(@connection.users.get(1337)).to.eventually.deep.equal({ id: 1337, job: 'Ring-bearer' })

              @connection.users.update(1337, { name: 'Frodo' }).then =>
                promise = @connection.users.get(1337)
                expect(promise).to.eventually.deep.equal({ id: 1337, name: 'Frodo', job: 'Ring-bearer' })

            it 'inserts a new entry', ->
              expect(@connection.users.get(1337)).to.eventually.be.null

              @connection.users.update(1337, { name: 'Frodo' }).then (data) =>
                promise = @connection.users.get(1337)
                expect(promise).to.eventually.deep.equal({ id: 1337, name: 'Frodo' })

            it 'deeply updates object attributes', ->
              @connection.users.add({ id: 1337, name: 'Sam', info: { age: 33 } })
              @connection.users.update(1337, { name: 'Frodo', info: { job: 'Ring-bearer' } }).then =>
                promise = @connection.users.get(1337)
                expect(promise).to.eventually.deep.equal({ id: 1337, name: 'Frodo', info: { age: 33, job: 'Ring-bearer' } })

        describe '#increment', ->
          describe 'with a key', ->
            it 'increments the entry', ->
              @connection.organizations.add('foo', 5)
              @connection.organizations.increment('foo').then =>
                promise = @connection.organizations.get('foo')
                expect(promise).to.eventually.equal(6)

            it 'initializes attribute to zero if null', ->
              @connection.organizations.increment('foo').then =>
                promise = @connection.organizations.get('foo')
                expect(promise).to.eventually.equal(1)

          describe 'without a key', ->
            it 'increments an object attribute', ->
              @connection.users.add({ id: 100, count: 5 })
              @connection.users.increment(100, { count: 4 }).then =>
                promise = @connection.users.get(100)
                expect(promise).to.eventually.deep.equal({ id: 100, count: 9 })

            it 'deeply increments multiple object attributes', ->
              @connection.users.add({ id: 100, count: 1, foo: { bar: 'baz', count: 5 } })
              @connection.users.increment(100, { count: 1, foo: { count: 2 }}).then =>
                promise = @connection.users.get(100)
                expect(promise).to.eventually.deep.equal({ id: 100, count: 2, foo: { bar: 'baz', count: 7 } })

            it 'initializes attribute to zero if null', ->
              @connection.users.add({ id: 100, foo: { bar: 'baz' }})
              @connection.users.increment(100, { count: 1, foo: { count: 2 }}).then =>
                promise = @connection.users.get(100)
                expect(promise).to.eventually.deep.equal({ id: 100, count: 1, foo: { bar: 'baz', count: 2 } })

        describe '#decrement', ->
          describe 'with a key', ->
            it 'increments the entry', ->
              @connection.organizations.add('foo', 5)
              @connection.organizations.decrement('foo').then =>
                promise = @connection.organizations.get('foo')
                expect(promise).to.eventually.equal(4)

            it 'initializes attribute to zero if null', ->
              @connection.organizations.decrement('foo').then =>
                promise = @connection.organizations.get('foo')
                expect(promise).to.eventually.equal(-1)

          describe 'without a key', ->
            it 'increments an object attribute', ->
              @connection.users.add({ id: 100, count: 5 })
              @connection.users.decrement(100, { count: 4 }).then =>
                promise = @connection.users.get(100)
                expect(promise).to.eventually.deep.equal({ id: 100, count: 1 })

            it 'deeply increments multiple object attributes', ->
              @connection.users.add({ id: 100, count: 1, foo: { bar: 'baz', count: 5 } })
              @connection.users.decrement(100, { count: 1, foo: { count: 2 }}).then =>
                promise = @connection.users.get(100)
                expect(promise).to.eventually.deep.equal({ id: 100, count: 0, foo: { bar: 'baz', count: 3 } })

            it 'initializes attribute to zero if null', ->
              @connection.users.add({ id: 100, foo: { bar: 'baz' }})
              @connection.users.decrement(100, { count: 1, foo: { count: 2 }}).then =>
                promise = @connection.users.get(100)
                expect(promise).to.eventually.deep.equal({ id: 100, count: -1, foo: { bar: 'baz', count: -2 } })

        describe '#delete', ->
          it 'removes an item', ->
            @connection.users.delete(2)
            expect(@connection.users.getAll()).to.eventually.deep.equal [
              { name: 'e', job: 'developer', id: 1 }
              { name: 'p', job: 'developer', id: 3 }
              { name: 't', job: 'designer',  id: 4 }
            ]

          it 'removes multiple items', ->
            @connection.users.delete([1, 3])
            expect(@connection.users.getAll()).to.eventually.deep.equal [
              { name: 'r', job: 'developer', id: 2 }
              { name: 't', job: 'designer',  id: 4 }
            ]

        describe '#clear', ->
          it 'clears an objectStore', ->
            @connection.users.clear()
            expect(@connection.users.getAll()).to.eventually.deep.equal []

        describe '#clearAll', ->
          it 'clears all objectStores', ->
            @connection.users.add({ foo: 'bar' })
            @connection.organizations.add('bar', { name: 'bar' })

            @connection.clearAll()

            expect(@connection.users.getAll()).to.eventually.deep.equal []
            expect(@connection.organizations.getAll()).to.eventually.deep.equal []

        describe '#reset', ->
          it 'clears an objectStore and adds items', (done) ->
            @connection.users.reset({ name: 'm', job: 'janitor', id: 5 }).then =>
              @connection.users.getAll().then (data) ->
                expect(data).to.deep.equal [{ name: 'm', job: 'janitor', id: 5 }]
                done()

        describe '#index', ->
          it '#get', ->
            promise = @connection.users.index('job').get('designer')
            expect(promise).to.eventually.deep.equal \
              { name: 't', job: 'designer',  id: 4 }

          it '#getAll', ->
            promise = @connection.users.index('job').getAll()
            expect(promise).to.eventually.deep.equal [
              { name: 't', job: 'designer',  id: 4 }
              { name: 'e', job: 'developer', id: 1 }
              { name: 'r', job: 'developer', id: 2 }
              { name: 'p', job: 'developer', id: 3 }
            ]

          it '#where', ->
            promise = @connection.users.index('job').where(limit: 1, offset: 2)
            expect(promise).to.eventually.deep.equal [
              { name: 'r', job: 'developer', id: 2 }
            ]

        describe '#where', ->
          describe ':lt', ->
            it 'returns all items lower than', ->
              promise = @connection.users.where(lt: 3)
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 'r', job: 'developer', id: 2 }
              ]

          describe ':lteq', ->
            it 'returns all items lower or equal to', ->
              promise = @connection.users.where(lteq: 3)
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 'r', job: 'developer', id: 2 }
                { name: 'p', job: 'developer', id: 3 }
              ]

          describe ':gt', ->
            it 'returns all items greater than', ->
              promise = @connection.users.where(gt: 3)
              expect(promise).to.eventually.deep.equal [
                { name: 't', job: 'designer', id: 4 }
              ]

          describe ':gteq', ->
            it 'returns all items greater or equal to', ->
              promise = @connection.users.where(gteq: 3)
              expect(promise).to.eventually.deep.equal [
                { name: 'p', job: 'developer', id: 3 }
                { name: 't', job: 'designer',  id: 4 }
              ]

          describe ':eq', ->
            it 'returns all items equal to', ->
              promise = @connection.users.where(eq: 1)
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
              ]

            it 'supports array', ->
              promise = @connection.users.where(eq: [4, 1])
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 't', job: 'designer',  id: 4 }
              ]

            it 'merges :only when an array', ->
              promise = @connection.users.where(eq: [1, 4], only: { job: 'developer' })
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
              ]

          describe ':limit', ->
            it 'limits to a number', ->
              promise = @connection.users.where(limit: 2)
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 'r', job: 'developer', id: 2 }
              ]

            it 'limits to a truthy function', ->
              limit = (data) -> data.length is 3

              promise = @connection.users.where(limit: limit)
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 'r', job: 'developer', id: 2 }
                { name: 'p', job: 'developer', id: 3 }
              ]

          describe ':offset', ->
            it 'offsets the items', ->
              promise = @connection.users.where(offset: 2)
              expect(promise).to.eventually.deep.equal [
                { name: 'p', job: 'developer', id: 3 }
                { name: 't', job: 'designer',  id: 4 }
              ]

          describe ':only', ->
            it 'returns items matching only', ->
              promise = @connection.users.where(only: { job: 'developer' })
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 'r', job: 'developer', id: 2 }
                { name: 'p', job: 'developer', id: 3 }
              ]

          describe ':except', ->
            it 'returns items except matching', ->
              promise = @connection.users.where(except: { job: 'developer' })
              expect(promise).to.eventually.deep.equal [
                { name: 't', job: 'designer', id: 4 }
              ]

          describe ':uniq', ->
            it 'returns only 1 item per uniq', ->
              promise = @connection.users.where(uniq: 'job')
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 't', job: 'designer',  id: 4 }
              ]

          describe ':order', ->
            it 'returns items in desc order', ->
              promise = @connection.users.where(order: 'desc')
              expect(promise).to.eventually.deep.equal [
                { name: 'e', job: 'developer', id: 1 }
                { name: 'r', job: 'developer', id: 2 }
                { name: 'p', job: 'developer', id: 3 }
                { name: 't', job: 'designer',  id: 4 }
              ]

          describe ':remove', ->
            it 'creates a write transaction', ->
              # Can only be tested in main thread
              return if @connection instanceof WorkerAdapter
              simple.mock(@connection.connection, 'enqueue')

              @connection.users.where(eq: 1, remove: true)
              expect(@connection.connection.enqueue.firstCall.args[0]).to.equal('write')

            it 'removes items from indexedDB', ->
              @connection.users.index('job').where(eq: 'developer', remove: true).then (data) =>
                promise = @connection.users.index('job').where(eq: 'developer')
                expect(promise).to.eventually.deep.equal []
