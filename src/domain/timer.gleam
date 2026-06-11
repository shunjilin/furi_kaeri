import gleam/float
import gleam/order
import gleam/time/duration
import gleam/time/timestamp

const max_timer_duration_seconds = 3600.0

pub opaque type Timer {
  Timer(init_timestamp: timestamp.Timestamp, duration: duration.Duration)
}

pub type TimerError {
  TimerDurationTooLong
}

pub fn new(
  init_timestamp: timestamp.Timestamp,
  duration: duration.Duration,
) -> Result(Timer, TimerError) {
  let seconds = duration.to_seconds(duration)

  case float.compare(seconds, max_timer_duration_seconds) {
    order.Gt -> Error(TimerDurationTooLong)
    _ -> Ok(Timer(init_timestamp:, duration:))
  }
}

pub fn end_timestamp(timer: Timer) -> timestamp.Timestamp {
  timestamp.add(timer.init_timestamp, timer.duration)
}

pub fn duration_remaining(timer: Timer) -> duration.Duration {
  let now = timestamp.system_time()
  let end_timestamp = end_timestamp(timer)
  timestamp.difference(now, end_timestamp)
}
