import domain/card
import domain/lane
import domain/user
import domain/values/non_empty_list
import domain/values/non_empty_string
import domain/vote
import friendly_id
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option
import gleam/result

pub opaque type Board {
  Board(
    id: BoardId,
    title: non_empty_string.NonEmptyString,
    lanes: non_empty_list.NonEmptyList(lane.Lane),
    phase: BoardPhase,
  )
}

pub type BoardPhase {
  DraftBoard(
    cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(card.Draft))),
  )
  ReviewBoard(
    cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(card.Review))),
  )
  VotingBoard(
    cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(card.Voting))),
  )
  TallyBoard(
    cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(card.Tallied))),
  )
}

pub type BoardId {
  BoardId(String)
}

pub fn generate_id() -> BoardId {
  friendly_id.new_generator()
  |> friendly_id.set_generator_separator("_")
  |> friendly_id.generate()
  |> BoardId
}

pub fn id(board: Board) -> BoardId {
  board.id
}

pub fn title(board: Board) -> non_empty_string.NonEmptyString {
  board.title
}

pub fn lanes(board: Board) -> non_empty_list.NonEmptyList(lane.Lane) {
  board.lanes
}

pub fn phase(board: Board) -> BoardPhase {
  board.phase
}

pub fn new(
  id: BoardId,
  title: non_empty_string.NonEmptyString,
  lanes: non_empty_list.NonEmptyList(lane.Lane),
) -> Board {
  Board(id, title, lanes:, phase: DraftBoard(dict.new()))
}

pub type AddCardError {
  AddCardLaneNotFound
  NotDraftPhase
}

pub fn add_card(
  board: Board,
  card: card.Card(card.Draft),
  lane_id: lane.LaneId,
) -> Result(Board, AddCardError) {
  case board.phase {
    DraftBoard(cards) -> {
      use lane <- result.try(
        board.lanes
        |> non_empty_list.as_list
        |> list.find(fn(l) { lane.id(l) == lane_id })
        |> result.replace_error(AddCardLaneNotFound),
      )

      let entry = #(lane.id(lane), card)
      let operations = [#(card.id(card), option.Some(entry))]
      let updated_cards = apply_updates(cards, operations)

      Ok(Board(..board, phase: DraftBoard(updated_cards)))
    }
    _ -> Error(NotDraftPhase)
  }
}

pub type UpdateCardError(error) {
  UpdateCardNotFound
  UpdateCardError(error)
  PhaseViolation
}

pub fn edit_card(
  board: Board,
  author_id: user.UserId,
  card_id: card.CardId,
  content: non_empty_string.NonEmptyString,
) -> Result(Board, UpdateCardError(card.EditError)) {
  case board.phase {
    DraftBoard(cards) -> {
      update_card(cards, card_id, fn(card) {
        card.edit(card:, author_id:, content:) |> result.map(option.Some)
      })
      |> result.map(fn(updated) { Board(..board, phase: DraftBoard(updated)) })
    }
    _ -> Error(PhaseViolation)
  }
}

pub fn remove_card(
  board: Board,
  author_id: user.UserId,
  card_id: card.CardId,
) -> Result(Board, UpdateCardError(card.RemoveError)) {
  case board.phase {
    DraftBoard(cards) -> {
      update_card(cards, card_id, fn(card) {
        card.remove(card:, author_id:) |> result.map(fn(_) { option.None })
      })
      |> result.map(fn(updated) { Board(..board, phase: DraftBoard(updated)) })
    }
    _ -> Error(PhaseViolation)
  }
}

pub fn vote(
  board: Board,
  vote: vote.Vote,
  card_id: card.CardId,
) -> Result(Board, UpdateCardError(card.VoteError)) {
  case board.phase {
    VotingBoard(cards) -> {
      update_card(cards, card_id, fn(card) {
        card.vote(card:, vote:) |> result.map(option.Some)
      })
      |> result.map(fn(updated) { Board(..board, phase: VotingBoard(updated)) })
    }
    _ -> Error(PhaseViolation)
  }
}

pub fn remove_vote(
  board: Board,
  vote: vote.Vote,
  card_id: card.CardId,
) -> Result(Board, UpdateCardError(card.RemoveVoteError)) {
  case board.phase {
    VotingBoard(cards) -> {
      update_card(cards, card_id, fn(card) {
        card.remove_vote(card:, vote:) |> result.map(option.Some)
      })
      |> result.map(fn(updated) { Board(..board, phase: VotingBoard(updated)) })
    }
    _ -> Error(PhaseViolation)
  }
}

pub type MergeCardsError {
  MergeTargetNotFound
  MergeSourceNotFound
  MergeCardError(card.MergeError)
  NotRevealedPhase
}

pub fn merge_cards(
  board: Board,
  target_id: card.CardId,
  source_id: card.CardId,
) -> Result(Board, MergeCardsError) {
  case board.phase {
    ReviewBoard(cards) -> {
      use #(target_lane, target_card) <- result.try(
        dict.get(cards, target_id) |> result.replace_error(MergeTargetNotFound),
      )
      use #(_source_lane, source_card) <- result.try(
        dict.get(cards, source_id) |> result.replace_error(MergeSourceNotFound),
      )

      use updated_target <- result.try(
        card.merge(into: target_card, from: source_card)
        |> result.map_error(MergeCardError),
      )

      let operations = [
        #(target_id, option.Some(#(target_lane, updated_target))),
        #(source_id, option.None),
      ]
      let updated_cards = apply_updates(cards, operations)

      Ok(Board(..board, phase: ReviewBoard(updated_cards)))
    }
    _ -> Error(NotRevealedPhase)
  }
}

