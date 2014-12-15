defmodule Decanter.ConnectionNegotiator do

  def find_best(mode, header, choices) do
    parts = set_client_defaults(mode, parse_header(header, mode))
    available = set_server_defaults(mode, choices)
                |> Enum.map(&simple_parse(mode, &1))

    scored = for candidate <- available do
               score(mode, parts, candidate)
             end
             |> Enum.reject(&is_nil/1)

    {stabilised,_} = Enum.reduce scored, {[], 0},
                      fn
                        ({0, _}, acc) -> acc
                        ({0.0, _}, acc) -> acc
                        ({q, v}, {r, dq}) -> {[{q+dq, v}|r], dq+0.01}
                      end

    case Enum.sort(stabilised) |> List.first do
      nil -> nil
      {_, result} -> do_format(mode, result)
    end
  end

  # Parse a part into an intermediate representation
  defp parse(:accept, part) do
    case Plug.Conn.Utils.media_type(part) do
      {:ok, type, subtype, _} -> {:ok, {type, subtype}}
      :error -> :error
    end
  end
  defp parse(_, part) do
    {:ok, part}
  end

  # Insert default client expectations
  defp set_client_defaults(:charset, parts) do
    if Enum.find(parts, fn {_, "iso-8859-1"} -> true
                           _ -> false end) do
      parts
    else
      [{-1.0, "iso-8859-1"}|parts]
    end
  end
  defp set_client_defaults(:encoding, parts) do
    if Enum.find(parts, fn {_, s} -> s in ["*", "identity"] end) do
      parts
    else
      [{-0.01, "identity"}|parts]
    end
  end
  defp set_client_defaults(_, parts) do
    parts
  end

  # Insert default server expectations
  defp set_server_defaults(:encoding, accepted) do
    if Enum.member?(accepted, "identity") do
      accepted
    else
      ["identity"|accepted]
    end
  end
  defp set_server_defaults(_, accepted) do
    accepted
  end

  # Simple extractor method for user choices
  defp simple_parse(mode, part) do
    {:ok, v} = parse(mode, part)
    v
  end

  # Format a result
  defp do_format(:accept, {t, st}) do
    "#{t}/#{st}"
  end
  defp do_format(_, result) do
    result
  end

  # Generate a score for a server accept given client parts
  defp score(mode, parts, accept) do
    case Enum.map(parts, &do_score(mode, accept, &1))
         |> Enum.sort
         |> List.first do
      {0, _, _} -> nil
      {_,q,accept} -> {q, accept}
    end
  end

  # Generate a {quality, qscore, result} tuple from a client part and server accept
  defp do_score(:accept, {t, st}, {q, {pt, pst}}) do
    case {pt, pst, t, st} do
      # Don't generate an accepted type with wildcards
      {"*", "*", "*", "*"} -> {0, nil, nil}
      {_, "*", _, "*"} -> {0, nil, nil}

      # usual client wildcards
      {"*", "*", _, _} -> {-1.0, q, {t, st}}
      {^t, "*", _, _} -> {-1.0, q, {t, st}}
      {^t, ^st, _, _} -> {-1.0, q, {t, st}}

      # server wildcards
      {t, st, "*", "*"} -> {-1.0, q, {t, st}}
      {^t, st, ^t, "*"} -> {-1.0, q, {t, st}}

      _ -> {0, nil, nil}
    end
  end
  defp do_score(:language, accept, {q, part}) do
    case accept do
      <<^part::binary-size(2), _rest::binary>> -> {-0.5, q, accept}
      ^part -> {-1.0, q, accept}
      _ -> {0, nil, nil}
    end
  end
  defp do_score(_, accept, {q, part}) do
    downcase_accept = String.downcase(accept)
    case String.downcase(part) do
      ^downcase_accept -> {-1.0, q, accept}
      "*" -> {-0.5, q, accept}
      _ -> {0, nil, nil}
    end
  end

  # Parse a header into q/header tuples
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
    Enum.sort(acc)
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
