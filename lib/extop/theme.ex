defmodule Extop.Theme do
  @moduledoc false

  alias ExRatatui.Style

  @teal {:rgb, 0, 212, 170}
  @cyan {:rgb, 0, 180, 216}
  @aqua {:rgb, 72, 202, 228}
  @mint {:rgb, 144, 224, 208}
  @teal_dim {:rgb, 0, 119, 112}
  @border {:rgb, 0, 80, 90}
  @border_bright {:rgb, 0, 140, 130}
  @text {:rgb, 190, 230, 225}
  @text_dim {:rgb, 70, 120, 115}
  @warn {:rgb, 255, 183, 77}
  @critical {:rgb, 255, 90, 90}

  def teal, do: @teal
  def cyan, do: @cyan
  def aqua, do: @aqua
  def mint, do: @mint
  def teal_dim, do: @teal_dim
  def border, do: @border
  def border_bright, do: @border_bright
  def text, do: @text
  def text_dim, do: @text_dim

  def style(fg, opts \\ []) do
    %Style{
      fg: fg,
      modifiers: Keyword.get(opts, :modifiers, [])
    }
  end

  def panel_border(accent \\ @border_bright), do: style(accent)
  def header_border, do: style(@teal, modifiers: [:bold])
  def title_style, do: style(@teal, modifiers: [:bold])
  def accent_style, do: style(@cyan, modifiers: [:bold])
  def text_style, do: style(@text)
  def dim_style, do: style(@text_dim)

  def usage_color(ratio) when ratio >= 0.9, do: @critical
  def usage_color(ratio) when ratio >= 0.7, do: @warn
  def usage_color(ratio) when ratio >= 0.4, do: @cyan
  def usage_color(_), do: @teal

  def load_color(load) when load >= 4.0, do: @critical
  def load_color(load) when load >= 2.0, do: @warn
  def load_color(_), do: @mint

  def chart_line, do: style(@teal)
  def chart_axis, do: style(@text_dim)
  def bar_default, do: style(@teal)
  def bar_label, do: style(@mint)
  def bar_value, do: style(@text_dim)
  def table_header, do: style(@cyan, modifiers: [:bold])
  def table_row, do: style(@text)
  def table_highlight, do: style(@teal, modifiers: [:bold])

  def gauge_accent(:memory), do: @teal
  def gauge_accent(:swap), do: @cyan
  def gauge_accent(:disk), do: @aqua
  def gauge_accent(_), do: @border_bright
end
