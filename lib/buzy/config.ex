defmodule Buzy.Config do
  alias Buzy.Llm.Config.Model

  @models %{
    "gemini-1.5-flash" => %Model{
      name: "gemini-1.5-flash",
      client: Buzy.Llm.Clients.Gemini
    },
    "gemini-2.0-flash" => %Model{
      name: "gemini-2.0-flash",
      client: Buzy.Llm.Clients.Gemini,
      client_opts: [thinking_budget_supported: false]
    },
    "gemini-2.5-pro-preview-03-25" => %Model{
      name: "gemini-2.5-pro-preview-03-25",
      client: Buzy.Llm.Clients.Gemini
    },
    "gemini-2.5-flash-preview-04-17" => %Model{
      name: "gemini-2.5-flash-preview-04-17",
      client: Buzy.Llm.Clients.Gemini
    },
    "gpt-4o" => %Model{
      name: "gpt-4o",
      client: Buzy.Llm.Clients.Openai.Chat
    },
    "gpt-4o-2024-11-20" => %Model{
      name: "gpt-4o",
      client: Buzy.Llm.Clients.Openai.Chat
    },
    "gpt-4o-mini-2024-07-18" => %Model{
      name: "gpt-4o-mini-2024-07-18",
      client: Buzy.Llm.Clients.Openai.Chat
    },
    "o3-mini-2025-01-31" => %Model{
      name: "gpt-4o-mini-2024-07-18",
      client: Buzy.Llm.Clients.Openai.Chat,
      client_opts: [temperature_supported: false]
    }
  }

  def config do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        ext_cfg = Application.get_env(:buzy, __MODULE__, [])

        cfg = [
          google_ai_base_url: Keyword.get(ext_cfg, :google_ai_base_url),
          google_ai_api_key: Keyword.get(ext_cfg, :google_ai_api_key),
          google_ai_api_version: Keyword.get(ext_cfg, :google_ai_api_version),
          openai_base_url: Keyword.get(ext_cfg, :openai_base_url),
          openai_url_path: Keyword.get(ext_cfg, :openai_url_path),
          openai_api_key: Keyword.get(ext_cfg, :openai_api_key),
          models: Keyword.get(ext_cfg, :models, %{}),
          plugins: Keyword.get(ext_cfg, :plugins, [])
        ]

        :ok = :persistent_term.put(__MODULE__, cfg)
        cfg

      cfg ->
        cfg
    end
  end

  def models, do: @models
  def model(name), do: Map.merge(@models[name], config()[:models])

  # google
  def google_ai_base_url, do: config()[:google_ai_base_url]
  def google_ai_api_key, do: config()[:google_ai_api_key]
  def google_ai_api_version, do: config()[:google_ai_api_version]

  # openai
  def openai_base_url, do: config()[:openai_base_url]
  def openai_url_path, do: config()[:openai_url_path]
  def openai_api_key, do: config()[:openai_api_key]

  def plugins, do: config()[:plugins] || []
end
