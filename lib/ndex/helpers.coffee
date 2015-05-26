module.exports =
  # Recursively stringify found functions of data
  stringifyFunctions: (data) ->
    # Functions
    if typeof data is 'function'
      data.toString().replace(/\s\s+/g, ' ')

    # Objects & Arrays
    else if typeof data is 'object'
      for k, v of data
        data[k] = this.stringifyFunctions(v)

      data

    # Other
    else
      data
