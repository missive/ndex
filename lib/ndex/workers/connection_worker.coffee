# Connection will be injected through blob
init = ({ name, migrations }) ->
  @connection = new Connection(name, migrations)

handleLogging = ->
  @connection.logging.handleLog = (args) ->
    postMessage(method: 'handleLog', args: args)

self.onmessage = (e) =>
  data = e.data
  data = [data] unless Array.isArray(data)

  data.forEach (datum) =>
    { id, method, args } = datum

    # Intercept known methods
    if typeof this[method] is 'function'
      return this[method](args)

    # Unknown methods are relayed to @connection
    @connection[method].apply(@connection, args)
      .then (data)  -> postMessage(id: id, resolve: data)
      .catch (data) -> postMessage(id: id, reject: data)
