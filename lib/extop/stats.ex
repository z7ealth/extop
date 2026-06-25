defmodule Extop.Stats do
  @moduledoc false

  @history_size 60

  @type t :: %{
          hostname: String.t(),
          uptime_seconds: non_neg_integer(),
          load_avg: {float(), float(), float()},
          cpu_cores: [%{id: non_neg_integer(), usage: float()}],
          cpu_total: float(),
          cpu_history: [float()],
          memory: %{total: non_neg_integer(), used: non_neg_integer()},
          swap: %{total: non_neg_integer(), used: non_neg_integer()},
          disk: %{total: non_neg_integer(), used: non_neg_integer()},
          network: [%{name: String.t(), rx_rate: non_neg_integer(), tx_rate: non_neg_integer()}],
          net_rx_history: [non_neg_integer()],
          net_tx_history: [non_neg_integer()],
          system_info: [String.t()],
          system_info_at: integer(),
          processes: [%{pid: non_neg_integer(), name: String.t(), cpu: float(), mem: float()}],
          prev_cpu: map() | nil,
          prev_net: map() | nil,
          prev_net_at: integer() | nil
        }

  @spec collect(map() | nil) :: t()
  def collect(prev \\ nil) do
    now = System.monotonic_time(:millisecond)
    prev_cpu = prev && Map.get(prev, :prev_cpu)
    prev_net = prev && Map.get(prev, :prev_net)
    prev_net_at = prev && Map.get(prev, :prev_net_at)

    {cpu_cores, cpu_total, new_prev_cpu} = read_cpu(prev_cpu)
    {network, new_prev_net} = read_network(prev_net, prev_net_at, now)

    cpu_history =
      (prev && Map.get(prev, :cpu_history, [])) |> push_history(cpu_total)

    total_rx = Enum.sum(Enum.map(network, & &1.rx_rate))
    total_tx = Enum.sum(Enum.map(network, & &1.tx_rate))

    net_rx_history =
      (prev && Map.get(prev, :net_rx_history, [])) |> push_history(total_rx)

    net_tx_history =
      (prev && Map.get(prev, :net_tx_history, [])) |> push_history(total_tx)

    {system_info, system_info_at} = Extop.Fastfetch.fetch(prev)

    %{
      hostname: Map.get_lazy(prev || %{}, :hostname, &read_hostname/0),
      uptime_seconds: read_uptime(),
      load_avg: read_load_avg(),
      cpu_cores: cpu_cores,
      cpu_total: cpu_total,
      cpu_history: cpu_history,
      memory: read_memory(),
      swap: read_swap(),
      disk: read_disk(),
      network: network,
      net_rx_history: net_rx_history,
      net_tx_history: net_tx_history,
      system_info: system_info,
      system_info_at: system_info_at,
      processes: read_processes(),
      prev_cpu: new_prev_cpu,
      prev_net: new_prev_net,
      prev_net_at: now
    }
  end

  defp push_history(nil, value), do: [value]
  defp push_history(history, value), do: Enum.take([value | history], @history_size)

  defp read_hostname do
    case File.read("/etc/hostname") do
      {:ok, name} -> String.trim(name)
      _ -> to_string(:net_adm.localhost())
    end
  end

  defp read_uptime do
    case File.read("/proc/uptime") do
      {:ok, content} ->
        content |> String.split(" ") |> List.first() |> String.to_float() |> trunc()

      _ ->
        {uptime_ms, _} = :erlang.statistics(:wall_clock)
        div(uptime_ms, 1000)
    end
  end

  defp read_load_avg do
    case File.read("/proc/loadavg") do
      {:ok, content} ->
        [one, five, fifteen | _] = String.split(content, " ")

        {String.to_float(one), String.to_float(five), String.to_float(fifteen)}

      _ ->
        {0.0, 0.0, 0.0}
    end
  end

  defp read_cpu(nil) do
    raw = read_proc_stat()
    {[], 0.0, raw}
  end

  defp read_cpu(prev) do
    raw = read_proc_stat()

    cores =
      raw
      |> Map.drop(["cpu"])
      |> Enum.map(fn {id, values} ->
        core_id = id |> String.replace_prefix("cpu", "") |> String.to_integer()
        usage = cpu_usage_percent(Map.get(prev, id), values)
        %{id: core_id, usage: usage}
      end)
      |> Enum.sort_by(& &1.id)

    total_usage =
      case {Map.get(prev, "cpu"), Map.get(raw, "cpu")} do
        {nil, _} -> 0.0
        {prev_vals, curr_vals} -> cpu_usage_percent(prev_vals, curr_vals)
      end

    {cores, total_usage, raw}
  end

  defp read_proc_stat do
    case File.read("/proc/stat") do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.take_while(&String.starts_with?(&1, "cpu"))
        |> Enum.reduce(%{}, fn line, acc ->
          [name | values] = String.split(line, ~r/\s+/, trim: true)
          nums = Enum.map(values, &String.to_integer/1)
          Map.put(acc, name, nums)
        end)

      _ ->
        %{}
    end
  end

  defp cpu_usage_percent(nil, _current), do: 0.0

  defp cpu_usage_percent(prev, current) when length(prev) >= 4 and length(current) >= 4 do
    idle_delta = Enum.at(current, 3) - Enum.at(prev, 3)
    iowait_delta = if(length(current) > 4, do: Enum.at(current, 4) - Enum.at(prev, 4), else: 0)

    total_delta =
      Enum.zip(prev, current)
      |> Enum.reduce(0, fn {a, b}, acc -> acc + (b - a) end)

    if total_delta > 0 do
      (1.0 - (idle_delta + iowait_delta) / total_delta) * 100.0
    else
      0.0
    end
    |> Float.round(1)
  end

  defp cpu_usage_percent(_, _), do: 0.0

  defp read_memory do
    info = read_meminfo()

    total = Map.get(info, "MemTotal", 0) * 1024
    available = Map.get(info, "MemAvailable", 0) * 1024
    used = max(total - available, 0)

    %{total: total, used: used}
  end

  defp read_swap do
    info = read_meminfo()

    total = Map.get(info, "SwapTotal", 0) * 1024
    free = Map.get(info, "SwapFree", 0) * 1024
    used = max(total - free, 0)

    %{total: total, used: used}
  end

  defp read_meminfo do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ~r/:\s+/) do
            [key, value | _] ->
              case Integer.parse(value) do
                {kb, _} -> Map.put(acc, key, kb)
                :error -> acc
              end

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp read_disk do
    output = :os.cmd(~c"df -k / 2>/dev/null") |> to_string()

    case String.split(output, "\n", trim: true) do
      [_header, data_line | _] ->
        case String.split(data_line, ~r/\s+/) do
          [_, total_str, used_str | _] ->
            %{
              total: String.to_integer(total_str) * 1024,
              used: String.to_integer(used_str) * 1024
            }

          _ ->
            %{total: 0, used: 0}
        end

      _ ->
        %{total: 0, used: 0}
    end
  rescue
    _ -> %{total: 0, used: 0}
  end

  defp read_network(prev, prev_at, now) when is_map(prev) and is_integer(prev_at) do
    current = read_net_dev()
    elapsed = max(now - prev_at, 1) / 1000.0

    interfaces =
      current
      |> Enum.reject(fn {name, _} -> name in ["lo", "lo0"] end)
      |> Enum.map(fn {name, {rx, tx}} ->
        {prev_rx, prev_tx} = Map.get(prev, name, {rx, tx})
        rx_rate = max(trunc((rx - prev_rx) / elapsed), 0)
        tx_rate = max(trunc((tx - prev_tx) / elapsed), 0)
        %{name: name, rx_rate: rx_rate, tx_rate: tx_rate}
      end)
      |> Enum.sort_by(& &1.name)

    {interfaces, current}
  end

  defp read_network(_prev, _prev_at, _now) do
    {[], read_net_dev()}
  end

  defp read_net_dev do
    case File.read("/proc/net/dev") do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.drop(2)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ~r/:\s*/, parts: 2) do
            [iface, rest] ->
              name = String.trim(iface)
              [rx_str | _] = String.split(rest, ~r/\s+/, trim: true)
              parts = String.split(rest, ~r/\s+/, trim: true)

              rx = String.to_integer(rx_str)
              tx = if(length(parts) > 8, do: String.to_integer(Enum.at(parts, 8)), else: 0)
              Map.put(acc, name, {rx, tx})

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp read_processes do
    output =
      :os.cmd(~c"ps ax -o pid=,comm=,pcpu=,pmem= --no-headers --sort=-pcpu 2>/dev/null")
      |> to_string()

    output
    |> String.split("\n", trim: true)
    |> Enum.take(50)
    |> Enum.map(fn line ->
      case Regex.run(~r/^\s*(\d+)\s+(\S+)\s+([\d.]+)\s+([\d.]+)/, line) do
        [_, pid, name, cpu, mem] ->
          %{
            pid: String.to_integer(pid),
            name: String.slice(name, 0, 20),
            cpu: String.to_float(cpu),
            mem: String.to_float(mem)
          }

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
  end
end
