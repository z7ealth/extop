defmodule Extop.TUI do
  @moduledoc false

  use ExRatatui.App

  alias ExRatatui.Event
  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Text.{Line, Span}
  alias ExRatatui.Widgets.{Bar, BarChart, Block, Chart, Paragraph, Table, Tabs}
  alias ExRatatui.Widgets.Chart.{Axis, Dataset}
  alias Extop.Theme
  alias Extop.Processes

  @refresh_interval 1_000
  @resize_debounce 100
  @tabs ["Dashboard", "Processes", "Network", "System"]

  @impl true
  def mount(_opts) do
    schedule_refresh()

    {:ok,
     Map.merge(Extop.Stats.collect(), %{
       process_selection: 0,
       process_filter: "",
       process_filter_active: false,
       process_sort: {:cpu, :desc},
       process_pending_signal: nil,
       process_status: nil,
       tab: 0,
       resize_timer: nil
     })}
  end

  @impl true
  def handle_event(%Event.Key{code: "q", kind: "press"}, state), do: {:stop, state}
  def handle_event(%Event.Key{code: "Q", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: "esc", kind: "press"}, %{tab: 1} = state) do
    cond do
      state.process_pending_signal ->
        {:noreply, %{state | process_pending_signal: nil}}

      state.process_filter_active ->
        {:noreply, %{state | process_filter_active: false}}

      state.process_filter != "" ->
        {:noreply, process_filter_changed(state, "")}

      true ->
        {:stop, state}
    end
  end

  def handle_event(%Event.Key{code: "esc", kind: "press"}, state), do: {:stop, state}

  def handle_event(%Event.Key{code: code, kind: "press"}, %{tab: 1, process_pending_signal: pending} = state)
      when not is_nil(pending) and code in ["y", "enter"] do
    {:noreply, confirm_process_signal(state)}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, %{tab: 1, process_pending_signal: pending} = state)
      when not is_nil(pending) and code in ["n"] do
    {:noreply, %{state | process_pending_signal: nil, process_status: "Signal cancelled"}}
  end

  def handle_event(%Event.Key{code: _code, kind: "press"}, %{tab: 1, process_pending_signal: pending} = state)
      when not is_nil(pending) do
    {:noreply, state}
  end

  def handle_event(%Event.Key{code: code, kind: "press", modifiers: []}, %{tab: 1, process_filter_active: true} = state)
      when code in ["enter"] do
    {:noreply, %{state | process_filter_active: false}}
  end

  def handle_event(%Event.Key{code: "backspace", kind: "press"}, %{tab: 1, process_filter_active: true} = state) do
    filter = String.slice(state.process_filter, 0..-2//1)
    {:noreply, process_filter_changed(state, filter)}
  end

  def handle_event(%Event.Key{code: code, kind: "press", modifiers: []}, %{tab: 1, process_filter_active: true} = state)
      when byte_size(code) == 1 do
    {:noreply, process_filter_changed(state, state.process_filter <> code)}
  end

  def handle_event(%Event.Key{code: code, kind: "press", modifiers: []}, %{tab: 1} = state)
      when code in ["/", "f"] do
    {:noreply, %{state | process_filter_active: true, process_status: nil}}
  end

  def handle_event(%Event.Key{code: code, kind: "press", modifiers: []}, %{tab: 1} = state)
      when code in ["p", "u", "n", "c", "m"] do
    {:noreply, process_sort_changed(state, code)}
  end

  def handle_event(%Event.Key{code: code, kind: "press", modifiers: []}, %{tab: 1} = state)
      when code in ["t", "k", "s", "r", "h", "i"] do
    {:noreply, request_process_signal(state, code)}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, %{tab: 1} = state)
      when code in ["up", "down", "j", "page_up", "page_down", "home", "end"] do
    {:noreply, process_move_selection(state, code)}
  end

  def handle_event(%Event.Key{code: "tab", kind: "press"}, state) do
    {:noreply, %{state | tab: rem(state.tab + 1, length(@tabs))}}
  end

  def handle_event(%Event.Key{code: code, kind: "press"}, state)
      when code in ["1", "2", "3", "4"] and is_integer(state.tab) do
    if state.tab == 1 and state.process_filter_active do
      {:noreply, process_filter_changed(state, state.process_filter <> code)}
    else
      {:noreply, %{state | tab: String.to_integer(code) - 1}}
    end
  end

  def handle_event(%Event.Key{code: "r", kind: "press"}, %{tab: 3} = state) do
    {:noreply, refresh(Map.delete(state, :system_info_at))}
  end

  def handle_event(%Event.Resize{}, state) do
    {:noreply, schedule_resize_render(state), render?: false}
  end

  def handle_event(_event, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    System.stop(0)
  end

  @impl true
  def handle_info(:refresh, state) do
    schedule_refresh()
    state = refresh(state)

    if Map.get(state, :resize_timer) do
      {:noreply, state, render?: false}
    else
      {:noreply, state}
    end
  end

  def handle_info(:resize_render, state) do
    {:noreply, %{state | resize_timer: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [header_area, tabs_area, content_area, footer_area] =
      Layout.split(area, :vertical, [
        {:length, 3},
        {:length, 3},
        {:min, 6},
        {:length, 1}
      ])

    tab_widgets(state, content_area) ++
      [
        {header_widget(state), header_area},
        {tabs_widget(state), tabs_area},
        {footer_widget(state), footer_area}
      ]
  end

  defp tab_widgets(state, area) do
    case state.tab do
      0 -> dashboard_widgets(state, area)
      1 -> [{process_widget(state, area), area}]
      2 -> network_tab_widgets(state, area)
      3 -> system_tab_widgets(state, area)
      _ -> []
    end
  end

  defp dashboard_widgets(state, area) do
    gauge_height = 3

    [gauges_area, cpu_area, gpu_area] =
      Layout.split(area, :vertical, [
        {:length, gauge_height},
        {:min, 8},
        {:min, 8}
      ])

    [mem_area, swap_area, disk_area] =
      Layout.split(gauges_area, :horizontal, [
        {:percentage, 33},
        {:percentage, 34},
        {:percentage, 33}
      ])

    [cpu_cores_area, cpu_chart_area] =
      Layout.split(cpu_area, :horizontal, [{:percentage, 32}, {:min, 0}])

    [gpu_util_area, gpu_chart_area] =
      Layout.split(gpu_area, :horizontal, [{:percentage, 32}, {:min, 0}])

    [
      {memory_widget(state), mem_area},
      {swap_widget(state), swap_area},
      {disk_widget(state), disk_area}
    ] ++
      cpu_cores_widgets(state, cpu_cores_area) ++
      [
        {cpu_chart_widget(state), cpu_chart_area},
        {gpu_util_widget(state), gpu_util_area},
        {gpu_chart_widget(state), gpu_chart_area}
      ]
  end

  defp network_tab_widgets(state, area) do
    net_stats_height = min(max(length(state.network) + 1, 2), 6)

    [net_stats_area, net_chart_area] =
      Layout.split(area, :vertical, [{:length, net_stats_height}, {:min, 0}])

    [
      {network_stats_widget(state), net_stats_area},
      {network_chart_widget(state), net_chart_area}
    ]
  end

  defp tabs_widget(state) do
    %Tabs{
      titles: @tabs,
      selected: state.tab,
      style: Theme.dim_style(),
      highlight_style: Theme.table_header(),
      divider: " │ ",
      block: %Block{
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.panel_border(Theme.border_bright())
      }
    }
  end

  defp panel_block(title, accent, borders \\ [:all]) do
    %Block{
      title: title,
      borders: borders,
      border_type: :rounded,
      border_style: Theme.panel_border(accent)
    }
  end

  @cpu_bar_height 1
  @cpu_bar_gap 0

  defp cpu_cores_widgets(state, area) do
    bars = cpu_core_bars(state)
    col_count = cpu_core_column_count(length(bars), area)
    rows_per_col = div(length(bars) + col_count - 1, col_count)
    chunks = Enum.chunk_every(bars, rows_per_col)

    constraints =
      Enum.map(chunks, fn _ ->
        {:ratio, 1, length(chunks)}
      end)

    columns = Layout.split(area, :horizontal, constraints)

    Enum.zip(chunks, columns)
    |> Enum.with_index()
    |> Enum.map(fn {{chunk, col}, idx} ->
      title = if idx == 0, do: cpu_panel_title(state), else: nil
      borders = cpu_cores_borders(idx, length(chunks))

      {cpu_cores_bar_chart(chunk, title, borders), col}
    end)
  end

  defp cpu_core_column_count(bar_count, area) do
    per_col = cpu_bars_per_column(area)
    div(bar_count + per_col - 1, per_col) |> max(1)
  end

  defp cpu_bars_per_column(area) do
    inner_height = max(area.height - 2, 1)
    row_cost = @cpu_bar_height + @cpu_bar_gap

    div(inner_height + @cpu_bar_gap, row_cost) |> max(1)
  end

  defp cpu_cores_borders(0, 1), do: [:left, :top, :bottom]
  defp cpu_cores_borders(0, _n), do: [:left, :top, :bottom]
  defp cpu_cores_borders(idx, n) when idx == n - 1, do: [:top, :right, :bottom]
  defp cpu_cores_borders(_idx, _n), do: [:top, :bottom]

  defp cpu_core_bars(state) do
    [
      %Bar{
        label: "tot",
        value: trunc(state.cpu_total),
        style: Theme.style(Theme.usage_color(state.cpu_total / 100.0), modifiers: [:bold]),
        text_value: "#{Float.round(state.cpu_total, 0)}%"
      }
      | Enum.map(state.cpu_cores, fn %{id: id, usage: usage} ->
          %Bar{
            label: "C#{id}",
            value: trunc(usage),
            style: Theme.style(Theme.usage_color(usage / 100.0)),
            text_value: "#{Float.round(usage, 0)}%"
          }
        end)
    ]
  end

  defp cpu_cores_bar_chart(bars, title, borders) do
    %BarChart{
      data: bars,
      direction: :horizontal,
      max: 100,
      bar_width: @cpu_bar_height,
      bar_gap: @cpu_bar_gap,
      bar_style: Theme.bar_default(),
      label_style: Theme.bar_label(),
      value_style: Theme.bar_value(),
      block: panel_block(title, Theme.mauve(), borders)
    }
  end

  defp cpu_chart_widget(state) do
    history = state.cpu_history
    chart_data = history_to_chart(history)

    %Chart{
      datasets: [
        %Dataset{
          name: "util",
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
      block: panel_block(cpu_chart_title(state), Theme.teal(), [:top, :right, :bottom])
    }
  end

  defp gpu_util_widget(state) do
    %BarChart{
      data: [
        %Bar{
          label: "gpu",
          value: trunc(state.gpu_usage),
          style: Theme.style(Theme.usage_color(state.gpu_usage / 100.0), modifiers: [:bold]),
          text_value: "#{Float.round(state.gpu_usage, 0)}%"
        }
      ],
      direction: :horizontal,
      max: 100,
      bar_style: Theme.style(Theme.mint()),
      label_style: Theme.bar_label(),
      value_style: Theme.bar_value(),
      block: panel_block(gpu_panel_title(state), Theme.aqua(), [:left, :top, :bottom])
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
        title: " extop v#{Extop.version()} ",
        borders: [:all],
        border_type: :rounded,
        border_style: Theme.header_border()
      }
    }
  end

  defp gpu_chart_widget(state) do
    history = state.gpu_history
    chart_data = history_to_chart(history)

    %Chart{
      datasets: [
        %Dataset{
          name: "util",
          data: chart_data,
          graph_type: :line,
          marker: :braille,
          style: Theme.style(Theme.mint())
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
      block: panel_block(gpu_chart_title(state), Theme.aqua(), [:top, :right, :bottom])
    }
  end

  defp cpu_panel_title(_state), do: " CPU "

  defp cpu_chart_title(state) do
    " #{short_hardware_name(state.cpu_name, 36)} · #{format_util(state.cpu_total)} · #{format_temp(state.cpu_temp)} "
  end

  defp gpu_panel_title(_state), do: " GPU "

  defp gpu_chart_title(state) do
    " #{short_hardware_name(state.gpu_name, 36)} · #{format_util(state.gpu_usage)} · #{format_temp(state.gpu_temp)} "
  end

  defp short_hardware_name(name, max) when is_binary(name) do
    name
    |> String.replace("(R)", "")
    |> String.replace("(TM)", "")
    |> String.replace(~r/\s+@.*\z/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> truncate(max)
  end

  defp short_hardware_name(_, _max), do: "N/A"

  defp truncate(text, max) when byte_size(text) <= max, do: text

  defp truncate(text, max) do
    String.slice(text, 0, max - 3) <> "..."
  end

  defp format_util(value) when is_float(value), do: "#{Float.round(value, 1)}%"
  defp format_util(_), do: "N/A"

  defp format_temp(nil), do: "N/A"
  defp format_temp(temp) when is_number(temp), do: "#{Float.round(temp, 1)}°C"

  defp memory_widget(state) do
    resource_widget(" Memory ", state.memory, :memory)
  end

  defp swap_widget(state) do
    resource_widget(" Swap ", state.swap, :swap)
  end

  defp disk_widget(state) do
    resource_widget(" Disk / ", state.disk, :disk)
  end

  defp resource_widget(title, %{total: total, used: used}, kind) do
    accent = Theme.gauge_accent(kind)

    stats =
      if total > 0 do
        ratio = used / total
        pct = ratio * 100

        "#{format_bytes(used)} / #{format_bytes(total)}  #{trunc(Float.round(pct, 0))}%"
      else
        "N/A"
      end

    %Paragraph{
      text: stats,
      style: Theme.text_style(),
      alignment: :center,
      block: panel_block(title, accent)
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
      block: panel_block(" Network ", Theme.pink())
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
          style: Theme.style(Theme.sky())
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
      block: panel_block(" Network Graph ", Theme.pink())
    }
  end

  defp system_tab_widgets(state, area) do
    [system_area, beam_area] =
      Layout.split(area, :horizontal, [{:percentage, 50}, {:min, 0}])

    [
      {system_info_widget(state), system_area},
      {beam_info_widget(), beam_area}
    ]
  end

  defp system_info_widget(state) do
    lines =
      case Map.get(state, :system_info, []) do
        [] -> [Line.new([Span.new("loading system info…", style: Theme.text_style())])]
        info -> info
      end

    %Paragraph{
      text: lines,
      style: Theme.text_style(),
      block: panel_block(" System ", Theme.flamingo())
    }
  end

  defp beam_info_widget do
    %Paragraph{
      text: Extop.BeamStats.lines(),
      style: Theme.text_style(),
      block: panel_block(" BEAM ", Theme.mauve())
    }
  end

  defp process_widget(state, area) do
    visible = max(area.height - 4, 1)
    procs = visible_processes(state)
    total = length(procs)
    selection = Processes.clamp_selection(state.process_selection, total)
    scroll = Processes.scroll_offset(selection, total, visible)
    relative = selection - scroll

    rows =
      procs
      |> Enum.drop(scroll)
      |> Enum.take(visible)
      |> Enum.map(fn proc ->
        [
          to_string(proc.pid),
          proc.user,
          proc.name,
          "#{Float.round(proc.cpu, 1)}%",
          "#{Float.round(proc.mem, 1)}%"
        ]
      end)

    rows = if rows == [], do: [["--", "--", "no processes", "--", "--"]], else: rows

    %Table{
      header: process_header(state),
      footer: process_footer(state, total),
      rows: rows,
      widths: [{:length, 8}, {:length, 10}, {:min, 10}, {:length, 8}, {:length, 8}],
      style: Theme.table_row(),
      header_style: Theme.table_header(),
      footer_style: Theme.dim_style(),
      highlight_style: Theme.table_highlight(),
      highlight_symbol: "▸ ",
      selected: if(total == 0, do: nil, else: relative),
      block: process_panel_block(state)
    }
  end

  defp process_panel_block(state) do
    title =
      cond do
        state.process_filter_active ->
          " Processes  /#{state.process_filter}_ "

        state.process_filter != "" ->
          " Processes  /#{state.process_filter} "

        true ->
          " Processes "
      end

    panel_block(title, Theme.lavender())
  end

  defp process_header(state) do
    {field, dir} = state.process_sort
    arrow = if dir == :desc, do: "↓", else: "↑"

    for {column, label} <- [pid: "PID", user: "User", name: "Name", cpu: "CPU", mem: "Mem"] do
      if column == field, do: "#{label} #{arrow}", else: label
    end
  end

  defp process_footer(state, total) do
    parts =
      [
        "#{total} shown",
        "sort #{Processes.sort_label(state.process_sort)}"
      ]
      |> maybe_prepend_filter(state.process_filter)
      |> maybe_prepend_pending_signal(state.process_pending_signal)
      |> maybe_prepend_status(state.process_status)

    [Enum.join(parts, "  ·  ")]
  end

  defp maybe_prepend_filter(parts, ""), do: parts
  defp maybe_prepend_filter(parts, filter), do: ["filter: #{filter}" | parts]

  defp maybe_prepend_pending_signal(parts, nil), do: parts

  defp maybe_prepend_pending_signal(parts, %{signal: signal, pid: pid, name: name}) do
    ["#{Processes.signal_name(signal)} → #{name} (#{pid})? y/n" | parts]
  end

  defp maybe_prepend_status(parts, nil), do: parts
  defp maybe_prepend_status(parts, status), do: [status | parts]

  defp visible_processes(state) do
    Processes.prepare(state.processes, state.process_filter, state.process_sort)
  end

  defp selected_process(state) do
    state |> visible_processes() |> Enum.at(state.process_selection)
  end

  defp process_filter_changed(state, filter) do
    procs = Processes.prepare(state.processes, filter, state.process_sort)

    state
    |> Map.put(:process_filter, filter)
    |> Map.put(:process_selection, Processes.clamp_selection(0, length(procs)))
    |> Map.put(:process_status, nil)
  end

  defp process_sort_changed(state, code) do
    field =
      case code do
        "p" -> :pid
        "u" -> :user
        "n" -> :name
        "c" -> :cpu
        "m" -> :mem
      end

    sort = Processes.toggle_sort(state.process_sort, field)
    pid = selected_process(state) && selected_process(state).pid
    procs = Processes.prepare(state.processes, state.process_filter, sort)

    selection =
      if pid do
        Enum.find_index(procs, &(&1.pid == pid)) || 0
      else
        0
      end

    %{state | process_sort: sort, process_selection: selection, process_status: nil}
  end

  defp process_move_selection(state, code) do
    total = length(visible_processes(state))

    delta =
      case code do
        "up" -> -1
        "down" -> 1
        "j" -> 1
        "page_up" -> -10
        "page_down" -> 10
        "home" -> -total
        "end" -> total
      end

    selection =
      state.process_selection
      |> Kernel.+(delta)
      |> Processes.clamp_selection(total)

    %{state | process_selection: selection, process_status: nil}
  end

  defp request_process_signal(state, code) do
    case selected_process(state) do
      nil ->
        %{state | process_status: "No process selected"}

      proc ->
        signal = Processes.signal_for_key(code)

        if Processes.confirm_signal?(signal) do
          %{state | process_pending_signal: %{signal: signal, pid: proc.pid, name: proc.name}}
        else
          deliver_process_signal(state, proc, signal)
        end
    end
  end

  defp confirm_process_signal(%{process_pending_signal: %{signal: signal, pid: pid, name: name}} = state) do
    state
    |> Map.put(:process_pending_signal, nil)
    |> deliver_process_signal(%{pid: pid, name: name}, signal)
  end

  defp deliver_process_signal(state, proc, signal) do
    status =
      case Processes.send_signal(proc.pid, signal) do
        :ok ->
          "Sent #{Processes.signal_name(signal)} to #{proc.name} (#{proc.pid})"

        {:error, reason} ->
          "Failed #{Processes.signal_name(signal)} on #{proc.pid}: #{inspect(reason)}"
      end

    %{state | process_status: status}
  end

  defp footer_widget(state) do
    hints =
      case state.tab do
        1 ->
          " ↑↓/j scroll · / filter · p/u/n/c/m sort · t/k/s/r/h/i signal · "

        3 ->
          " r refresh system · "

        _ ->
          " "
      end

    %Paragraph{
      text:
        " 1-4 tabs · Tab next ·#{hints}q/esc quit",
      style: Theme.dim_style()
    }
  end

  defp history_to_chart(history) do
    history
    |> Enum.reverse()
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

  defp refresh(state) do
    preserved =
      Map.take(state, [
        :process_selection,
        :process_filter,
        :process_filter_active,
        :process_sort,
        :process_pending_signal,
        :process_status,
        :tab,
        :resize_timer
      ])

    filter = Map.get(preserved, :process_filter, "")
    sort = Map.get(preserved, :process_sort, {:cpu, :desc})
    procs_before = Processes.prepare(state.processes, filter, sort)
    selected_pid = procs_before |> Enum.at(Map.get(preserved, :process_selection, 0)) |> then(&(&1 && &1.pid))

    state
    |> Extop.Stats.collect()
    |> then(fn fresh ->
      procs_after = Processes.prepare(fresh.processes, filter, sort)

      selection =
        if selected_pid do
          Enum.find_index(procs_after, &(&1.pid == selected_pid)) ||
            Processes.clamp_selection(Map.get(preserved, :process_selection, 0), length(procs_after))
        else
          Processes.clamp_selection(Map.get(preserved, :process_selection, 0), length(procs_after))
        end

      fresh
      |> Map.merge(preserved)
      |> Map.put(:process_selection, selection)
    end)
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  defp schedule_resize_render(%{resize_timer: ref} = state) when is_reference(ref) do
    Process.cancel_timer(ref)
    %{state | resize_timer: Process.send_after(self(), :resize_render, @resize_debounce)}
  end

  defp schedule_resize_render(state) do
    %{state | resize_timer: Process.send_after(self(), :resize_render, @resize_debounce)}
  end

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
