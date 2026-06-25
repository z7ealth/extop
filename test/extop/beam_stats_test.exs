defmodule Extop.BeamStatsTest do
  use ExUnit.Case

  alias Extop.BeamStats

  test "lines returns beam runtime info" do
    lines = BeamStats.lines()

    assert length(lines) > 10
    assert Enum.any?(lines, &line_contains?(&1, "OTP"))
    assert Enum.any?(lines, &line_contains?(&1, "Memory total"))
    assert Enum.any?(lines, &line_contains?(&1, "Processes"))
  end

  defp line_contains?(%ExRatatui.Text.Line{spans: spans}, needle) do
    spans
    |> Enum.map_join("", fn %ExRatatui.Text.Span{content: content} -> content end)
    |> String.contains?(needle)
  end
end
