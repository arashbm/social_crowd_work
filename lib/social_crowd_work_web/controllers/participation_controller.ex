defmodule SocialCrowdWorkWeb.ParticipationController do
  use SocialCrowdWorkWeb, :controller

  alias SocialCrowdWork.Experiments
  alias SocialCrowdWork.{DataCollection, Prolific}
  alias SocialCrowdWork.Experiments.Condition
  alias SocialCrowdWorkWeb.ParticipantContexts

  @prolific_fields [
    prolific_participant_id: "PROLIFIC_PID",
    prolific_study_id: "STUDY_ID",
    prolific_session_id: "SESSION_ID"
  ]

  def start(conn, %{"entry_token" => entry_token} = params) do
    context =
      Map.new(@prolific_fields, fn {field, param} ->
        {Atom.to_string(field), Map.get(params, param)}
      end)

    with %Condition{} = condition <- Experiments.get_condition_by_entry_token(entry_token),
         :ok <- validate_context(context),
         :ok <- validate_study(condition, context) do
      context = Map.put(context, "condition_id", condition.id)

      case ParticipantContexts.put(contexts(conn), context) do
        {:ok, contexts, context_token} ->
          conn
          |> configure_session(renew: true)
          |> put_session(ParticipantContexts.session_key(), contexts)
          |> redirect(to: ~p"/participate/#{context_token}")

        {:error, reason} ->
          redirect_error(conn, reason)
      end
    else
      nil -> redirect_error(conn, :unknown_condition)
      {:error, reason} -> redirect_error(conn, reason)
    end
  end

  def error(conn, params) do
    render(conn, :error, reason: error_reason(params["reason"]))
  end

  def decline(conn, %{"context_token" => context_token}) do
    conn
    |> put_contexts(ParticipantContexts.delete(contexts(conn), context_token))
    |> redirect(to: ~p"/participate/declined")
  end

  def declined(conn, _params) do
    render(conn, :declined)
  end

  def complete(conn, %{"context_token" => context_token}) do
    with {:ok, context} <- ParticipantContexts.fetch(get_session(conn), context_token),
         %Condition{} = condition <- Experiments.get_condition(context["condition_id"]),
         {:ok, participation} <-
           DataCollection.resume_participation(condition, participant_attrs(context)),
         :completed <- participation.status do
      conn
      |> put_contexts(ParticipantContexts.delete(contexts(conn), context_token))
      |> redirect(external: Prolific.completion_url(condition.prolific_completion_code))
    else
      _other -> redirect(conn, to: ~p"/participate/#{context_token}")
    end
  end

  defp put_contexts(conn, contexts) do
    conn
    |> configure_session(renew: true)
    |> put_session(ParticipantContexts.session_key(), contexts)
  end

  defp contexts(conn) do
    get_session(conn, ParticipantContexts.session_key()) || %{}
  end

  defp participant_attrs(context) do
    %{
      prolific_participant_id: context["prolific_participant_id"],
      prolific_study_id: context["prolific_study_id"],
      prolific_session_id: context["prolific_session_id"]
    }
  end

  defp redirect_error(conn, reason) do
    redirect(conn, to: ~p"/participate/error?#{[reason: reason]}")
  end

  defp error_reason("unknown_condition"), do: :unknown_condition
  defp error_reason("invalid_prolific_parameters"), do: :invalid_prolific_parameters
  defp error_reason("prolific_study_mismatch"), do: :prolific_study_mismatch
  defp error_reason("capacity_reached"), do: :capacity_reached
  defp error_reason(_reason), do: :entry_error

  defp validate_context(context) do
    if Enum.all?(context, fn {_key, value} ->
         is_binary(value) and String.trim(value) != "" and byte_size(value) <= 255
       end) do
      :ok
    else
      {:error, :invalid_prolific_parameters}
    end
  end

  defp validate_study(condition, %{"prolific_study_id" => study_id}) do
    if condition.prolific_study_id == study_id do
      :ok
    else
      {:error, :prolific_study_mismatch}
    end
  end
end
