Connection = require('./ndex/connection')
BrowserAdapter = require('./ndex/adapters/browser_adapter')
WorkerAdapter = require('./ndex/adapters/worker_adapter')

class Ndex
  constructor: ->
    @connections = {}

  connect: (name, migrations, adapter = null) ->
    new Promise (resolve, reject) =>
      unless adapter
        if connection = @connections[name]
          return reject(new Error("Already connected to “#{name}”"))

        connection = new Connection(name, migrations)
        adapter = @connections[name] = this.getAdapter(connection)

      adapter.handleMethod('open')
        .then (objectStoreNames) ->
          adapter.proxyObjectStoresNamespace(objectStoreNames)
          resolve(adapter)

        .catch (error) =>
          # WorkerAdapter errors
          if adapter instanceof WorkerAdapter
            # indexedDB not supported
            # Try to connect in the main thread
            if /indexedDB isn’t supported/.test(error)
              adapter = @connections[name] = new BrowserAdapter(connection)
              return resolve(this.connect(null, null, adapter))

          reject(error)

  getAdapter: (connection) ->
    adapterClass = this.getAdapterClass()
    new adapterClass(connection)

  getAdapterClass: ->
    return WorkerAdapter if this.workersAreSupported()
    BrowserAdapter

  workersAreSupported: (scope = window) ->
    @_workersAreSupported ?= 'Worker' of scope

# Singleton
module.exports = new Ndex
