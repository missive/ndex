require('./ndex_spec.coffee')

describe('Adapters', function() {
  require('./ndex/adapter_spec.coffee')
  require('./ndex/adapters/browser_adapter_spec.coffee')
  require('./ndex/adapters/worker_adapter_spec.coffee')
})

require('./ndex/connection_spec.coffee')
