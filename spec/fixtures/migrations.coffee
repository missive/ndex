migrations =
  # '201412041358_CreateUsersObjectStore': ->
  #   this.createObjectStore('users', { keyPath: 'id', autoIncrement: true })
  '201412041358_CreateUsersObjectStore': [
    {
      type: 'createObjectStore'
      args: ['users', { keyPath: 'id', autoIncrement: true }]
    }
  ]

  # '201412041527_CreateOrganizationsObjectStore': ->
  #   this.createObjectStore('organizations')
  '201412041527_CreateOrganizationsObjectStore': {
    type: 'createObjectStore'
    args: ['organizations']
  }

  # '201412041527_AddJobIndexToUsers': ->
  #   this.createIndex('users', 'job', 'job')
  '201412041527_AddJobIndexToUsers': [
    {
      type: 'createIndex'
      args: ['users', 'job', 'job']
    }]

module.exports = migrations
