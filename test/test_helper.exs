# Load the ENV key for running live OpenAI tests.

Logger.configure(level: System.get_env("LOG_LEVEL", "warning") |> String.to_atom())
# todo try to fix so not needed
Application.ensure_all_started(:bypass)

Application.put_env(:buzy, Buzy.Config,
  openai_api_key: System.get_env("OPENAI_API_KEY", "fake-key"),
  google_ai_api_key: System.get_env("GEMINI_API_KEY", "fake-key")
)

Application.put_env(
  :test_llm,
  :base_dir,
  Path.join([__DIR__, "support", "fixtures", "llm"])
)

ExUnit.start(capture_log: true, level: :warn)
