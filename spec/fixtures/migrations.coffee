migrations =
  '201412041358_CreateUsersObjectStore': [
    {
      type: 'createObjectStore'
      args: ['users', { keyPath: 'id', autoIncrement: true }]
    }
  ]

  '201412041527_CreateOrganizationsObjectStore': {
    type: 'createObjectStore'
    args: ['organizations']
  }

  '201412041527_AddJobIndexToUsers': [
    {
      type: 'createIndex'
      args: ['users', 'job', 'job']
    }]

module.exports = migrations
