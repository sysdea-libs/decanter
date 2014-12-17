defmodule Decanter.ConnectionNegotiator do

  @type mode          :: :accept | :charset | :encoding | :language
  @type parsed_part   :: String.t | {String.t, String.t}
  @type q_parsed_part :: {float, parsed_part}

  @spec find_best(mode, String.t, [String.t]) :: String.t | nil
  def find_best(mode, header, choices) do
    parts = set_client_defaults(mode, parse_header(mode, header))
            |> Enum.filter(fn {0.0,_} -> false
                              _ -> true end)
    available = set_server_defaults(mode, choices)
                |> Enum.map(&simple_parse(mode, &1))

    do_find_best(mode, parts, available, [])
  end

  @spec do_find_best(mode, [q_parsed_part], [parsed_part], [q_parsed_part]) :: String.t | nil
  defp do_find_best(mode, parts, [nil|rest], candidates) do
    do_find_best(mode, parts, rest, candidates)
  end
  defp do_find_best(mode, parts, [head|rest], candidates) do
    case score(mode, parts, head) do
      nil       -> do_find_best(mode, parts, rest, candidates)
      {-1.0, v} -> do_format(mode, v)
      candidate -> do_find_best(mode, parts, rest, [candidate|candidates])
    end
  end
  defp do_find_best(mode, _, _, candidates) do
    case :lists.keysort(1, Enum.reverse(candidates)) |> List.first do
      nil -> nil
      {_, result} -> do_format(mode, result)
    end
  end

  # Insert default client expectations
  @spec set_client_defaults(mode, [q_parsed_part]) :: [q_parsed_part]
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
  @spec set_server_defaults(mode, [String.t]) :: [String.t]
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
  @spec simple_parse(mode, String.t) :: parsed_part
  defp simple_parse(mode, part) do
    {_q, v} = parse(mode, part)
    v
  end

  # Format a result
  @spec do_format(mode, parsed_part) :: String.t
  defp do_format(:accept, {t, st}) do
    "#{t}/#{st}"
  end
  defp do_format(_, result) do
    result
  end

  # Generate a score for a server accept given client parts
  @spec score(mode, [q_parsed_part], parsed_part) :: q_parsed_part | nil
  defp score(_, [], _), do: nil
  defp score(_, _, []), do: nil
  defp score(mode, parts, accept) do
    score(mode, parts, accept, nil)
  end

  defp score(mode, [{q, part}|parts], accept, best) do
    {quality, v} = do_score(mode, accept, part)
    case quality do
      0 -> score(mode, parts, accept, best)
      -1 ->
        case best do
          {bq, _} when q < bq -> score(mode, parts, accept, best)
          _ -> score(mode, parts, accept, {q, v})
        end
      -2 -> {q, v}
    end
  end
  defp score(_, _, _, best), do: best

  # Generate a {quality, result} tuple from a client part and server accept
  @spec do_score(mode, parsed_part, parsed_part) :: {integer, parsed_part | nil}
  defp do_score(:accept, {t, st}, {pt, pst}) do
    case {pt, pst, t, st} do
      # Don't generate an accepted type with wildcards
      {"*",  _, "*",  _ } -> {0, nil}
      { _,  "*",  _, "*"} -> {0, nil}

      # usual client wildcards
      {"*", "*", t, st} -> {-2, {t, st}}
      {^t,  "*", t, st} -> {-2, {t, st}}
      {^t,  ^st, t, st} -> {-2, {t, st}}

      # server wildcards
      {t, st, "*", "*"} -> {-2, {t, st}}
      {t, st,  t,  "*"} -> {-2, {t, st}}

      _ -> {0, nil}
    end
  end
  defp do_score(:language, accept, part) do
    case accept do
      <<^part::binary-size(2), _rest::binary>> -> {-1, accept}
      ^part -> {-2, accept}
      _ -> {0, nil}
    end
  end
  defp do_score(_, accept, part) do
    downcase_accept = String.downcase(accept)
    case String.downcase(part) do
      ^downcase_accept -> {-2, accept}
      "*" -> {-1, accept}
      _ -> {0, nil}
    end
  end

  # Parse a header into q/header tuples
  @spec parse_header(mode, String.t) :: [q_parsed_part]
  defp parse_header(mode, header) do
    parse_header_parts(mode, Plug.Conn.Utils.list(header), [])
  end

  @spec parse_header_parts(mode, [String.t], [q_parsed_part]) :: [q_parsed_part]
  defp parse_header_parts(mode, [part|rest], acc) do
    case parse(mode, part) do
      :error -> parse_header_parts(mode, rest, acc)
      v -> parse_header_parts(mode, rest, [v|acc])
    end
  end
  defp parse_header_parts(_, [], acc) do
    :lists.keysort(1, Enum.reverse(acc))
  end

  # Parse a part into an intermediate representation
  @spec parse(mode, String.t) :: q_parsed_part | :error
  defp parse(:accept, part) do
    case Plug.Conn.Utils.media_type(part) do
      {:ok, type, subtype, args} -> {-parse_q(args), {type, subtype}}
      :error -> :error
    end
  end
  defp parse(_, part) do
    case String.split(String.strip(part), ";") do
      [part] -> {-1.0, part}
      [part, args] -> {-parse_q(Plug.Conn.Utils.params(args)), part}
    end
  end

  @spec parse_q(%{}) :: float
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
