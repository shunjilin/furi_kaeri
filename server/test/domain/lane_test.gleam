import domain/lane
import helpers/factories as f

pub fn new_test() {
  let title = f.non_empty_string("Pros")
  let lane = lane.new(title)

  assert lane.title(lane) == title
}
