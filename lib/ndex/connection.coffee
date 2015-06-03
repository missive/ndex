factory = ->
  Connection = {}

  # Public API
  class Connection.API
    constructor: (@name, @migrations) ->
      @database = null
      @queue = {}
      @logging = new Connection.Logging

    parseMigrations: (migrations) ->
      keys = Object.keys(migrations).sort()
      keys.map (k) =>
        version = parseInt(k)
        titleMatches = k.match(/_(.+)/)
        title = if titleMatches then titleMatches[1].replace(/(\w)([A-Z])/g, ($1, $2, $3) -> "#{$2} #{$3.toLowerCase()}") else ''

        version: version
        title: title
        migration: migrations[k]
        key: k

    deleteDatabase: ->
      new Promise (resolve) =>
        return resolve() unless @database

        delete @dbPromise
        @database.close()

        request = indexedDB.deleteDatabase(@database.name)
        request.onsuccess = (e) -> setTimeout (-> resolve()), 0

    open: ->
      return @dbPromise if @dbPromise
      @dbPromise = new Promise (resolve, reject) =>
        migrations = this.parseMigrations(@migrations)

        request = indexedDB.open(@name, migrations.length + 1)
        request.onerror = (e) => reject(e)

        # Migrations
        request.onupgradeneeded = (e) =>
          db = e.target.result
          transaction = e.target.transaction

          migrationTransaction = new Connection.Migration(db, transaction)
          migrationTransaction.createObjectStore('migrations', keyPath: 'version')

          for migration in migrations
            # Migrations functions where transfered as string to worker
            if typeof migration.migration is 'string'
              migration.migration = eval("__#{migration.key} = #{migration.migration}")

            (migration.migration.up || migration.migration).bind(migrationTransaction).call()
            delete migration.migration

            transaction.objectStore('migrations').put(migration)

        # Opened
        request.onsuccess = (e) =>
          db = e.target.result
          objectStoreNames = [].slice.call(db.objectStoreNames)
          this.createNamespaceForObjectStores(objectStoreNames)

          # Same DB opened on another tab
          db.onversionchange = =>
            db.close()
            delete @dbPromise

          @database = db
          resolve(objectStoreNames)

    get: (objectStoreName, key, indexName) ->
      new Promise (resolve) =>
        if Array.isArray(key)
          promises = Promise.all key.map (k) => this.get(objectStoreName, k)
          promises.then(resolve)
        else
          this.enqueue 'read', objectStoreName, (transaction) =>
            @logging.addRequest(transaction, 'get', objectStoreName, indexName, { key: key })
            request = this.createRequest(transaction, objectStoreName, indexName)
            request.get(key).onsuccess = (e) ->
              value = e.target.result
              value = null if value is undefined

              resolve(value)

    getAll: (objectStoreName, indexName) ->
      new Promise (resolve) =>
        this.enqueue 'read', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'getAll', objectStoreName, indexName)
          result = []

          request = this.createRequest(transaction, objectStoreName, indexName)
          request.openCursor().onsuccess = (e) ->
            return resolve(result) unless cursor = e.target.result
            result.push(cursor.value)
            cursor.continue()

    add: (objectStoreName, key, data) ->
      [key, data] = [null, key] if data is undefined

      new Promise (resolve) =>
        if !key && Array.isArray(data)
          promises = Promise.all data.map (d) => this.add(objectStoreName, d)
          promises.then(resolve)
        else if key && Array.isArray(key) && Array.isArray(data)
          promises = Promise.all key.map (key, i) => this.add(objectStoreName, key, data[i])
          promises.then(resolve)
        else
          this.enqueue 'write', objectStoreName, (transaction) =>
            @logging.addRequest(transaction, 'add', objectStoreName, null, { key: key, data: data })
            args = if key then [data, key] else [data]
            request = this.createRequest(transaction, objectStoreName)
            request.put(args...).onsuccess = (e) ->
              resolve(data)

    update: (objectStoreName, key, value) ->
      new Promise (resolve) =>
        this.enqueue 'write', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'update', objectStoreName, null, { key: key, data: value })
          getRequest = this.createRequest(transaction, objectStoreName)
          getRequest.get(key).onsuccess = (e) =>
            keyPath = e.target.source.keyPath
            hasKeyPath = !!keyPath
            data = e.target.result

            if data is undefined
              data = value
              data[keyPath] = key if hasKeyPath
            else
              deepUpdate = (o, root) =>
                for k, v of o
                  if typeof v is 'object'
                    deepUpdate(v, root[k])
                    continue

                  root[k] = v

              deepUpdate(value, data)

            args = if hasKeyPath then [data] else [data, key]
            putRequest = this.createRequest(transaction, objectStoreName)
            putRequest.put(args...).onsuccess = ->
              resolve(data)

    increment: (objectStoreName, key, value = 1, decrement) ->
      new Promise (resolve) =>
        this.enqueue 'write', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, (if decrement then 'decrement' else 'increment'), objectStoreName, null, { key: key, data: value })
          getRequest = this.createRequest(transaction, objectStoreName)
          getRequest.get(key).onsuccess = (e) =>
            keyPath = e.target.source.keyPath
            hasKeyPath = !!keyPath
            data = e.target.result

            if hasKeyPath
              deepIncrement = (o, root) ->
                for k, v of o
                  if typeof v is 'object'
                    deepIncrement(v, root[k])
                    continue

                  root[k] ||= 0
                  root[k] += if decrement then -v else v

              deepIncrement(value, data)
            else
              data ||= 0
              data += if decrement then -value else value

            args = if hasKeyPath then [data] else [data, key]
            putRequest = this.createRequest(transaction, objectStoreName)
            putRequest.put(args...).onsuccess = ->
              resolve(data)

    decrement: (objectStoreName, key, value) ->
      this.increment(objectStoreName, key, value, true)

    delete: (objectStoreName, key) ->
      new Promise (resolve) =>
        if Array.isArray(key)
          promises = Promise.all key.map (k) => this.delete(objectStoreName, k)
          promises.then(resolve)
        else
          this.enqueue 'write', objectStoreName, (transaction) =>
            @logging.addRequest(transaction, 'delete', objectStoreName, null, { key: key })
            request = this.createRequest(transaction, objectStoreName)
            request.delete(key).onsuccess = (e) ->
              resolve(key)

    deleteWhere: (objectStoreName, predicates, indexName) ->
      predicates.remove = true
      this.where(objectStoreName, predicates, indexName)

    clear: (objectStoreName) ->
      new Promise (resolve) =>
        this.enqueue 'write', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'clear', objectStoreName)
          request = this.createRequest(transaction, objectStoreName)
          request.clear().onsuccess = -> resolve()

    clearAll: ->
      new Promise (resolve) =>
        objectStoreNames = [@database.objectStoreNames...]
        objectStoreNames = objectStoreNames.filter (objectStoreName) -> objectStoreName isnt 'migrations'

        promises = Promise.all objectStoreNames.map (objectStoreName) => this.clear(objectStoreName)
        promises.then(resolve)

    reset: (objectStoreName, key, data) ->
      new Promise (resolve) =>
        this.clear(objectStoreName).then =>
          this.add(objectStoreName, key, data).then(resolve)

    index: (objectStoreName, indexName) ->
      this.createNamespaceForIndex(indexName, objectStoreName)

    where: (objectStoreName, predicates, indexName) ->
      readWrite = if predicates.remove then 'write' else 'read'

      new Promise (resolve) =>
        this.enqueue readWrite, objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'where', objectStoreName, indexName, { data: predicates })
          { lt, lteq, gt, gteq, eq, limit, offset, only, except, uniq, order, remove } = predicates

          uniques = if Array.isArray(uniq) then uniq else if uniq then [uniq] else []
          order = if order is 'desc' then 'prev' else 'next'

          # Bounds
          bounds = {}

          for k, v of { lt: lt, lteq: lteq, gt: gt, gteq: gteq, eq: eq }
            continue if v is undefined
            isInclusive = k is 'gteq' || k is 'lteq'
            isEquivalent = k is 'eq'
            isLowerBound = k is 'gt' || k is 'gteq'
            bound = if isEquivalent then 'exact' else if isLowerBound then 'lower' else 'upper'
            bounds[bound] =
              value: v
              open: !isInclusive

          # Range
          range = null
          eqIsArray = false
          { lower, upper, exact } = bounds

          if exact
            if eqIsArray = Array.isArray(eq)
              eq.sort()

              lower = { value: eq[0], open: false }
              upper = { value: eq[eq.length - 1], open: false }

              range = IDBKeyRange.bound(lower.value, upper.value, lower.open, upper.open)
            else
              range = IDBKeyRange.only(exact.value)
          else if lower and upper
            range = IDBKeyRange.bound(lower.value, upper.value, lower.open, upper.open)
          else if lower
            range = IDBKeyRange.lowerBound(lower.value, lower.open)
          else if upper
            range = IDBKeyRange.upperBound(upper.value, upper.open)

          # Request
          result = []
          count = 0
          knownUniques = {}

          hasValues = (object, k, v) ->
            v = [v] unless Array.isArray(v)
            v.indexOf(object[k]) isnt -1

          request = this.createRequest(transaction, objectStoreName, indexName)
          request = if range then request.openCursor(range, order) else request.openCursor()
          request.onsuccess = (e) ->
            return resolve(result) unless cursor = e.target.result
            value = cursor.value

            # Only
            if eqIsArray
              keyPath = e.target.source.keyPath
              only ||= {}
              only[keyPath] = eq

            for k, v of only
              return cursor.continue() unless hasValues(value, k, v)

            # Except
            for k, v of except
              return cursor.continue() if hasValues(value, k, v)

            # Unique
            for k in uniques
              knownValues = knownUniques[k] ||= []
              if knownValues.indexOf(value[k]) isnt -1
                return cursor.continue()

              knownUniques[k].push(value[k])

            # Offset
            count++
            if offset && count <= offset
              return cursor.continue()

            # Add value to the result
            result.push(value)
            cursor.delete() if remove

            # Limit
            if limit
              # Limit functions where transfered as string to worker
              if typeof limit is 'string'
                limit = eval("__limit = #{limit}")

              if typeof limit is 'function' && limit(result)
                return resolve(result)
              else if limit is result.length
                return resolve(result)

            cursor.continue()

    # Helpers
    getMethodsForObjectStore: -> @_getMethodsForObjectStore ||= ['get', 'getAll', 'add', 'update', 'increment', 'decrement', 'delete', 'deleteWhere', 'clear', 'reset', 'index', 'where']
    getMethodsForIndex: -> @_getMethodsForIndex ||= ['get', 'getAll', 'where', 'deleteWhere']

    createNamespaceForObjectStores: (objectStoreNames = [], context = this) ->
      for objectStoreName in objectStoreNames
        continue if objectStoreName is 'migrations'
        this.createNamespaceForObjectStore(objectStoreName, context)

    createNamespaceForObjectStore: (objectStoreName, context = this) ->
      namespace = context[objectStoreName] = {}
      this.getMethodsForObjectStore().forEach (method) =>
        namespace[method] = => context[method](objectStoreName, arguments...)

      namespace

    createNamespaceForIndex: (indexName, objectStoreName, context = this) ->
      namespace = {}
      this.getMethodsForIndex().forEach (method) =>
        namespace[method] = => context[method](objectStoreName, arguments..., indexName)

      namespace

    createRequest: (transaction, objectStoreName, indexName) ->
      objectStore = transaction.objectStore(objectStoreName)
      if indexName then objectStore.index(indexName) else objectStore

    createTransaction: (mode, objectStoreName, callback) ->
      this.open().then =>
        transaction = @database.transaction([objectStoreName], mode)
        callback(transaction)

    # Queue
    # TOOD: Support multiple objectStores per transaction
    #       https://github.com/missive/ndex/issues/1
    enqueue: (readwrite, objectStoreName, callback) ->
      @queue[objectStoreName] ||= []

      request =
        readwrite: readwrite
        callback: callback

      this.scheduleTransaction(objectStoreName) unless @queue[objectStoreName].length
      @queue[objectStoreName].push(request)

    scheduleTransaction: (objectStoreName) ->
      setTimeout =>
        requests = @queue[objectStoreName].splice(0)

        modes = requests.map (r) -> r.readwrite
        needsWriteMode = modes.some (m) -> m is 'write'
        mode = if needsWriteMode then 'readwrite' else 'readonly'

        this.createTransaction mode, objectStoreName, (transaction) =>
          @logging.addTransaction(transaction, objectStoreName)
          request.callback(transaction) for request in requests
      , 0

  # Migration
  class Connection.Migration
    constructor: (@db, @transaction) ->

    createObjectStore: (name, options) ->
      return if @db.objectStoreNames.contains(name)
      @db.createObjectStore(name, options)

    deleteObjectStore: (name) ->
      return unless @db.objectStoreNames.contains(name)
      @db.deleteObjectStore(name)

    createIndex: (objectStoreName, indexName, keyPath, options) ->
      objectStore = @transaction.objectStore(objectStoreName)
      return if objectStore && objectStore.indexNames.contains(indexName)
      objectStore.createIndex(indexName, keyPath, options)

    deleteIndex: (objectStoreName, indexName) ->
      objectStore = @transaction.objectStore(objectStoreName)
      return unless objectStore && objectStore.indexNames.contains(indexName)
      objectStore.deleteIndex(indexName)

  # Logging
  class Connection.Logging
    constructor: ->
      @queues = []

    addTransaction: (transaction, objectStoreNames) ->
      return unless @handleLog

      @queues.push {
        transaction: transaction
        objectStoreNames: objectStoreNames
        requests: []
        start: Date.now()
      }

      callback = (e) => this.logTransaction(e.target)
      transaction.addEventListener('abort', callback)
      transaction.addEventListener('complete', callback)
      transaction.addEventListener('error', callback)

    addRequest: (transaction, method, objectStoreName, indexName, data) ->
      return unless @handleLog

      queue = @queues.filter((q) -> q.transaction is transaction)[0]
      return unless queue

      queue.requests.push
        method: method
        objectStoreName: objectStoreName
        indexName: indexName
        data: data

    logTransaction: (transaction) ->
      return unless @handleLog

      queue = @queues.filter((q) -> q.transaction is transaction)[0]
      return unless queue

      mode = if queue.transaction.mode is 'readwrite' then 'write' else 'read '
      requestsLenght = queue.requests.length

      end = Date.now()
      time = end - queue.start

      this.handleLog
        type: 'transaction.start'
        data: "Ndex: #{mode} #{queue.objectStoreNames} #{time}ms (#{requestsLenght} request#{if requestsLenght > 1 then 's' else ''})"

      for request in queue.requests
        { method, objectStoreName, indexName, data } = request
        { key, data } = data if data

        logs = []

        switch method
          when 'get'
            logs = ['GET', key, 'FROM', objectStoreName]
          when 'getAll'
            logs = ['GET ALL', 'FROM', objectStoreName]
          when 'add'
            logs = ['ADD', JSON.stringify(data), 'TO', objectStoreName]
            logs = logs.concat(['WITH KEY', key]) if key
          when 'update'
            logs = ['UPDATE', key, 'FROM', objectStoreName, 'SET', JSON.stringify(data)]
          when 'increment'
            data = JSON.stringify(data) if typeof data is 'object'
            logs = ['INCREMENT', data, 'TO KEY', key, 'FROM', objectStoreName]
          when 'decrement'
            data = JSON.stringify(data) if typeof data is 'object'
            logs = ['DECREMENT', data, 'TO KEY', key, 'FROM', objectStoreName]
          when 'delete'
            logs = ['DELETE', key, 'FROM', objectStoreName]
          when 'clear'
            logs = ['CLEAR', objectStoreName]
          when 'where'
            data.limit = '[FUNCTION]' if typeof data.limit is 'function'
            logs = ['WHERE', JSON.stringify(data), 'FROM', objectStoreName]

        if indexName
          logs = logs.concat(['INDEX', indexName])

        this.handleLog
          type: 'request'
          data: logs.join(' ')

      this.handleLog
        type: 'transaction.end'

  # Public API
  return Connection.API

# Export
if typeof exports isnt 'undefined'
  module.exports = factory()
else
  this.Connection = factory()