pub type RevealError {
  NotInDraftPhase
  NoCardsToReveal
}

pub fn reveal_content(board: Board) -> Result(Board, RevealError) {
  use cards <- result.try(case board.phase {
    DraftBoard(cards) -> Ok(cards)
    _ -> Error(NotInDraftPhase)
  })
  use <- bool.guard(when: dict.is_empty(cards), return: Error(NoCardsToReveal))
  let transitioned = transition_cards(cards, card.reveal_content)
  Ok(Board(..board, phase: ReviewBoard(transitioned)))
}

pub type TransitionError {
  InvalidTransitionState
}

pub fn reveal_votes(board: Board) -> Result(Board, TransitionError) {
  case board.phase {
    VotingBoard(cards) -> {
      let transitioned = transition_cards(cards, card.reveal_votes)
      Ok(Board(..board, phase: TallyBoard(transitioned)))
    }
    _ -> Error(InvalidTransitionState)
  }
}

pub fn start_voting(board: Board) -> Result(Board, TransitionError) {
  case board.phase {
    ReviewBoard(cards) -> {
      let transitioned = transition_cards(cards, card.start_voting)
      Ok(Board(..board, phase: VotingBoard(transitioned)))
    }
    _ -> Error(InvalidTransitionState)
  }
}

fn transition_cards(
  cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(from_phase))),
  transition: fn(card.Card(from_phase)) -> card.Card(to_phase),
) -> dict.Dict(card.CardId, #(lane.LaneId, card.Card(to_phase))) {
  dict.fold(over: cards, from: dict.new(), with: fn(acc_dict, card_id, entry) {
    let #(lane_id, card) = entry
    dict.insert(acc_dict, card_id, #(lane_id, transition(card)))
  })
}

fn update_card(
  cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(phase))),
  card_id: card.CardId,
  transform: fn(card.Card(phase)) ->
    Result(option.Option(card.Card(phase)), error),
) -> Result(
  dict.Dict(card.CardId, #(lane.LaneId, card.Card(phase))),
  UpdateCardError(error),
) {
  use #(lane_id, card_to_update) <- result.try(
    dict.get(cards, card_id) |> result.replace_error(UpdateCardNotFound),
  )

  use updated_card <- result.try(
    transform(card_to_update) |> result.map_error(UpdateCardError),
  )

  let operations = [
    #(card_id, option.map(updated_card, fn(card) { #(lane_id, card) })),
  ]
  Ok(apply_updates(cards, operations))
}

fn apply_updates(
  cards: dict.Dict(card.CardId, #(lane.LaneId, card.Card(phase))),
  operations: List(
    #(card.CardId, option.Option(#(lane.LaneId, card.Card(phase)))),
  ),
) -> dict.Dict(card.CardId, #(lane.LaneId, card.Card(phase))) {
  list.fold(over: operations, from: cards, with: fn(current_cards, operation) {
    let #(id, decision) = operation
    case decision {
      option.Some(updated_entry) ->
        dict.insert(current_cards, id, updated_entry)
      option.None -> dict.delete(current_cards, id)
    }
  })
}
