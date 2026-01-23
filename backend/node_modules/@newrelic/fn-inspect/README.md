# @newrelic/fn-inspect

[![Test](https://github.com/newrelic-forks/node-fn-inspect/actions/workflows/test.yml/badge.svg)](https://github.com/newrelic-forks/node-fn-inspect/actions/workflows/test.yml)

This module exposes some useful information about functions from the v8 engine,
including:

- file and line number given a function reference

## Usage

Getting details about a function:

```js
const { funcInfo } = require('@newrelic/fn-inspect');

function testFn() {}

const results = funcInfo(testFn);
// => { lineNumber: 2, column: 15, file: 'example.js', method: 'testFn', type: 'Function' }
```

## Building locally

`npm run build` will build the project for your current OS and architecture.

## Publishing

Simply run `npm version` and then invoke the `release` workflow. You can run
`release` using the github UI or, if you have the github CLI installed, you
can run `gh workflow run release.yml`.

