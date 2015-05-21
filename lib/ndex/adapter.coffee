class Adapter
  constructor: (@connection) ->
    this.proxyAPIMethods()

  # Sync
  proxyAPIMethods: (objectStoreNames = []) ->
    methods = (k for k, v of @connection when typeof v is 'function')
    methods.forEach (method) =>
      return if method is 'index'
      this[method] = => this.handleMethod(method, arguments...)

  index: (objectStoreName, indexName) ->
    @connection.createNamespaceForIndex(indexName, objectStoreName, this)

  # Async
  proxyObjectStoresNamespace: (objectStoreNames) ->
    @connection.createNamespaceForObjectStores(objectStoreNames, this)

module.exports = Adapter
