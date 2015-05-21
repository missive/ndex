Connection = require('./ndex/connection')
BrowserAdapter = require('./ndex/adapters/browser_adapter')
WorkerAdapter = require('./ndex/adapters/worker_adapter')

class Ndex
  constructor: ->
    @connections = {}

  connect: (name, migrations) ->
    new Promise (resolve, reject) =>
      if connection = @connections[name]
        return reject(new Error("Already connected to “#{name}”"))

      connection = new Connection(name, migrations)
      adapter = @connections[name] = this.getAdapter(connection)
      adapter.handleMethod('open').then (objectStoreNames) ->
        adapter.proxyObjectStoresNamespace(objectStoreNames)
        resolve(adapter)

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
