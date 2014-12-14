defmodule Decanter.ConnectionNegotiator do

  defp parse(:accept, part) do
    case Plug.Conn.Utils.media_type(part) do
      {:ok, type, subtype, _} -> {:ok, {type, subtype}}
      :error -> :error
    end
  end
  defp parse(_, part) do
    {:ok, part}
  end

  defp handle(:charset, v, accept) do
    case v do
      "*" -> {:accept, accept}
      ^accept -> {:accept, accept}
      _ -> :pass
    end
  end
  defp handle(:accept, v, {t, st}) do
    case v do
      {"*", "*"} -> {:accept, "#{t}/#{st}"}
      {^t, "*"} -> {:accept, "#{t}/#{st}"}
      {^t, ^st} -> {:accept, "#{t}/#{st}"}
      _ -> :pass
    end
  end
  defp handle(:encoding, v, accept) do
    case v do
      ^accept -> {:accept, accept}
      "*" -> {:accept, accept}
      _ -> :pass
    end
  end
  defp handle(:language, v, accept) do
    case accept do
      "*" -> {:accept, v}
      ^v -> {:accept, v}
      _ -> :pass
    end
  end

  # Simple extractor method for user choices
  defp simple_parse(mode, part) do
    {:ok, v} = parse(mode, part)
    v
  end

  def find_best(mode, header, choices) do
    parts = parse_header(header, mode)
    available = Enum.map(choices, &simple_parse(mode, &1))
    check_candidates(parts, available, available, mode)
  end

  defp check_candidates([v|_]=parts, [candidate|rest], available, mode) do
    case handle(mode, v, candidate) do
      {:accept, v} -> v
      :pass -> check_candidates(parts, rest, available, mode)
    end
  end
  defp check_candidates([_|rest], [], available, mode) do
    check_candidates(rest, available, available, mode)
  end
  defp check_candidates([], _, _, _) do
    nil
  end

  defp parse_header(header, mode) do
    parse_header_parts(String.split(header, ","), [], mode)
  end

  defp parse_header_parts([part|rest], acc, mode) do
    case String.split(String.strip(part), ";") do
      [part] ->
        parse_part(rest, acc, mode, -1.0, part)
      [part, args] ->
        parse_part(rest, acc, mode, -parse_q(Plug.Conn.Utils.params(args)), part)
    end
  end
  defp parse_header_parts([], acc, _) do
    for {_, v} <- Enum.sort(acc), do: v
  end

  defp parse_part(rest, acc, mode, q, part) do
    case parse(mode, part) do
      {:ok, v} -> parse_header_parts(rest, [{q, v}|acc], mode)
      :error -> parse_header_parts(rest, acc, mode)
    end
  end

  defp parse_q(args) do
    case Map.fetch(args, "q") do
      {:ok, float} ->
        case Float.parse(float) do
          {float, _} -> float
          :error -> 1.0
        end
      :error ->
        1.0
    end
  end
end
