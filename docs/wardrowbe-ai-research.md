# Wardrowbe model providers

Reviewed: 2026-09-26. Scope: Wardrowbe 1.10.1 at commit
`8f91c82bca7c3684d0cc36f36e9dac62bf382cd2`, current OpenAI and Ollama documentation,
and locally installed Codex CLI 0.155.1.

## Answer

Use Wardrowbe's OpenAI compatible interface for Ollama and ordinary OpenAI API
access. Offer ChatGPT OAuth through an optional private Codex CLI adapter. Keep
Codex responsible for authentication and token refresh. Do not extract its tokens
and send them to the general OpenAI API.

API keys remain OpenAI's recommended default for automation. Codex OAuth is
appropriate here only as an explicit option for a trusted private deployment
whose owner wants ChatGPT subscription access. Available Codex models depend on
the account and its catalog. Subscription login does not grant arbitrary OpenAI
API model access. [Codex authentication](https://learn.chatgpt.com/docs/auth),
[Codex automation](https://learn.chatgpt.com/docs/non-interactive-mode),
[OpenAI API credentials](https://developers.openai.com/api/reference/overview).

## Findings and sources

### Existing Wardrowbe integration

Wardrowbe sends non-streaming `/chat/completions` requests, chooses independent
text and vision models, discovers models through `/models`, and supports endpoint
fallbacks. Its AI service attaches the same configured Bearer credential to all
endpoints. Consequently a deployment must avoid combining an API secret with an
untrusted fallback endpoint. Endpoint selection also affects where clothing
photos and wardrobe descriptions leave the host.
[Pinned AI service](https://github.com/Anyesh/wardrowbe/blob/8f91c82bca7c3684d0cc36f36e9dac62bf382cd2/backend/app/services/ai_service.py).

### OAuth through Codex

Codex supports ChatGPT browser login and headless device login through
`codex login --device-auth`. Device login requires account or workspace permission.
The CLI reuses saved credentials and refreshes ChatGPT tokens during use.
File storage under a dedicated `CODEX_HOME` works on a headless service, but the
file contains account credentials and must have restricted ownership and mode.
Codex must be able to persist refreshed credentials between requests. A read-only
copy of an initial token file does not implement reliable token refresh.
[Authentication and headless setup](https://learn.chatgpt.com/docs/auth),
[Persisting account auth](https://learn.chatgpt.com/docs/auth/ci-cd-auth).

`codex exec` accepts a selected model, image attachments, and a JSON Schema for
structured final output. `--ephemeral` avoids session rollout persistence.
`--ignore-user-config` skips user settings while retaining authentication. An
adapter can translate a small supported subset of chat completions into an
argument-array invocation and return a compatible response. Reject unsupported
streaming, tool calls, arbitrary URLs, and malformed or oversized images instead
of pretending that every OpenAI API capability is implemented.
[Exec interface](https://learn.chatgpt.com/docs/developer-commands#cli-codex-exec),
[Structured output and automation](https://learn.chatgpt.com/docs/non-interactive-mode).

For the adapter, disable shell, apps, hooks, subagents, and web search. Use a
dedicated empty working directory, a read-only sandbox, restricted service
filesystem access, bounded concurrency and execution time, and private temporary
files. Read-only sandboxing alone permits reads and is insufficient to protect
the credential file against a prompt that induces tool use. Never load personal
MCP servers or project instructions. Configuration keys include
`features.shell_tool`, `features.apps`, `features.hooks`, `features.multi_agent`,
and `web_search = "disabled"`. This recommendation needs verification against
the packaged CLI's actual tool catalog.
[Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

Model selection should use administrator-configured IDs, with distinct text and
vision selections. `codex debug models --bundled` provides offline catalog
inspection on CLI 0.155.1. A bundled catalog is not evidence that the account can
use every listed model. Authentication and inference errors must remain visible
without including raw prompts, provider logs, or tokens in the journal.
[Model catalog command](https://learn.chatgpt.com/docs/developer-commands#codex-debug-models).

### Llama through Ollama

Ollama exposes `/v1/chat/completions` and `/v1/models`, including image input and
JSON response formats. Local Ollama ignores the API key supplied by an OpenAI
client. Bind it to loopback or protect access with an authenticated gateway.
Wardrowbe can use it directly without another inference proxy.
[OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility).

The `llama3.2:3b` family is text only and suitable as a small configurable local
text option. Clothing photo analysis needs a vision model such as
`llama3.2-vision:11b`. Ollama lists the latter download at 7.8 GB; runtime memory
requirements exceed download size and depend on context, backend and concurrency.
Its model card specifies English for image plus text tasks. Keep model names
configurable and avoid pulling the much larger 90B model by default.
[Llama text model](https://ollama.com/library/llama3.2),
[Llama vision model](https://ollama.com/library/llama3.2-vision).

Ollama supports schema-constrained output locally. Prompts and validation remain
necessary, especially when Wardrowbe asks for JSON without specifying an API
schema. Limit loaded models and parallel requests for a shared host. Context
memory scales with concurrency. Configure idle unload time rather than keeping
all models resident indefinitely. GPU acceleration remains host policy.
[Structured outputs](https://docs.ollama.com/capabilities/structured-outputs),
[Memory, concurrency and keep-alive](https://docs.ollama.com/faq).

## Validation and limits

Reviewed official documentation and Wardrowbe's pinned AI service. Checked local
`codex --version`, `codex exec --help`, and `codex debug models --help`. No login,
token inspection, paid request, or model inference ran during this research.
OAuth entitlement, model quality, image support for the chosen Codex model,
hardware performance and the adapter's complete tool isolation need runtime
verification. Model download sizes are upstream catalog values rather than
measured local allocations.

## Implication for this repository

Keep provider selection explicit and opt-in. Expose base URL, text model and
vision model through module options. The OAuth adapter should own a separate
service identity and persistent credential directory; Wardrowbe should receive
only its local endpoint. A generic OpenAI compatible provider should receive its
credential through a runtime secret file. A Llama preset can configure Ollama
models, while users retain upstream Ollama options for resource and GPU policy.

## Implemented transport controls

The adapter derives a static catalog from `codex debug models --bundled`, clears
`apply_patch_tool_type` and experimental tools, disables shell and search
capabilities, and passes the result through `model_catalog_json`. This avoids
maintaining a duplicate hardcoded model catalog and rejects model IDs missing
from the packaged catalog. CLI 0.155.1's tool planner otherwise exposes
`apply_patch` even with shell tools disabled. Its static models manager ignores
remote catalog refreshes.
[Codex tool planner](https://github.com/openai/codex/blob/rust-v0.155.1/codex-rs/core/src/tools/spec_plan.rs),
[Static model manager](https://github.com/openai/codex/blob/rust-v0.155.1/codex-rs/models-manager/src/manager.rs).

The adapter does not forward API keys, access tokens, personal configuration or
project rules. Its supported API subset omits sampling controls, log probabilities
and exact token budgets; documented limits bound body size, output size and wall
time instead. Tests use a disposable fake CLI and mock HTTP providers, plus the packaged CLI's offline catalog and prompt configuration in the Nix sandbox. Actual
subscription inference and model quality still require attended acceptance tests.
