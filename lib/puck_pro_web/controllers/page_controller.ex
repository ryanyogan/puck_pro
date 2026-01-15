defmodule PuckProWeb.PageController do
  use PuckProWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
