# DiceDB

DiceDB is a fork of [Valkey](https://valkey.io/) (a fork of Redis). DiceDB extends Valkey with additional capabilities while staying fully compatible with Valkey and Redis tooling and SDK ecosystem.

This is a quick start guide. For full documentation, visit [dicedb.io](https://dicedb.io).

DiceDB builds on Valkey, so you may still see Valkey references in logs, metrics, and parts of the codebase.

> [!NOTE]
> DiceDB originally started as a Golang-based storage engine and offered reactivity and higher throughput as its core offering. That implementation is now archived: [dice-legacy](https://github.com/dicedb/dice-legacy). Selected features from the legacy engine will be gradually ported into the current codebase.

## Get Started

The quickest and easiest way to start using DiceDB is with the official Docker image. It comes with everything pre-configured, so you can get up and running in seconds without worrying about setup details.

```bash
docker run \
  --name dicedb-1 -p 6379:6379 -v $(pwd)/data:/data/ \
  dicedb:latest
```

This command starts a DiceDB container with the `spill` module already enabled. By default, the spill module uses RocksDB and is configured with a maximum memory limit of 250MB.

### Custom Configuration

If you prefer not to use the defaults and want to explicitly [configure DiceDB](https://dicedb.io/docs/conf), you can run DiceDB with explicit configuration

```bash
docker run \
  --name dicedb-1 -p 6379:6379 -v $(pwd)/data:/data/ \
  dicedb:latest \
  dicedb-server \
  --port 6379 \
  --maxmemory 500mb \
  --protected-mode no \
  --loadmodule /usr/local/lib/lib-spill.so path /data/spill/ max-memory 262144000
```

This configuration sets:

- DiceDB max memory limit to 500MB
- Spill memory limit to 250MB

## What's Different

DiceDB extends Valkey with the following key capabilities:

- [dicedb-spill](https://github.com/dicedb/dicedb-spill) - transparently persists evicted keys to disk and restores them on cache misses, enabling larger working sets within fixed memory budgets.

## Building DiceDB from Source

DiceDB supports Linux, macOS, OpenBSD, NetBSD, and FreeBSD. Both little-endian and big-endian systems are supported, including 32-bit and 64-bit architectures.

Basic build:

```
make
make test
```

For additional build and configuration options, refer to [DiceDB documentation](https://dicedb.io).

## Running DiceDB

Start server with default configuration:

```
./src/dicedb-server
```

Start with a configuration file:

```
./src/dicedb-server /path/to/valkey.conf
```

You can also pass configuration options directly:

```
./src/dicedb-server --port 9999 --replicaof 127.0.0.1 6379
./src/dicedb-server --loglevel debug
```

For advanced configuration, refer to [DiceDB](https://dicedb.io) or [Valkey](https://valkey.io) documentation.

## Using DiceDB

Use `dicedb-cli` or any compatible client.

Example:

```
./src/dicedb-cli

> ping
> set foo bar
> get foo
> incr counter
```

## Sponsors

We are incredibly grateful to our sponsor(s) for their generous support, which makes the development of DiceDB possible.

<a href="https://www.coderabbit.ai/?utm_source=github&utm_medium=social&utm_campaign=sponsor&utm_term=dicedb">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://www.coderabbit.ai/images/logo-white.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://www.coderabbit.ai/images/logo-orange.svg">
    <img alt="CodeRabbit" src="https://www.coderabbit.ai/images/logo-orange.svg" width="240">
  </picture>
</a>

## Support

DiceDB has a strong vision and roadmap. If you find DiceDB useful, please consider supporting us by starring this repo and [sponsoring us on GitHub](https://github.com/sponsors/arpitbbhayani).
