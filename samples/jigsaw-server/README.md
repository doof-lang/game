# Jigsaw Server

Runs a small WebSocket server for the jigsaw sample so multiple clients can share one board.

## Run

```sh
doof run game/samples/jigsaw-server
```

By default the server listens on `127.0.0.1:8765` and accepts WebSocket connections at `/jigsaw`.

Point the jigsaw sample at `ws://127.0.0.1:8765/jigsaw` to use the shared board.
The sample currently configures its server address in `game/samples/jigsaw/main.do`.

## Options

```sh
doof run game/samples/jigsaw-server -- [--listen host:port] [--state path] [--no-persist] [--reset]
```

- `--listen host:port` changes the bind address.
- `--state path` changes the JSON state file path.
- `--no-persist` keeps board state in memory only.
- `--reset` starts from a fresh board. If persistence is enabled, it also overwrites the saved state file with the fresh board.

The default state file lives in the platform data directory for `dev.doof.jigsaw-server`.

## Tests

```sh
doof test game/samples/jigsaw-server
```
