defmodule Extop.Fastfetch do
  @moduledoc false

  @refresh_seconds 30

  @spec fetch(map() | nil) :: {list(String.t()), integer()}
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
        ["  fastfetch not found"]

      _path ->
        {output, 0} =
          System.cmd("fastfetch", ["--logo", "none", "--pipe", "true"],
            stderr_to_stdout: true
          )

        output
        |> String.split("\n", trim: true)
        |> Enum.map(&("  " <> &1))
    end
  rescue
    _ -> ["  fastfetch failed"]
  end
end
