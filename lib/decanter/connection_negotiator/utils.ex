defmodule Decanter.ConnectionNegotiator.Utils do
  @moduledoc """
  Utilities for working with connection data
  """

  @upper ?A..?Z
  @lower ?a..?z
  @alpha ?0..?9

  @doc ~S"""
  Parses language headers (with wildcards).

  Language primary and secondary are case insensitive
  while the sensitiveness of params depends on its key
  and therefore are not handled by this parser.

  ## Examples

      iex> language "en"
      {:ok, "en", %{}}

      iex> language "en-GB"
      {:ok, "en-gb", %{}}

      iex> language "*"
      {:ok, "*", %{}}

      iex> language "x-special-impl;q=0.8"
      {:ok, "x-special-impl", %{"q" => "0.8"}}

      iex> language "en; q=1.0"
      {:ok, "en", %{"q" => "1.0"}}

      iex> language "en a"
      :error

      iex> language ""
      :error

  """
  @spec language(binary) :: {:ok, type :: binary, subtype :: binary | nil, %{}} | :error
  def language(binary) do
    case strip_spaces(binary) do
      ""       -> :error
      "*" <> t -> lang_params(t, "*")
      t        -> lang_parse(t, "")
    end
  end

  defp lang_parse(<<h, t :: binary>>, buf) when h in @upper,
    do: lang_parse(t, <<buf :: binary, h + 32>>)
  defp lang_parse(<<h, t :: binary>>, buf) when h in @lower or h == ?-,
    do: lang_parse(t, << buf :: binary, h>>)
  defp lang_parse(t, acc),
    do: lang_params(t, acc)

  defp lang_params(t, str) do
    case t do
      ""       -> {:ok, str, %{}}
      ";" <> t -> {:ok, str, Plug.Conn.Utils.params(t)}
      _        -> :error
    end
  end

  @doc ~S"""
  Parses charsets.

  Charset names are case insensitive while the sensitiveness
  of params depends on its key and therefore are not handled
  by this parser.

  ## Examples

      iex> charset "utf-8"
      {:ok, "utf-8", %{}}

      iex> charset "ASCII"
      {:ok, "ascii", %{}}

      iex> charset "*;q=0.8"
      {:ok, "*", %{"q" => "0.8"}}

      iex> charset "b a"
      :error

      iex> charset ""
      :error

  """
  def charset(binary) do
    case strip_spaces(binary) do
      ""       -> :error
      "*" <> t -> charset_params(t, "*")
      t        -> charset_parse(t, "")
    end
  end

  defp charset_parse(<<h, t :: binary>>, acc) when h in @upper,
    do: charset_parse(t, <<acc :: binary, h + 32>>)
  defp charset_parse(<<h, t :: binary>>, acc) when h in @lower or h in @alpha or h == ?-,
    do: charset_parse(t, << acc :: binary, h>>)
  defp charset_parse(t, acc),
    do: charset_params(t, acc)

  defp charset_params(t, charset) do
    case strip_spaces(t) do
      ""       -> {:ok, charset, %{}}
      ";" <> t -> {:ok, charset, Plug.Conn.Utils.params(t)}
      _        -> :error
    end
  end

  @valid_encodings ["compress", "deflate", "exi", "gzip", "identity", "pack200-gzip", "*"]

  @doc ~S"""
  Parses encodings, matching those registered by IANA:
  http://www.iana.org/assignments/http-parameters/http-parameters.xhtml

  ## Examples

      iex> encoding "identity"
      {:ok, "identity", %{}}

      iex> encoding "gzip"
      {:ok, "gzip", %{}}

      iex> encoding "*;q=0.8"
      {:ok, "*", %{"q" => "0.8"}}

      iex> encoding "myownencoding"
      :error

  """
  def encoding(binary) do
    {encoding, t} = case :binary.split(strip_spaces(binary), ";") do
      [encoding] -> {encoding, ""}
      [encoding, t] -> {encoding, ";" <> t}
    end
    case encoding do
      encoding when encoding in @valid_encodings ->
        encoding_params(t, encoding)
      _ ->
        :error
    end
  end

  defp encoding_params(t, encoding) do
    case strip_spaces(t) do
      ""       -> {:ok, encoding, %{}}
      ";" <> t -> {:ok, encoding, Plug.Conn.Utils.params(t)}
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
