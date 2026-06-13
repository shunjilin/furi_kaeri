import domain/board
import domain/lane
import domain/values/non_empty_list
import helpers/factories as f

pub fn new_test() {
  let title = f.non_empty_string("Retro")

  let lane_1 = lane.new(f.non_empty_string("Yes"))
  let lane_2 = lane.new(f.non_empty_string("No"))

  let board =
    board.new(
      "test",
      title,
      non_empty_list.NonEmptyList(first: lane_1, rest: [lane_2]),
    )

  assert board.title(board) == title
}
