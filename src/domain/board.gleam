import domain/card
import domain/lane
import domain/phase
import domain/user
import domain/values/non_empty_string as nes
import domain/vote
import gleam/bool
import gleam/list
import gleam/result

pub type BoardId {
  BoardId(String)
}

pub opaque type Board {
  Board(
    id: String,
    title: nes.NonEmptyString,
    lanes: List(lane.Lane),
    phase: phase.Phase,
    cards: List(#(lane.LaneId, card.Card)),
  )
}

pub fn id(board: Board) -> String {
  board.id
}

pub fn new(
  id: String,
  title: nes.NonEmptyString,
  lanes: List(lane.Lane),
) -> Board {
  Board(id, title, lanes: lanes, phase: phase.Draft, cards: [])
}

pub fn title(board: Board) -> nes.NonEmptyString {
  board.title
}

pub fn lanes(board: Board) -> List(lane.Lane) {
  board.lanes
}

pub fn phase(board: Board) -> phase.Phase {
  board.phase
}

pub type RevealError {
  RevealBoardAlreadyRevealed
  RevealBoardNoCardsToReveal
}

pub type StartVotingError {
  StartVotingAlreadyVoting
  StartVotingCardsNotReveled
}

pub fn reveal_board(board: Board) -> Result(Board, RevealError) {
  use <- bool.guard(
    when: board.phase != phase.Draft,
    return: Error(RevealBoardAlreadyRevealed),
  )

  let cards = board |> lanes |> list.flat_map(lane.cards)

  use <- bool.guard(
    when: cards == [],
    return: Error(RevealBoardNoCardsToReveal),
  )

  Ok(Board(..board, phase: phase.Preview))
}

pub fn start_voting(board: Board) -> Result(Board, StartVotingError) {
  case board.phase {
    phase.Draft -> Error(StartVotingCardsNotReveled)
    phase.Voting -> Error(StartVotingAlreadyVoting)
    phase.Preview -> Ok(Board(..board, phase: phase.Voting))
  }
}

pub type UpdateLaneError(e) {
  LaneToUpdateNotFound
  TransformError(e)
}

pub fn update_lane(
  board: Board,
  lane_id: lane.LaneId,
  transform: fn(lane.Lane) -> Result(lane.Lane, e),
) {
  case find_lane(board, lane_id) {
    Ok(lane) -> {
      lane
      |> transform
      |> result.map(fn(updated_lane) { do_update_lane(board, updated_lane) })
      |> result.map_error(TransformError)
    }
    Error(Nil) -> Error(LaneToUpdateNotFound)
  }
}

pub fn find_lane(board: Board, lane_id: lane.LaneId) -> Result(lane.Lane, Nil) {
  list.find(board.lanes, fn(lane) { lane.id(lane) == lane_id })
}

fn do_update_lane(board: Board, updated_lane: lane.Lane) {
  Board(
    ..board,
    lanes: list.map(board.lanes, fn(lane) {
      case lane.id(lane) == lane.id(updated_lane) {
        True -> updated_lane
        False -> lane
      }
    }),
  )
}

pub fn add_card_to_lane(
  board board: Board,
  lane_id lane_id: lane.LaneId,
  card card: card.Card,
) -> Result(Board, UpdateLaneError(e)) {
  use lane <- update_lane(board, lane_id)

  Ok(lane.add_card(lane, card))
}

pub type EditCardError(e) {
  EditCardNotFound
  EditCardNotDraftPhase
  EditCardError(e)
}

pub fn edit_card_content(
  board board: Board,
  author_id author_id: user.UserId,
  card_id card_id: card.CardId,
  content content: nes.NonEmptyString,
) -> Result(Board, EditCardError(card.EditError)) {
  use <- bool.guard(
    when: board.phase != phase.Draft,
    return: Error(EditCardNotDraftPhase),
  )
  use lane <- try_update_any_lane(board, EditCardNotFound)

  lane.update_card(lane:, card_id:, transform: fn(card) {
    card.edit(card:, author_id:, content:)
  })
  |> result.map_error(fn(e) {
    case e {
      lane.CardToUpdateNotFound -> EditCardNotFound
      lane.TransformError(e) -> EditCardError(e)
    }
  })
}

pub type RemoveCardError {
  RemoveCardNotDraftPhase
  RemoveCardNotAuthor
  RemoveCardNotFound
}

pub fn remove_card(
  board board: Board,
  author_id author_id: user.UserId,
  card_id card_id: card.CardId,
) -> Result(Board, RemoveCardError) {
  use <- bool.guard(
    when: board.phase != phase.Draft,
    return: Error(RemoveCardNotDraftPhase),
  )
  use lane <- try_update_any_lane(board, RemoveCardNotFound)

  use #(removed_card, lane) <- result.try(
    lane.remove_card(lane:, card_id:)
    |> result.map_error(fn(error) {
      case error {
        lane.CardToRemoveNotFound -> RemoveCardNotFound
      }
    }),
  )

  case card.author_id(removed_card) == author_id {
    True -> Ok(lane)
    False -> Error(RemoveCardNotAuthor)
  }
}

