defmodule Extop.Theme do
  @moduledoc false

  # Catppuccin Mocha — https://github.com/catppuccin/catppuccin

  alias ExRatatui.Style

  @teal {:rgb, 148, 226, 213}
  @cyan {:rgb, 137, 220, 235}
  @aqua {:rgb, 116, 199, 236}
  @mint {:rgb, 166, 227, 161}
  @teal_dim {:rgb, 203, 166, 247}
  @border {:rgb, 69, 71, 90}
  @border_bright {:rgb, 148, 226, 213}
  @text {:rgb, 205, 214, 244}
  @text_dim {:rgb, 127, 132, 156}
  @warn {:rgb, 250, 179, 135}
  @critical {:rgb, 243, 139, 168}

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
  def usage_color(ratio) when ratio >= 0.4, do: @aqua
  def usage_color(_), do: @mint

  def load_color(load) when load >= 4.0, do: @critical
  def load_color(load) when load >= 2.0, do: @warn
  def load_color(_), do: @mint

  def temp_color(temp) when is_number(temp) and temp >= 85, do: @critical
  def temp_color(temp) when is_number(temp) and temp >= 70, do: @warn
  def temp_color(temp) when is_number(temp), do: @mint
  def temp_color(_), do: @text_dim

  def chart_line, do: style(@teal)
  def chart_axis, do: style(@text_dim)
  def bar_default, do: style(@teal)
  def bar_label, do: style(@text)
  def bar_value, do: style(@text_dim)
  def table_header, do: style(@cyan, modifiers: [:bold])
  def table_row, do: style(@text)
  def table_highlight, do: style(@teal, modifiers: [:bold])

  def gauge_accent(:memory), do: @teal
  def gauge_accent(:swap), do: @cyan
  def gauge_accent(:disk), do: @aqua
  def gauge_accent(_), do: @border_bright
end
