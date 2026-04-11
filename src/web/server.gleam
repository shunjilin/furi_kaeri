import domain/board.{type Board}
import domain/lane
import domain/phase.{type Drafting}
import domain/values/non_empty_string
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type StateMsg {
  GetBoard(reply_to: Subject(Board(Drafting)))
  UpdateBoard(Board(Drafting))
}

pub fn start() {
  let initial_board = init_board()

  initial_board
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(board: Board(Drafting), message: StateMsg) {
  case message {
    GetBoard(reply_to) -> {
      process.send(reply_to, board)
      actor.continue(board)
    }

    UpdateBoard(new_board) -> {
      actor.continue(new_board)
    }
  }
}

pub fn init_board() -> Board(Drafting) {
  board.new(new_string("Retro"), [
    lane.new(new_string("Start")),
    lane.new(new_string("Stop")),
    lane.new(new_string("Continue")),
  ])
}

fn new_string(str: String) {
  let assert Ok(val) = non_empty_string.new(str)
  val
}
