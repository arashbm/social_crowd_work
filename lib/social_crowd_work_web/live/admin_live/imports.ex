defmodule SocialCrowdWorkWeb.AdminLive.Imports do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{AdminAudit, AdminPanel}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Imports")
     |> assign(:form, to_form(%{}, as: :manifest))
     |> assign(:import_result, nil)
     |> assign(:import_errors, [])
     |> allow_upload(:manifest,
       accept: ~w(.json application/json),
       max_entries: 1,
       max_file_size: 20_000_000
     )
     |> stream(:imports, AdminPanel.list_import_summaries(scope),
       dom_id: fn %{batch: batch} -> "import-#{batch.id}" end
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    results =
      consume_uploaded_entries(socket, :manifest, fn %{path: path}, entry ->
        contents = File.read!(path)

        {:ok,
         AdminPanel.import_manifest(socket.assigns.current_scope, contents,
           filename: entry.client_name
         )}
      end)

    case results do
      [{:ok, result}] ->
        {:ok, _event} =
          AdminAudit.record(socket.assigns.current_scope, "manifest_imported",
            target_type: "import_batch",
            target_id: result.import_batch && result.import_batch.id,
            metadata: %{
              "status" => Atom.to_string(result.status),
              "filename" => result.import_batch && result.import_batch.original_filename
            }
          )

        {:noreply,
         socket
         |> assign(:import_result, result)
         |> assign(:import_errors, [])
         |> stream(:imports, AdminPanel.list_import_summaries(socket.assigns.current_scope),
           reset: true
         )}

      [{:error, errors}] ->
        {:noreply, socket |> assign(:import_result, nil) |> assign(:import_errors, errors)}

      [] ->
        {:noreply, put_flash(socket, :error, "Choose a JSON manifest before importing.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Imports"
        description="Upload immutable experiment manifests. Validation and insertion are transactional."
      />

      <section class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900">
        <.form for={@form} id="manifest-upload-form" phx-submit="import" phx-change="validate">
          <div class="rounded-2xl border-2 border-dashed border-slate-300 bg-slate-50 p-8 text-center dark:border-slate-700 dark:bg-slate-950/50">
            <.icon
              name="hero-document-arrow-up"
              class="mx-auto size-9 text-indigo-600 dark:text-indigo-400"
            />
            <p class="mt-3 font-semibold text-slate-900 dark:text-white">
              Select a versioned JSON manifest
            </p>
            <p class="mt-1 text-sm text-slate-500 dark:text-slate-400">Maximum file size: 20 MB</p>
            <.live_file_input
              upload={@uploads.manifest}
              class="mx-auto mt-5 block max-w-md text-sm text-slate-600 file:mr-4 file:rounded-lg file:border-0 file:bg-indigo-100 file:px-4 file:py-2 file:font-semibold file:text-indigo-800 hover:file:bg-indigo-200 dark:text-slate-300 dark:file:bg-indigo-500/15 dark:file:text-indigo-300"
            />
          </div>
          <p :for={error <- upload_errors(@uploads.manifest)} class="mt-2 text-sm text-rose-600">
            {upload_error_to_string(error)}
          </p>
          <div class="mt-5 flex justify-end">
            <button
              id="import-manifest"
              type="submit"
              class="rounded-xl bg-indigo-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500 disabled:opacity-50"
              disabled={@uploads.manifest.entries == []}
            >
              Validate and import
            </button>
          </div>
        </.form>

        <div
          :if={@import_result}
          id="import-success"
          class="mt-5 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-900 dark:border-emerald-800 dark:bg-emerald-500/10 dark:text-emerald-200"
        >
          {String.capitalize(Atom.to_string(@import_result.status))}: {@import_result.condition_count} conditions, {@import_result.run_count} runs, and {@import_result.task_count} tasks.
        </div>
        <div
          :if={@import_errors != []}
          id="import-errors"
          class="mt-5 rounded-xl border border-rose-200 bg-rose-50 p-4 dark:border-rose-900 dark:bg-rose-500/10"
        >
          <p class="font-semibold text-rose-900 dark:text-rose-200">Manifest validation failed</p>
          <ul class="mt-3 space-y-2 text-sm text-rose-800 dark:text-rose-300">
            <li :for={error <- @import_errors}><code>{error.path}</code>: {error.message}</li>
          </ul>
        </div>
      </section>

      <section class="mt-8">
        <h2 class="mb-4 text-lg font-semibold text-slate-950 dark:text-white">Import history</h2>
        <div
          id="import-history"
          phx-update="stream"
          class="overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900"
        >
          <div
            id="import-history-empty"
            class="hidden only:block px-6 py-12 text-center text-sm text-slate-500"
          >
            No manifests imported yet.
          </div>
          <div
            :for={{id, summary} <- @streams.imports}
            id={id}
            class="grid gap-2 border-b border-slate-100 px-5 py-4 last:border-b-0 dark:border-slate-800 sm:grid-cols-[minmax(0,1fr)_auto_auto] sm:items-center sm:gap-6"
          >
            <div class="min-w-0">
              <p class="truncate font-semibold text-slate-900 dark:text-white">
                {summary.batch.original_filename}
              </p>
              <p class="mt-1 truncate font-mono text-xs text-slate-400">
                {summary.batch.source_sha256}
              </p>
            </div>
            <p class="text-sm text-slate-600 dark:text-slate-300">
              {summary.runs} runs · {summary.tasks} tasks
            </p>
            <time class="text-xs text-slate-500">{Calendar.strftime(
              summary.batch.imported_at,
              "%Y-%m-%d %H:%M"
            )}</time>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp upload_error_to_string(:too_large), do: "The manifest exceeds 20 MB."
  defp upload_error_to_string(:not_accepted), do: "Only JSON files are accepted."
  defp upload_error_to_string(:too_many_files), do: "Upload one manifest at a time."
end
