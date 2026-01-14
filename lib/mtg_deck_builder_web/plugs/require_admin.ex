defmodule MtgDeckBuilderWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that ensures the current user is an admin.
  Redirects to home page with error message if not.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias MtgDeckBuilder.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)
    user = user_id && Accounts.get_user(user_id)

    if Accounts.admin?(user) do
      assign(conn, :current_user, user)
    else
      conn
      |> put_flash(:error, "You must be an admin to access this page.")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
