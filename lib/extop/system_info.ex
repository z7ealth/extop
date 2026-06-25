defmodule Extop.SystemInfo do
  @moduledoc false

  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias Extop.Theme

  @refresh_seconds 30
  @label_width 16
  @palette_indent 2

  @type snapshot :: map()

  @spec fetch(map() | nil, snapshot()) :: {[Line.t()], integer()}
  def fetch(prev, snapshot) do
    now = System.monotonic_time(:second)

    if stale?(prev, now) do
      {lines(snapshot), now}
    else
      {Map.get(prev, :system_info, lines(snapshot)), Map.get(prev, :system_info_at, now)}
    end
  end

  defp stale?(nil, _now), do: true

  defp stale?(prev, now) do
    now - Map.get(prev, :system_info_at, 0) >= @refresh_seconds
  end

  @spec lines(snapshot()) :: [Line.t()]
  def lines(snapshot) do
    os = read_os_release()
    {one, five, fifteen} = Map.get(snapshot, :load_avg, {0.0, 0.0, 0.0})

    rows = [
      {"OS", os[:pretty_name] || os[:name] || "Linux"},
      {"Host", Map.get(snapshot, :hostname, "unknown")},
      {"Kernel", kernel_version()},
      {"Arch", arch()},
      {"Uptime", format_uptime(Map.get(snapshot, :uptime_seconds, 0))},
      {"Load", "#{Float.round(one, 2)} #{Float.round(five, 2)} #{Float.round(fifteen, 2)}"},
      {"Packages", package_count()},
      {"Shell", env("SHELL")},
      {"Session", session_type()},
      {"Desktop", env("XDG_CURRENT_DESKTOP")},
      {"WM", window_manager()},
      {"Theme", gsetting("org.gnome.desktop.interface", "gtk-theme")},
      {"Icons", gsetting("org.gnome.desktop.interface", "icon-theme")},
      {"Font", gsetting("org.gnome.desktop.interface", "font-name")},
      {"Cursor", gsetting("org.gnome.desktop.interface", "cursor-theme")},
      {"Terminal", terminal_name()},
      {"CPU", Map.get(snapshot, :cpu_name, "N/A")},
      {"CPU usage", format_percent(Map.get(snapshot, :cpu_total))},
      {"CPU temp", format_temp(Map.get(snapshot, :cpu_temp))},
      {"GPU", Map.get(snapshot, :gpu_name, "N/A")},
      {"GPU usage", format_percent(Map.get(snapshot, :gpu_usage))},
      {"GPU temp", format_temp(Map.get(snapshot, :gpu_temp))},
      {"Memory", format_usage(Map.get(snapshot, :memory))},
      {"Swap", format_usage(Map.get(snapshot, :swap))},
      {"Disk /", format_usage(Map.get(snapshot, :disk))},
      {"Local IP", local_ips() |> Enum.join(", ")},
      {"Battery", battery_status()},
      {"Locale", env("LANG")},
      {"User", env("USER")}
    ]

    [title_row(os), blank_row()] ++ Enum.map(rows, &format_row/1) ++ color_palette_lines()
  end

  defp title_row(os) do
    title = os[:pretty_name] || Map.get(os, :name, "Linux")

    Line.new([
      Span.new(title, style: Theme.title_style()),
      Span.new("  ·  extop", style: Theme.dim_style())
    ])
  end

  defp blank_row, do: Line.new([])

  defp format_row({label, value}) do
    Line.new([
      Span.new(String.pad_trailing(label <> ":", @label_width), style: Theme.dim_style()),
      Span.new(present(value), style: Theme.text_style())
    ])
  end

  defp present(nil), do: "N/A"
  defp present(""), do: "N/A"
  defp present(value) when is_binary(value), do: value |> String.replace("\n", " ") |> String.trim()
  defp present(value), do: value |> to_string() |> String.replace("\n", " ") |> String.trim()

  defp read_os_release do
    case File.read("/etc/os-release") do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              normalized =
                value
                |> String.trim("\"")
                |> String.trim("'")

              case key do
                "PRETTY_NAME" -> Map.put(acc, :pretty_name, normalized)
                "NAME" -> Map.put(acc, :name, normalized)
                "VERSION_ID" -> Map.put(acc, :version_id, normalized)
                "ID" -> Map.put(acc, :id, normalized)
                _ -> acc
              end

            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp kernel_version do
    case File.read("/proc/version") do
      {:ok, "Linux version " <> rest} ->
        rest |> String.split(" ", parts: 2) |> List.first()

      {:ok, content} ->
        content |> String.split(" ", parts: 3) |> Enum.at(2) |> Kernel.||("N/A")

      _ ->
        case :os.type() do
          {:unix, :linux} ->
            case System.cmd("uname", ["-r"], stderr_to_stdout: true) do
              {output, 0} -> String.trim(output)
              _ -> "N/A"
            end

          _ ->
            "N/A"
        end
    end
  end

  defp arch do
    case System.cmd("uname", ["-m"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> :erlang.system_info(:system_architecture) |> to_string()
    end
  rescue
    _ -> "N/A"
  end

  defp package_count do
    cond do
      File.regular?("/var/lib/dpkg/status") ->
        "/var/lib/dpkg/status"
        |> File.stream!()
        |> Enum.count(&String.starts_with?(&1, "Package: "))
        |> Integer.to_string()

      File.exists?("/usr/bin/rpm") ->
        case System.cmd("rpm", ["-qa"], stderr_to_stdout: true) do
          {output, 0} -> output |> String.split("\n", trim: true) |> length() |> Integer.to_string()
          _ -> "N/A"
        end

      true ->
        "N/A"
    end
  rescue
    _ -> "N/A"
  end

  defp session_type do
    cond do
      env("WAYLAND_DISPLAY") != "N/A" ->
        "Wayland (#{System.get_env("WAYLAND_DISPLAY")})"

      env("DISPLAY") != "N/A" ->
        "X11 (#{System.get_env("DISPLAY")})"

      true ->
        "N/A"
    end
  end

  defp window_manager do
    first_present([
      System.get_env("XDG_SESSION_DESKTOP"),
      System.get_env("DESKTOP_SESSION"),
      System.get_env("XDG_CURRENT_DESKTOP")
    ])
  end

  defp terminal_name do
    first_present([
      System.get_env("TERM_PROGRAM"),
      System.get_env("TERMINAL_EMULATOR"),
      System.get_env("WT_SESSION") && "Windows Terminal",
      System.get_env("KONSOLE_VERSION") && "Konsole",
      System.get_env("GNOME_TERMINAL_SERVICE") && "GNOME Terminal",
      System.get_env("VTE_VERSION") && "VTE",
      System.get_env("TERM")
    ])
  end

  defp gsetting(schema, key) do
    case System.cmd("gsettings", ["get", schema, key], stderr_to_stdout: true) do
      {output, 0} -> output |> String.trim() |> String.trim("'")
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp local_ips do
    case :inet.getifaddrs() do
      {:ok, ifaddrs} ->
        ifaddrs
        |> Enum.reject(fn {name, _} ->
          n = List.to_string(name)
          n == "lo" or String.starts_with?(n, "docker") or String.starts_with?(n, "br-")
        end)
        |> Enum.flat_map(fn {name, opts} ->
          name = List.to_string(name)

          if interface_up?(opts) do
            opts
            |> Keyword.get_values(:addr)
            |> Enum.flat_map(&format_addr(name, &1))
          else
            []
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp interface_up?(opts) do
    flags = Keyword.get(opts, :flags, [])
    :up in flags or :running in flags
  end

  defp format_addr(name, {a, b, c, d})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    ip = Enum.join([a, b, c, d], ".")
    if ip == "127.0.0.1", do: nil, else: "#{name}: #{ip}"
  end

  defp format_addr(name, {a, b, c, d, e, f, g, h})
       when is_integer(a) and h != nil do
    if a == 0xfe and band(b, 0xc0) == 0x80, do: nil, else: "#{name}: #{format_ipv6({a, b, c, d, e, f, g, h})}"
  end

  defp format_addr(_name, _), do: nil

  defp band(a, b), do: :erlang.band(a, b)

  defp format_ipv6(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  defp battery_status do
    "/sys/class/power_supply/BAT*"
    |> Path.wildcard()
    |> Enum.map(&battery_info/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("  ")
    |> case do
      "" -> nil
      status -> status
    end
  end

  defp battery_info(path) do
    capacity = read_sysfs_int(Path.join(path, "capacity"))
    status = read_sysfs(Path.join(path, "status"))
    name = Path.basename(path)

    cond do
      capacity && status ->
        "#{name}: #{capacity}% (#{status})"

      capacity ->
        "#{name}: #{capacity}%"

      true ->
        nil
    end
  end

  defp read_sysfs(path) do
    case File.read(path) do
      {:ok, value} ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  defp read_sysfs_int(path) do
    case read_sysfs(path) do
      nil -> nil
      value -> String.to_integer(value)
    end
  rescue
    _ -> nil
  end

  defp env(key) do
    case System.get_env(key) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  defp first_present(values) do
    Enum.find_value(values, fn
      nil -> nil
      "" -> nil
      false -> nil
      value -> value
    end)
  end

  defp format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    mins = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{mins}m"
      hours > 0 -> "#{hours}h #{mins}m"
      true -> "#{mins}m"
    end
  end

  defp format_usage(%{total: total, used: used}) when total > 0 do
    pct = Float.round(used / total * 100, 0)
    "#{format_bytes(used)} / #{format_bytes(total)}  (#{trunc(pct)}%)"
  end

  defp format_usage(_), do: "N/A"

  defp format_percent(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  defp format_percent(_), do: "N/A"

  defp format_temp(nil), do: "N/A"
  defp format_temp(temp) when is_number(temp), do: "#{Float.round(temp, 1)}°C"

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{:erlang.float_to_binary(bytes / 1_073_741_824, decimals: 1)} GiB"

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{:erlang.float_to_binary(bytes / 1_048_576, decimals: 1)} MiB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{:erlang.float_to_binary(bytes / 1024, decimals: 1)} KiB"

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(_), do: "N/A"

  defp color_palette_lines do
    [
      blank_row(),
      palette_line(40..47),
      palette_line(100..107)
    ]
  end

  defp palette_line(codes) do
    padding = String.duplicate(" ", @palette_indent)

    swatches =
      Enum.map(codes, fn code ->
        Span.new("   ", style: %Style{bg: ansi_bg(code)})
      end)

    Line.new([Span.new(padding, style: Theme.text_style()) | swatches])
  end

  defp ansi_bg(40), do: :black
  defp ansi_bg(41), do: :red
  defp ansi_bg(42), do: :green
  defp ansi_bg(43), do: :yellow
  defp ansi_bg(44), do: :blue
  defp ansi_bg(45), do: :magenta
  defp ansi_bg(46), do: :cyan
  defp ansi_bg(47), do: :white
  defp ansi_bg(100), do: {:rgb, 85, 85, 85}
  defp ansi_bg(101), do: {:rgb, 255, 85, 85}
  defp ansi_bg(102), do: {:rgb, 85, 255, 85}
  defp ansi_bg(103), do: {:rgb, 255, 255, 85}
  defp ansi_bg(104), do: {:rgb, 85, 85, 255}
  defp ansi_bg(105), do: {:rgb, 255, 85, 255}
  defp ansi_bg(106), do: {:rgb, 85, 255, 255}
  defp ansi_bg(107), do: {:rgb, 255, 255, 255}
end
