import { runMainEventLoop } from "std/event"

import {
  JigsawHttpServerOptions,
  createDefaultJigsawServerState,
  defaultJigsawServerStatePath,
  startJigsawHttpServer,
} from "./index"

function usage(): void {
  println("Usage: doof run game/samples/jigsaw-server -- [--listen host:port] [--state path] [--no-persist] [--reset]")
}

function applyListenAddress(options: JigsawHttpServerOptions, text: string): Result<void, string> {
  separator := text.indexOf(":")
  if separator <= 0 || separator >= text.length - 1 {
    return Failure("Listen address must be host:port")
  }

  port := int.parse(text.slice(separator + 1)) else error {
    return Failure("Invalid listen port: ${error}")
  }

  options.host = text.substring(0, separator)
  options.port = port
  return Success()
}

function parseOptions(args: string[]): Result<JigsawHttpServerOptions, string> {
  let options = JigsawHttpServerOptions {}
  try defaultStatePath := defaultJigsawServerStatePath()
  options.statePath = defaultStatePath

  let index = 0
  while index < args.length {
    if args[index] == "--listen" {
      if index + 1 >= args.length {
        return Failure("--listen requires host:port")
      }
      try applyListenAddress(options, args[index + 1])
      index = index + 2
    } else if args[index] == "--state" {
      if index + 1 >= args.length {
        return Failure("--state requires a path")
      }
      options.statePath = args[index + 1]
      index = index + 2
    } else if args[index] == "--no-persist" {
      options.statePath = null
      index = index + 1
    } else if args[index] == "--reset" {
      options.resetState = true
      index = index + 1
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
