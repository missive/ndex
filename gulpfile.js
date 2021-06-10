var gulp = require('gulp');
var del = require('del');
var connect = require('gulp-connect');
var webpack = require('gulp-webpack');
var webpackConfig = require('./webpack.config.js');

var port = process.env.PORT || 8080;
var reloadPort = process.env.RELOAD_PORT || 35729;

function webpackFor(target) {
  del([target])

  configs = webpackConfig[target]
  if (!Array.isArray(configs)) { configs = [configs] }

  let promises = []

  for (var i = 0; i < configs.length; i++) {
    config = configs[i]

    let promise = webpack(config)
      .pipe(gulp.dest(target))

    promises.push(promise)
  }

  return Promise.all(promises)
}

function build() {
  return webpackFor('build')
}

function dist() {
  return webpackFor('dist')
}

function serve() {
  connect.server({
    port: port,
    livereload: {
      port: reloadPort
    }
  });
}

function reloadJs() {
  return gulp.src('./build/*.js')
    .pipe(connect.reload());
}

function watch() {
  gulp.watch(['./build/*.js'], reloadJs);
}

exports.dist = dist
exports.default = gulp.parallel(build, serve, watch)
