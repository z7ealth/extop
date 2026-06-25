defmodule Extop.TUI do
  @moduledoc false

  use ExRatatui.App

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Block, Chart, Gauge, Paragraph, Table}
  alias ExRatatui.Widgets.Chart.{Axis, Dataset}
  alias Extop.Theme

  @refresh_interval 1_000
  @visible_processes 12

  @impl true
  def mount(_opts) do
    schedule_refresh()
    {:ok, Map.merge(Extop.Stats.collect(), %{process_offset: 0})}
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}
  def handle_event(%Event.Key{code: "Q", kind: "press"}, state), do: {:stop, state}
  def handle_event(%Event.Key{code: "esc", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["up", "k"] do
    {:noreply, %{state | process_offset: max(state.process_offset - 1, 0)}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state) when code in ["down", "j"] do
    max_offset = max(length(state.processes) - @visible_processes, 0)
    {:noreply, %{state | process_offset: min(state.process_offset + 1, max_offset)}}
  end

  def handle_event(%Event.Key{code: "r", kind: "press"}, state) do
    {:noreply, refresh(Map.delete(state, :system_info_at))}
  end

  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    {:noreply, refresh(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, body_area, proc_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:min, 8},
        {:length, min(@visible_processes + 3, max(frame.height - 12, 6))},
        {:length, 1}
      ])

    [left_col, right_col] =
      Layout.split(body_area, :horizontal, [{:percentage, 58}, {:percentage, 42}])

    [cpu_area, net_area] =
      Layout.split(left_col, :vertical, [{:percentage, 55}, {:percentage, 45}])

    cpu_stats_height = min(max(length(state.cpu_cores) + 2, 3), 8)
    net_stats_height = min(max(length(state.network) + 1, 2), 5)

    [cpu_stats_area, cpu_chart_area] =
      Layout.split(cpu_area, :vertical, [{:length, cpu_stats_height}, {:min, 0}])

    [net_stats_area, net_chart_area] =
      Layout.split(net_area, :vertical, [{:length, net_stats_height}, {:min, 0}])

    [mem_area, swap_area, disk_area, info_area] =
      Layout.split(right_col, :vertical, [
        {:length, 3},
        {:length, 3},
        {:length, 3},
        {:min, 3}
      ])

    [
      {header_widget(state), header_area},
      {cpu_stats_widget(state), cpu_stats_area},
      {cpu_chart_widget(state), cpu_chart_area},
      {network_stats_widget(state), net_stats_area},
      {network_chart_widget(state), net_chart_area},
      {memory_widget(state), mem_area},
      {swap_widget(state), swap_area},
      {disk_widget(state), disk_area},
      {info_widget(state), info_area},
      {process_widget(state), proc_area},
      {footer_widget(), footer_area}
    ]
  end

  defp panel_block(title, accent) do
    %Block{
      title: title,
      borders: [:all],
      border_type: :rounded,
      border_style: Theme.panel_border(accent)
    }
  end

  defp header_widget(state) do
    {one, five, fifteen} = state.load_avg
    uptime = format_uptime(state.uptime_seconds)

    %Paragraph{
      text:
        Line.new([
          Span.new(" #{state.hostname}", style: Theme.title_style()),
          Span.new("  │  up #{uptime}", style: Theme.text_style()),
          Span.new(
            "  │  load #{Float.round(one, 2)} #{Float.round(five, 2)} #{Float.round(fifteen, 2)}",
            style: Theme.style(Theme.load_color(one))
          ),
          Span.new(
            "  │  CPU #{Float.round(state.cpu_total, 1)}%",
            style:
              Theme.style(Theme.usage_color(state.cpu_total / 100.0), modifiers: [:bold])
          )
        ]),
      style: Theme.text_style(),
      block: %Block{
        title: " extop ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.header_border()
      }
    }
  end

  defp cpu_stats_widget(state) do
    lines =
      [
        "  #{String.pad_trailing("total", 10)} #{Float.round(state.cpu_total, 1)}%"
        | Enum.map(state.cpu_cores, fn %{id: id, usage: usage} ->
            "  #{String.pad_trailing("C#{id}", 10)} #{Float.round(usage, 1)}%"
          end)
      ]

    %Paragraph{
      text: Enum.join(lines, "\n"),
      style: Theme.text_style(),
      block: panel_block(" CPU ", Theme.teal())
    }
  end

  defp cpu_chart_widget(state) do
    history = state.cpu_history
    chart_data = history_to_chart(history)

    %Chart{
      datasets: [
        %Dataset{
          name: "cpu",
          data: chart_data,
          graph_type: :line,
          marker: :braille,
          style: Theme.chart_line()
        }
      ],
      x_axis: chart_x_axis(history),
      y_axis: %Axis{
        bounds: {0.0, 100.0},
        labels: ["0", "50", "100"],
        labels_alignment: :right,
        style: Theme.chart_axis()
      },
      legend_position: nil,
      block: panel_block(" CPU Graph ", Theme.cyan())
    }
  end

  defp memory_widget(state) do
    gauge_widget(" Memory ", state.memory, :memory)
  end

  defp swap_widget(state) do
    gauge_widget(" Swap ", state.swap, :swap)
  end

  defp disk_widget(state) do
    gauge_widget(" Disk / ", state.disk, :disk)
  end

  defp gauge_widget(title, %{total: total, used: used}, kind) do
    {ratio, label} =
      if total > 0 do
        {used / total, "#{format_bytes(used)} / #{format_bytes(total)}"}
      else
        {0.0, "N/A"}
      end

    %Gauge{
      ratio: ratio,
      label: label,
      gauge_style: Theme.style(Theme.usage_color(ratio)),
      block: panel_block(title, Theme.gauge_accent(kind))
    }
  end

  defp network_stats_widget(state) do
    lines =
      if state.network == [] do
        ["  no active interfaces"]
      else
        Enum.map(state.network, fn iface ->
          "  #{String.pad_trailing(iface.name, 10)} ↓ #{format_rate(iface.rx_rate)}  ↑ #{format_rate(iface.tx_rate)}"
        end)
      end

    %Paragraph{
      text: Enum.join(lines, "\n"),
      style: Theme.text_style(),
      block: panel_block(" Network ", Theme.aqua())
    }
  end

  defp network_chart_widget(state) do
    rx_data = history_to_chart(state.net_rx_history)
    tx_data = history_to_chart(state.net_tx_history)
    max_y = chart_rate_max(state.net_rx_history, state.net_tx_history)

    %Chart{
      datasets: [
        %Dataset{
          name: "down",
          data: rx_data,
          graph_type: :line,
          marker: :braille,
          style: Theme.chart_line()
        },
        %Dataset{
          name: "up",
          data: tx_data,
          graph_type: :line,
          marker: :braille,
          style: Theme.style(Theme.cyan())
        }
      ],
      x_axis: chart_x_axis(state.net_rx_history),
      y_axis: %Axis{
        bounds: {0.0, max_y},
        labels: rate_axis_labels(max_y),
        labels_alignment: :right,
        style: Theme.chart_axis()
      },
      legend_position: :top_right,
      block: panel_block(" Network Graph ", Theme.aqua())
    }
  end

  defp history_to_chart(history) do
    history
    |> Enum.with_index()
    |> Enum.map(fn {value, idx} -> {idx * 1.0, value * 1.0} end)
  end

  defp chart_x_axis(history) do
    %Axis{
      bounds: {0.0, max(length(history) - 1, 1) * 1.0},
      labels: [],
      style: Theme.chart_axis()
    }
  end

  defp chart_rate_max(rx_history, tx_history) do
    [rx_history, tx_history]
    |> List.flatten()
    |> Enum.max(fn -> 0 end)
    |> max(1024)
    |> Kernel.*(1.0)
  end

  defp rate_axis_labels(max_y) do
    mid = max_y / 2.0
    [format_rate(trunc(max_y)), format_rate(trunc(mid)), "0"]
  end

  defp info_widget(state) do
    lines =
      case Map.get(state, :system_info, []) do
        [] -> ["  loading system info…"]
        info -> info
      end

    %Paragraph{
      text: Enum.join(lines, "\n"),
      style: Theme.dim_style(),
      block: panel_block(" System ", Theme.border())
    }
  end

  defp process_widget(state) do
    rows =
      state.processes
      |> Enum.drop(state.process_offset)
      |> Enum.take(@visible_processes)
      |> Enum.map(fn proc ->
        [
          to_string(proc.pid),
          proc.name,
          "#{Float.round(proc.cpu, 1)}%",
          "#{Float.round(proc.mem, 1)}%"
        ]
      end)

    rows = if rows == [], do: [["--", "no processes", "--", "--"]], else: rows

    %Table{
      header: ["PID", "Name", "CPU", "Mem"],
      rows: rows,
      widths: [{:length, 8}, {:min, 10}, {:length, 8}, {:length, 8}],
      style: Theme.table_row(),
      header_style: Theme.table_header(),
      highlight_style: Theme.table_highlight(),
      highlight_symbol: "▸ ",
      selected: 0,
      block: panel_block(" Processes ", Theme.teal_dim())
    }
  end

  defp footer_widget do
    %Paragraph{
      text: " q/esc quit · r refresh · ↑↓ scroll processes",
      style: Theme.dim_style()
    }
  end

  defp refresh(state) do
    offset = Map.get(state, :process_offset, 0)
    state |> Extop.Stats.collect() |> Map.put(:process_offset, offset)
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  defp format_uptime(seconds) do
    days = div(seconds, 86_400)
    hours = div(rem(seconds, 86_400), 3600)
    mins = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{mins}m"
      hours > 0 -> "#{hours}h #{mins}m"
      true -> "#{mins}m"
    end
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{:erlang.float_to_binary(bytes / 1_073_741_824, decimals: 1)} GiB"

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{:erlang.float_to_binary(bytes / 1_048_576, decimals: 1)} MiB"

  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{:erlang.float_to_binary(bytes / 1024, decimals: 1)} KiB"

  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_rate(bytes_per_sec) when bytes_per_sec >= 1_048_576,
    do: "#{:erlang.float_to_binary(bytes_per_sec / 1_048_576, decimals: 1)} MiB/s"

  defp format_rate(bytes_per_sec) when bytes_per_sec >= 1024,
    do: "#{:erlang.float_to_binary(bytes_per_sec / 1024, decimals: 1)} KiB/s"

  defp format_rate(bytes_per_sec), do: "#{bytes_per_sec} B/s"
end
