import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'

const source = fs.readFileSync(
  new URL('../NeuroMetaDemo/ViewModels/ViewModels.swift', import.meta.url),
  'utf8'
)
const contentViewSource = fs.readFileSync(
  new URL('../NeuroMetaDemo/Views/ContentView.swift', import.meta.url),
  'utf8'
)

function methodBody(name) {
  const marker = `func ${name}()`
  const start = source.indexOf(marker)
  assert.notEqual(start, -1, `${name} method must exist`)

  const openBrace = source.indexOf('{', start)
  assert.notEqual(openBrace, -1, `${name} method must have a body`)

  let depth = 0
  for (let index = openBrace; index < source.length; index += 1) {
    const char = source[index]
    if (char === '{') depth += 1
    if (char === '}') {
      depth -= 1
      if (depth === 0) {
        return source.slice(openBrace + 1, index)
      }
    }
  }

  assert.fail(`${name} method body must be closed`)
}

test('iOS demo data listener lifecycle is idempotent', () => {
  const startBody = methodBody('startListening')
  const stopBody = methodBody('stopListening')

  assert.match(
    startBody,
    /guard\s+realtimeListenerId\s*==\s*nil,\s*statusListenerId\s*==\s*nil,\s*unfilteredListenerId\s*==\s*nil\s+else\s*\{\s*return\s*\}/s,
    'startListening must not add duplicate DataCollector listeners when already active'
  )

  assert.match(
    stopBody,
    /guard\s+realtimeListenerId\s*!=\s*nil\s*\|\|\s*statusListenerId\s*!=\s*nil\s*\|\|\s*unfilteredListenerId\s*!=\s*nil\s+else\s*\{\s*return\s*\}/s,
    'stopListening must avoid repeated SDK stop calls when listeners are already cleared'
  )
})

test('iOS demo uses the binary-compatible SDK entry point', () => {
  const appSource = `${source}\n${contentViewSource}`
  assert.match(appSource, /NeuroMeta\.shared/)
  assert.doesNotMatch(appSource, /NeuroMetaSDK\.shared/)
})
