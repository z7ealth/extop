defmodule Extop.Stats do
  @moduledoc false

  @history_size 60

  # Intel PCI device IDs (8086:XXXX) → marketing name
  @intel_gpu_names %{
    "9a40" => "Intel UHD Graphics",
    "9a49" => "Intel Iris Xe Graphics",
    "9a59" => "Intel Iris Xe Graphics",
    "9a60" => "Intel UHD Graphics",
    "9a68" => "Intel Iris Xe Graphics",
    "9a70" => "Intel UHD Graphics",
    "9a78" => "Intel Iris Xe Graphics",
    "8a51" => "Intel Iris Plus Graphics",
    "8a52" => "Intel Iris Plus Graphics",
    "8a53" => "Intel UHD Graphics",
    "4680" => "Intel UHD Graphics 770",
    "4682" => "Intel UHD Graphics 770",
    "4626" => "Intel UHD Graphics 730",
    "4628" => "Intel UHD Graphics 730",
    "46a0" => "Intel Iris Xe Graphics",
    "46a1" => "Intel Iris Xe Graphics",
    "46a3" => "Intel Iris Xe Graphics",
    "46a6" => "Intel Iris Xe Graphics",
    "46aa" => "Intel Iris Xe Graphics",
    "a780" => "Intel UHD Graphics 770",
    "a781" => "Intel UHD Graphics 770",
    "a788" => "Intel UHD Graphics",
    "a7a0" => "Intel Iris Xe Graphics",
    "a7a1" => "Intel Iris Xe Graphics",
    "5690" => "Intel Arc A750",
    "5691" => "Intel Arc A750",
    "56a0" => "Intel Arc A770",
    "56a1" => "Intel Arc A770M",
    "56a5" => "Intel Arc A730M",
    "56a6" => "Intel Arc A580"
  }

  @amd_gpu_names %{
    "747e" => "Radeon RX 7700 XT / 7800 XT",
    "744c" => "Radeon RX 6800 / 6800 XT / 6900 XT",
    "73df" => "Radeon RX 6600 / 6600 XT / 6700 XT",
    "7340" => "Radeon RX 7600 / 7600 XT",
    "7480" => "Radeon RX 7700S / 7600S",
    "15bf" => "Radeon 780M",
    "15c8" => "Radeon 780M",
    "164e" => "Radeon 780M",
    "1900" => "Radeon 8060S",
    "1901" => "Radeon 8050S"
  }

  @cpu_hwmon_names ~w(k10temp coretemp zenpower cpu_thermal)

  @type t :: %{
          hostname: String.t(),
          uptime_seconds: non_neg_integer(),
          load_avg: {float(), float(), float()},
          cpu_cores: [%{id: non_neg_integer(), usage: float()}],
          cpu_total: float(),
          cpu_history: [float()],
          cpu_temp: float() | nil,
          cpu_name: String.t(),
          gpu_usage: float(),
          gpu_history: [float()],
          gpu_temp: float() | nil,
          gpu_name: String.t(),
          gpu_vendor: :nvidia | :amd | :intel | :unknown,
          gpu_card: map() | nil,
          memory: %{total: non_neg_integer(), used: non_neg_integer()},
          swap: %{total: non_neg_integer(), used: non_neg_integer()},
          disk: %{total: non_neg_integer(), used: non_neg_integer()},
          network: [%{name: String.t(), rx_rate: non_neg_integer(), tx_rate: non_neg_integer()}],
          net_rx_history: [non_neg_integer()],
          net_tx_history: [non_neg_integer()],
          system_info: [ExRatatui.Text.Line.t()],
          system_info_at: integer(),
          processes: [
            %{pid: non_neg_integer(), user: String.t(), name: String.t(), cpu: float(), mem: float()}
          ],
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

    {gpu_usage, gpu_temp, gpu_name, gpu_vendor, gpu_card} = read_gpu(prev)

    gpu_history =
      (prev && Map.get(prev, :gpu_history, [])) |> push_history(gpu_usage)

    cpu_temp = read_cpu_temp()

    total_rx = Enum.sum(Enum.map(network, & &1.rx_rate))
    total_tx = Enum.sum(Enum.map(network, & &1.tx_rate))

    net_rx_history =
      (prev && Map.get(prev, :net_rx_history, [])) |> push_history(total_rx)

    net_tx_history =
      (prev && Map.get(prev, :net_tx_history, [])) |> push_history(total_tx)

    hostname = Map.get_lazy(prev || %{}, :hostname, &read_hostname/0)
    cpu_name = Map.get_lazy(prev || %{}, :cpu_name, &read_cpu_name/0)
    uptime_seconds = read_uptime()
    load_avg = read_load_avg()
    memory = read_memory()
    swap = read_swap()
    disk = read_disk()

    snapshot = %{
      hostname: hostname,
      uptime_seconds: uptime_seconds,
      load_avg: load_avg,
      cpu_name: cpu_name,
      cpu_total: cpu_total,
      cpu_temp: cpu_temp,
      gpu_name: gpu_name,
      gpu_usage: gpu_usage,
      gpu_temp: gpu_temp,
      memory: memory,
      swap: swap,
      disk: disk,
      network: network
    }

    {system_info, system_info_at} = Extop.SystemInfo.fetch(prev, snapshot)

    %{
      hostname: hostname,
      uptime_seconds: uptime_seconds,
      load_avg: load_avg,
      cpu_cores: cpu_cores,
      cpu_total: cpu_total,
      cpu_history: cpu_history,
      cpu_temp: cpu_temp,
      cpu_name: cpu_name,
      gpu_usage: gpu_usage,
      gpu_history: gpu_history,
      gpu_temp: gpu_temp,
      gpu_name: gpu_name,
      gpu_vendor: gpu_vendor,
      gpu_card: gpu_card,
      memory: memory,
      swap: swap,
      disk: disk,
      network: network,
      net_rx_history: net_rx_history,
      net_tx_history: net_tx_history,
      system_info: system_info,
      system_info_at: system_info_at,
      processes: read_processes(prev),
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

  defp read_gpu(prev) do
    card = Map.get_lazy(prev || %{}, :gpu_card, &detect_gpu_card/0)
    {usage, temp} = gpu_metrics(card)
    {usage, temp, card.name, card.vendor, card}
  end

  defp detect_gpu_card do
    case list_drm_gpus() |> select_gpu_card() do
      nil -> %{vendor: :unknown, device_path: nil, name: "No GPU"}
      card -> card
    end
  end

  defp list_drm_gpus do
    "/sys/class/drm/card*/device"
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      path |> Path.dirname() |> Path.basename() |> drm_card?()
    end)
    |> Enum.sort()
    |> Enum.map(&build_gpu_card/1)
    |> Enum.reject(&is_nil/1)
  end

  defp drm_card?(name), do: Regex.match?(~r/^card\d+$/, name)

  defp build_gpu_card(device_path) do
    vendor = read_pci_vendor(device_path)

    if vendor == :unknown do
      nil
    else
      %{
        vendor: vendor,
        device_path: device_path,
        name: read_gpu_device_name(device_path, vendor)
      }
    end
  end

  defp read_pci_vendor(device_path) do
    case File.read(Path.join(device_path, "vendor")) do
      {:ok, vendor} ->
        case String.downcase(String.trim(vendor)) do
          "0x10de" -> :nvidia
          "0x1002" -> :amd
          "0x8086" -> :intel
          _ -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp select_gpu_card([]), do: nil

  defp select_gpu_card(cards) do
    nvidia_drm = Enum.find(cards, &(&1.vendor == :nvidia))

    case read_nvidia_smi_metrics() do
      %{name: name} ->
        %{
          vendor: :nvidia,
          device_path: nvidia_drm && nvidia_drm.device_path,
          name: name
        }

      _ ->
        Enum.find(cards, &(&1.vendor == :nvidia)) ||
          Enum.find(cards, &(&1.vendor == :amd)) ||
          Enum.find(cards, &(&1.vendor == :intel)) ||
          List.first(cards)
    end
  end

  defp read_nvidia_smi_metrics do
    case System.cmd(
           "nvidia-smi",
           [
             "--query-gpu=name,utilization.gpu,temperature.gpu",
             "--format=csv,noheader,nounits"
           ],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n", trim: true)
        |> List.first()
        |> parse_nvidia_smi_line()

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp parse_nvidia_smi_line(nil), do: nil

  defp parse_nvidia_smi_line(line) do
    case String.split(line, ",", parts: 3) do
      [name, util, temp] ->
        %{
          name: String.trim(name),
          usage: parse_gpu_percent(util),
          temp: parse_gpu_percent(temp)
        }

      [name, util] ->
        %{
          name: String.trim(name),
          usage: parse_gpu_percent(util),
          temp: nil
        }

      _ ->
        nil
    end
  end

  defp gpu_metrics(%{vendor: :nvidia} = card) do
    case read_nvidia_smi_metrics() do
      %{usage: usage, temp: temp} ->
        {usage || 0.0, temp || read_device_temp(card.device_path)}

      _ ->
        {read_device_busy(card) || 0.0, read_device_temp(card.device_path)}
    end
  end

  defp gpu_metrics(%{vendor: :amd} = card) do
    {read_device_busy(card) || 0.0, read_device_temp(card.device_path)}
  end

  defp gpu_metrics(%{vendor: :intel} = card) do
    {read_device_busy(card) || 0.0, read_device_temp(card.device_path)}
  end

  defp gpu_metrics(%{vendor: :unknown}) do
    {0.0, nil}
  end

  defp read_gpu_device_name(device_path, vendor) do
    cond do
      (name = read_sysfs_string(Path.join(device_path, "product_name"))) != nil ->
        name

      vendor == :nvidia ->
        case read_nvidia_smi_metrics() do
          %{name: name} -> name
          _ -> lspci_gpu_name(device_path) || "NVIDIA GPU"
        end

      vendor == :amd ->
        amd_name_from_pci(device_path) || lspci_gpu_name(device_path) ||
          driver_label(device_path, "AMD Radeon Graphics")

      vendor == :intel ->
        intel_name_from_pci(device_path) || lspci_gpu_name(device_path) ||
          driver_label(device_path, "Intel Graphics")

      true ->
        "Unknown GPU"
    end
  end

  defp driver_label(device_path, fallback) do
    case File.read(Path.join(device_path, "uevent")) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          case String.split(line, "=", parts: 2) do
            ["DRIVER", driver] when driver not in ["", "simple-framebuffer"] ->
              case driver do
                "i915" -> nil
                "xe" -> nil
                "amdgpu" -> "AMD Radeon Graphics"
                "nvidia" -> "NVIDIA GPU"
                "nouveau" -> "NVIDIA GPU"
                other -> other
              end

            _ ->
              nil
          end
        end) || fallback

      _ ->
        fallback
    end
  end

  defp read_sysfs_string(path) do
    case File.read(path) do
      {:ok, value} ->
        trimmed = String.trim(value)
        if trimmed != "" and trimmed not in ["unknown", "Unknown"], do: trimmed

      _ ->
        nil
    end
  end

  defp intel_name_from_pci(device_path) do
    case read_pci_device_id(device_path) do
      id when is_binary(id) -> Map.get(@intel_gpu_names, String.downcase(id))
      _ -> nil
    end
  end

  defp amd_name_from_pci(device_path) do
    case read_pci_device_id(device_path) do
      id when is_binary(id) -> Map.get(@amd_gpu_names, String.downcase(id))
      _ -> nil
    end
  end

  defp lspci_gpu_name(device_path) do
    with slot when is_binary(slot) <- read_uevent_field(device_path, "PCI_SLOT_NAME"),
         {output, 0} <- System.cmd("lspci", ["-nn", "-s", slot], stderr_to_stdout: true) do
      parse_lspci_gpu_name(output)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp read_uevent_field(device_path, key) do
    case File.read(Path.join(device_path, "uevent")) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          case String.split(line, "=", parts: 2) do
            [^key, value] -> String.trim(value)
            _ -> nil
          end
        end)

      _ ->
        nil
    end
  end

  defp parse_lspci_gpu_name(output) do
    output = String.trim(output)

    cond do
      match = Regex.run(~r/\[(Radeon[^[\]]+)\]/, output) ->
        List.last(match)

      match = Regex.run(~r/\[(GeForce[^[\]]+)\]/, output) ->
        List.last(match)

      match = Regex.run(~r/\[(Arc [^[\]]+)\]/, output) ->
        List.last(match)

      true ->
        case String.split(output, ": ", parts: 2) do
          [_, desc] ->
            desc
            |> String.replace(~r/\s*\[[0-9a-f]{4}:[0-9a-f]{4}\]\s*$/i, "")
            |> String.replace(~r/\[[0-9a-f]{4}\]:\s*/, "")
            |> String.trim()
            |> case do
              "" -> nil
              name -> name
            end

          _ ->
            nil
        end
    end
  end

  defp read_pci_device_id(device_path) do
    case read_sysfs_string(Path.join(device_path, "device")) do
      "0x" <> id ->
        id

      id when is_binary(id) ->
        String.trim_leading(id, "0x")

      _ ->
        read_pci_id_from_uevent(device_path)
    end
  end

  defp read_pci_id_from_uevent(device_path) do
    case read_uevent_field(device_path, "PCI_ID") do
      pci_id when is_binary(pci_id) ->
        case String.split(pci_id, ":", parts: 2) do
          [_vendor, id] -> String.downcase(id)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp read_device_busy(%{vendor: :amd, device_path: path}) when is_binary(path) do
    read_percent_file(Path.join(path, "gpu_busy_percent"))
  end

  defp read_device_busy(%{vendor: :intel, device_path: path}) when is_binary(path) do
    intel_busy_paths(path)
    |> Enum.find_value(&read_percent_file/1)
  end

  defp read_device_busy(%{vendor: :nvidia, device_path: path}) when is_binary(path) do
    read_percent_file(Path.join(path, "gpu_busy_percent"))
  end

  defp read_device_busy(_), do: nil

  defp intel_busy_paths(device_path) do
    [
      Path.join(device_path, "gt/gt0/gt_busy_percent"),
      Path.join(device_path, "gt_busy_percent")
    ] ++ Path.wildcard(Path.join(device_path, "gt/gt*/gt_busy_percent"))
  end

  defp read_percent_file(path) do
    case File.read(path) do
      {:ok, content} -> parse_gpu_percent(String.trim(content))
      _ -> nil
    end
  end

  defp read_device_temp(nil), do: nil

  defp read_device_temp(device_path) when is_binary(device_path) do
    device_path
    |> Path.join("hwmon/hwmon*/temp*_input")
    |> Path.wildcard()
    |> Enum.find_value(fn path ->
      case File.read(path) do
        {:ok, content} -> parse_millidegrees(content)
        _ -> nil
      end
    end)
  end

  defp parse_millidegrees(content) do
    case Integer.parse(String.trim(content)) do
      {millidegrees, _} -> Float.round(millidegrees / 1000.0, 1)
      :error -> nil
    end
  end

  defp read_cpu_temp do
    read_hwmon_cpu_temp() ||
      read_thermal_temp(["x86_pkg_temp", "TCPU", "cpu"]) ||
      read_thermal_temp(["acpitz"]) ||
      read_thermal_zone0_temp()
  end

  defp read_hwmon_cpu_temp do
    "/sys/class/hwmon/hwmon*"
    |> Path.wildcard()
    |> Enum.find_value(&hwmon_cpu_temp/1)
  end

  defp hwmon_cpu_temp(dir) do
    with {:ok, name} <- File.read(Path.join(dir, "name")),
         true <- String.trim(name) in @cpu_hwmon_names do
      read_labeled_hwmon_temp(dir, ["Tctl", "Tdie", "Package id 0", "CPU"]) ||
        read_first_hwmon_temp(dir)
    else
      _ -> nil
    end
  end

  defp read_labeled_hwmon_temp(dir, preferred_labels) do
    labels =
      dir
      |> Path.join("temp*_label")
      |> Path.wildcard()
      |> Enum.reduce(%{}, fn label_path, acc ->
        with {:ok, label} <- File.read(label_path),
             num when is_binary(num) <- hwmon_temp_number(label_path) do
          Map.put(acc, String.trim(label), num)
        else
          _ -> acc
        end
      end)

    Enum.find_value(preferred_labels, fn label ->
      case Map.get(labels, label) do
        nil -> nil
        num -> read_hwmon_temp_file(dir, num)
      end
    end)
  end

  defp hwmon_temp_number(path) do
    case Regex.run(~r/temp(\d+)_label$/, path) do
      [_, num] -> num
      _ -> nil
    end
  end

  defp read_hwmon_temp_file(dir, num) do
    case File.read(Path.join(dir, "temp#{num}_input")) do
      {:ok, content} -> parse_millidegrees(content)
      _ -> nil
    end
  end

  defp read_first_hwmon_temp(dir) do
    dir
    |> Path.join("temp*_input")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.find_value(fn path ->
      case File.read(path) do
        {:ok, content} -> parse_millidegrees(content)
        _ -> nil
      end
    end)
  end

  defp read_cpu_name do
    case File.read("/proc/cpuinfo") do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.find_value(fn line ->
          if String.starts_with?(line, "model name") do
            line
            |> String.split(":", parts: 2)
            |> Enum.at(1)
            |> String.trim()
          end
        end) || "Unknown CPU"

      _ ->
        "Unknown CPU"
    end
  end

  defp read_thermal_temp(preferred_types) do
    zones =
      "/sys/class/thermal/thermal_zone*"
      |> Path.wildcard()
      |> Enum.reduce(%{}, fn zone, acc ->
        with {:ok, type} <- File.read(Path.join(zone, "type")),
             {:ok, temp} <- File.read(Path.join(zone, "temp")),
             {millidegrees, _} <- Integer.parse(String.trim(temp)) do
          Map.put(acc, String.trim(type), millidegrees / 1000.0)
        else
          _ -> acc
        end
      end)

    Enum.find_value(preferred_types, fn type ->
      case Map.get(zones, type) do
        nil -> nil
        temp -> Float.round(temp, 1)
      end
    end)
  end

  defp read_thermal_zone0_temp do
    case File.read("/sys/class/thermal/thermal_zone0/temp") do
      {:ok, content} ->
        content |> String.trim() |> String.to_integer() |> Kernel./(1000.0) |> Float.round(1)

      _ ->
        nil
    end
  end

  defp parse_gpu_percent(value) do
    case Float.parse(value) do
      {percent, _} -> Float.round(percent, 1)
      :error -> nil
    end
  end

  defp read_processes(prev) do
    cached = prev && Map.get(prev, :processes, [])
    Extop.Processes.fetch(cached)
  end
end
