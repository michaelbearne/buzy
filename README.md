# Buzy

**Currently under active development**

Buzy is a framework to help build applications powered by large language models (LLMs) heavily inspired by [langchain](https://www.langchain.com/langchain) and [langgraph](https://www.langchain.com/langgraph).

Buzy.Llm can be used as a unified interface that abstracts away the interactions with model provider's API, additionally Buzy.Runner can be used as the foundation to build stateful workflows/agents using a graph-based approach.

Buzy currently uses a fork of [peri](https://hex.pm/packages/peri) that adds support for building openapi and json schemas.

## Buzy.Llm

**Features** 

* Unified interface
* Configruble clients easy to add your own client
* Tool Calling
* Structured Outputs
* Streaming support 
* Live cycle callbacks
* Validation of the return tool calls or structured outputs
* Pluging support to wrap a call

**Plugins**

* Simple cache

## Buzy.Runner

Buzy Runner enables you to create stateful workflows/agents that run in there own process with the own live cycle that can be commincate with other processes through subscriptions.

A runner is defined as a graph of nodes and edge, where "nodes" represent individual steps or actions (like calling an LLM or using a tool) and "edges" dictate the flow of execution between them. This graph-based approach provides fine-grained control, enables features like conversational flows, human-in-the-loop oversight, and facilitates building reliable, long-running agentic applications with memory and dynamic decision-making.

**Features** 

* Short term memory (stateful)
* Long term peristance (checkpointing) *in progress*
* Concurent execution of nodes 
* Subscriptions
* Recursions lmits
* Idling can pause when no selectable next node and wait for additional state to then continue 
* Can stop when inactive for a defined period of time.

## Buzy.Runner Registry

The runner registry enables a runner to be started and located through a thread_id. This thread_id can be used allow other process to subscribe to a runner to recive callbacks with out being coupled pid.

## TODO 

* Subgraphs
* Digrams of the graph in mutiple formats for example Mermaid and Asci
* Automatic retries on stucured output errors
* Falbacks to other providers and or models
* Distributed Registry with [global](https://www.erlang.org/doc/apps/kernel/global.html)
* Distributed Registry with [swarm](https://hex.pm/packages/swarm)
* Distributed Registry with [horde](https://hex.pm/packages/horde)

## Installation

```elixir
def deps do
  [
    {:buzy, "~> 0.1.0"}
  ]
end
```