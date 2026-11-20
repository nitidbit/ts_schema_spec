// Runs ts-json-schema-generator's own CLI once per request line, in one
// process, so the TypeScript work every run repeats is done once: parsing
// tsconfig (a glob over the project) and the lib and node_modules
// declarations. Each request is the CLI's argv as a JSON array; each reply is
// {stdout, stderr, status}, one JSON line.
const fs = require('node:fs')
const path = require('node:path')
const readline = require('node:readline')
const { format } = require('node:util')

const generatorDir = path.dirname(
  require.resolve('ts-json-schema-generator/package.json', {
    paths: [process.cwd()],
  })
)
// Before 2.4 the CLI writes the schema with process.stdout.write and fails
// with process.exit, neither of which runCli can capture.
const { version } = require(path.join(generatorDir, 'package.json'))
const [major, minor] = version.split('.').map(Number)
if (major !== 2 || minor < 4) {
  throw new Error(
    `ts_schema_spec supports ts-json-schema-generator 2.4 or later 2.x; this project has ${version}.`
  )
}
// The copy the generator itself loads, which may be nested under it rather
// than the project's own.
const tsPath = require.resolve('typescript', { paths: [generatorDir] })
const cliPath = path.join(generatorDir, 'dist/ts-json-schema-generator.js')
const ts = require(tsPath)

const parsedConfigs = new Map()
const hosts = new Map()
let previousProgram

function cachingHost(options) {
  const key = JSON.stringify(options)
  if (!hosts.has(key)) {
    const host = ts.createCompilerHost(options)
    const sourceFiles = new Map()
    const getSourceFile = host.getSourceFile
    host.getSourceFile = (fileName, languageVersion, onError, createNew) => {
      const cached = sourceFiles.get(fileName)
      if (!createNew && cached?.text === ts.sys.readFile(fileName))
        return cached
      const file = getSourceFile(fileName, languageVersion, onError, createNew)
      if (file) sourceFiles.set(fileName, file)
      return file
    }
    hosts.set(key, host)
  }
  return hosts.get(key)
}

// TypeScript's exports are read-only getters, so the generator is handed a
// module that copies them all as its own and overrides these two.
require.cache[tsPath].exports = Object.defineProperties(
  {},
  {
    ...Object.getOwnPropertyDescriptors(ts),
    parseJsonConfigFileContent: {
      enumerable: true,
      value: (...args) => {
        const key = JSON.stringify(args.filter((arg) => arg !== ts.sys))
        if (!parsedConfigs.has(key))
          parsedConfigs.set(key, ts.parseJsonConfigFileContent(...args))
        const parsed = parsedConfigs.get(key)
        return { ...parsed, options: { ...parsed.options } }
      },
    },
    createProgram: {
      enumerable: true,
      value: (rootNames, options, host, oldProgram, ...rest) => {
        if (!Array.isArray(rootNames))
          return ts.createProgram(rootNames, options, host, oldProgram, ...rest)
        previousProgram = ts.createProgram(
          rootNames,
          options,
          host || cachingHost(options),
          oldProgram || previousProgram,
          ...rest
        )
        return previousProgram
      },
    },
  }
)

function runCli(args) {
  const stdout = []
  const stderr = []
  const { log, info, debug, warn, error } = console
  const { argv } = process
  console.log =
    console.info =
    console.debug =
      (...line) => stdout.push(format(...line))
  console.warn = console.error = (...line) => stderr.push(format(...line))
  process.argv = [argv[0], cliPath, ...args]
  process.exitCode = 0
  const index = module.children.indexOf(require.cache[cliPath])
  if (index >= 0) module.children.splice(index, 1)
  delete require.cache[cliPath]
  try {
    require(cliPath)
  } catch (e) {
    stderr.push(String(e?.stack ?? e))
    process.exitCode = 1
  } finally {
    Object.assign(console, { log, info, debug, warn, error })
    process.argv = argv
  }
  const status = process.exitCode
  process.exitCode = 0
  return { stdout: stdout.join('\n'), stderr: stderr.join('\n'), status }
}

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  process.stdout.write(`${JSON.stringify(runCli(JSON.parse(line)))}\n`)
})
