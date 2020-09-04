factory = ->
  Connection = {}

  # Public API
  class Connection.API
    CONNECTION_TIMEOUT: 3000
    REQUEST_TIMEOUT: 3000

    constructor: (@name, @migrations) ->
      @database = null
      @queue = {}
      @logging = new Connection.Logging

    parseMigrations: (migrations) ->
      if version = migrations.version
        @version = version
        delete migrations.version

      keys = Object.keys(migrations).sort()
      keys.map (key) =>
        version = parseInt(key)
        titleMatches = key.match(/_(.+)/)
        title = if titleMatches then titleMatches[1].replace(/(\w)([A-Z])/g, ($1, $2, $3) -> "#{$2} #{$3.toLowerCase()}") else ''
        actions = migrations[key] || []
        actions = [actions] unless Array.isArray(actions)

        { version, title, actions, key }

    deleteDatabase: ->
      new Promise (resolve) =>
        return resolve() unless @database
        this.close()

        request = indexedDB.deleteDatabase(@database.name)
        request.onsuccess = (e) -> setTimeout (-> resolve()), 0

    open: ->
      return @dbPromise if @dbPromise
      @dbPromise = new Promise (resolve, reject) =>
        return reject('indexedDB isn’t supported') unless self.indexedDB
        migrations = this.parseMigrations(@migrations)

        try
          request = indexedDB.open(@name, @version || migrations.length + 1)
          if @CONNECTION_TIMEOUT? && @CONNECTION_TIMEOUT > -1
            request.__timeout = setTimeout ->
              request.__timedout = true
              reject(new Error('Connection timed out'))
            , @CONNECTION_TIMEOUT
        catch e
          clearTimeout(request.__timeout)
          return reject(e.message || e.name)

        # Migrations
        request.onupgradeneeded = (e) =>
          clearTimeout(request.__timeout)
          return if request.__timedout

          db = e.target.result
          transaction = e.target.transaction

          migrationTransaction = new Connection.Migration(db, transaction)
          migrationTransaction.createObjectStore('migrations', keyPath: 'version')

          for migration in migrations
            for action in migration.actions
              migrationTransaction[action.type]?(action.args...)

            transaction.objectStore('migrations').put(migration)

        # Opened
        request.onsuccess = (e) =>
          clearTimeout(request.__timeout)
          return if request.__timedout

          db = e.target.result
          objectStoreNames = [].slice.call(db.objectStoreNames)
          this.createNamespaceForObjectStores(objectStoreNames)

          # Same DB opened on another tab
          db.onversionchange = =>
            this.close()

          @database = db
          resolve(objectStoreNames)

        # Error
        request.onerror = (e) =>
          reject(request.error.message || request.error.name)

    close: ->
      new Promise (resolve) =>
        delete @dbPromise if @dbPromise
        @database.close() if @database

        resolve()

    get: (objectStoreName, key, indexName) ->
      new Promise (resolve, reject) =>
        if Array.isArray(key)
          promises = Promise.all key.map (k) => this.get(objectStoreName, k)
          promises.then(resolve)
        else
          this.enqueue 'read', objectStoreName, (transaction) =>
            @logging.addRequest(transaction, 'get', objectStoreName, indexName, { key: key })

            request = this.createRequest({ transaction, objectStoreName, indexName, reject })
            request.get(key).onsuccess = (e) ->
              clearTimeout(request.__timeout)
              return if request.__timedout

              value = e.target.result
              value = null if value is undefined

              resolve(value)

    getFirst: (objectStoreName, indexName) ->
      new Promise (resolve, reject) =>
        this.enqueue 'read', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'getFirst', objectStoreName, indexName)

          request = this.createRequest({ transaction, objectStoreName, indexName, reject })
          request.openCursor().onsuccess = (e) ->
            clearTimeout(request.__timeout)
            return if request.__timedout

            if cursor = e.target.result
              value = cursor.value
              unless request.keyPath
                value._key = cursor.key

              resolve(value)
            else
              resolve(null)

    getAll: (objectStoreName, indexName) ->
      new Promise (resolve, reject) =>
        this.enqueue 'read', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'getAll', objectStoreName, indexName)

          result = []
          request = this.createRequest({ transaction, objectStoreName, indexName, reject })
          request.openCursor().onsuccess = (e) ->
            clearTimeout(request.__timeout)
            return if request.__timedout

            return resolve(result) unless cursor = e.target.result
            value = cursor.value
            unless request.keyPath
              value._key = cursor.key

            result.push(value)
            cursor.continue()

    count: (objectStoreName, indexName) ->
      new Promise (resolve, reject) =>
        this.enqueue 'read', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'count', objectStoreName, indexName)

          request = this.createRequest({ transaction, objectStoreName, indexName, reject })
          request.count().onsuccess = (e) ->
            clearTimeout(request.__timeout)
            return if request.__timedout

            value = e.target.result
            value = 0 unless value

            resolve(value)

    add: (objectStoreName, key, data) ->
      [key, data] = [null, key] if data is undefined

      new Promise (resolve, reject) =>
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
            request = this.createRequest({ transaction, objectStoreName, reject })
            request.put(args...).onsuccess = (e) ->
              clearTimeout(request.__timeout)
              return if request.__timedout

              data._key = e.target.result
              resolve(data)

    update: (objectStoreName, key, value) ->
      new Promise (resolve, reject) =>
        this.enqueue 'write', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'update', objectStoreName, null, { key: key, data: value })

          getRequest = this.createRequest({ transaction, objectStoreName, reject })
          getRequest.get(key).onsuccess = (e) =>
            clearTimeout(getRequest.__timeout)
            return if getRequest.__timedout

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
            putRequest = this.createRequest({ transaction, objectStoreName, reject })
            putRequest.put(args...).onsuccess = ->
              clearTimeout(putRequest.__timeout)
              return if putRequest.__timedout

              resolve(data)

    increment: (objectStoreName, key, value = 1, decrement) ->
      new Promise (resolve, reject) =>
        this.enqueue 'write', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, (if decrement then 'decrement' else 'increment'), objectStoreName, null, { key: key, data: value })

          getRequest = this.createRequest({ transaction, objectStoreName, reject })
          getRequest.get(key).onsuccess = (e) =>
            clearTimeout(getRequest.__timeout)
            return if getRequest.__timedout

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
            putRequest = this.createRequest({ transaction, objectStoreName, reject })
            putRequest.put(args...).onsuccess = ->
              clearTimeout(putRequest.__timeout)
              return if putRequest.__timedout

              resolve(data)

    decrement: (objectStoreName, key, value) ->
      this.increment(objectStoreName, key, value, true)

    delete: (objectStoreName, key) ->
      new Promise (resolve, reject) =>
        if Array.isArray(key)
          promises = Promise.all key.map (k) => this.delete(objectStoreName, k)
          promises.then(resolve)
        else
          this.enqueue 'write', objectStoreName, (transaction) =>
            @logging.addRequest(transaction, 'delete', objectStoreName, null, { key: key })

            request = this.createRequest({ transaction, objectStoreName, reject })
            request.delete(key).onsuccess = (e) ->
              clearTimeout(request.__timeout)
              return if request.__timedout

              resolve(key)

    deleteWhere: (objectStoreName, predicates, indexName) ->
      predicates.remove = true
      this.where(objectStoreName, predicates, indexName)

    clear: (objectStoreName) ->
      new Promise (resolve, reject) =>
        this.enqueue 'write', objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'clear', objectStoreName)

          request = this.createRequest({ transaction, objectStoreName, reject })
          request.clear().onsuccess = ->
            clearTimeout(request.__timeout)
            return if request.__timedout

            resolve()

    clearAll: ->
      new Promise (resolve, reject) =>
        objectStoreNames = [@database.objectStoreNames...]
        objectStoreNames = objectStoreNames.filter (objectStoreName) -> objectStoreName isnt 'migrations'

        promises = Promise.all objectStoreNames.map (objectStoreName) => this.clear(objectStoreName)
        promises.then(resolve)
        promises.catch(reject)

    reset: (objectStoreName, key, data) ->
      new Promise (resolve, reject) =>
        clearPromise = this.clear(objectStoreName)
        clearPromise.catch(reject)
        clearPromise.then =>
          addPromise = this.add(objectStoreName, key, data)
          addPromise.catch(reject)
          addPromise.then(resolve)

    index: (objectStoreName, indexName) ->
      this.createNamespaceForIndex(indexName, objectStoreName)

    where: (objectStoreName, predicates, indexName) ->
      readWrite = if predicates.remove then 'write' else 'read'

      new Promise (resolve, reject) =>
        this.enqueue readWrite, objectStoreName, (transaction) =>
          @logging.addRequest(transaction, 'where', objectStoreName, indexName, { data: predicates })

          { lt, lteq, gt, gteq, eq, limit, offset, only, contains, except, uniq, order, remove } = predicates
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

          request = this.createRequest({ transaction, objectStoreName, indexName, reject })
          request = if range then request.openCursor(range, order) else request.openCursor()
          request.onsuccess = (e) =>
            clearTimeout(request.__timeout)
            return if request.__timedout

            return resolve(result) unless cursor = e.target.result
            value = cursor.value

            # Only
            if eqIsArray
              keyPath = e.target.source.keyPath
              only ||= {}
              only[keyPath] = eq

            for k, v of only
              return cursor.continue() unless hasValues(value, k, v)

            # Contains
            for k, v of contains
              v = [v] unless Array.isArray(v)

              a = value[k]
              a = [a] unless Array.isArray(a)

              return cursor.continue() unless this.intersect(a, v).length

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
              if typeof limit is 'function' && limit(result)
                return resolve(result)
              else if limit is result.length
                return resolve(result)

            cursor.continue()

    # Helpers
    getMethodsForObjectStore: -> @_getMethodsForObjectStore ||= ['get', 'getFirst', 'getAll', 'count', 'add', 'update', 'increment', 'decrement', 'delete', 'deleteWhere', 'clear', 'reset', 'index', 'where']
    getMethodsForIndex: -> @_getMethodsForIndex ||= ['get', 'getFirst', 'getAll', 'count', 'where', 'deleteWhere']

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

    createRequest: ({ transaction, objectStoreName, indexName, reject }) ->
      objectStore = transaction.objectStore(objectStoreName)
      request = if indexName then objectStore.index(indexName) else objectStore

      if reject && @REQUEST_TIMEOUT? && @REQUEST_TIMEOUT > -1
        request.__timeout = setTimeout ->
          request.__timedout = true
          reject(new Error('Request timed out'))
        , @REQUEST_TIMEOUT

      request

    createTransaction: (mode, objectStoreName, callback) ->
      this.open()
        .then =>
          transaction = @database.transaction([objectStoreName], mode)
          callback(transaction)

        .catch (err) =>
          throw(err)

    intersect: (a, b) ->
      ai = 0; bi = 0; result = []
      while (ai < a.length && bi < b.length)
        if      (a[ai] < b[bi]) then ai++
        else if (a[ai] > b[bi]) then bi++
        else
          result.push(a[ai])
          ai++; bi++

      result

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
      transaction.onabort    = callback
      transaction.onerror    = callback
      transaction.oncomplete = callback

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
          when 'getFirst'
            logs = ['GET FIRST', key, 'FROM', objectStoreName]
          when 'getAll'
            logs = ['GET ALL', 'FROM', objectStoreName]
          when 'count'
            logs = ['COUNT', 'FROM', objectStoreName]
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
