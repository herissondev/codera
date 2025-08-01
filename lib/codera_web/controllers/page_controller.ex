defmodule CoderaWeb.PageController do
  use CoderaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
