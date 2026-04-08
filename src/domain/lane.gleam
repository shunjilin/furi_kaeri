import domain/card
import domain/phase
import domain/user
import domain/values/non_empty_string as nes
import gleam/list
import gleam/result
import youid/uuid

pub type LaneId {
  LaneId(uuid.Uuid)
}

pub opaque type Lane(phase) {
  Lane(id: LaneId, title: nes.NonEmptyString, cards: List(card.Card(phase)))
}

pub fn new(title: nes.NonEmptyString) {
  Lane(id: LaneId(uuid.v7()), title: title, cards: [])
}

pub fn id(lane: Lane(phase)) -> LaneId {
  lane.id
}

pub fn title(lane: Lane(phase)) -> nes.NonEmptyString {
  lane.title
}

pub fn cards(lane: Lane(phase)) -> List(card.Card(phase)) {
  lane.cards
}

pub fn add_card(lane: Lane(phase.Drafting), card: card.Card(phase.Drafting)) {
  Lane(..lane, cards: list.prepend(lane.cards, card))
}

pub type UpdateCardError(e) {
  CardToUpdateNotFound
  TransformError(e)
}

pub fn update_card(
  lane: Lane(phase),
  card_id: card.CardId,
  transform: fn(card.Card(phase)) -> Result(card.Card(phase), e),
) -> Result(Lane(phase), UpdateCardError(e)) {
  case find_card(lane, card_id) {
    Ok(card) -> {
      card
      |> transform
      |> result.map(fn(updated_card) { do_update_card(lane, updated_card) })
      |> result.map_error(TransformError)
    }

    Error(Nil) -> Error(CardToUpdateNotFound)
  }
}

pub type RemoveCardError {
  CardToRemoveNotFound
  NotAuthorOfCardToRemove
}

pub fn remove_card(
  lane: Lane(phase.Drafting),
  card_id: card.CardId,
  author_id: user.UserId,
) -> Result(Lane(phase.Drafting), RemoveCardError) {
  case find_card(lane, card_id) {
    Ok(card) -> {
      case card.author_id(card) == author_id {
        True -> Ok(do_remove_card(lane, card_id))
        False -> Error(NotAuthorOfCardToRemove)
      }
    }
    Error(Nil) -> Error(CardToRemoveNotFound)
  }
}

pub fn do_update_card(lane: Lane(phase), updated_card: card.Card(phase)) {
  Lane(
    ..lane,
    cards: list.map(lane.cards, fn(card) {
      case card.id(card) == card.id(updated_card) {
        True -> updated_card
        False -> card
      }
    }),
  )
}

pub fn reveal(lane: Lane(phase.Drafting)) -> Lane(phase.Reviewing) {
  Lane(id: lane.id, title: lane.title, cards: list.map(lane.cards, card.reveal))
}

fn do_remove_card(lane: Lane(phase.Drafting), card_id: card.CardId) {
  Lane(
    ..lane,
    cards: list.filter(lane.cards, fn(card) { card.id(card) != card_id }),
  )
}

fn find_card(lane: Lane(phase), card_id: card.CardId) {
  list.find(lane.cards, fn(card) { card.id(card) == card_id })
}
