defmodule Buzy.Llm.Error do
  # todo
  @type t :: %__MODULE__{}

  defexception [
    :provider,
    :model,
    :code,
    :reason,
    :status_code,
    :type,
    :provider_type,
    :provider_code,
    :provider_message,
    retryable: false,
    message: ""
  ]

  def build(status_code, opts \\ []) do
    %__MODULE__{
      model: opts[:model],
      message: opts[:message] || "",
      reason: opts[:reason],
      retryable: opts[:retryable],
      provider_type: opts[:provider_type],
      provider_code: opts[:provider_code],
      provider_message: opts[:provider_message],
      status_code: status_code,
      code: opts[:code]
    }
  end
end
