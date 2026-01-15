defmodule PuckProWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PuckProWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout with hockey-themed navigation.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- Navigation --%>
    <nav class="bg-base-200 border-b border-base-300 sticky top-0 z-50">
      <div class="max-w-6xl mx-auto px-4">
        <div class="flex items-center justify-between h-14">
          <%!-- Logo --%>
          <.link navigate={~p"/"} class="flex items-center gap-2 font-bold text-lg">
            <div class="w-8 h-8 bg-primary rounded flex items-center justify-center">
              <span class="text-primary-content text-sm">PP</span>
            </div>
            <span class="hidden sm:inline">PuckPro</span>
          </.link>

          <%!-- Desktop Nav --%>
          <div class="hidden md:flex items-center gap-1">
            <.nav_link href={~p"/"} icon="hero-home">Dashboard</.nav_link>
            <.nav_link href={~p"/practice"} icon="hero-play">Practice</.nav_link>
            <.nav_link href={~p"/plans"} icon="hero-academic-cap">Plans</.nav_link>
            <.nav_link href={~p"/drills"} icon="hero-clipboard-document-list">Drills</.nav_link>
            <.nav_link href={~p"/progress"} icon="hero-chart-bar">Progress</.nav_link>
          </div>

          <%!-- Theme Toggle --%>
          <div class="flex items-center gap-2">
            <.theme_toggle />
          </div>
        </div>
      </div>

      <%!-- Mobile Nav --%>
      <div class="md:hidden border-t border-base-300 px-2 py-2">
        <div class="flex justify-around">
          <.mobile_nav_link href={~p"/"} icon="hero-home">Home</.mobile_nav_link>
          <.mobile_nav_link href={~p"/practice"} icon="hero-play">Practice</.mobile_nav_link>
          <.mobile_nav_link href={~p"/plans"} icon="hero-academic-cap">Plans</.mobile_nav_link>
          <.mobile_nav_link href={~p"/progress"} icon="hero-chart-bar">Stats</.mobile_nav_link>
        </div>
      </div>
    </nav>

    <%!-- Main Content --%>
    <main>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-1.5 px-3 py-2 text-sm font-medium text-base-content/70 hover:text-base-content hover:bg-base-300/50 transition-colors"
    >
      <.icon name={@icon} class="w-4 h-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp mobile_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex flex-col items-center gap-0.5 px-3 py-1 text-xs text-base-content/70 hover:text-base-content transition-colors"
    >
      <.icon name={@icon} class="w-5 h-5" />
      <span>{render_slot(@inner_block)}</span>
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-16 right-4 z-50 w-80 space-y-2">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Connection lost")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Server error")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Reconnecting...")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center bg-base-300 rounded p-0.5">
      <button
        class="p-1.5 rounded hover:bg-base-200 transition-colors [[data-theme=light]_&]:bg-base-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light mode"
      >
        <.icon name="hero-sun-micro" class="w-4 h-4" />
      </button>

      <button
        class="p-1.5 rounded hover:bg-base-200 transition-colors [[data-theme=dark]_&]:bg-base-100"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark mode"
      >
        <.icon name="hero-moon-micro" class="w-4 h-4" />
      </button>
    </div>
    """
  end
end
