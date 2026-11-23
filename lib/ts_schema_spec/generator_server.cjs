// Runs ts-json-schema-generator's own CLI once per request line, in one
// process, so the TypeScript work every run repeats is done once: parsing
// tsconfig (a glob over the project) and the lib and node_modules
// declarations. Each request is the CLI's argv as a JSON array; each reply is
// {stdout, stderr, status}, one JSON line.
const fs = require('node:fs')
const path = require('node:path')
const readline = require('node:readline')

const generatorDir = path.dirname(
  require.resolve('ts-json-schema-generator/package.json', {
    paths: [process.cwd()],
  })
)
// Before 2.4 the CLI fails with process.exit, which would end node on every
// schema that fails to generate.
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

function snapshot(calls) {
  return JSON.stringify(calls.map(([method, path]) => ts.sys[method](path)))
}

function cachingHost(options) {
  const key = JSON.stringify(options)
  if (!hosts.has(key)) {
    const host = ts.createCompilerHost(options)
    const sourceFiles = new Map()
    const getSourceFile = host.getSourceFile
    host.getSourceFile = (fileName, languageVersion, onError, createNew) => {
      // TypeScript 5 passes an object carrying the module format a file is
      // parsed as, which a package.json "type" can change.
      const format =
        typeof languageVersion === 'object'
          ? [languageVersion.languageVersion, languageVersion.impliedNodeFormat]
          : [languageVersion]
      const key = JSON.stringify([fileName, ...format])
      const cached = sourceFiles.get(key)
      if (!createNew && cached?.text === ts.sys.readFile(fileName))
        return cached
      const file = getSourceFile(fileName, languageVersion, onError, createNew)
      if (file) sourceFiles.set(key, file)
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
      value: (json, host, ...rest) => {
        if (host !== ts.sys)
          return ts.parseJsonConfigFileContent(json, host, ...rest)
        const key = JSON.stringify([json, ...rest])
        let cached = parsedConfigs.get(key)
        if (!cached || cached.state !== snapshot(cached.calls)) {
          // Records the configs json extends, and where TypeScript looked for
          // them, with what it found, which a later edit or install can change.
          const calls = []
          const recordingHost = Object.create(host)
          for (const method of ['readFile', 'fileExists', 'directoryExists']) {
            if (!host[method]) continue
            recordingHost[method] = (path) => {
              const result = host[method](path)
              calls.push([method, path, result])
              return result
            }
          }
          const parsed = ts.parseJsonConfigFileContent(
            json,
            recordingHost,
            ...rest
          )
          const state = JSON.stringify(calls.map(([, , result]) => result))
          cached = { parsed, calls, state }
          parsedConfigs.set(key, cached)
        }
        return { ...cached.parsed, options: { ...cached.parsed.options } }
      },
    },
    createProgram: {
      enumerable: true,
      value: (rootNames, options, host, oldProgram, ...rest) => {
        if (!Array.isArray(rootNames))
          return ts.createProgram(rootNames, options, host, oldProgram, ...rest)
        return ts.createProgram(
          rootNames,
          options,
          host || cachingHost(options),
          oldProgram,
          ...rest
        )
      },
    },
  }
)

function runCli(args) {
  const chunks = []
  const writes = {}
  const { argv } = process
  // Captures the streams rather than console methods, so console.dir or
  // TypeScript's own ts.sys.write can't land on the reply pipe.
  for (const name of ['stdout', 'stderr']) {
    writes[name] = process[name].write
    process[name].write = (chunk, encoding, callback) => {
      const text = typeof chunk === 'string'
      chunks.push([
        name,
        Buffer.from(
          chunk,
          text && typeof encoding === 'string' ? encoding : undefined
        ),
      ])
      ;(typeof encoding === 'function' ? encoding : callback)?.()
      return true
    }
  }
  // --help and --version end node with process.exit; what they wrote reaches
  // ts_schema_spec through stderr, written before the process goes.
  const flush = () =>
    fs.writeSync(2, Buffer.concat(chunks.map(([, bytes]) => bytes)))
  process.once('exit', flush)
  process.argv = [argv[0], cliPath, ...args]
  process.exitCode = 0
  const index = module.children.indexOf(require.cache[cliPath])
  if (index >= 0) module.children.splice(index, 1)
  delete require.cache[cliPath]
  try {
    require(cliPath)
  } catch (e) {
    chunks.push(['stderr', Buffer.from(String(e?.stack ?? e))])
    process.exitCode = 1
  } finally {
    process.removeListener('exit', flush)
    for (const name of ['stdout', 'stderr']) process[name].write = writes[name]
    process.argv = argv
  }
  const status = process.exitCode
  process.exitCode = 0
  const text = (name) =>
    Buffer.concat(
      chunks.filter(([from]) => from === name).map(([, bytes]) => bytes)
    ).toString()
  return { stdout: text('stdout'), stderr: text('stderr'), status }
}

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  process.stdout.write(`${JSON.stringify(runCli(JSON.parse(line)))}\n`)
  // Marks where stderr written after this reply begins, once any warning node
  // emits on the next tick is out.
  setImmediate(() => process.stderr.write('\0'))
})
