defmodule Decanter.ConnectionNegotiator.Utils do
  @moduledoc """
  Utilities for working with connection data
  """

  @upper ?A..?Z
  @lower ?a..?z

  @doc ~S"""
  Parses language headers (with wildcards).

  Language primary and secondary are case insensitive
  while the sensitiveness of params depends on its key
  and therefore are not handled by this parser.

  ## Examples

      iex> language "en"
      {:ok, "en", nil, %{}}

      iex> language "en-GB"
      {:ok, "en", "gb", %{}}

      iex> language "*"
      {:ok, "*", nil, %{}}

      iex> language "x-special-impl"
      {:ok, "x-special-impl", nil, %{}}

      iex> language "x-special-impl;q=0.8"
      {:ok, "x-special-impl", nil, %{"q" => "0.8"}}

      iex> language "en; q=1.0"
      {:ok, "en", nil, %{"q" => "1.0"}}

      iex> language "en-cockney; q=0.6"
      {:ok, "en", "cockney", %{"q" => "0.6"}}

      iex> language "en a"
      :error

  """
  @spec language(binary) :: {:ok, type :: binary, subtype :: binary | nil, %{}} | :error
  def language(binary) do
    case strip_spaces(binary) do
      <<?*>> -> lang_params("*", nil, "")
      <<?*, ?;, t :: binary>> -> lang_params("*", nil, t)
      <<a, b>> when a in @upper or a in @lower and
                    b in @upper or b in @lower ->
        lang_params(downcase_primary(a, b), nil, "")
      <<a, b, ?;, t :: binary>> when a in @upper or a in @lower and
                                     b in @upper or b in @lower ->
        lang_params(downcase_primary(a, b), nil, t)
      <<a, b, ?-, t :: binary>> when a in @upper or a in @lower and
                                     b in @upper or b in @lower ->
        case lang_string(t, "") do
          :error -> :error
          {secondary, t} -> lang_params(downcase_primary(a, b), secondary, t)
        end
      t ->
        case lang_string(t, "") do
          :error -> :error
          {primary, t} -> lang_params(primary, nil, t)
        end
    end
  end

  defp downcase_primary(a, b) do
    <<(if a in @upper, do: a + 32, else: a),
      (if b in @upper, do: b + 32, else: b)>>
  end

  defp lang_string(<<?;, t :: binary>>, acc) when acc != "",
    do: {acc, t}
  defp lang_string(<<h, t :: binary>>, acc) when h in @upper,
    do: lang_string(t, <<acc :: binary, h + 32>>)
  defp lang_string(<<h, t :: binary>>, acc) when h in @lower or h == ?-,
    do: lang_string(t, << acc :: binary, h>>)
  defp lang_string(<<>>, acc) when acc != "",
    do: {acc, ""}
  defp lang_string(_, _),
    do: :error

  defp lang_params(primary, secondary, t) do
    case t do
      "" -> {:ok, primary, secondary, %{}}
      t  -> {:ok, primary, secondary, Plug.Conn.Utils.params(t)}
    end
  end

  defp strip_spaces("\r\n" <> t),
    do: strip_spaces(t)
  defp strip_spaces(<<h, t :: binary>>) when h in [?\s, ?\t],
    do: strip_spaces(t)
  defp strip_spaces(t),
    do: t
end
