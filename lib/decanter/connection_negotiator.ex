defmodule Decanter.ConnectionNegotiator do

  @type mode          :: :accept | :charset | :encoding | :language
  @type parsed_part   :: String.t | {String.t, String.t}
  @type q_parsed_part :: {float, parsed_part}

  @spec find_best(mode, String.t, [String.t]) :: nil | String.t
  def find_best(mode, header, choices) do
    parts = set_client_defaults(mode, parse_header(header, mode))
    available = set_server_defaults(mode, choices)
                |> Enum.map(&simple_parse(mode, &1))

    scored = Enum.map(available, &score(mode, parts, &1))
             |> Enum.reject(&is_nil/1)

    case :lists.keysort(1, scored) |> List.first do
      nil -> nil
      {_, result} -> do_format(mode, result)
    end
  end

  # Parse a part into an intermediate representation
  @spec parse(mode, String.t) :: {:ok, parsed_part} | :error
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
    {:ok, v} = parse(mode, part)
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
  @spec score(mode, [parsed_part], parsed_part) :: q_parsed_part | nil
  defp score(_, [], _), do: nil
  defp score(_, _, []), do: nil
  defp score(mode, parts, accept) do
    candidate = for {q, v} <- parts do
                  case q do
                    0.0 -> {0, nil, nil}
                    _ ->
                      {quality, v} = do_score(mode, accept, v)
                      {quality, q, v}
                  end
                end
                |> Enum.sort
                |> List.first

    case candidate do
      {0, _, _} -> nil
      {_, q, accept} -> {q, accept}
    end
  end

  # Generate a {quality, qscore, result} tuple from a client part and server accept
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
  @spec parse_header(String.t, mode) :: [q_parsed_part]
  defp parse_header(header, mode) do
    parse_header_parts(String.split(header, ","), [], mode)
  end

  @spec parse_header_parts([String.t], [q_parsed_part], mode) :: [q_parsed_part]
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

  @spec parse_part([String.t], [q_parsed_part], mode, float, parsed_part) :: [q_parsed_part]
  defp parse_part(rest, acc, mode, q, part) do
    case parse(mode, part) do
      {:ok, v} -> parse_header_parts(rest, [{q, v}|acc], mode)
      :error -> parse_header_parts(rest, acc, mode)
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
