defmodule MtgDeckBuilderWeb.Plugs.FetchCurrentUser do
  @moduledoc """
  Plug that fetches the current user from session and assigns it to conn.
  Does not require authentication - just loads user if present.
  """
  import Plug.Conn

  alias MtgDeckBuilder.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user(user_id)
    assign(conn, :current_user, user)
  end
end
