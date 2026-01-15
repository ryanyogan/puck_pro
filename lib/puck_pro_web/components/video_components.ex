defmodule PuckProWeb.VideoComponents do
  @moduledoc """
  UI components for video capture and analysis display.
  """
  use Phoenix.Component

  attr :is_recording, :boolean, default: false
  attr :camera_ready, :boolean, default: false
  attr :timer_seconds, :integer, default: 0
  attr :camera_error, :string, default: nil
  attr :uploads, :any, default: nil
  attr :dev_mode, :boolean, default: false

  def camera_capture(assigns) do
    ~H"""
    <div
      id="video-capture"
      phx-hook="VideoCapture"
      data-dev-mode={to_string(@dev_mode)}
      class="relative bg-black rounded-lg aspect-video"
    >
      <%!-- Hidden file input for programmatic uploads --%>
      <.live_file_input :if={@uploads && @uploads[:video_stream]} upload={@uploads[:video_stream]} class="hidden" />

      <%!-- Video and Canvas Container - ignored by LiveView to prevent stream disruption --%>
      <div id="video-container" phx-update="ignore" class="absolute inset-0">
        <%!-- Live Preview --%>
        <video
          id="video-preview"
          class="w-full h-full object-cover rounded-lg"
          autoplay
          muted
          playsinline
        />

        <%!-- Dev Mode Overlay Canvas - always rendered, visibility controlled by JS --%>
        <canvas
          id="detection-overlay"
          class="absolute inset-0 w-full h-full pointer-events-none rounded-lg z-10"
          style="display: none;"
        />
      </div>

      <%!-- Recording Indicator --%>
      <div :if={@is_recording} class="absolute top-4 left-4 flex items-center gap-2 z-20">
        <div class="w-3 h-3 bg-error rounded-full animate-pulse"></div>
        <span class="text-white text-sm font-mono bg-black/50 px-2 py-1 rounded">
          REC {format_time(@timer_seconds)}
        </span>
      </div>

      <%!-- Dev Mode Indicator --%>
      <div :if={@dev_mode && @is_recording} class="absolute top-4 right-4 z-20">
        <span class="text-xs font-mono bg-warning text-warning-content px-2 py-1 rounded">
          DEV
        </span>
      </div>

      <%!-- Camera Permission Prompt --%>
      <div
        :if={!@camera_ready && !@is_recording && !@camera_error}
        class="absolute inset-0 flex items-center justify-center bg-base-300 rounded-lg"
      >
        <div class="text-center p-6">
          <.icon name="hero-video-camera" class="w-16 h-16 text-base-content/20 mx-auto mb-4" />
          <p class="text-base-content/60">Camera will start when you begin your session</p>
        </div>
      </div>

      <%!-- Camera Error --%>
      <div
        :if={@camera_error}
        class="absolute inset-0 flex items-center justify-center bg-error/10 rounded-lg"
      >
        <div class="text-center p-6">
          <.icon name="hero-exclamation-triangle" class="w-12 h-12 text-error mx-auto mb-4" />
          <p class="text-error font-medium mb-2">Camera Error</p>
          <p class="text-sm text-base-content/60">{@camera_error}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :content, :string, default: ""
  attr :is_streaming, :boolean, default: false
  attr :status, :string, default: nil

  def analysis_stream(assigns) do
    ~H"""
    <div class="bg-base-200 border border-base-300 rounded-lg">
      <div class="px-4 py-2 bg-base-300/50 border-b border-base-300 flex items-center gap-2">
        <div :if={@is_streaming} class="w-2 h-2 bg-primary rounded-full animate-pulse"></div>
        <.icon
          :if={@status == "completed"}
          name="hero-check-circle"
          class="w-4 h-4 text-success"
        />
        <.icon :if={@status == "failed"} name="hero-x-circle" class="w-4 h-4 text-error" />
        <span class="text-xs font-bold uppercase tracking-wider text-base-content/50">
          AI Analysis
        </span>
      </div>
      <div class="p-4">
        <div class="prose prose-sm text-base-content whitespace-pre-wrap max-w-none">
          {@content}<span :if={@is_streaming} class="animate-pulse">|</span>
        </div>
      </div>
    </div>
    """
  end

  attr :metrics, :map, required: true

  def form_metrics(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-4">
      <.metric_card label="Stance" value={@metrics["stance"] || @metrics[:stance] || 0} />
      <.metric_card label="Grip" value={@metrics["grip"] || @metrics[:grip] || 0} />
      <.metric_card
        label="Follow-through"
        value={@metrics["follow_through"] || @metrics[:follow_through] || 0}
      />
    </div>
    """
  end

  attr :scores, :map, required: true

  def technique_scores(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-4">
      <.metric_card label="Release" value={@scores["release"] || @scores[:release] || 0} />
      <.metric_card label="Accuracy" value={@scores["accuracy"] || @scores[:accuracy] || 0} />
      <.metric_card label="Power" value={@scores["power"] || @scores[:power] || 0} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp metric_card(assigns) do
    ~H"""
    <div class="bg-base-300/50 p-3 text-center rounded">
      <div class="text-2xl font-bold stat-value" style={"color: #{score_color(@value)}"}>
        {@value}
      </div>
      <div class="text-xs text-base-content/50">{@label}</div>
    </div>
    """
  end

  attr :shots, :list, required: true

  def detected_shots(assigns) do
    ~H"""
    <div :if={length(@shots) > 0} class="space-y-2">
      <div class="text-xs font-bold uppercase tracking-wider text-base-content/50 mb-2">
        Detected Shots
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
        <div
          :for={shot <- @shots}
          class="bg-base-300/50 px-3 py-2 rounded text-sm flex items-center gap-2"
        >
          <.icon name={shot_result_icon(shot["result"])} class={shot_result_color(shot["result"])} />
          <div>
            <div class="font-medium capitalize">{shot["type"] || "Shot"}</div>
            <div class="text-xs text-base-content/50">Frame {shot["frame"]}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :strengths, :list, required: true

  def strengths_list(assigns) do
    ~H"""
    <div :if={length(@strengths) > 0} class="space-y-3">
      <div class="text-xs font-bold uppercase tracking-wider text-success mb-2">
        Strengths
      </div>
      <div :for={item <- @strengths} class="flex gap-3">
        <.icon name="hero-check-circle" class="w-5 h-5 text-success flex-shrink-0 mt-0.5" />
        <div>
          <div class="font-medium">{item["title"]}</div>
          <div :if={item["detail"]} class="text-sm text-base-content/60">{item["detail"]}</div>
        </div>
      </div>
    </div>
    """
  end

  attr :improvements, :list, required: true

  def improvements_list(assigns) do
    ~H"""
    <div :if={length(@improvements) > 0} class="space-y-3">
      <div class="text-xs font-bold uppercase tracking-wider text-warning mb-2">
        Areas to Improve
      </div>
      <div :for={item <- @improvements} class="flex gap-3">
        <.icon name="hero-arrow-trending-up" class="w-5 h-5 text-warning flex-shrink-0 mt-0.5" />
        <div>
          <div class="font-medium">{item["title"]}</div>
          <div :if={item["detail"]} class="text-sm text-base-content/60">{item["detail"]}</div>
          <div
            :if={item["tip"]}
            class="text-sm text-primary mt-1 bg-primary/10 px-2 py-1 rounded inline-block"
          >
            Tip: {item["tip"]}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :score, :integer, required: true

  def overall_score(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-6xl font-bold stat-value" style={"color: #{score_color(@score)}"}>
        {@score}
      </div>
      <div class="text-sm text-base-content/50 mt-1">Overall Score</div>
      <div class="text-xs text-base-content/40 mt-1">{score_label(@score)}</div>
    </div>
    """
  end

  # Helper functions

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    mins = String.pad_leading("#{minutes}", 2, "0")
    secs_str = String.pad_leading("#{secs}", 2, "0")
    "#{mins}:#{secs_str}"
  end

  defp score_color(score) when score >= 80, do: "oklch(70% 0.18 150)"
  defp score_color(score) when score >= 60, do: "oklch(78% 0.16 85)"
  defp score_color(score) when score >= 40, do: "oklch(70% 0.15 60)"
  defp score_color(_), do: "oklch(65% 0.20 25)"

  defp score_label(score) when score >= 90, do: "Outstanding!"
  defp score_label(score) when score >= 80, do: "Excellent!"
  defp score_label(score) when score >= 70, do: "Great job!"
  defp score_label(score) when score >= 60, do: "Good work!"
  defp score_label(score) when score >= 50, do: "Keep practicing!"
  defp score_label(_), do: "Room to grow!"

  defp shot_result_icon("goal"), do: "hero-check-circle"
  defp shot_result_icon("on_goal"), do: "hero-arrow-right-circle"
  defp shot_result_icon("miss"), do: "hero-x-circle"
  defp shot_result_icon(_), do: "hero-minus-circle"

  defp shot_result_color("goal"), do: "w-4 h-4 text-success"
  defp shot_result_color("on_goal"), do: "w-4 h-4 text-warning"
  defp shot_result_color("miss"), do: "w-4 h-4 text-error"
  defp shot_result_color(_), do: "w-4 h-4 text-base-content/50"

  # Icon component (delegate to core components)
  defp icon(assigns) do
    PuckProWeb.CoreComponents.icon(assigns)
  end
end
