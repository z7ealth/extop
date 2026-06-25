defmodule Extop.ProcessesTest do
  use ExUnit.Case

  alias Extop.Processes

  @processes [
    %{pid: 100, user: "root", name: "beam.smp", cpu: 5.0, mem: 2.0},
    %{pid: 200, user: "alice", name: "firefox", cpu: 10.0, mem: 8.0},
    %{pid: 300, user: "bob", name: "code", cpu: 1.0, mem: 4.0}
  ]

  test "filters by name, user, or pid" do
    assert [%{pid: 200}] = Processes.prepare(@processes, "fire", {:cpu, :desc})
    assert [%{pid: 300}] = Processes.prepare(@processes, "bob", {:cpu, :desc})
    assert [%{pid: 100}] = Processes.prepare(@processes, "100", {:cpu, :desc})
  end

  test "sorts by field and direction" do
    assert [%{pid: 200} | _] = Processes.prepare(@processes, "", {:cpu, :desc})
    assert [%{pid: 300} | _] = Processes.prepare(@processes, "", {:cpu, :asc})
    assert [%{pid: 100}, %{pid: 200}, %{pid: 300}] =
             Processes.prepare(@processes, "", {:pid, :asc})
  end

  test "toggle_sort flips direction for same field" do
    assert {:cpu, :asc} = Processes.toggle_sort({:cpu, :desc}, :cpu)
    assert {:mem, :desc} = Processes.toggle_sort({:cpu, :desc}, :mem)
  end

  test "scroll_offset keeps selection visible" do
    assert 0 == Processes.scroll_offset(0, 10, 5)
    assert 5 == Processes.scroll_offset(7, 10, 5)
    assert 3 == Processes.scroll_offset(99, 10, 7)
  end

  test "parse_ps_line handles comm names with spaces" do
    line = "  18455 root     Isolated Web Co  3.0  7.8"

    assert [%{pid: 18455, user: "root", name: "Isolated Web Co", cpu: 3.0, mem: 7.8}] =
             Processes.parse_ps_line(line)
  end

  test "resolve_fetch keeps cached list when refresh is empty" do
    cached = [%{pid: 1, user: "root", name: "init", cpu: 0.0, mem: 0.0}]

    assert cached == Processes.resolve_fetch([], cached)
    assert [] == Processes.resolve_fetch([], [])
    assert cached == Processes.resolve_fetch(cached, [])
  end

  test "send_signal rejects missing pid" do
    assert {:error, _} = Processes.send_signal(999_999_999, :sigterm)
  end
end
