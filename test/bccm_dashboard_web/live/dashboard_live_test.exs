defmodule BccmDashboardWeb.DashboardLiveTest do
  @moduledoc """
  End-to-end tests for the dashboard: stubbed HTTP responses in, rendered
  markup out, with the real clients, pollers, contexts, and template in
  between.

  This is the layer where card ordering has to be asserted. The context tests
  in `test/bccm_dashboard/semaphore_test.exs` cover `from_snapshot/1` in
  isolation, and they passed for weeks while the template re-sorted every
  section alphabetically and threw that ordering away.

  `Req.Test` runs in shared mode here, and both pollers are globally-named
  singletons, so these tests can't be async.
  """
  use BccmDashboardWeb.ConnCase, async: false

  import Cerberus
  import Cerberus.Expect
  import Cerberus.Locator

  # The error-path tests make the pollers log a failed fetch on purpose.
  @moduletag :capture_log

  alias BccmDashboard.Gatus
  alias BccmDashboard.Semaphore

  @semaphore_stub BccmDashboard.Semaphore.Client
  @gatus_stub BccmDashboard.Gatus.Client

  setup context do
    # The pollers fetch from their own processes (and Semaphore fans out to
    # Tasks), so ownership has to be shared rather than tied to the test pid.
    Req.Test.set_req_test_to_shared(context)
    Cerberus.Test.setup(context)
  end

  describe "build pipelines section" do
    test "cards are ordered most recently active first, not alphabetically", %{conn: conn} do
      # Alphabetical order (alpha, mike, zulu) is the exact reverse of run
      # recency here, so a template that re-sorts can't accidentally pass.
      stub_semaphore(%{
        "alpha" => [pipeline(done_at: ago(3600))],
        "mike" => [pipeline(done_at: ago(600))],
        "zulu" => [pipeline(done_at: ago(30))]
      })

      stub_gatus([])
      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(0) |> filter(has_text: "zulu"))
      )
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(1) |> filter(has_text: "mike"))
      )
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(2) |> filter(has_text: "alpha"))
      )
    end

    test "a queued build doesn't outrank one that has actually run since", %{conn: conn} do
      # Mirrors the context test in semaphore_test.exs, but asserted on the
      # rendered page. "queued" was created more recently than "ran" was, so
      # sorting on creation time (the bug) puts it first; "ran" has since
      # finished, so sorting on run time puts "ran" first.
      stub_semaphore(%{
        "queued" => [pipeline(state: "QUEUING", result: nil, created_at: ago(600))],
        "ran" => [pipeline(created_at: ago(900), running_at: ago(200), done_at: ago(60))]
      })

      stub_gatus([])
      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(0) |> filter(has_text: "ran"))
      )
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(1) |> filter(has_text: "queued"))
      )
    end

    test "a project with no runs in the window sorts last", %{conn: conn} do
      stub_semaphore(%{
        "aaa-idle" => [],
        "zzz-active" => [pipeline(done_at: ago(30))]
      })

      stub_gatus([])
      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(0) |> filter(has_text: "zzz-active"))
      )
      |> expect(
        visible(by_css("#section-build_pipelines h3") |> nth(1) |> filter(has_text: "aaa-idle"))
      )
    end

    test "a failing pipeline renders as failed and shows the red viewport border", %{conn: conn} do
      stub_semaphore(%{
        "broken" => [pipeline(result: "FAILED", done_at: ago(30))]
      })

      stub_gatus([])
      start_pollers()

      session = start_session(:phoenix, conn: conn) |> visit(~p"/")

      session
      |> expect(visible(by_css("#item-broken") |> filter(has_text: "FAILED")))
      |> expect(count(by_css("[aria-hidden='true'].border-semantic-error"), 1))
    end
  end

  describe "service health section" do
    test "endpoints are ordered alphabetically regardless of API order", %{conn: conn} do
      stub_semaphore(%{})

      stub_gatus([
        endpoint("zeta", success: true),
        endpoint("alpha", success: true),
        endpoint("mid", success: true)
      ])

      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(
        visible(by_css("#section-service_health h3") |> nth(0) |> filter(has_text: "alpha"))
      )
      |> expect(
        visible(by_css("#section-service_health h3") |> nth(1) |> filter(has_text: "mid"))
      )
      |> expect(
        visible(by_css("#section-service_health h3") |> nth(2) |> filter(has_text: "zeta"))
      )
    end

    test "a down endpoint renders as down", %{conn: conn} do
      stub_semaphore(%{})
      stub_gatus([endpoint("api", success: false, error: "connection refused")])
      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(visible(by_css("#item-api") |> filter(has_text: "DOWN")))
      |> expect(visible(by_css("#item-api") |> filter(has_text: "connection refused")))
    end
  end

  describe "page chrome" do
    test "renders both sections and the build sha", %{conn: conn} do
      stub_semaphore(%{})
      stub_gatus([])
      start_pollers()

      session =
        start_session(:phoenix, conn: conn)
        |> visit(~p"/")
        |> expect(visible(by_css("h2") |> filter(has_text: "Build pipelines")))
        |> expect(visible(by_css("h2") |> filter(has_text: "Service health")))

      # The footer is omitted entirely when the sha can't be resolved, so only
      # assert on it when this build actually has one.
      if sha = BccmDashboard.BuildInfo.short_sha() do
        expect(session, visible(by_css("[aria-label='Build commit']") |> filter(has_text: sha)))
      end
    end

    test "a section with no items renders its empty state", %{conn: conn} do
      stub_semaphore(%{})
      stub_gatus([])
      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(visible(by_css("#section-build_pipelines") |> filter(has_text: "No items")))
    end

    test "a failing source surfaces the fetch error instead of the whole page dying", %{
      conn: conn
    } do
      Req.Test.stub(@semaphore_stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
      stub_gatus([])
      start_pollers()

      start_session(:phoenix, conn: conn)
      |> visit(~p"/")
      |> expect(
        visible(
          by_css("#section-build_pipelines")
          |> filter(has_text: "Couldn't reach Semaphore")
        )
      )
      |> expect(visible(by_css("h2") |> filter(has_text: "Service health")))
    end
  end

  describe "live updates" do
    test "a poller broadcast re-orders the cards without a reload", %{conn: conn} do
      stub_semaphore(%{
        "first" => [pipeline(done_at: ago(30))],
        "second" => [pipeline(done_at: ago(600))]
      })

      stub_gatus([])
      start_pollers()

      session =
        start_session(:phoenix, conn: conn)
        |> visit(~p"/")
        |> expect(
          visible(by_css("#section-build_pipelines h3") |> nth(0) |> filter(has_text: "first"))
        )

      # "second" now has the most recent run. The poller broadcasts on refresh
      # and the LiveView re-renders from the new snapshot.
      stub_semaphore(%{
        "first" => [pipeline(done_at: ago(600))],
        "second" => [pipeline(done_at: ago(5))]
      })

      Semaphore.refresh()

      # `refresh/0` is a cast; a following call serializes behind it, so once
      # this returns the broadcast is already in the LiveView's mailbox and
      # will be handled before it answers the render.
      _ = Semaphore.Poller.snapshot()

      expect(
        session,
        visible(by_css("#section-build_pipelines h3") |> nth(0) |> filter(has_text: "second"))
      )
    end
  end

  # -- helpers ---------------------------------------------------------------

  # Starts both pollers under the test supervisor. Each does its first fetch in
  # `handle_continue`, before it will answer a `snapshot` call, so by the time
  # this returns the stubbed data is already in place — no polling or sleeping.
  defp start_pollers do
    start_supervised!({Semaphore.Poller, refresh_ms: :timer.minutes(5), window_days: 14})
    start_supervised!({Gatus.Poller, refresh_ms: :timer.minutes(5)})
    :ok
  end

  # `projects` maps project name => list of pipeline maps. Serves the two
  # Semaphore endpoints the poller calls: /projects, then /pipelines per
  # project (keyed by the project_id param, which we set to the name).
  defp stub_semaphore(projects) do
    Req.Test.stub(@semaphore_stub, fn conn ->
      case conn.request_path do
        "/api/v1alpha/projects" -> Req.Test.json(conn, project_metadata(projects))
        "/api/v1alpha/pipelines" -> Req.Test.json(conn, pipelines_for(conn, projects))
      end
    end)
  end

  defp project_metadata(projects) do
    for {name, _pipelines} <- projects, do: %{"metadata" => %{"id" => name, "name" => name}}
  end

  # The poller asks for one project at a time, and probes `main` then `master`;
  # the branch doesn't matter here, so every project's pipelines answer to both.
  defp pipelines_for(conn, projects) do
    params = Plug.Conn.fetch_query_params(conn).query_params
    Map.get(projects, params["project_id"], [])
  end

  defp stub_gatus(endpoints) do
    Req.Test.stub(@gatus_stub, fn conn ->
      Req.Test.json(conn, endpoints)
    end)
  end

  # A Semaphore pipeline as the API serves it: DONE/PASSED on main unless
  # overridden, with second-granularity timestamps wrapped in {"seconds": n}.
  defp pipeline(opts) do
    %{
      "state" => Keyword.get(opts, :state, "DONE"),
      "result" => Keyword.get(opts, :result, "PASSED"),
      "branch_name" => "main",
      "created_at" => seconds(Keyword.get(opts, :created_at, Keyword.get(opts, :done_at))),
      "running_at" => seconds(Keyword.get(opts, :running_at, Keyword.get(opts, :done_at))),
      "done_at" => seconds(Keyword.get(opts, :done_at))
    }
  end

  defp seconds(nil), do: nil
  defp seconds(unix), do: %{"seconds" => unix}

  defp endpoint(name, opts) do
    success = Keyword.fetch!(opts, :success)

    %{
      "key" => name,
      "name" => name,
      "group" => Keyword.get(opts, :group, "core"),
      "results" => [
        %{
          "success" => success,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "duration" => 12_000_000,
          "errors" => List.wrap(Keyword.get(opts, :error))
        }
      ]
    }
  end

  defp ago(seconds), do: System.system_time(:second) - seconds
end
