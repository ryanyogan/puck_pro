defmodule PuckProWeb.ManualEntryComponents do
  @moduledoc """
  UI components for manual stat entry during practice sessions.

  Used as a fallback when video capture is unavailable.
  """
  use Phoenix.Component

  attr :fields, :list, required: true
  attr :values, :map, required: true

  def dynamic_entry_form(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :for={field <- @fields} class="bg-base-200 border border-base-300 rounded-lg p-4">
        <label class="block text-sm font-medium mb-3">{field["label"] || field[:label]}</label>

        <%= case field["type"] || field[:type] do %>
          <% "counter" -> %>
            <.counter_input
              field_name={field["name"] || field[:name]}
              value={Map.get(@values, field["name"] || field[:name], 0)}
            />
          <% "select" -> %>
            <.select_input
              field_name={field["name"] || field[:name]}
              options={field["options"] || field[:options] || []}
              value={Map.get(@values, field["name"] || field[:name], "")}
            />
          <% "number" -> %>
            <.number_input
              field_name={field["name"] || field[:name]}
              value={Map.get(@values, field["name"] || field[:name], 0)}
              min={field["min"] || field[:min] || 0}
              max={field["max"] || field[:max] || 1000}
            />
          <% _ -> %>
            <.text_input
              field_name={field["name"] || field[:name]}
              value={Map.get(@values, field["name"] || field[:name], "")}
            />
        <% end %>
      </div>
    </div>
    """
  end

  attr :field_name, :string, required: true
  attr :value, :integer, required: true

  def counter_input(assigns) do
    ~H"""
    <div class="flex items-center justify-center gap-4">
      <button
        type="button"
        phx-click="decrement"
        phx-value-field={@field_name}
        class="w-14 h-14 bg-base-300 hover:bg-base-content/20 text-2xl font-bold rounded-lg transition-colors touch-manipulation"
      >
        -
      </button>
      <span class="text-4xl font-mono font-bold w-20 text-center tabular-nums">
        {@value}
      </span>
      <button
        type="button"
        phx-click="increment"
        phx-value-field={@field_name}
        class="w-14 h-14 bg-base-300 hover:bg-base-content/20 text-2xl font-bold rounded-lg transition-colors touch-manipulation"
      >
        +
      </button>
    </div>
    """
  end

  attr :field_name, :string, required: true
  attr :options, :list, required: true
  attr :value, :string, required: true

  def select_input(assigns) do
    ~H"""
    <select
      name={@field_name}
      phx-change="update_field"
      class="w-full bg-base-300 border-0 p-3 text-base rounded-lg"
    >
      <option value="">Select...</option>
      <option :for={opt <- @options} value={opt} selected={opt == @value}>
        {humanize(opt)}
      </option>
    </select>
    """
  end

  attr :field_name, :string, required: true
  attr :value, :integer, required: true
  attr :min, :integer, default: 0
  attr :max, :integer, default: 1000

  def number_input(assigns) do
    ~H"""
    <input
      type="number"
      name={@field_name}
      value={@value}
      min={@min}
      max={@max}
      phx-change="update_field"
      class="w-full bg-base-300 border-0 p-3 text-base rounded-lg text-center font-mono"
    />
    """
  end

  attr :field_name, :string, required: true
  attr :value, :string, required: true

  def text_input(assigns) do
    ~H"""
    <input
      type="text"
      name={@field_name}
      value={@value}
      phx-change="update_field"
      class="w-full bg-base-300 border-0 p-3 text-base rounded-lg"
    />
    """
  end

  @doc """
  Default tracking fields for shot tracking.
  """
  def default_shot_tracking_fields do
    [
      %{name: "shots", label: "Total Shots", type: "counter"},
      %{name: "goals", label: "Goals Scored", type: "counter"},
      %{name: "on_goal", label: "Shots On Goal", type: "counter"}
    ]
  end

  @doc """
  Quick shot tracker with large touch targets for mobile.
  """
  attr :shots, :integer, required: true
  attr :goals, :integer, required: true
  attr :on_goal, :integer, required: true

  def quick_shot_tracker(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-3">
      <.stat_counter label="Shots" value={@shots} field="shots" color="primary" />
      <.stat_counter label="On Goal" value={@on_goal} field="on_goal" color="warning" />
      <.stat_counter label="Goals" value={@goals} field="goals" color="success" />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :field, :string, required: true
  attr :color, :string, default: "primary"

  defp stat_counter(assigns) do
    ~H"""
    <div class="bg-base-200 border border-base-300 rounded-lg p-3 text-center">
      <div class={"text-3xl font-bold stat-value text-#{@color} mb-2"}>
        {@value}
      </div>
      <div class="text-xs text-base-content/50 mb-3">{@label}</div>
      <div class="flex gap-2 justify-center">
        <button
          type="button"
          phx-click="decrement"
          phx-value-field={@field}
          class="w-10 h-10 bg-base-300 hover:bg-base-content/20 rounded text-lg font-bold touch-manipulation"
        >
          -
        </button>
        <button
          type="button"
          phx-click="increment"
          phx-value-field={@field}
          class="w-10 h-10 bg-base-300 hover:bg-base-content/20 rounded text-lg font-bold touch-manipulation"
        >
          +
        </button>
      </div>
    </div>
    """
  end

  # Helpers

  defp humanize(string) when is_binary(string) do
    string
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp humanize(other), do: "#{other}"
end
