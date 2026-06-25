defmodule Extop.BeamStats do
  @moduledoc false

  alias ExRatatui.Text.{Line, Span}
  alias Extop.Theme

  @label_width 16

  @spec lines() :: [Line.t()]
  def lines do
    memory = :erlang.memory()
    {wall_ms, _} = :erlang.statistics(:wall_clock)
    {reductions, _} = :erlang.statistics(:reductions)

    rows = [
      {"OTP", otp_release()},
      {"Elixir", System.version()},
      {"ERTS", erts_version()},
      {"Arch", arch()},
      {"Schedulers", schedulers()},
      {"Processes", count_limit(:process_count, :process_limit)},
      {"Atoms", count_limit(:atom_count, :atom_limit)},
      {"Ports", count_limit(:port_count, :port_limit)},
      {"ETS tables", ets_count()},
      {"Run queue", run_queue()},
      {"Reductions", format_int(reductions)},
      {"Uptime", format_uptime(wall_ms)},
      {"", ""},
      {"Memory total", format_bytes(Keyword.get(memory, :total))},
      {"  processes", format_bytes(Keyword.get(memory, :processes))},
      {"  system", format_bytes(Keyword.get(memory, :system))},
      {"  atom", format_bytes(Keyword.get(memory, :atom))},
      {"  binary", format_bytes(Keyword.get(memory, :binary))},
      {"  ets", format_bytes(Keyword.get(memory, :ets))},
      {"  code", format_bytes(Keyword.get(memory, :code))}
    ]

    Enum.map(rows, &format_row/1)
  end

  defp format_row({"", ""}), do: Line.new([])

  defp format_row({label, value}) do
    Line.new([
      Span.new(String.pad_trailing(label <> ":", @label_width), style: Theme.dim_style()),
      Span.new(value, style: Theme.text_style())
    ])
  end

  defp otp_release do
    :erlang.system_info(:otp_release) |> to_string()
  end

  defp erts_version do
    :erlang.system_info(:version) |> to_string()
  end

  defp arch do
    :erlang.system_info(:system_architecture) |> to_string()
  end

  defp schedulers do
    online = :erlang.system_info(:schedulers_online)
    total = :erlang.system_info(:schedulers)
    "#{online} / #{total}"
  end

  defp count_limit(count_key, limit_key) do
    count = :erlang.system_info(count_key)
    limit = :erlang.system_info(limit_key)
    "#{format_int(count)} / #{format_int(limit)}"
  end

  defp ets_count do
    length(:ets.all()) |> format_int()
  rescue
    _ -> "N/A"
  end

  defp run_queue do
    case :erlang.statistics(:total_run_queue_lengths) do
      {total, _, _, _} ->
        format_int(total)

      _ ->
        case :erlang.statistics(:run_queue) do
          n when is_integer(n) -> format_int(n)
          _ -> "N/A"
        end
    end
  rescue
    _ -> "N/A"
  end

  defp format_uptime(ms) when is_integer(ms) do
    total_sec = div(ms, 1000)
    days = div(total_sec, 86_400)
    hours = div(rem(total_sec, 86_400), 3600)
    mins = div(rem(total_sec, 3600), 60)
    secs = rem(total_sec, 60)

    cond do
      days > 0 -> "#{days}d #{hours}h #{mins}m"
      hours > 0 -> "#{hours}h #{mins}m #{secs}s"
      mins > 0 -> "#{mins}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  defp format_int(n) when is_integer(n), do: :erlang.integer_to_binary(n)

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_073_741_824,
    do: "#{:erlang.float_to_binary(bytes / 1_073_741_824, decimals: 2)} GiB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576,
    do: "#{:erlang.float_to_binary(bytes / 1_048_576, decimals: 1)} MiB"

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1024,
    do: "#{:erlang.float_to_binary(bytes / 1024, decimals: 1)} KiB"

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(_), do: "N/A"
end
