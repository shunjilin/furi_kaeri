import domain/values/non_empty_string as nes
import youid/uuid

pub type LaneId {
  LaneId(uuid.Uuid)
}

pub opaque type Lane {
  Lane(id: LaneId, title: nes.NonEmptyString)
}

pub fn new(title: nes.NonEmptyString) {
  Lane(id: LaneId(uuid.v7()), title: title)
}

pub fn id(lane: Lane) -> LaneId {
  lane.id
}

pub fn title(lane: Lane) -> nes.NonEmptyString {
  lane.title
}
