defmodule SocialCrowdWorkWeb.ParticipationController do
  use SocialCrowdWorkWeb, :controller

  alias SocialCrowdWork.Experiments
  alias SocialCrowdWork.Experiments.Condition

  @session_key "participant_context"
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

      conn
      |> put_resp_header("referrer-policy", "no-referrer")
      |> configure_session(renew: true)
      |> delete_session(@session_key)
      |> put_session(@session_key, context)
      |> redirect(to: ~p"/participate")
    else
      nil -> render_error(conn, :unknown_condition, :not_found)
      {:error, reason} -> render_error(conn, reason, :bad_request)
    end
  end

  def declined(conn, _params) do
    conn
    |> put_resp_header("referrer-policy", "no-referrer")
    |> delete_session(@session_key)
    |> render(:declined)
  end

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

  defp render_error(conn, reason, status) do
    conn
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_status(status)
    |> render(:error, reason: reason)
  end
end
