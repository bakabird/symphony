defmodule SymphonyElixir.JsonTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Json

  test "sanitize preserves structs" do
    date = ~D[2026-04-23]

    assert Json.sanitize(date) == date
  end
end
