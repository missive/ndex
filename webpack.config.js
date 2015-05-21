var webpack = require('webpack')

// Examples & Specs
var examples_and_specs = {
  cache: true,
  watch: true,

  entry: {
    'spec': ['mocha!./spec'],
  },

  output: {
    filename: '[name].js'
  },

  module: {
    loaders: [
      { test: /\.coffee$/, loader: 'coffee-loader' },
    ]
  },

  resolve: {
    root: __dirname,
    extensions: ['', '.js', '.coffee'],
    alias: {
      'ndex': 'lib/ndex.coffee'
    }
  },
}

// Ndex
var ndex = {
  cache: true,

  entry: './lib/ndex.coffee',
  output: {
    filename: 'ndex.min.js',
    library: 'Ndex',
    libraryTarget: 'umd',
  },

  module: {
    loaders: [
      { test: /\.coffee$/, loader: 'coffee-loader' },
    ]
  },

  resolve: {
    extensions: ['', '.js', '.coffee'],
  },

  plugins: [
    new webpack.optimize.UglifyJsPlugin({
      compressor: { warnings: false }
    })
  ],
}

// Export
module.exports = {
  build: [examples_and_specs],
  dist:  [ndex],
}
