defmodule Extop.SystemInfoTest do
  use ExUnit.Case

  alias Extop.SystemInfo

  @snapshot %{
    hostname: "test-host",
    uptime_seconds: 3600,
    load_avg: {0.5, 0.4, 0.3},
    cpu_name: "Test CPU",
    cpu_total: 12.5,
    cpu_temp: 55.0,
    gpu_name: "Test GPU",
    gpu_usage: 8.0,
    gpu_temp: 45.0,
    memory: %{total: 8_000_000_000, used: 4_000_000_000},
    swap: %{total: 2_000_000_000, used: 0},
    disk: %{total: 100_000_000_000, used: 50_000_000_000},
    network: []
  }

  test "lines includes host and hardware snapshot fields" do
    lines = SystemInfo.lines(@snapshot)

    assert length(lines) > 10
    assert Enum.any?(lines, &contains?(&1, "test-host"))
    assert Enum.any?(lines, &contains?(&1, "Test CPU"))
    assert Enum.any?(lines, &contains?(&1, "Test GPU"))
  end

  test "fetch caches for refresh interval" do
    prev = %{system_info: [ExRatatui.Text.Line.new([])], system_info_at: System.monotonic_time(:second)}

    {lines, at} = SystemInfo.fetch(prev, @snapshot)
    assert lines == prev.system_info
    assert at == prev.system_info_at
  end

  defp contains?(%ExRatatui.Text.Line{spans: spans}, needle) do
    spans
    |> Enum.map_join("", fn %ExRatatui.Text.Span{content: content} -> content end)
    |> String.contains?(needle)
  end
end
