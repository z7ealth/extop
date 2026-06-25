defmodule ExtopTest do
  use ExUnit.Case

  alias Extop.Stats

  test "collect returns expected keys" do
    stats = Stats.collect()

    assert is_binary(stats.hostname)
    assert is_integer(stats.uptime_seconds)
    assert match?({_, _, _}, stats.load_avg)
    assert is_list(stats.cpu_cores)
    assert is_float(stats.cpu_total)
    assert is_list(stats.cpu_history)
    assert is_binary(stats.cpu_name)
    assert is_binary(stats.gpu_name)
    assert stats.gpu_vendor in [:nvidia, :amd, :intel, :unknown]
    assert %{total: _, used: _} = stats.memory
    assert %{total: _, used: _} = stats.swap
    assert %{total: _, used: _} = stats.disk
    assert is_list(stats.network)
    assert is_list(stats.system_info)
    assert stats.system_info != []
    assert is_integer(stats.system_info_at)
    assert is_list(stats.processes)
  end

  test "second collect produces cpu history" do
    first = Stats.collect()
    Process.sleep(1100)
    second = Stats.collect(first)

    assert length(second.cpu_history) >= 1
  end
end
