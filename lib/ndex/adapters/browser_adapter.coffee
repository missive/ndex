Adapter = require('../adapter')

class BrowserAdapter extends Adapter
  # Every method is relayed to
  # connection in the main thread
  handleMethod: (method, args...) ->
    @connection[method].apply(@connection, args)

module.exports = BrowserAdapter
