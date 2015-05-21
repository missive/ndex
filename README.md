# Ndex — An indexedDB wrapper
It will automatically handle transactions and reuse them as many times as possible within the same event loop. You can therefore `Ndex.get` in a loop and Ndex will still only create a single transaction for maximum performance.

## Table of Content
- [API](#API)
  - [connect](#connect)
  - [get](#get)
  - [getAll](#getall)
  - [add](#add)
  - [update](#update)
  - [increment](#increment)
  - [decrement](#decrement)
  - [delete](#delete)
  - [deleteWhere](#deletewhere)
  - [clear](#clear)
  - [clearAll](#clearall)
  - [index](#index)
  - [where](#where)
- [Migrations](#Migrations)
- [Logging](#Logging)
- [Specs](#Specs)

## API
Ndex methods return a [Promise](https://developer.mozilla.org/en/docs/Web/JavaScript/Reference/Global_Objects/Promise), which means you can chain them or call them concurrently with `Promise.all`.

```js
// Result is accessible via .then
Ndex.users.get(1).then(function(data) {
  console.log(data) // => { id: 1 }
})

// All you can chain™
Ndex.open('test', migrations)
  .then(function() {
    return Promise.all([
      Ndex.users.add({ id: 1, name: 'e' })
      Ndex.users.add({ id: 2, name: 'r' })
    ])
  })
  .then(function() {
    return Ndex.users.get(1)
  })
  .then(function() {
    console.log('done')
  })
```

CoffeeScript sweetness
```coffee
# Haters gonna hate
Ndex.open('test', migrations)
  .then -> Promise.all([
    Ndex.users.add(id: 1, name: 'e')
    Ndex.users.add(id: 2, name: 'r')
   ])
  .then -> Ndex.users.get(1)
  .then -> console.log('done')
```

### connect
Before using Ndex, you must always open a connection with the database. You must provide a name and a migrations object. You don’t have to provide a database version, Ndex will take care of that for you. See the [migrations](#Migrations) section.
```js
Ndex.connect('test', migrations).then(function(connection) {
  connection.users.get(1).then(function(userData) {
    console.log(userData)
  })
})
```

### get
`Connection#get` returns a single item (unless an array of keys is passed) even if multiple items match the search for it doesn’t use a cursor. If you want all results (`i.e. Connection.users.index('job').get('developer')`) use [`Connection#where`](#where).
```js
connection.users.get(1)
connection.users.get([1, 4])
```

### getAll
```js
connection.users.getAll()
```

### add
`Connection#add` overwrites the entry with the data passed.
```js
// Don’t provide a key for objectStores with a keyPath
connection.users.add({ id: 1, name: 'e', job: 'developer' })
connection.users.add([
  { id: 1, name: 'e', job: 'developer' },
  { id: 2, name: 'r', job: 'developer' },
])

// Provide a key for objectStores without keyPath
connection.organizations.add('missive', { name: 'missive', est: 2014 })
connection.organizations.add(
  ['missive', 'heliom'],
  [
    { name: 'missive', est: 2014 },
    { name: 'heliom',  est: 2012 },
  ]
)
```

### update
`Connection#update` only updates passed data without overwriting the entry. It will also insert the entry when non-existent.
```
connection.users.get(1) // { id: 1, name: 'e' }

// Waiting for the update success is required for the get to be accurate
connection.users.update(1, { name: 'r' }).then(function() {
  connection.users.get(1) // { id: 1, name: 'r' }
})
```

### increment
`Connection#increment` initializes attribute to zero if null and adds the value passed (default is 1). Only makes sense for number-based attributes.
```js
// For objectStores without keyPath
connection.stats.increment('visits')    // Increments visits entry by 1
connection.stats.increment('visits', 4) // Increments visits entry by 4

// For objectStores with a keyPath
connection.stats.increment(1, { count: 1 })            // Increments id 1’s count attribute by 1
connection.stats.increment(1, { visits: { count: 4 }}) // Increments id 1’s visits.count by 4
```

### decrement
`Ndex#decrement` is an alias for `Ndex#increment` where the value passed is changed to a negative.
```js
connection.stats.decrement('visits')    // Increments visits entry by -1
connection.stats.decrement('visits', 4) // Increments visits entry by -4
```

### delete
```js
connection.users.delete(1)
connection.users.delete([1, 4])
```

### deleteWhere
`connection#deleteWhere` is an alias for `Ndex#where:remove`, see [`Ndex#where`](#where).
```js
connection.users.deleteWhere({ gteq: 3 })
connection.users.index('job').deleteWhere({ eq: 'developer' })
```

### clear
Clear the given object store. Note that if the object store has an `autoIncrement: true` key, the key won’t be reseted.
```js
connection.users.clear()
```

### clearAll
```js
connection.clearAll()
```

### index
Indexes can be used with `get`, `getAll` and `where`.
```js
connection.users.index('job').get('developer')
```

### where
`Connection#where` uses a cursor to iterate on a given range. Use the keyPath predicates to narrow down your range and the keys predicates to filter items in your range. For maximum performance, you really want to be as precise as possible with the range.

```js
// keyPath predicates
// These will be applied to your objectStore’s key
connection.users.where({ lt: 3 })
connection.users.where({ lteq: 3 })
connection.users.where({ gt: 3 })
connection.users.where({ gteq: 3 })
connection.users.where({ eq: 3 })

// :eq also supports arrays. It will create a range between min (1) and max (3) (both inclusive) and filter out any results that aren’t 1 or 3 (2)
// Depending on the range it creates (i.e. `eq: [1, 1000]`), `Ndex.get([1, 1000])` will definitely be much more performant
connection.users.where({ eq: [1, 3] })

// When using an index, the predicate is applied to the index’s key
connection.users.index('job').where({ eq: 'developer' })

// Any keys predicates
// These can be used on any keys, even the non-indexed ones
connection.users.where({ only: { job: ['developer'] } })
connection.users.where({ except: { job: ['developer'] } })
connection.users.where({ uniq: 'job' })

// Pagination
connection.users.where({ limit: 3 })
connection.users.where({ offset: 2 })
connection.users.where({ order: 'desc' })

// By adding the :remove key, Ndex will delete found items from indexedDB
connection.users.where({ gteq: 3, remove: true }) // Is equivalent to `connection.users.deleteWhere({ gteq: 3 })`
```

## Migrations
With Ndex, you don’t have handle the database version. It will always increase on each reload. Fear not! Ndex is aware of its migrations and will never run the same migration twice. We haven’t experienced any performance issue with that checkup (that is done with the existing transaction when opening the database).

- [createObjectStore#Parameters](https://developer.mozilla.org/en-US/docs/Web/API/IDBDatabase.createObjectStore#Parameters)
- [deleteObjectStore#Parameters](https://developer.mozilla.org/en-US/docs/Web/API/IDBDatabase.deleteObjectStore#Parameters)
- [createIndex#Parameters](https://developer.mozilla.org/en-US/docs/Web/API/IDBObjectStore.createIndex#Parameters)
- [deleteIndex#Parameters](https://developer.mozilla.org/en-US/docs/Web/API/IDBObjectStore.deleteIndex#Parameters)

```js
migrations = {
  '201412041358_CreateUsersObjectStore': function() {
    this.createObjectStore('users', { keyPath: 'id', autoIncrement: true })
  },

  '201412041527_CreateOrganizationsObjectStore': function() {
    this.createObjectStore('organizations')
    this.createIndex('organizations', 'est', 'est')
  },

  '201412041527_AddJobIndexToUsers': function() {
    this.createIndex('users', 'job', 'job')
  }
}
```
![](http://f.cl.ly/items/3D1k1g1J0Z29381w2f3s/Screen%20Shot%202014-12-08%20at%2010.18.22%20PM.png)

## Logging
Ndex has a built-in logging system that will group requests by transaction. Gives you a pretty accurate idea of what Ndex does for you and where you can refactor your requests.
```js
// Can be info, log, dir
// `collapsed: true` by default
Ndex.logging.use('info', { collapsed: false })

connection.users.add({ id: 1, name: 'e', job: 'developer' })
connection.users.add({ id: 2, name: 'r', job: 'developer' })
connection.users.add({ id: 3, name: 'p', job: 'developer' })
connection.users.add({ id: 4, name: 't', job: 'designer'  })

setTimeout(function() {
  connection.users.get(1)
  connection.users.get(3)
}, 100)
```
![](http://f.cl.ly/items/021l173X1b451J2B3E2A/Screen%20Shot%202014-12-08%20at%209.58.25%20PM.png)

Without the timeout, Ndex will reuse the same transaction
```js
connection.users.add({ id: 1, name: 'e', job: 'developer' })
connection.users.add({ id: 2, name: 'r', job: 'developer' })
connection.users.add({ id: 3, name: 'p', job: 'developer' })
connection.users.add({ id: 4, name: 't', job: 'designer'  })

connection.users.get(1)
connection.users.get(3)
```
![](http://f.cl.ly/items/2G2R0L2h311U2M2L3M08/Screen%20Shot%202014-12-08%20at%2010.09.03%20PM.png)

## Dist
```sh
$ gulp dist
```

## Specs
```sh
$ gulp
$ open http://localhost:8080/spec
```
