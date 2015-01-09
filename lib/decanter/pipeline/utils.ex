defmodule Decanter.Pipeline.Utils do
  import Plug.Conn

  # Header postprocessing

  def postprocess(conn) do
    postprocess(conn.assigns, conn, [])
  end

  defp postprocess(%{media_type: media_type, charset: charset}=assigns, conn, vary) do
    postprocess(Map.delete(assigns, :media_type) |> Map.delete(:charset),
                   put_resp_header(conn, "Content-Type", "#{media_type};charset=#{charset}"),
                   ["Accept-Charset","Accept"|vary])
  end
  defp postprocess(%{media_type: media_type}=assigns, conn, vary) do
    postprocess(Map.delete(assigns, :media_type),
                   put_resp_header(conn, "Content-Type", media_type),
                   ["Accept"|vary])
  end
  defp postprocess(%{language: language}=assigns, conn, vary) do
    postprocess(Map.delete(assigns, :language),
                   put_resp_header(conn, "Content-Language", language),
                   ["Accept-Language"|vary])
  end
  defp postprocess(%{encoding: encoding}=assigns, conn, vary) do
    case encoding do
      "identity" -> postprocess(Map.delete(assigns, :encoding),
                                   conn,
                                   ["Accept-Encoding"|vary])
      encoding -> postprocess(Map.delete(assigns, :encoding),
                                 put_resp_header(conn, "Content-Encoding", encoding),
                                 ["Accept-Encoding"|vary])
    end
  end
  defp postprocess(%{location: location}=assigns, conn, vary) do
    postprocess(Map.delete(assigns, :location),
                put_resp_header(conn, "Location", location),
                vary)
  end
  defp postprocess(%{etag: etag}=assigns, conn, vary) when not is_nil(etag) do
    postprocess(Map.delete(assigns, :etag),
                put_resp_header(conn, "ETag", etag),
                vary)
  end
  defp postprocess(%{last_modified: last_modified}=assigns, conn, vary) when not is_nil(last_modified) do
    postprocess(Map.delete(assigns, :last_modified),
                put_resp_header(conn, "Last-Modified",
                                :httpd_util.rfc1123_date(last_modified) |> to_string),
                vary)
  end

  defp postprocess(_assigns, conn, vary) do
    case vary do
      [] -> conn
      vary -> put_resp_header(conn, "Vary", Enum.join(vary, ","))
    end
  end

  defp format_etag(etag) do
    case etag do
      nil -> nil
      etag -> "\"#{to_string(etag)}\""
    end
  end

  # Cache Checking

  def cache_check(conn, headers, last_modified, etag) do
    etag = format_etag(etag)

    conn = conn
           |> Plug.Conn.assign(:etag, etag)
           |> Plug.Conn.assign(:last_modified, last_modified)

    status = case cache_check_ifmatch(headers, etag) do
      :ok ->
        case cache_check_ifnonematch(conn.method, headers, etag) do
          :ok ->
            case cache_check_ifunmodified(headers, last_modified) do
              :ok ->
                cache_check_ifmodified(headers, last_modified)
              status -> status
            end
          status -> status
        end
      status -> status
    end

    {status, conn}
  end

  defp cache_check_ifmatch(headers, etag) do
    case headers["if-match"] do
      nil -> :ok
      "*" -> :ok
      ^etag -> :ok
      _ -> :precondition
    end
  end

  defp cache_check_ifnonematch(method, headers, etag) do
    case headers["if-none-match"] do
      nil -> :ok
      i_n_m when i_n_m == "*" or i_n_m == etag ->
        if method in ["GET", "HEAD"] do
          :not_modified
        else
          :precondition
        end
      _ ->
        :ok
    end
  end

  defp cache_check_ifunmodified(headers, last_modified) do
    case headers["if-unmodified-since"] do
      nil -> :ok
      ds ->
        case :httpd_util.convert_request_date(ds |> to_char_list) do
          :bad_date -> :ok
          ^last_modified -> :ok
          _ -> :precondition
        end
    end
  end

  defp cache_check_ifmodified(headers, last_modified) do
    case headers["if-modified-since"] do
      nil -> :ok
      ds ->
        case :httpd_util.convert_request_date(ds |> to_char_list) do
          :bad_date -> :ok
          ^last_modified -> :not_modified
          _ -> :ok
        end
    end
  end

  def negotiate(:media_type, conn, available) do
    case Decanter.ConnectionNegotiator.negotiate(
          :media_type, conn.assigns.headers["accept"] || "*/*", available) do
      nil -> {:not_acceptable, conn}
      media_type -> {:ok, assign(conn, :media_type, media_type)}
    end
  end

  def negotiate(:charset, conn, available) do
    case conn.assigns.headers["accept-charset"] do
      nil -> {:ok, conn}
      header ->
        case Decanter.ConnectionNegotiator.negotiate(:charset, header, available) do
          nil -> {:not_acceptable, conn}
          charset -> {:ok, assign(conn, :charset, charset)}
        end
    end
  end

  def negotiate(:language, conn, available) do
    case conn.assigns.headers["accept-language"] do
      nil -> {:ok, conn}
      header ->
        case Decanter.ConnectionNegotiator.negotiate(:language, header, available) do
          nil -> {:not_acceptable, conn}
          language -> {:ok, assign(conn, :language, language)}
        end
    end
  end
end
