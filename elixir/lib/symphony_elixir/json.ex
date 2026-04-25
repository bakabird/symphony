defmodule SymphonyElixir.Json do
  @moduledoc false

  @replacement <<0xEF, 0xBF, 0xBD>>

  @spec decode(iodata(), keyword()) :: {:ok, term()} | {:error, Jason.DecodeError.t()}
  def decode(value, opts \\ []) do
    Jason.decode(value, opts)
  end

  @spec decode!(iodata(), keyword()) :: term()
  def decode!(value, opts \\ []) do
    Jason.decode!(value, opts)
  end

  @spec encode!(term(), keyword()) :: String.t()
  def encode!(value, opts \\ []) do
    value
    |> sanitize()
    |> Jason.encode!(opts)
  end

  @spec sanitize(term()) :: term()
  def sanitize(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      String.replace_invalid(value, @replacement)
    end
  end

  def sanitize(%_{} = value), do: value

  def sanitize(value) when is_map(value) do
    Map.new(value, fn {key, mapped_value} ->
      {sanitize(key), sanitize(mapped_value)}
    end)
  end

  def sanitize(value) when is_list(value) do
    Enum.map(value, &sanitize/1)
  end

  def sanitize(value), do: value
end