pub type VoteError(e) {
  VoteCardNotFound
  VoteNotVotingPhase
  VoteCardError(e)
}

pub fn vote_for_card(
  board board: Board,
  vote vote: vote.Vote,
  card_id card_id: card.CardId,
) -> Result(Board, VoteError(card.VoteError)) {
  use <- bool.guard(
    when: board.phase != phase.Voting,
    return: Error(VoteNotVotingPhase),
  )
  use lane <- try_update_any_lane(board, VoteCardNotFound)
  lane.update_card(lane, card_id, fn(card) { card.vote(card, vote) })
  |> result.map_error(fn(e) {
    case e {
      lane.CardToUpdateNotFound -> VoteCardNotFound
      lane.TransformError(e) -> VoteCardError(e)
    }
  })
}

pub type RemoveVoteError(e) {
  RemoveVoteCardNotFound
  RemoveVoteNotVotingPhase
  RemoveVoteCardError(e)
}

pub fn remove_vote_for_card(
  board board: Board,
  vote vote: vote.Vote,
  card_id card_id: card.CardId,
) -> Result(Board, RemoveVoteError(card.RemoveVoteError)) {
  use <- bool.guard(
    when: board.phase != phase.Voting,
    return: Error(RemoveVoteNotVotingPhase),
  )
  use lane <- try_update_any_lane(board, RemoveVoteCardNotFound)
  lane.update_card(lane, card_id, fn(card) { card.remove_vote(card, vote) })
  |> result.map_error(fn(e) {
    case e {
      lane.CardToUpdateNotFound -> RemoveVoteCardNotFound
      lane.TransformError(e) -> RemoveVoteCardError(e)
    }
  })
}

pub type MergeCardsError(e) {
  MergeCardsNotInPreviewPhase
  MergeCardsFromCardNotFound
  MergeCardsToCardNotFound
  MergeCardsCardError(e)
}

pub fn merge_cards(
  board board: Board,
  from_card_id from_card_id: card.CardId,
  to_card_id to_card_id: card.CardId,
) -> Result(Board, MergeCardsError(card.MergeError)) {
  use <- bool.guard(
    when: board.phase != phase.Preview,
    return: Error(MergeCardsNotInPreviewPhase),
  )
  let #(from_card_result, lanes) =
    extract_card_from_lanes(board.lanes, from_card_id)

  let board = Board(..board, lanes:)
  use from_card <- result.try(
    from_card_result
    |> result.map_error(fn(error) {
      case error {
        Nil -> MergeCardsFromCardNotFound
      }
    }),
  )
  use lane <- try_update_any_lane(board, MergeCardsToCardNotFound)
  lane.update_card(lane:, card_id: to_card_id, transform: fn(to_card) {
    card.merge(from: from_card, to: to_card)
  })
  |> result.map_error(fn(e) {
    case e {
      lane.CardToUpdateNotFound -> MergeCardsToCardNotFound
      lane.TransformError(e) -> MergeCardsCardError(e)
    }
  })
}

fn extract_card_from_lanes(
  lanes: List(lane.Lane),
  id: card.CardId,
) -> #(Result(card.Card, Nil), List(lane.Lane)) {
  let #(extracted_card, lanes) =
    list.fold(lanes, #(Error(Nil), []), fn(acc, lane) {
      let #(from_card, acc_lanes) = acc
      case from_card {
        Ok(card) -> #(Ok(card), [lane, ..acc_lanes])
        Error(Nil) -> {
          let result = lane.remove_card(lane, id)
          case result {
            Ok(#(from_card, updated_lane)) -> #(Ok(from_card), [
              updated_lane,
              ..acc_lanes
            ])
            Error(lane.CardToRemoveNotFound) -> #(Error(Nil), [
              lane,
              ..acc_lanes
            ])
          }
        }
      }
    })

  #(extracted_card, list.reverse(lanes))
}

fn try_update_any_lane(
  board: Board,
  not_found_error: e,
  apply_fn: fn(lane.Lane) -> Result(lane.Lane, e),
) -> Result(Board, e) {
  use updated_lanes <- result.try(
    list.try_map(board.lanes, fn(lane) {
      case apply_fn(lane) {
        Ok(updated) -> Ok(updated)
        Error(error) if error == not_found_error -> Ok(lane)
        Error(error) -> Error(error)
      }
    }),
  )
  ensure_changed(board, updated_lanes, not_found_error)
}

fn ensure_changed(
  board: Board,
  new_lanes: List(lane.Lane),
  on_no_change: e,
) -> Result(Board, e) {
  case new_lanes == board.lanes {
    True -> Error(on_no_change)
    False -> Ok(Board(..board, lanes: new_lanes))
  }
}
