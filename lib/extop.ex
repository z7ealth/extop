defmodule Extop do
  @moduledoc """
  A system monitor built with [ex_ratatui](https://hex.pm/packages/ex_ratatui).

  ## Usage

      mix run

  The TUI is started under supervision when the app boots. Press `q` or `Esc` to quit.

  On the **Processes** tab: use `↑`/`↓`/`j` to select, `/` to filter, `p`/`u`/`n`/`c`/`m` to sort,
  and `t`/`k`/`s`/`r`/`h`/`i` to send signals (TERM/KILL/STOP/CONT/HUP/INT).
  """

  @spec version() :: String.t()
  def version do
    Application.spec(:extop, :vsn) |> to_string()
  end
end
