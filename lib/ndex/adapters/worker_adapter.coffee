Adapter = require('../adapter')
Helpers = require('../helpers')
ConnectionRaw = require('raw!../connection')
WorkerRaw = require('raw!../workers/connection_worker')

class WorkerAdapter extends Adapter
  constructor: ->
    super
    @promises = {}
    @id = 1
    this.spawnWorker()

  # Worker will instantiate a new connection object in it’s own thread
  spawnWorker: ->
    { name, migrations } = @connection

    # Cannot transfer functions to a worker
    # Will be eval’d in the worker thread
    migrations = Helpers.stringifyFunctions(migrations)

    blob = new Blob([ConnectionRaw, WorkerRaw])
    blobURL = window.URL.createObjectURL(blob)

    @worker = new Worker(blobURL)
    @worker.onmessage = this.handleMessage
    @worker.postMessage
      method: 'init'
      args: { name: name, migrations: migrations }

    console.info "Ndex: Worker for “#{name}” spawned at #{blobURL}"

  handleLogging: (@handler) ->
    @worker.postMessage
      method: 'handleLogging'

  # Every method is sent to the worker
  # A promise if cached and resolved/rejected
  # on response
  handleMethod: (method, args...) ->
    id = @id++

    # Cannot transfer functions to a worker
    # Will be eval’d in the worker thread for supported functions (i.e. :limit predicate)
    args = Helpers.stringifyFunctions(args)

    new Promise (resolve, reject) =>
      @promises[id] = { id: id, resolve: resolve, reject: reject }
      @worker.postMessage
        id: id
        method: method
        args: args

  handleMessage: (e) =>
    { id, resolve, reject, method, args } = e.data
    return this[method](args) if method

    promise = @promises[id]
    delete @promises[id]

    if 'resolve' of e.data
      promise.resolve(resolve)
    else
      promise.reject(reject)

module.exports = WorkerAdapter
