# Connection will be injected through blob
init = ({ name, migrations }) ->
  @connection = new Connection(name, migrations)

self.onmessage = (e) =>
  { id, method, args } = e.data
  return init(args) if method is 'init'

  @connection[method].apply(@connection, args)
    .then (data)  -> postMessage(id: id, resolve: data)
    .catch (data) -> postMessage(id: id, reject: data)
