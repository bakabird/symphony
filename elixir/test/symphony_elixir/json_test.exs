defmodule SymphonyElixir.JsonTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Json

  test "sanitize preserves structs" do
    date = ~D[2026-04-23]

    assert Json.sanitize(date) == date
  end

  test "decode delegates to Jason" do
    assert Json.decode("{\"ok\":true}") == {:ok, %{"ok" => true}}
    assert Json.decode!("{\"ok\":true}") == %{"ok" => true}
  end
end
