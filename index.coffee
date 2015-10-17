
process = require 'process'
child = require 'child_process'

oboe = require 'oboe'

proto = require './i3bar-proto'

sig = require 'get-signal'
EventEmitter = require 'events'

class Client extends EventEmitter
  constructor: (cmd_line) ->
    @process = child.spawn 'bash', ['-c', cmd_line]

    processHeader = (header) =>
      @version = header.version
      @stop_signal = if header.stop_signal? then sig.getSignalName(header.stop_signal) else 'SIGSTOP'
      @cont_signal = if header.cont_signal? then sig.getSignalName(header.cont_signal) else 'SIGCONT'
      @click_events = !!header.click_events
      @process.stdin.write '[' if @click_events
      @emit 'ready'

    processData = (boxes) =>
      @emit('msg', boxes...)

    o = oboe(@process.stdout)
    o.node('{version}', (header) ->
      @forget()
      processHeader(header)
      o.node('![*]', processData)
      oboe.drop)

  click: (event) -> @process.stdin.write JSON.stringify(event) + ',' if @click_events

  stop: -> process.kill @process.pid, @stop_signal
  cont: -> process.kill @process.pid, @cont_signal

clients = [(new Client 'node ' + __dirname + '/click_example.js'), (new Client 'i3status -c ~/.i3/status')]

i = 0
for c in clients
  c.on 'ready', ->
    start() if ++i == clients.length

start = ->
  version = Math.max (c.version for c in clients)...
  click_events = clients.some (c) -> c.click_events

  p = proto({version: version, click_events: click_events})

  p.on 'stop', -> c.stop() for c in clients
  p.on 'cont', -> c.cont() for c in clients
  p.on 'click', (e) -> c.click e for c in clients

  cache = []

  pending = false
  send = ->
    if not pending
      pending = true
      setImmediate ->
        pending = false
        msgs = [].concat cache...
        p.send msgs...

  for c,i in clients
    do (i) ->
      c.on 'msg', (msgs...) ->
        cache[i] = msgs
        send()
