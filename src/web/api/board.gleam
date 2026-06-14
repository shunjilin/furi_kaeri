import domain/board
import domain/card
import domain/lane
import domain/timer
import domain/user
import domain/values/non_empty_list
import domain/values/non_empty_string
import domain/vote
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/otp/actor
import gleam/result
import gleam/time/duration
import gleam/time/timestamp
import web/shared_message

pub type CountdownTimer {
  CountdownTimer(timer: timer.Timer, process_timer: process.Timer)
}

pub type State {
  State(
    board: board.Board,
    countdown_timer: option.Option(CountdownTimer),
    subscribers: dict.Dict(String, Subject(shared_message.SharedMsg)),
    stale_timer: option.Option(process.Timer),
    subject: Subject(Message),
  )
}

pub type Message {
  GetBoardSnapshot(reply_to: Subject(shared_message.BoardSnapshot))
  AddCard(user_id: user.UserId, lane_id: lane.LaneId, content: String)
  EditCard(user_id: user.UserId, card_id: card.CardId, content: String)
  RemoveCard(user_id: user.UserId, card_id: card.CardId)
  MergeCard(from_card_id: card.CardId, to_card_id: card.CardId)
  Vote(user_id: user.UserId, card_id: card.CardId)
  RemoveVote(user_id: user.UserId, card_id: card.CardId)
  RevealCardContents
  StartVoting
  RevealVotes
  Subscribe(id: String, client: Subject(shared_message.SharedMsg))
  Unsubscribe(id: String)
  DeleteBoard
  StartCountdownTimer(duration: duration.Duration)
  StopCountdownTimer
  CountdownFinished
}

pub type BoardInitArgs {
  BoardInitArgs(id: String, lanes: non_empty_list.NonEmptyList(lane.Lane))
}

pub fn start_link(
  board: board.Board,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    State(
      board:,
      countdown_timer: option.None,
      subscribers: dict.new(),
      stale_timer: option.None,
      subject: subject,
    )
    |> actor.initialised
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    GetBoardSnapshot(reply_to) -> handle_get_board_snapshot(state, reply_to)

    AddCard(user_id, lane_id, content) -> {
      state.board
      |> do_add_card(user_id, lane_id, content)
      |> handle_board_result(state)
    }

    EditCard(user_id, card_id, content) -> {
      state.board
      |> do_edit_card(user_id, card_id, content)
      |> handle_board_result(state)
    }

    RemoveCard(user_id, card_id) -> {
      state.board
      |> do_remove_card(user_id, card_id)
      |> handle_board_result(state)
    }

    MergeCard(from_card_id, to_card_id) -> {
      state.board
      |> board.merge_cards(to_card_id, from_card_id)
      |> result.map_error(fn(err) {
        case err {
          board.MergeTargetNotFound -> "Merge target not found."
          board.MergeSourceNotFound -> "Merge source not found."
          board.NotRevealedPhase -> "Can only merge in revealed phase."
          board.MergeCardError(card.MergeCannotMergeToSelf) ->
            "Cannot merge card with itself."
        }
      })
      |> handle_board_result(state)
    }

    Vote(user_id, card_id) -> {
      let vote = vote.Vote(user_id)
      state.board
      |> board.vote(vote, card_id)
      |> result.map_error(fn(err) {
        case err {
          board.UpdateCardNotFound -> "Card to vote for not found."
          board.PhaseViolation -> "Can only vote in voting phase."
          board.UpdateCardError(card.VoteAlreadyVoted) -> "Already voted."
        }
      })
      |> handle_board_result(state)
    }

    RemoveVote(user_id, card_id) -> {
      let vote = vote.Vote(user_id)
      state.board
      |> board.remove_vote(vote, card_id)
      |> result.map_error(fn(err) {
        case err {
          board.UpdateCardNotFound -> "Card to remove vote for not found."
          board.PhaseViolation -> "Can only remove vote in voting phase."
          board.UpdateCardError(card.RemoveVoteNotFound) -> "Not yet voted."
        }
      })
      |> handle_board_result(state)
    }

    RevealCardContents -> {
      state.board
      |> board.reveal_content()
      |> result.map_error(fn(error) {
        case error {
          board.NotInDraftPhase -> "Can only reveal content in draft phase."
          board.NoCardsToReveal -> "No cards to reveal."
        }
      })
      |> handle_board_result(state)
    }

    RevealVotes -> {
      state.board
      |> board.reveal_votes()
      |> result.map_error(fn(err) {
        case err {
          board.InvalidTransitionState ->
            "Can only reveal content in draft phase."
        }
      })
      |> handle_board_result(state)
    }

    StartVoting -> {
      state.board
      |> board.start_voting()
      |> result.map_error(fn(err) {
        case err {
          board.InvalidTransitionState ->
            "Can only reveal votes in voting phase."
        }
      })
      |> handle_board_result(state)
    }

    Subscribe(id, client) -> {
      let subscribers = dict.insert(state.subscribers, id, client)
      let next_state =
        State(..state, subscribers:)
        |> stop_stale_timer()
      actor.continue(next_state)
    }

    Unsubscribe(id) -> {
      let subscribers = dict.delete(state.subscribers, id)
      let next_state =
        State(..state, subscribers:)
        |> start_stale_timer_if_no_subscribers()

      actor.continue(next_state)
    }

    DeleteBoard -> actor.stop()

    StartCountdownTimer(duration) -> {
      let clean_state = stop_countdown_timer(state)
      let now = timestamp.system_time()

      timer.new(now, duration)
      |> result.map_error(fn(err) {
        case err {
          timer.TimerDurationTooLong ->
            "Timer duration is too long (must be less than 1 hour)."
        }
      })
      |> result.map(fn(valid_timer) {
        let process_timer =
          process.send_after(
            clean_state.subject,
            duration.to_milliseconds(duration),
            CountdownFinished,
          )
        CountdownTimer(timer: valid_timer, process_timer:)
      })
      |> handle_timer_result(clean_state)
    }
    StopCountdownTimer -> {
      let clean_state = stop_countdown_timer(state)

      process.send(clean_state.subject, CountdownFinished)

      actor.continue(clean_state)
    }
    CountdownFinished -> {
      State(..state, countdown_timer: option.None)
      |> broadcast_snapshot()
      |> actor.continue()
    }
  }
}

