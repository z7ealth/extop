defmodule Extop.Theme do
  @moduledoc false

  # Catppuccin Macchiato - softer contrast than Mocha, warmer mid-tones
  # https://github.com/catppuccin/catppuccin

  alias ExRatatui.Style

  @teal {:rgb, 139, 213, 202}
  @sky {:rgb, 145, 215, 227}
  @sapphire {:rgb, 125, 196, 228}
  @green {:rgb, 166, 218, 149}
  @yellow {:rgb, 238, 212, 159}
  @mauve {:rgb, 198, 160, 246}
  @lavender {:rgb, 183, 189, 248}
  @pink {:rgb, 245, 189, 230}
  @flamingo {:rgb, 240, 198, 198}
  @peach {:rgb, 245, 169, 127}
  @red {:rgb, 237, 135, 150}
  @border {:rgb, 73, 77, 100}
  @border_bright {:rgb, 139, 213, 202}
  @surface {:rgb, 54, 58, 79}
  @text {:rgb, 202, 211, 245}
  @subtext {:rgb, 184, 192, 224}
  @text_dim {:rgb, 128, 135, 162}

  def teal, do: @teal
  def cyan, do: @sky
  def sky, do: @sky
  def aqua, do: @sapphire
  def mint, do: @green
  def teal_dim, do: @lavender
  def pink, do: @pink
  def mauve, do: @mauve
  def lavender, do: @lavender
  def flamingo, do: @flamingo
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
  def panel_title(accent), do: style(accent, modifiers: [:bold])
  def gauge_track, do: style(@text, bg: @surface, modifiers: [:bold])
  def gauge_fill(ratio), do: style(@text, bg: usage_color(ratio), modifiers: [:bold])
  def gauge_name_style, do: style(@subtext, modifiers: [:bold])
  def header_border, do: style(@mauve, modifiers: [:bold])
  def title_style, do: style(@teal, modifiers: [:bold])
  def accent_style, do: style(@sky, modifiers: [:bold])
  def text_style, do: style(@text)
  def dim_style, do: style(@text_dim)

  def usage_color(ratio) when ratio >= 0.9, do: @red
  def usage_color(ratio) when ratio >= 0.7, do: @peach
  def usage_color(ratio) when ratio >= 0.4, do: @yellow
  def usage_color(_), do: @green

  def load_color(load) when load >= 4.0, do: @red
  def load_color(load) when load >= 2.0, do: @peach
  def load_color(_), do: @teal

  def temp_color(temp) when is_number(temp) and temp >= 85, do: @red
  def temp_color(temp) when is_number(temp) and temp >= 70, do: @peach
  def temp_color(temp) when is_number(temp), do: @teal
  def temp_color(_), do: @text_dim

  def chart_line, do: style(@teal)
  def chart_axis, do: style(@text_dim)
  def bar_default, do: style(@teal)
  def bar_label, do: style(@subtext)
  def bar_value, do: style(@text_dim)
  def table_header, do: style(@sky, modifiers: [:bold])
  def table_row, do: style(@text)
  def table_highlight, do: style(@mauve, modifiers: [:bold])

  def gauge_accent(:memory), do: @teal
  def gauge_accent(:swap), do: @sky
  def gauge_accent(:disk), do: @sapphire
  def gauge_accent(_), do: @lavender
end
