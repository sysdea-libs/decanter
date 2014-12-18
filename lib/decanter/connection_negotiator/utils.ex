defmodule Decanter.ConnectionNegotiator.Utils do
  @moduledoc """
  Utilities for working with connection data
  """

  @upper ?A..?Z
  @lower ?a..?z
  @alpha ?0..?9

  @doc ~S"""
  Parses header values (with wildcards).

  Useful for charsets/languages/encodings.

  Header values are case insensitive while the sensitiveness
  of params depends on its key and therefore are not handled
  by this parser.

  ## Languages

      iex> header_value "en"
      {:ok, "en", %{}}

      iex> header_value "en-GB"
      {:ok, "en-gb", %{}}

      iex> header_value "*;q=0.8"
      {:ok, "*", %{"q" => "0.8"}}

      iex> header_value "x-special-impl;q=0.8"
      {:ok, "x-special-impl", %{"q" => "0.8"}}

      iex> header_value "en; q=1.0"
      {:ok, "en", %{"q" => "1.0"}}

      iex> header_value "en a"
      :error

      iex> header_value ""
      :error

  ## Charsets

      iex> header_value "utf-8"
      {:ok, "utf-8", %{}}

      iex> header_value "ASCII"
      {:ok, "ascii", %{}}

  ## Encodings

      iex> header_value "identity"
      {:ok, "identity", %{}}

      iex> header_value "GZIP"
      {:ok, "gzip", %{}}

  """
  @spec header_value(binary) :: {:ok, value :: binary | nil, %{}} | :error
  def header_value(binary) do
    case strip_spaces(binary) do
      ""       -> :error
      "*" <> t -> lang_params(t, "*")
      t        -> header_parse(t, "")
    end
  end

  defp header_parse(<<h, t :: binary>>, buf) when h in @upper,
    do: header_parse(t, <<buf :: binary, h + 32>>)
  defp header_parse(<<h, t :: binary>>, buf) when h in @lower or h in @alpha or h == ?-,
    do: header_parse(t, << buf :: binary, h>>)
  defp header_parse(t, acc),
    do: lang_params(t, acc)

  defp lang_params(t, str) do
    case t do
      ""       -> {:ok, str, %{}}
      ";" <> t -> {:ok, str, Plug.Conn.Utils.params(t)}
      _        -> :error
    end
  end

  # Util functions

  defp strip_spaces("\r\n" <> t),
    do: strip_spaces(t)
  defp strip_spaces(<<h, t :: binary>>) when h in [?\s, ?\t],
    do: strip_spaces(t)
  defp strip_spaces(t),
    do: t
end
