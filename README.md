# Buzy

Buzy is a framework to help build applications powered by large language models (LLMs) heavily inspired by [langchain](https://www.langchain.com/langchain) and [langgraph](https://www.langchain.com/langgraph).

At the lowest level Buzy can be used to interface with an LLM through a unified interface that abstracts away the model provider's API  through pluggable clients this enables switching from one model to another just through a model name change.

At the next level up, Buzy provides the foundations to build agentic and conversational workflows with or without humans in the loop.

## Installation

```elixir
def deps do
  [
    {:buzy, "~> 0.1.0"}
  ]
end
```