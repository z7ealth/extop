defmodule Extop.Fastfetch do
  @moduledoc false

  alias ExRatatui.Style
  alias ExRatatui.Text.{Line, Span}
  alias Extop.Theme

  @refresh_seconds 30
  @palette_indent 47

  @structure [
    "Title",
    "Separator",
    "OS",
    "Host",
    "Kernel",
    "Uptime",
    "Packages",
    "Shell",
    "Display",
    "DE",
    "WM",
    "WMTheme",
    "Theme",
    "Icons",
    "Font",
    "Cursor",
    "Terminal",
    "CPU",
    "GPU",
    "Memory",
    "Swap",
    "Disk",
    "LocalIp",
    "Battery",
    "Locale"
  ]

  @spec fetch(map() | nil) :: {[Line.t()], integer()}
  def fetch(prev \\ nil) do
    now = System.monotonic_time(:second)

    if stale?(prev, now) do
      {run(), now}
    else
      {Map.get(prev, :system_info, run()), Map.get(prev, :system_info_at, now)}
    end
  end

  defp stale?(nil, _now), do: true

  defp stale?(prev, now) do
    now - Map.get(prev, :system_info_at, 0) >= @refresh_seconds
  end

  defp run do
    case System.find_executable("fastfetch") do
      nil ->
        [plain_line("fastfetch not found")]

      _path ->
        {output, 0} =
          System.cmd(
            "fastfetch",
            ["--pipe", "true", "--structure", Enum.join(@structure, ":")],
            stderr_to_stdout: true
          )

        output
        |> String.split("\n")
        |> trim_trailing_empty()
        |> Enum.reject(&ansi_line?/1)
        |> Enum.map(&plain_line/1)
        |> Kernel.++(color_palette_lines())
    end
  rescue
    _ -> [plain_line("fastfetch failed")]
  end

  defp plain_line(text) do
    Line.new([Span.new(text, style: Theme.text_style())])
  end

  defp ansi_line?(line), do: String.contains?(line, "\e")

  defp color_palette_lines do
    [
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

  defp trim_trailing_empty(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end
end
