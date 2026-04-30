# takos-agent

`takos-agent` は Takos の agent execution service です。`takos-agent-engine` を
Rust library として利用し、agent loop、managed skills の Rust runtime copy、
prompt construction、tool bridge を service process 内で扱います。PaaS/control
plane とは Control RPC で接続します。

このディレクトリの正本責務は次です。

- agent loop orchestration
- memory substrate と local memory tools
- managed skill 定義
- skill catalog 合成と selection
- skill prompt / system prompt 構築
- model runner wiring
- control plane との RPC client
- remote tool 実行の bridge

## 境界

Takos の agent architecture では、「all Rust」にする対象を container
の内側に限定します。

Rust container が正本として持つもの:

- 推論ループ
- memory / context assembly
- local tool execution internals
- skill activation
- prompt construction
- model runner wiring

Workers / control plane 側に残すもの:

- run queue と run lifecycle 管理
- DB / billing / auth / space state
- remote tool の実体
- custom skill の CRUD と永続化
- executor-host の host process

この分離により、agent の思考と実行本体は Rust で固定しつつ、Takos platform の
stateful backend と tool backend は Workers/TS のまま運用できます。

## 主要モジュール

- `src/main.rs`
  - `/start` entrypoint。control RPC から bootstrap して agent loop を起動
- `src/engine_support.rs`
  - agent engine support wiring
- `src/skills.rs`
  - managed/custom skill catalog 合成、selection、local skill tools
- `src/managed_skills.rs`
  - managed skill の Rust runtime copy
- `src/prompts.rs`
  - agent type ごとの system prompt 正本
- `src/tool_bridge.rs`
  - local memory/skill tools と remote tool catalog の合成
- `src/control_rpc.rs`
  - control plane との RPC contract

## Contract

`takos-agent` は remote tool backend を内包しません。tool 実行は次の 2 層です。

`/start` は executor-host から渡される `executorTier` / `executorContainerId`
を受け取り、全 Control RPC に `X-Takos-Executor-Tier` /
`X-Takos-Executor-Container-Id` として転送します。 これにより tiered executor
pool の token verify / heartbeat / token revoke は Rust container でも同じ
contract で動きます。

`/start` は executor-host からのみ呼ばれる internal entrypoint です。
`TAKOS_AGENT_START_TOKEN` を設定し、リクエストには
`Authorization: Bearer <TAKOS_AGENT_START_TOKEN>` を付けます。未設定時は
`503`、bearer token が欠落または不一致の場合は `401` を返します。

同時実行上限は `MAX_CONCURRENT_RUNS` で指定します。未設定時の既定値は `5`
です。executor-host の tiered pool では tier1 に `4`、tier3 に `32`
を注入します。同じ `runId` の duplicate `/start` は accepted として扱い、別の
run が上限を超えた場合は `503 At capacity` を返します。

現状の `/rpc/control/*` は PaaS internal API
`takos/paas/packages/paas-contract/src/internal-api.ts` の contract にはまだ
存在せず、実装は `takos/app` の executor-host / local executor-host が持つ
legacy control RPC surface です。そのため agent は PaaS internal API base と
legacy control RPC base を分けて扱います。

- `TAKOS_LEGACY_CONTROL_RPC_BASE_URL` / `TAKOS_LEGACY_CONTROL_RPC_TOKEN`
  - `/rpc/control/*` 用の明示的な設定名
- `CONTROL_RPC_BASE_URL` / `CONTROL_RPC_TOKEN`
  - 既存の executor-host 互換設定名
- `TAKOS_CONTROL_RPC_BASE_URL` / `TAKOS_CONTROL_RPC_TOKEN`
  - 旧互換 alias。新規設定では使わない
- `/start` payload の `controlRpcBaseUrl` / `controlRpcToken`
  - executor-host から渡される fallback
- `TAKOS_PAAS_INTERNAL_URL`
  - PaaS internal API 用。PaaS に `/rpc/control/*` 相当の contract が追加されるまでは
    agent の control RPC base としては使わない

PaaS 側へ移す場合は、`takos/paas/packages/paas-contract/src/internal-api.ts`
に agent control RPC contract を追加し、run bootstrap / context / config /
tool catalog / tool execute / heartbeat / status update / run event などの
surface を明示してから agent の呼び先を移行します。

`/rpc/control/run-config` の budget は `maxGraphSteps` / `maxToolRounds`
を正本の field name として読みます。互換のため `max_graph_steps` /
`max_tool_rounds` も受け入れます。

memory embedding backend は未設定時に smoke/test 用の Rust hash embedder を使います。
`/rpc/control/run-config` または env で `embeddingProvider` に `openai` /
`openai-compatible` を指定すると、`takos-agent-engine` の
`OpenAiCompatibleEmbedder` を使います。設定名は `embeddingModel` /
`embeddingBaseUrl` / `embeddingApiKey` / `embeddingDimensions` です。env は
`TAKOS_EMBEDDING_PROVIDER`、`TAKOS_EMBEDDING_MODEL`、
`TAKOS_EMBEDDING_BASE_URL`、`TAKOS_EMBEDDING_API_KEY`、
`TAKOS_EMBEDDING_DIMENSIONS` を優先します。API key は control plane の
`/rpc/control/api-keys` の OpenAI key、最後に `OPENAI_API_KEY` も fallback
として使います。

## Repository layout

この repo は ecosystem checkout では `../../takos-agent-engine/` を参照します。

```text
agent/
  Cargo.toml
  Dockerfile
  src/
../../takos-agent-engine/
  Cargo.toml
  src/
```

Docker image は ecosystem root を build context にして作成します。

```sh
docker build -f takos/agent/Dockerfile -t takos-agent .
```

- model-visible catalog / tool discovery
  - control plane の remote catalog が正本
  - `CompositeToolExecutor::exposed_tools()` は remote_tools のみを返し、model
    に渡す tool list も remote catalog を前提にします
- local runtime execution
  - `semantic_search_memory`
  - `graph_search_memory`
  - `provenance_lookup`
  - `timeline_search`
  - `skill_list`
  - `skill_get`
  - `skill_context`
  - `skill_catalog`
  - `skill_describe`
- remote
  - Takos control plane が catalog / execution を提供する tool 群

tool discovery は control plane の catalog を正としつつ、`skill_*` の実行は
Rust 側で local intercept します。`skill_list` / `skill_get` は legacy custom
skill lookup として custom skill のみを返します。managed skill を含む合成 catalog
は `skill_context` / `skill_catalog` / `skill_describe` が返します。local memory
tools と `skill_*` は model-visible catalog に直接追加されるとは限らず、remote
catalog の同名 call や local execution path を Rust container が intercept /
execute します。同名 tool がある場合に local execution が優先されるのは runtime
dispatch の話であって、`exposed_tools()` が local tools を常に返すという意味では
ありません。
