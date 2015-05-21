BrowserAdapter = require('../../../lib/ndex/adapters/browser_adapter')
Connection = require('../../../lib/ndex/connection')

{ simple, expect } = require('../../spec_helper.coffee')

describe 'BrowserAdapter < Adapter', ->
  beforeEach ->
    @connection = new Connection('foo', {})
    @adapter = new BrowserAdapter(@connection)

  describe '#handleMethod', ->
    beforeEach -> simple.mock(@connection, 'open', ->)

    it 'relays to connection', ->
      @adapter.open()
      expect(@connection.open.calls.length).to.equal(1)
