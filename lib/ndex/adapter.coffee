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

  handleLog: (args) ->
    return unless @handler
    return @handler(args) if @handler isnt console
    { type, data } = args

    switch type
      when 'transaction.start'
        console.groupCollapsed(data)
      when 'request'
        console.log(data)
      when 'transaction.end'
        console.groupEnd()

  # Async
  proxyObjectStoresNamespace: (objectStoreNames) ->
    @connection.createNamespaceForObjectStores(objectStoreNames, this)

module.exports = Adapter
