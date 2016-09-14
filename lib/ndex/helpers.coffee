module.exports =
  # Recursively stringify found functions of data
  stringifyFunctions: (data, stringified = []) ->
    # Functions
    if typeof data is 'function'
      data.toString().replace(/\s\s+/g, ' ')

    # Objects & Arrays
    else if typeof data is 'object'
      if stringified.indexOf(data) >= 0
        data
      else
        stringified.push(data)
        for k, v of data
          data[k] = this.stringifyFunctions(v, stringified)

      data

    # Other
    else
      data
