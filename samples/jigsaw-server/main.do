import { runMainEventLoop } from "std/event"

import {
  JigsawHttpServerOptions,
  createDefaultJigsawServerState,
  startJigsawHttpServer,
} from "./index"

function usage(): void {
  println("Usage: doof run game/samples/jigsaw-server -- [--listen host:port]")
}

function parseListenAddress(text: string): Result<JigsawHttpServerOptions, string> {
  separator := text.indexOf(":")
  if separator <= 0 || separator >= text.length - 1 {
    return Failure("Listen address must be host:port")
  }

  port := int.parse(text.slice(separator + 1)) else error {
    return Failure("Invalid listen port: ${error}")
  }

  return Success(JigsawHttpServerOptions {
    host: text.substring(0, separator),
    port,
  })
}

function parseOptions(args: string[]): Result<JigsawHttpServerOptions, string> {
  let options = JigsawHttpServerOptions {}
  let index = 0
  while index < args.length {
    if args[index] == "--listen" {
      if index + 1 >= args.length {
        return Failure("--listen requires host:port")
      }
      try parsed := parseListenAddress(args[index + 1])
      options = parsed
      index = index + 2
    } else {
      return Failure("Unknown option ${args[index]}")
    }
  }
  return Success(options)
}

function main(args: string[]): int {
  options := parseOptions(args) else error {
    println(error)
    usage()
    return 1
  }

  server := startJigsawHttpServer(createDefaultJigsawServerState(), options) else error {
    println("Could not start jigsaw server: ${error}")
    return 1
  }

  println("Jigsaw server listening at ws://${server.host}:${server.port}${server.socketPath}")
  runMainEventLoop()
  server.close()
  return 0
}
