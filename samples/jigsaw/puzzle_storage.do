import { exists, readText, writeText, IoError } from "std/fs"
import { formatJsonValue, parseJsonValue } from "std/json"
import { dataDirectory, join } from "std/path"

import {
  Piece,
  PuzzleCamera,
  PuzzleState,
  createPuzzleState,
  validatePuzzleState,
} from "./jigsaw_model"
import { JigsawRuntime } from "./client_runtime"

readonly PUZZLE_STATE_FILE = "puzzle-state.json"

function ioErrorMessage(operation: string, path: string, error: IoError): string {
  return "${operation} failed for ${path}: ${error}"
}

export function puzzleStatePath(): string {
  directory := dataDirectory() else error {
    panic("Failed to resolve puzzle state data directory: ${error}")
  }
  return join([directory, PUZZLE_STATE_FILE])
}

export function loadPuzzleState(path: string): Result<PuzzleState, string> {
  text := readText(path) else error {
    return Failure(ioErrorMessage("read", path, error))
  }

  try json := parseJsonValue(text)
  try state := PuzzleState.fromJsonValue(json)
  try validatePuzzleState(state)
  return Success(state)
}

export function savePuzzleState(path: string, pieces: Piece[], drawOrder: int[], camera: PuzzleCamera): Result<void, string> {
  state := createPuzzleState(pieces, drawOrder, camera)
  try validatePuzzleState(state)

  writeText(path, formatJsonValue(state.toJsonObject())) else error {
    return Failure(ioErrorMessage("write", path, error))
  }

  return Success()
}

export function savePuzzleStateSafely(
  statePath: string,
  pieces: Piece[],
  drawOrder: int[],
  camera: PuzzleCamera,
): void {
  savePuzzleState(statePath, pieces, drawOrder, camera) else error {
    println("Failed to save puzzle state: ${error}")
  }
}

export function savePuzzleStateForRuntime(
  runtime: JigsawRuntime,
  statePath: string,
  pieces: Piece[],
  drawOrder: int[],
  camera: PuzzleCamera,
): void {
  if !runtime.isServerMode() {
    canonical := runtime.currentState(pieces, drawOrder, camera)
    savePuzzleStateSafely(statePath, canonical.pieces, canonical.drawOrder, camera)
  }
}

export function loadSavedPuzzleStateForLocalMode(
  serverAddress: string | null,
  statePath: string,
  fallback: PuzzleState,
): PuzzleState {
  if serverAddress == null && exists(statePath) {
    case loadPuzzleState(statePath) {
      loaded: Success -> return loaded.value
      failed: Failure -> println("Ignoring saved puzzle state: ${failed.error}")
    }
  }
  return fallback
}
