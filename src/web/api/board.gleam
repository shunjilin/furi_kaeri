import domain/board_v2
import domain/card_v2
import domain/lane_v2
import domain/user
import domain/values/non_empty_string
import domain/vote
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/otp/actor
import gleam/result
import web/shared_message

pub type State {
  State(
    board: board_v2.Board,
    subscribers: dict.Dict(String, Subject(shared_message.SharedMsg)),
    stale_timer: option.Option(process.Timer),
    subject: Subject(Message),
  )
}

pub type Message {
  GetBoard(reply_to: Subject(board_v2.Board))
  AddCard(user_id: user.UserId, lane_id: lane_v2.LaneId, content: String)
  EditCard(user_id: user.UserId, card_id: card_v2.CardId, content: String)
  RemoveCard(user_id: user.UserId, card_id: card_v2.CardId)
  MergeCard(from_card_id: card_v2.CardId, to_card_id: card_v2.CardId)
  Vote(user_id: user.UserId, card_id: card_v2.CardId)
  RemoveVote(user_id: user.UserId, card_id: card_v2.CardId)
  RevealBoard
  StartVoting
  Subscribe(id: String, client: Subject(shared_message.SharedMsg))
  Unsubscribe(id: String)
  DeleteBoard
}

pub fn start_link(
  id: String,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    State(
      board: init_board(id),
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
    GetBoard(reply_to) -> handle_get_board(state, reply_to)

    AddCard(user_id, lane_id, content) -> {
      state.board
      |> do_add_card(user_id, lane_id, content)
      |> respond(state)
    }

    EditCard(user_id, card_id, content) -> {
      state.board
      |> do_edit_card(user_id, card_id, content)
      |> respond(state)
    }

    RemoveCard(user_id, card_id) -> {
      state.board
      |> do_remove_card(user_id, card_id)
      |> respond(state)
    }

    MergeCard(from_card_id, to_card_id) -> {
      state.board
      |> board_v2.merge_cards(to_card_id, from_card_id)
      |> result.map_error(fn(err) {
        case err {
          board_v2.MergeTargetNotFound -> "Merge target not found."
          board_v2.MergeSourceNotFound -> "Merge source not found."
          board_v2.NotRevealedPhase -> "Can only merge in revealed phase."
          board_v2.MergeCardError(card_v2.MergeCannotMergeToSelf) ->
            "Cannot merge card with itself."
        }
      })
      |> respond(state)
    }

    Vote(user_id, card_id) -> {
      let vote = vote.Vote(user_id)
      state.board
      |> board_v2.vote(vote, card_id)
      |> result.map_error(fn(err) {
        case err {
          board_v2.UpdateCardNotFound -> "Card to vote for not found."
          board_v2.PhaseViolation -> "Can only vote in voting phase."
          board_v2.UpdateCardError(card_v2.VoteAlreadyVoted) -> "Already voted."
        }
      })
      |> respond(state)
    }

    RemoveVote(user_id, card_id) -> {
      let vote = vote.Vote(user_id)
      state.board
      |> board_v2.remove_vote(vote, card_id)
      |> result.map_error(fn(err) {
        case err {
          board_v2.UpdateCardNotFound -> "Card to remove vote for not found."
          board_v2.PhaseViolation -> "Can only remove vote in voting phase."
          board_v2.UpdateCardError(card_v2.RemoveVoteNotFound) ->
            "Not yet voted."
        }
      })
      |> respond(state)
    }

    RevealBoard -> {
      state.board
      |> board_v2.reveal()
      |> result.replace_error("Can only reveal in draft phase.")
      |> respond(state)
    }

    StartVoting -> {
      state.board
      |> board_v2.start_voting()
      |> result.replace_error("Can only start voting in revealed phase.")
      |> respond(state)
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
  }
}

fn do_add_card(
  board: board_v2.Board,
  user_id: user.UserId,
  lane_id: lane_v2.LaneId,
  content: String,
) -> Result(board_v2.Board, String) {
  use validated_content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  let card = card_v2.new(user_id, validated_content)

  board
  |> board_v2.add_card(card, lane_id)
  |> result.map_error(fn(error) {
    case error {
      board_v2.AddCardLaneNotFound -> "Lane not found."
      board_v2.NotDraftPhase -> "Can only add to draft board."
    }
  })
}

fn do_edit_card(
  board: board_v2.Board,
  author_id: user.UserId,
  card_id: card_v2.CardId,
  content: String,
) -> Result(board_v2.Board, String) {
  use content <- result.try(
    content
    |> non_empty_string.new()
    |> result.replace_error("Invalid content."),
  )

  board
  |> board_v2.edit_card(author_id, card_id, content)
  |> result.map_error(fn(error) {
    case error {
      board_v2.UpdateCardNotFound -> "Card to edit not found."
      board_v2.PhaseViolation -> "Can only edit card in draft phase."
      board_v2.UpdateCardError(card_v2.EditNotAuthor) ->
        "Can only edit as author."
    }
  })
}

fn do_remove_card(
  board: board_v2.Board,
  author_id: user.UserId,
  card_id: card_v2.CardId,
) -> Result(board_v2.Board, String) {
  board
  |> board_v2.remove_card(author_id, card_id)
  |> result.map_error(fn(error) {
    case error {
      board_v2.UpdateCardNotFound -> "Card to remove not found."
      board_v2.PhaseViolation -> "Can only remove card in draft phase."
      board_v2.UpdateCardError(card_v2.RemoveNotAuthor) ->
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

fn handle_get_board(state: State, reply_to: Subject(board_v2.Board)) {
  process.send(reply_to, state.board)
  actor.continue(state)
}

pub fn init_board(id) -> board_v2.Board {
  board_v2.new(id, new_string("Retro"), [
    lane_v2.new(new_string("Start")),
    lane_v2.new(new_string("Stop")),
    lane_v2.new(new_string("Continue")),
  ])
}

fn new_string(str: String) {
  let assert Ok(val) = non_empty_string.new(str)
  val
}

fn respond(
  result: Result(board_v2.Board, String),
  state: State,
) -> actor.Next(State, Message) {
  case result {
    Ok(updated_board) -> {
      dict.each(state.subscribers, fn(_, sub) {
        process.send(sub, shared_message.ApiReturnedBoard(updated_board))
      })
      actor.continue(State(..state, board: updated_board))
    }
    Error(message) -> {
      dict.each(state.subscribers, fn(_, sub) {
        process.send(sub, shared_message.ApiReturnedError(message))
      })
      actor.continue(state)
    }
  }
}
