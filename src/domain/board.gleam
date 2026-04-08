import domain/lane
import domain/phase
import domain/values/non_empty_string as nes
import gleam/list
import gleam/result
import youid/uuid

pub type BoardId {
  BoardId(uuid.Uuid)
}

pub opaque type Board(phase) {
  Board(id: BoardId, title: nes.NonEmptyString, lanes: List(lane.Lane(phase)))
}

pub fn new(
  title: nes.NonEmptyString,
  lanes: List(lane.Lane(phase.Drafting)),
) -> Board(phase.Drafting) {
  Board(BoardId(uuid.v7()), title, lanes: lanes)
}

pub fn title(board: Board(phase)) -> nes.NonEmptyString {
  board.title
}

pub fn lanes(board: Board(phase)) -> List(lane.Lane(phase)) {
  board.lanes
}

pub fn reveal_board(board: Board(phase.Drafting)) -> Board(phase.Reviewing) {
  let updated_lanes = list.map(board.lanes, fn(lane) { lane.reveal(lane) })

  Board(..board, lanes: updated_lanes)
}

pub type UpdateLaneError(e) {
  LaneToUpdateNotFound
  TransformError(e)
}

pub fn update_lane(
  board: Board(phase),
  lane_id: lane.LaneId,
  transform: fn(lane.Lane(phase)) -> Result(lane.Lane(phase), e),
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

fn find_lane(board: Board(phase), lane_id: lane.LaneId) {
  list.find(board.lanes, fn(lane) { lane.id(lane) == lane_id })
}

fn do_update_lane(board: Board(phase), updated_lane: lane.Lane(phase)) {
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
