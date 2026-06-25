defmodule Extop.Processes do
  @moduledoc false

  @type process :: %{
          pid: non_neg_integer(),
          user: String.t(),
          name: String.t(),
          cpu: float(),
          mem: float()
        }

  @type sort_field :: :pid | :user | :name | :cpu | :mem
  @type sort_dir :: :asc | :desc
  @type sort :: {sort_field(), sort_dir()}
  @type signal :: :sigterm | :sigkill | :sigstop | :sigcont | :sighup | :sigint

  @signals %{
    "t" => :sigterm,
    "k" => :sigkill,
    "s" => :sigstop,
    "r" => :sigcont,
    "h" => :sighup,
    "i" => :sigint
  }

  @signal_names %{
    sigterm: "SIGTERM",
    sigkill: "SIGKILL",
    sigstop: "SIGSTOP",
    sigcont: "SIGCONT",
    sighup: "SIGHUP",
    sigint: "SIGINT"
  }

  @spec prepare([process()], String.t(), sort()) :: [process()]
  def prepare(processes, filter, sort) do
    processes
    |> filter(filter)
    |> sort(sort)
  end

  @spec filter([process()], String.t()) :: [process()]
  def filter(processes, ""), do: processes

  def filter(processes, query) do
    q = String.downcase(query)

    Enum.filter(processes, fn proc ->
      String.contains?(String.downcase(proc.name), q) or
        String.contains?(String.downcase(proc.user), q) or
        String.contains?(to_string(proc.pid), q)
    end)
  end

  @spec sort([process()], sort()) :: [process()]
  def sort(processes, {field, dir}) do
    Enum.sort(processes, fn left, right ->
      cmp = compare_field(field, left, right)
      if dir == :desc, do: cmp == :gt, else: cmp == :lt
    end)
  end

  @spec toggle_sort(sort(), sort_field()) :: sort()
  def toggle_sort({field, dir}, field), do: {field, flip(dir)}
  def toggle_sort(_sort, field), do: {field, :desc}

  @spec scroll_offset(non_neg_integer(), non_neg_integer(), pos_integer()) :: non_neg_integer()
  def scroll_offset(_selection, 0, _visible), do: 0

  def scroll_offset(selection, total, visible) do
    max_offset = max(total - visible, 0)
    selection |> max(0) |> min(max_offset)
  end

  @spec clamp_selection(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def clamp_selection(_selection, 0), do: 0

  def clamp_selection(selection, total) do
    selection |> max(0) |> min(total - 1)
  end

  @spec signal_for_key(String.t()) :: signal() | nil
  def signal_for_key(key), do: Map.get(@signals, key)

  @spec signal_name(signal()) :: String.t()
  def signal_name(signal), do: Map.fetch!(@signal_names, signal)

  @spec confirm_signal?(signal()) :: boolean()
  def confirm_signal?(signal), do: signal in [:sigterm, :sigkill, :sigstop]

  @signal_numbers %{
    sigterm: 15,
    sigkill: 9,
    sigstop: 19,
    sigcont: 18,
    sighup: 1,
    sigint: 2
  }

  @spec send_signal(non_neg_integer(), signal()) :: :ok | {:error, term()}
  def send_signal(pid, signal) when is_integer(pid) and pid > 0 do
    case System.cmd(
           "kill",
           ["-#{Map.fetch!(@signal_numbers, signal)}", Integer.to_string(pid)],
           stderr_to_stdout: true
         ) do
      {"", 0} ->
        :ok

      {output, _} ->
        {:error, String.trim(output)}
    end
  end

  @spec sort_label(sort()) :: String.t()
  def sort_label({field, dir}) do
    arrow = if dir == :desc, do: "↓", else: "↑"
    label = field |> Atom.to_string() |> String.upcase()
    "#{label} #{arrow}"
  end

  @spec fetch([process()]) :: [process()]
  def fetch(cached \\ []) do
    cached |> then(&resolve_fetch(read_ps_output(), &1))
  end

  @spec resolve_fetch([process()], [process()]) :: [process()]
  def resolve_fetch([], cached) when cached != [], do: cached
  def resolve_fetch(fresh, _cached), do: fresh

  @spec parse_ps_output(String.t()) :: [process()]
  def parse_ps_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.take(500)
    |> Enum.flat_map(&parse_ps_line/1)
  end

  @spec parse_ps_line(String.t()) :: [process()]
  def parse_ps_line(line) do
    case Regex.run(~r/^\s*(\d+)\s+(\S+)\s+(.+?)\s+([\d.]+)\s+([\d.]+)\s*$/, line) do
      [_, pid, user, name, cpu, mem] ->
        with {cpu_f, _} <- Float.parse(cpu),
             {mem_f, _} <- Float.parse(mem) do
          [
            %{
              pid: String.to_integer(pid),
              user: String.slice(user, 0, 12),
              name: name |> String.trim() |> String.slice(0, 24),
              cpu: Float.round(cpu_f, 1),
              mem: Float.round(mem_f, 1)
            }
          ]
        else
          _ -> []
        end

      _ ->
        []
    end
  end

  defp read_ps_output do
    case System.cmd(
           "ps",
           ["ax", "-o", "pid=,user=,comm=,pcpu=,pmem=", "--no-headers", "--sort=-pcpu"],
           env: [{"LC_ALL", "C"}],
           stderr_to_stdout: true
         ) do
      {output, 0} -> parse_ps_output(output)
      _ -> []
    end
  rescue
    _ -> []
  end

  defp compare_field(:pid, left, right), do: compare(left.pid, right.pid)
  defp compare_field(:user, left, right), do: compare(left.user, right.user)
  defp compare_field(:name, left, right), do: compare(left.name, right.name)
  defp compare_field(:cpu, left, right), do: compare(left.cpu, right.cpu)
  defp compare_field(:mem, left, right), do: compare(left.mem, right.mem)

  defp compare(left, right) when left == right, do: :eq
  defp compare(left, right) when left < right, do: :lt
  defp compare(_left, _right), do: :gt

  defp flip(:asc), do: :desc
  defp flip(:desc), do: :asc
end
