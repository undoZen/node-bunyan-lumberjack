
{Writable} = require 'stream'
lumberjack = require 'lumberjack-protocol'
bunyan     = require 'bunyan'

LEVELS = do ->
    answer = {}

    ['trace', 'debug', 'info', 'warn', 'error', 'fatal'].forEach (level) ->
        answer[bunyan[level.toUpperCase()]] = level

    return answer

# Shallow clone
clone = (obj) ->
    answer = {}
    answer[key] = value for key, value of obj
    return answer

class BunyanLumberjackStream extends Writable
    constructor: (tlsOptions, lumberjackOptions={}, options={}) ->
        super {objectMode: true}

        @_client = lumberjack.client tlsOptions, lumberjackOptions

        @_client.on 'connect', (count) => @emit 'connect', count
        @_client.on 'dropped', (count) => @emit 'dropped', count
        @_client.on 'disconnect', (err) => @emit 'disconnect', err

        @_host = require('os').hostname()
        @_tags = options.tags ? ['bunyan']
        @_type = options.type
        @_application = options.appName ? process.title

        @on 'finish', =>
            @_client.close()

    _write: (entry, encoding, done) ->
        # Clone the entry so we can modify it
        entry = clone(entry)

        host = entry.hostname ? @_host

        # Massage the entry to look like a logstash entry.
        bunyanLevel = entry.level
        if LEVELS[entry.level]?
            entry.level = LEVELS[entry.level]

        entry.message = entry.msg ? ''
        delete entry.msg

        entry['@timestamp'] = entry.time.toISOString()
        delete entry.time

        delete entry.v

        # Add some extra fields
        entry.tags ?= @_tags
        entry.source = "#{host}/#{@_application}"
        if @_type? then entry.type = @_type

        @_client.writeDataFrame {
            line: JSON.stringify(entry)
            host: host
            bunyanLevel: bunyanLevel
        }

        done()

module.exports = (options={}) ->
    return new BunyanLumberjackStream(
        options.tlsOptions,
        options.lumberjackOptions,
        options
    )