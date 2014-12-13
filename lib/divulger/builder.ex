defmodule Divulger.Builder do
  defmacro action(name, handle) do
    quote do
      def unquote(name)(conn) do
        conn
        |> send_resp(200, "NYI")
      end
      def decide(unquote(name), conn) do
        decide(unquote(handle), unquote(name)(conn))
      end

      defoverridable [{unquote(name), 1}]
    end
  end

  defmacro default_bool(name, bool) do
    quote do
      def unquote(name)(_conn) do
        unquote(bool)
      end

      defoverridable [{unquote(name), 1}]
    end
  end

  # dispatch :handle_ok to handle_ok(conn)
  # handle(:ok, conn) would be nicer, but will require more careful
  # code generation instead of just using defoverridable
  # WIP..
  # Atom.to_string(:handle_not_found)
  # |> String.split("_")
  # |> Enum.slice(1, 10)
  # |> Enum.join("_")
  # |> String.to_atom
  defmacro handler(name, status, response) do
    quote do
      def unquote(name)(conn) do
        unquote(response)
      end
      def decide(unquote(name), conn) do

        if etag = gen_etag(conn) do
          conn = put_resp_header(conn, "ETag", etag)
        end

        if lm = gen_last_modified(conn) do
          conn = put_resp_header(conn, "Last-Modified", :httpd_util.rfc1123_date(lm) |> to_string)
        end

        if media_type = conn.assigns[:media_type] do
          if charset = conn.assigns[:charset] do
            conn = put_resp_header(conn, "Content-Type", "#{media_type};charset=#{charset}")
          else
            conn = put_resp_header(conn, "Content-Type", media_type)
          end
        end

        if language = conn.assigns[:language] do
          conn = put_resp_header(conn, "Content-Language", language)
        end

        if conn.assigns[:encoding] && conn.assigns[:encoding] != "identity" do
          conn = put_resp_header(conn, "Content-Encoding", conn.assigns[:encoding])
        end

        conn
        |> send_resp(unquote(status), unquote(name)(conn))
      end

      defoverridable [{unquote(name), 1}]
    end
  end

  defmacro decision(name, consequent, alternate) do
    quote do
      def decide(unquote(name), conn) do
        case unquote(name)(conn) do
          true  -> decide(unquote(consequent), conn)
          false -> decide(unquote(alternate), conn)
          {true, assigns}  -> decide(unquote(consequent), %{conn | assigns: Map.merge(conn.assigns, assigns)})
          {false, assigns} -> decide(unquote(alternate), %{conn | assigns: Map.merge(conn.assigns, assigns)})
        end
      end
    end
  end

  defmacro decision(name, predicate, consequent, alternate) when is_atom(predicate) do
    quote do
      def decide(unquote(name), conn) do
        case unquote(predicate)(conn) do
          true  -> decide(unquote(consequent), conn)
          false -> decide(unquote(alternate), conn)
          {true, assigns}  -> decide(unquote(consequent), %{conn | assigns: Map.merge(conn.assigns, assigns)})
          {false, assigns} -> decide(unquote(alternate), %{conn | assigns: Map.merge(conn.assigns, assigns)})
        end
      end
    end
  end

  defmacro decision(name, predicate, consequent, alternate) do
    quote do
      def decide(unquote(name), conn) do
        case unquote(predicate).(conn) do
          true  -> decide(unquote(consequent), conn)
          false -> decide(unquote(alternate), conn)
          {true, assigns}  -> decide(unquote(consequent), %{conn | assigns: Map.merge(conn.assigns, assigns)})
          {false, assigns} -> decide(unquote(alternate), %{conn | assigns: Map.merge(conn.assigns, assigns)})
        end
      end
    end
  end
end