fn do_add_card(
  board: board.Board,
  user_id: user.UserId,
  lane_id: lane.LaneId,
  content: String,
) -> Result(board.Board, String) {
  use validated_content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  let card = card.new(user_id, validated_content)

  board
  |> board.add_card(card, lane_id)
  |> result.map_error(fn(error) {
    case error {
      board.AddCardLaneNotFound -> "Lane not found."
      board.NotDraftPhase -> "Can only add to draft board."
    }
  })
}

fn do_edit_card(
  board: board.Board,
  author_id: user.UserId,
  card_id: card.CardId,
  content: String,
) -> Result(board.Board, String) {
  use content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  board
  |> board.edit_card(author_id, card_id, content)
  |> result.map_error(fn(error) {
    case error {
      board.UpdateCardNotFound -> "Card to edit not found."
      board.PhaseViolation -> "Can only edit card in draft phase."
      board.UpdateCardError(card.EditNotAuthor) -> "Can only edit as author."
    }
  })
}

fn do_remove_card(
  board: board.Board,
  author_id: user.UserId,
  card_id: card.CardId,
) -> Result(board.Board, String) {
  board
  |> board.remove_card(author_id, card_id)
  |> result.map_error(fn(error) {
    case error {
      board.UpdateCardNotFound -> "Card to remove not found."
      board.PhaseViolation -> "Can only remove card in draft phase."
      board.UpdateCardError(card.RemoveNotAuthor) ->
        "Can only remove card as author."
    }
  })
}

fn stop_stale_timer(state: State) {
  case state.stale_timer {
    option.Some(timer) -> {
      process.cancel_timer(timer)
      State(..state, stale_timer: option.None)
    }
    option.None -> state
  }
}

fn start_stale_timer_if_no_subscribers(state: State) {
  case dict.is_empty(state.subscribers) {
    True -> {
      State(
        ..state,
        stale_timer: option.Some(process.send_after(
          state.subject,
          60 * 60 * 1000,
          DeleteBoard,
        )),
      )
    }
    False -> state
  }
}

fn stop_countdown_timer(state: State) -> State {
  case state.countdown_timer {
    option.Some(active_timer) -> {
      process.cancel_timer(active_timer.process_timer)
      State(..state, countdown_timer: option.None)
    }
    option.None -> state
  }
}

fn handle_get_board_snapshot(
  state: State,
  reply_to: Subject(shared_message.BoardSnapshot),
) {
  process.send(reply_to, make_snapshot(state))
  actor.continue(state)
}

fn handle_board_result(
  result: Result(board.Board, String),
  state: State,
) -> actor.Next(State, Message) {
  case result {
    Ok(updated_board) -> {
      State(..state, board: updated_board)
      |> broadcast_snapshot()
      |> actor.continue()
    }
    Error(message) -> {
      state
      |> broadcast_error(message)
      |> actor.continue()
    }
  }
}

fn handle_timer_result(
  result: Result(CountdownTimer, String),
  state: State,
) -> actor.Next(State, Message) {
  case result {
    Ok(countdown_timer) -> {
      State(..state, countdown_timer: option.Some(countdown_timer))
      |> broadcast_snapshot()
      |> actor.continue()
    }
    Error(message) -> {
      state
      |> broadcast_error(message)
      |> actor.continue()
    }
  }
}

fn make_snapshot(state: State) -> shared_message.BoardSnapshot {
  shared_message.BoardSnapshot(
    board: state.board,
    countdown_timer: option.map(state.countdown_timer, fn(ct) { ct.timer }),
  )
}

fn broadcast_snapshot(state: State) -> State {
  let snapshot = make_snapshot(state)
  let msg = shared_message.ApiReturnedBoardSnapshot(snapshot)

  dict.each(state.subscribers, fn(_, sub) { process.send(sub, msg) })
  state
}

fn broadcast_error(state: State, error_message: String) -> State {
  dict.each(state.subscribers, fn(_, sub_subject) {
    process.send(sub_subject, shared_message.ApiReturnedError(error_message))
  })
  state
}
