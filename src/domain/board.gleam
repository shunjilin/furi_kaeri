import domain/lane
import domain/phase
import domain/values/non_empty_string as nes
import gleam/bool
import gleam/list
import gleam/result
import youid/uuid

pub type BoardId {
  BoardId(uuid.Uuid)
}

pub opaque type Board {
  Board(
    id: BoardId,
    title: nes.NonEmptyString,
    lanes: List(lane.Lane),
    phase: phase.Phase,
  )
}

pub fn new(title: nes.NonEmptyString, lanes: List(lane.Lane)) -> Board {
  Board(BoardId(uuid.v7()), title, lanes: lanes, phase: phase.Draft)
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

pub fn reveal_board(board: Board) -> Result(Board, RevealError) {
  use <- bool.guard(
    when: board.phase == phase.Review,
    return: Error(RevealBoardAlreadyRevealed),
  )

  let cards = board |> lanes |> list.flat_map(lane.cards)

  use <- bool.guard(
    when: cards == [],
    return: Error(RevealBoardNoCardsToReveal),
  )

  Ok(Board(..board, phase: phase.Review))
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

fn find_lane(board: Board, lane_id: lane.LaneId) {
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
